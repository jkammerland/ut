#!/bin/bash
# Minimal shell script for CI testing - most logic is in CMake/CTest

set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 <executable> <participant_count>"
  exit 1
fi

EXECUTABLE="$1"
PARTICIPANTS="$2"
TEST_NAME="ci-test-$$"
NETWORK_NAME="${TEST_NAME}-net"

# Cleanup on exit
cleanup() {
  for ((i=0; i<PARTICIPANTS; i++)); do
    podman rm -f ${TEST_NAME}-$i 2>/dev/null || true
  done
  podman network rm $NETWORK_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Create network
podman network create $NETWORK_NAME --subnet 10.99.0.0/24

# Start containers
echo "Starting $PARTICIPANTS containers..."
for ((i=0; i<PARTICIPANTS; i++)); do
  podman run -d --name ${TEST_NAME}-$i --network $NETWORK_NAME \
    -v "$EXECUTABLE:/test:ro,Z" \
    -e PROCESS_ID=$i \
    -e PARTICIPANT_COUNT=$PARTICIPANTS \
    -e MULTICAST_ADDRESS=239.255.0.1 \
    -e MULTICAST_PORT=15000 \
    multiprocess-test /test
done

# Wait and check results
SUCCESS=true
for ((i=0; i<PARTICIPANTS; i++)); do
  if ! timeout 30 podman wait ${TEST_NAME}-$i; then
    SUCCESS=false
  fi
done

if $SUCCESS; then
  echo "All containers completed successfully"
  exit 0
else
  echo "Some containers failed"
  exit 1
fi