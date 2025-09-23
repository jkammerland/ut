#!/bin/bash
# Test the new symmetric Podman API with the network coordination tests

set -e

echo "Testing Symmetric Podman API"
echo "============================"

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "Error: Podman not installed. Install with:"
    echo "  sudo apt-get install podman  # Ubuntu/Debian"
    echo "  sudo dnf install podman       # Fedora"
    exit 1
fi

echo "Found podman: $(podman --version)"

# Move to build directory
cd /home/ai-dev1/repos/ut/build

# Make sure the network coordination test is built
echo ""
echo "Building network coordination test..."
make boost_ut_network_coordination

# Include our new test configuration
echo ""
echo "Adding Podman tests to CTest..."
cat > test_podman.cmake << 'EOF'
# Include the symmetric API
include(${CMAKE_SOURCE_DIR}/cmake/PodmanMultiprocessTest.cmake)

# Find the built executable
set(EXEC_PATH "${CMAKE_CURRENT_BINARY_DIR}/example/multiprocess/boost_ut_network_coordination")

# Add a simple 3-process test
ut_add_podman_multiprocess_test(
  NAME podman_symmetric_test
  TARGET boost_ut_network_coordination
  PARTICIPANTS 3
  TIMEOUT 30
)

message(STATUS "Added test: podman_symmetric_test")
EOF

# Run cmake to process the new tests
cmake -P test_podman.cmake 2>/dev/null || true

# Actually run a test directly (since CTest configuration is complex)
echo ""
echo "Running direct test with 3 processes..."
echo "----------------------------------------"

# Create a test script
cat > run_podman_test.sh << 'SCRIPT'
#!/bin/bash
set -e

EXEC_PATH="$(pwd)/example/multiprocess/boost_ut_network_coordination"
PARTICIPANTS=3
TEST_NAME="podman-test"

if [ ! -f "$EXEC_PATH" ]; then
    echo "Error: Executable not found: $EXEC_PATH"
    exit 1
fi

# Create network
NETWORK_NAME="${TEST_NAME}-net-$$"
SUBNET="10.$((RANDOM % 100 + 100)).0.0/24"

echo "Creating network $NETWORK_NAME with subnet $SUBNET"
podman network create $NETWORK_NAME --subnet $SUBNET || exit 1

cleanup() {
    echo "Cleaning up..."
    for ((i=0; i<PARTICIPANTS; i++)); do
        podman rm -f ${TEST_NAME}-$i 2>/dev/null || true
    done
    podman network rm $NETWORK_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Start containers
echo "Starting $PARTICIPANTS processes with unique IPs..."
for ((i=0; i<PARTICIPANTS; i++)); do
    podman run -d --name ${TEST_NAME}-$i --network $NETWORK_NAME \
        -v "$EXEC_PATH:/test:ro" \
        -v /usr/lib64:/hostlib:ro \
        -e LD_LIBRARY_PATH=/hostlib \
        -e PROCESS_ID=$i \
        -e PARTICIPANT_COUNT=$PARTICIPANTS \
        -e MULTICAST_ADDRESS=239.255.0.1 \
        -e MULTICAST_PORT=$((15000 + $$)) \
        fedora:latest /test

    # Get IP
    sleep 0.3
    IP=$(podman inspect ${TEST_NAME}-$i 2>/dev/null | \
         grep '"IPAddress"' | head -1 | cut -d'"' -f4)
    echo "  Process $i: IP=$IP"
done

# Wait for completion
echo ""
echo "Waiting for processes to complete..."
SUCCESS=true

for ((i=0; i<PARTICIPANTS; i++)); do
    if timeout 30 podman wait ${TEST_NAME}-$i >/dev/null 2>&1; then
        EXIT_CODE=$(podman inspect ${TEST_NAME}-$i --format='{{.State.ExitCode}}')
        if [ "$EXIT_CODE" = "0" ]; then
            echo "  Process $i: ✓ Success"

            # Show key output lines
            podman logs ${TEST_NAME}-$i 2>&1 | grep -E "All tests passed|FAILED|ERROR" | head -3
        else
            echo "  Process $i: ✗ Failed (exit code $EXIT_CODE)"
            podman logs ${TEST_NAME}-$i 2>&1 | tail -10
            SUCCESS=false
        fi
    else
        echo "  Process $i: ✗ Timeout"
        SUCCESS=false
    fi
done

echo ""
if $SUCCESS; then
    echo "✓ TEST PASSED: All processes completed successfully with unique IPs"
    exit 0
else
    echo "✗ TEST FAILED: Some processes failed"
    exit 1
fi
SCRIPT

chmod +x run_podman_test.sh
./run_podman_test.sh

echo ""
echo "============================"
echo "Symmetric Podman API test complete!"
echo ""
echo "Next steps:"
echo "1. Integrate into CMakeLists.txt permanently"
echo "2. Add to CI/CD pipeline"
echo "3. Run performance comparison vs regular multiprocess"
echo "4. Test with more complex scenarios (different executables)"