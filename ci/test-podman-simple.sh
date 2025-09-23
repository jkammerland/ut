#!/bin/bash
# Simple CI test for Podman multiprocess - uses existing build

set -e

echo "Simple Podman Multiprocess Test"
echo "==============================="

# Check Podman is available
if ! command -v podman &>/dev/null; then
  echo "Error: Podman not installed"
  exit 1
fi

# Use existing build directory
cd /home/ai-dev1/repos/ut/build

# Check if network coordination executable exists
if [ ! -f example/multiprocess/boost_ut_network_coordination ]; then
  echo "Building network coordination test..."
  make boost_ut_network_coordination
fi

# Build container image
echo "Building container image..."
cat > Dockerfile.test << 'EOF'
FROM fedora:42
RUN dnf install -y boost-system libstdc++ && dnf clean all
RUN mkdir -p /test
WORKDIR /
EOF
podman build -t multiprocess-test -f Dockerfile.test .

# Run the test
echo "Running Podman multiprocess test..."

EXEC="example/multiprocess/boost_ut_network_coordination"
NET="ci-$$"
SUCCESS=true

cleanup() {
  for i in 0 1 2; do
    podman rm -f test-$i 2>/dev/null || true
  done
  podman network rm $NET 2>/dev/null || true
}
trap cleanup EXIT

# Create network
podman network create $NET --subnet 10.99.0.0/24

# Start 3 containers
for i in 0 1 2; do
  podman run -d --name test-$i --network $NET \
    -v "$(pwd)/$EXEC:/app:ro,Z" \
    -e PROCESS_ID=$i \
    -e PARTICIPANT_COUNT=3 \
    -e MULTICAST_ADDRESS=239.255.0.1 \
    -e MULTICAST_PORT=15000 \
    multiprocess-test /app

  # Get IP
  sleep 0.3
  IP=$(podman inspect test-$i | jq -r '.[0].NetworkSettings.Networks["'$NET'"].IPAddress')
  echo "  Process $i started with IP: $IP"
done

# Wait for completion
echo "Waiting for processes to complete..."
for i in 0 1 2; do
  if ! timeout 30 podman wait test-$i >/dev/null 2>&1; then
    echo "  Process $i: TIMEOUT"
    SUCCESS=false
  else
    EXIT_CODE=$(podman inspect test-$i --format='{{.State.ExitCode}}')
    if [ "$EXIT_CODE" = "0" ]; then
      echo "  Process $i: SUCCESS"
    else
      echo "  Process $i: FAILED (exit code $EXIT_CODE)"
      SUCCESS=false
    fi
  fi
done

if $SUCCESS; then
  echo ""
  echo "✅ TEST PASSED: All processes completed successfully"
  exit 0
else
  echo ""
  echo "❌ TEST FAILED: Some processes failed"
  # Show logs for debugging
  for i in 0 1 2; do
    echo "Logs from process $i:"
    podman logs test-$i 2>&1 | tail -5
  done
  exit 1
fi