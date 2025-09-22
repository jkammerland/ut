#!/bin/bash
# Simple test of rootless Podman for multiprocess coordination
# Uses podman run with bind mounts instead of building images

echo "Simple rootless Podman test for multiprocess coordination"
echo "=========================================================="

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "ERROR: podman is not installed"
    exit 1
fi

# Build the test executable
cd /home/ai-dev1/repos/ut/build
make boost_ut_network_coordination

# Test 1: Using podman with ubuntu image and bind mount
echo -e "\n1. Testing with bind-mounted executable in shared pod:"
echo "------------------------------------------------------"

# Create a pod (containers in same pod share network namespace)
podman pod create --name test-pod

# Run coordinator
podman run -d --pod test-pod --name coord \
    -v $(pwd)/example/multiprocess/boost_ut_network_coordination:/test:ro \
    -e PROCESS_ID=0 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=127.255.0.1 -e MULTICAST_PORT=15000 \
    ubuntu:22.04 /test

# Run participant
podman run -d --pod test-pod --name part \
    -v $(pwd)/example/multiprocess/boost_ut_network_coordination:/test:ro \
    -e PROCESS_ID=1 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=127.255.0.1 -e MULTICAST_PORT=15000 \
    ubuntu:22.04 /test

# Check logs after a moment
sleep 3
echo "Coordinator output:"
podman logs coord 2>&1 | head -20
echo -e "\nParticipant output:"
podman logs part 2>&1 | head -20

# Cleanup
podman pod rm -f test-pod

# Test 2: Direct execution without containers but with podman unshare
echo -e "\n2. Testing with podman unshare (enters user namespace):"
echo "--------------------------------------------------------"

timeout 5 bash -c '
# podman unshare enters the user namespace that rootless podman uses
podman unshare -- bash -c "
  PROCESS_ID=0 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15010 \
    /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination &
  PID1=\$!

  sleep 0.5

  PROCESS_ID=1 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15010 \
    /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination &
  PID2=\$!

  wait \$PID1 \$PID2
"
' && echo "✓ SUCCESS: Processes synchronized" || echo "✗ FAILED: Timeout or error"

echo -e "\n=========================================================="
echo "Key insights:"
echo "- Podman pods allow containers to share network namespaces"
echo "- This enables UDP multicast on loopback (127.x.x.x) addresses"
echo "- podman unshare provides user namespace for testing"