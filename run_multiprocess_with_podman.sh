#!/bin/bash
# Run multiprocess tests using rootless Podman for network isolation
# This provides a userspace alternative to bwrap that supports networking

set -e

print_usage() {
    echo "Usage: $0 <executable> <participant_count> [options]"
    echo ""
    echo "Options:"
    echo "  --multicast-addr ADDRESS   Multicast address (default: 239.255.0.1)"
    echo "  --multicast-port PORT      Multicast port (default: 15000)"
    echo "  --timeout SECONDS          Test timeout (default: 10)"
    echo "  --use-pod                  Use Podman pod with shared namespace"
    echo "  --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 ./boost_ut_test 3"
    echo "  $0 ./gtest_example 2 --multicast-port 15001"
    echo "  $0 ./doctest_test 4 --use-pod"
}

# Parse arguments
EXECUTABLE=""
PARTICIPANT_COUNT=""
MULTICAST_ADDR="239.255.0.1"
MULTICAST_PORT="15000"
TIMEOUT=10
USE_POD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --multicast-addr)
            MULTICAST_ADDR="$2"
            shift 2
            ;;
        --multicast-port)
            MULTICAST_PORT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --use-pod)
            USE_POD=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            if [[ -z "$EXECUTABLE" ]]; then
                EXECUTABLE="$1"
            elif [[ -z "$PARTICIPANT_COUNT" ]]; then
                PARTICIPANT_COUNT="$1"
            else
                echo "Error: Unexpected argument: $1"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$EXECUTABLE" ]] || [[ -z "$PARTICIPANT_COUNT" ]]; then
    echo "Error: Missing required arguments"
    print_usage
    exit 1
fi

if [[ ! -f "$EXECUTABLE" ]]; then
    echo "Error: Executable not found: $EXECUTABLE"
    exit 1
fi

# Make executable absolute path
EXECUTABLE=$(realpath "$EXECUTABLE")

echo "Running multiprocess test with rootless Podman"
echo "=============================================="
echo "Executable: $EXECUTABLE"
echo "Participants: $PARTICIPANT_COUNT"
echo "Multicast: $MULTICAST_ADDR:$MULTICAST_PORT"
echo "Timeout: ${TIMEOUT}s"
echo ""

if $USE_POD; then
    echo "Mode: Podman pod with shared network namespace"
    echo "----------------------------------------------"

    # Create a unique pod name
    POD_NAME="multiprocess-test-$$"

    # Create the pod
    podman pod create --name "$POD_NAME" > /dev/null

    # Start all processes in the pod
    CONTAINER_IDS=()
    for ((i=0; i<PARTICIPANT_COUNT; i++)); do
        CONTAINER_ID=$(podman run -d --pod "$POD_NAME" \
            -v "$EXECUTABLE:/test:ro" \
            -e PROCESS_ID=$i \
            -e PARTICIPANT_COUNT=$PARTICIPANT_COUNT \
            -e MULTICAST_ADDRESS=$MULTICAST_ADDR \
            -e MULTICAST_PORT=$MULTICAST_PORT \
            alpine:latest /test)
        CONTAINER_IDS+=("$CONTAINER_ID")
        echo "Started process $i (container ${CONTAINER_ID:0:12})"
    done

    # Wait for completion or timeout
    SECONDS=0
    while [[ $SECONDS -lt $TIMEOUT ]]; do
        ALL_DONE=true
        for CID in "${CONTAINER_IDS[@]}"; do
            if podman ps -q | grep -q "$CID"; then
                ALL_DONE=false
                break
            fi
        done

        if $ALL_DONE; then
            break
        fi

        sleep 1
    done

    # Collect results
    echo ""
    echo "Results:"
    echo "--------"
    SUCCESS=true
    for ((i=0; i<PARTICIPANT_COUNT; i++)); do
        CID="${CONTAINER_IDS[$i]}"
        echo "Process $i:"
        OUTPUT=$(podman logs "$CID" 2>&1 | tail -5)
        echo "$OUTPUT"

        if ! echo "$OUTPUT" | grep -q "All tests passed\|PASSED\|Success"; then
            SUCCESS=false
        fi
        echo ""
    done

    # Cleanup
    podman pod rm -f "$POD_NAME" > /dev/null 2>&1

    if $SUCCESS; then
        echo "✓ All processes completed successfully"
        exit 0
    else
        echo "✗ Some processes failed"
        exit 1
    fi

else
    echo "Mode: Podman unshare with shared network"
    echo "-----------------------------------------"

    # Use podman unshare to run all processes in the same namespace
    timeout "$TIMEOUT" podman unshare -- bash -c "
        PIDS=()

        # Start all processes
        for ((i=0; i<$PARTICIPANT_COUNT; i++)); do
            PROCESS_ID=\$i PARTICIPANT_COUNT=$PARTICIPANT_COUNT \\
            MULTICAST_ADDRESS=$MULTICAST_ADDR MULTICAST_PORT=$MULTICAST_PORT \\
                '$EXECUTABLE' &
            PIDS+=(\$!)
            echo \"Started process \$i (PID \${PIDS[\$i]})\"
        done

        # Wait for all processes
        SUCCESS=true
        for PID in \"\${PIDS[@]}\"; do
            if ! wait \$PID; then
                SUCCESS=false
            fi
        done

        if \$SUCCESS; then
            echo ''
            echo '✓ All processes completed successfully'
            exit 0
        else
            echo ''
            echo '✗ Some processes failed'
            exit 1
        fi
    "

    exit $?
fi