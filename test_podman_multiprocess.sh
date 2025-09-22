#!/bin/bash
# Test multiprocess coordination with rootless Podman
# Podman pods allow containers to share network namespaces

echo "Testing multiprocess coordination with rootless Podman"
echo "======================================================="

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "ERROR: podman is not installed"
    echo "Install with: sudo apt-get install podman (Ubuntu) or sudo dnf install podman (Fedora)"
    exit 1
fi

# Build the test executable first
cd /home/ai-dev1/repos/ut/build
make boost_ut_network_coordination

# Create a simple Dockerfile for our test
cat > /tmp/multiprocess.dockerfile <<EOF
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y libboost-system1.74.0
COPY boost_ut_network_coordination /usr/local/bin/
WORKDIR /tmp
EOF

# Build the container image
echo -e "\nBuilding container image..."
podman build -t multiprocess-test -f /tmp/multiprocess.dockerfile \
    --build-arg-file <(echo "boost_ut_network_coordination=./example/multiprocess/boost_ut_network_coordination") \
    .

# Test 1: Run two containers in the same pod (shared network namespace)
echo -e "\n1. Testing with Podman pod (shared network namespace):"
echo "-------------------------------------------------------"

# Create a pod
podman pod create --name multiprocess-pod

# Run coordinator in the pod
podman run -d --pod multiprocess-pod --name coord \
    -e PROCESS_ID=0 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=127.255.0.1 -e MULTICAST_PORT=15000 \
    multiprocess-test /usr/local/bin/boost_ut_network_coordination

# Run participant in the same pod
podman run -d --pod multiprocess-pod --name participant \
    -e PROCESS_ID=1 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=127.255.0.1 -e MULTICAST_PORT=15000 \
    multiprocess-test /usr/local/bin/boost_ut_network_coordination

# Wait and check results
sleep 3
echo "Coordinator logs:"
podman logs coord
echo -e "\nParticipant logs:"
podman logs participant

# Check if they synchronized
if podman logs coord 2>&1 | grep -q "All tests passed" && \
   podman logs participant 2>&1 | grep -q "All tests passed"; then
    echo "✓ SUCCESS: Processes synchronized in Podman pod"
else
    echo "✗ FAILED: Processes couldn't synchronize"
fi

# Cleanup
podman pod rm -f multiprocess-pod

# Test 2: Alternative - use host networking (less isolated but works)
echo -e "\n2. Testing with host networking (--network=host):"
echo "--------------------------------------------------"

timeout 5 bash -c '
podman run --rm --network=host \
    -e PROCESS_ID=0 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=239.255.0.1 -e MULTICAST_PORT=15001 \
    multiprocess-test /usr/local/bin/boost_ut_network_coordination &
PID1=$!

sleep 0.5

podman run --rm --network=host \
    -e PROCESS_ID=1 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=239.255.0.1 -e MULTICAST_PORT=15001 \
    multiprocess-test /usr/local/bin/boost_ut_network_coordination &
PID2=$!

wait $PID1 $PID2
' && echo "✓ SUCCESS: Processes synchronized" || echo "✗ FAILED: Timeout or error"

# Test 3: Create a custom bridge network (rootless)
echo -e "\n3. Testing with custom Podman network:"
echo "---------------------------------------"

# Create a custom network
podman network create multiprocess-net

# Run containers on the custom network
timeout 5 bash -c '
podman run --rm --network=multiprocess-net \
    -e PROCESS_ID=0 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=239.255.0.1 -e MULTICAST_PORT=15002 \
    multiprocess-test /usr/local/bin/boost_ut_network_coordination &
PID1=$!

sleep 0.5

podman run --rm --network=multiprocess-net \
    -e PROCESS_ID=1 -e PARTICIPANT_COUNT=2 \
    -e MULTICAST_ADDRESS=239.255.0.1 -e MULTICAST_PORT=15002 \
    multiprocess-test /usr/local/bin/boost_ut_network_coordination &
PID2=$!

wait $PID1 $PID2
' && echo "✓ SUCCESS: Processes synchronized" || echo "✗ FAILED: Timeout or error"

# Cleanup
podman network rm multiprocess-net

echo -e "\n======================================================="
echo "Analysis:"
echo "- Podman pods with shared network namespace should work for multicast on loopback"
echo "- Host networking works but provides less isolation"
echo "- Custom networks may or may not support multicast depending on CNI plugin"