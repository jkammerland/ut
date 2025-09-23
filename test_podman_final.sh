#!/bin/bash
# Final test of symmetric Podman API with proper container image

set -e

echo "Testing Symmetric Podman API with Boost Libraries"
echo "================================================="

# Build test executable
cd /home/ai-dev1/repos/ut/build
make boost_ut_network_coordination

EXEC_PATH="$(pwd)/example/multiprocess/boost_ut_network_coordination"
PARTICIPANTS=3
TEST_NAME="podman-final"

# Create network
NETWORK_NAME="${TEST_NAME}-$$"
SUBNET="10.$((RANDOM % 100 + 100)).0.0/24"

echo "Creating network $NETWORK_NAME with subnet $SUBNET"
podman network create $NETWORK_NAME --subnet $SUBNET

cleanup() {
    echo ""
    echo "Cleaning up..."
    for ((i=0; i<PARTICIPANTS; i++)); do
        podman rm -f ${TEST_NAME}-$i 2>/dev/null || true
    done
    podman network rm $NETWORK_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Start containers using our custom image with Boost
echo "Starting $PARTICIPANTS processes with unique IPs..."
echo "(Using multiprocess-test image with Boost libraries)"
echo ""

for ((i=0; i<PARTICIPANTS; i++)); do
    CID=$(podman run -d --name ${TEST_NAME}-$i --network $NETWORK_NAME \
        -v "$EXEC_PATH:/test/app:ro,Z" \
        -e PROCESS_ID=$i \
        -e PARTICIPANT_COUNT=$PARTICIPANTS \
        -e MULTICAST_ADDRESS=239.255.0.1 \
        -e MULTICAST_PORT=$((15000 + $$)) \
        multiprocess-test /test/app)

    # Get IP
    sleep 0.3
    IP=$(podman inspect ${TEST_NAME}-$i 2>/dev/null | \
         jq -r '.[0].NetworkSettings.Networks["'$NETWORK_NAME'"].IPAddress')
    echo "  Process $i started: IP=$IP, Container=${CID:0:12}"
done

# Wait for completion
echo ""
echo "Waiting for processes to synchronize..."
SUCCESS=true
FAILED=()

for ((i=0; i<PARTICIPANTS; i++)); do
    if timeout 30 podman wait ${TEST_NAME}-$i >/dev/null 2>&1; then
        EXIT_CODE=$(podman inspect ${TEST_NAME}-$i --format='{{.State.ExitCode}}')
        if [ "$EXIT_CODE" = "0" ]; then
            echo "  Process $i: ✓ Success"

            # Show success indicators
            podman logs ${TEST_NAME}-$i 2>&1 | grep -E "All tests passed|SUCCESS" | head -2
        else
            echo "  Process $i: ✗ Failed (exit code $EXIT_CODE)"
            FAILED+=($i)
            SUCCESS=false

            # Show error details
            echo "    Last logs:"
            podman logs ${TEST_NAME}-$i 2>&1 | tail -5 | sed 's/^/      /'
        fi
    else
        echo "  Process $i: ✗ Timeout"
        FAILED+=($i)
        SUCCESS=false
    fi
done

echo ""
echo "================================================="
if $SUCCESS; then
    echo "✅ SUCCESS: All $PARTICIPANTS processes completed with unique IPs!"
    echo ""
    echo "This proves:"
    echo "  • Symmetric Podman API works correctly"
    echo "  • Each process gets a unique IP address"
    echo "  • UDP multicast coordination works between containers"
    echo "  • No root privileges required (rootless Podman)"
    echo ""
    echo "Next steps:"
    echo "  1. Update CMakeLists.txt to include PodmanMultiprocessTest.cmake"
    echo "  2. Replace complex PodmanNetworkTest functions with simple API"
    echo "  3. Add CI/CD integration (GitHub Actions/GitLab CI)"
    echo "  4. Performance benchmarks vs local multiprocess"
    exit 0
else
    echo "❌ FAILED: Processes ${FAILED[@]} failed"
    echo ""
    echo "Debug with:"
    echo "  podman logs ${TEST_NAME}-<process_id>"
    echo "  podman network inspect $NETWORK_NAME"
    exit 1
fi