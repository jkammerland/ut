#!/bin/bash
# Test multiple clients with different IPs connecting to same server:port
# Uses rootless podman with ubuntu containers that have required libraries

set -e

echo "Testing multiple clients with different IPs using rootless Podman"
echo "================================================================="

# Build test executable
cd /home/ai-dev1/repos/ut/build
make boost_ut_network_coordination

# Create a custom podman network (each container will get a unique IP)
NETWORK_NAME="multitest-net-$$"
echo "Creating podman network: $NETWORK_NAME"

# Generate random subnet to avoid conflicts
SUBNET="10.$((RANDOM % 100 + 100)).0.0/24"
echo "Using subnet: $SUBNET"
podman network create $NETWORK_NAME --subnet $SUBNET

# Show network info
echo "Network configuration:"
podman network inspect $NETWORK_NAME | grep -E '"subnet"|"gateway"'

# Test with our multiprocess coordination (each process gets unique IP)
echo ""
echo "Test: Multiprocess coordination with unique IPs"
echo "-----------------------------------------------"

NUM_PROCESSES=3

# We need ubuntu with boost libraries
# First, let's use the existing executable that's already built
EXEC_PATH=$(pwd)/example/multiprocess/boost_ut_network_coordination

echo "Starting $NUM_PROCESSES processes, each in a container with its own IP..."

# Start containers (ubuntu has the required glibc and we'll bind mount libraries)
CONTAINER_IDS=()
for i in $(seq 0 $((NUM_PROCESSES-1))); do
    # Use ubuntu and bind mount the required libraries and executable
    CID=$(podman run -d --name mp-test-$i --network $NETWORK_NAME \
        -v $EXEC_PATH:/test:ro \
        -v /usr/lib/x86_64-linux-gnu:/host/lib:ro \
        -e LD_LIBRARY_PATH=/host/lib \
        -e PROCESS_ID=$i \
        -e PARTICIPANT_COUNT=$NUM_PROCESSES \
        -e MULTICAST_ADDRESS=239.255.0.1 \
        -e MULTICAST_PORT=15000 \
        ubuntu:22.04 /test)

    CONTAINER_IDS+=($CID)

    # Get container IP
    sleep 0.5  # Give container time to get IP
    PROC_IP=$(podman inspect mp-test-$i 2>/dev/null | grep '"IPAddress"' | head -1 | cut -d'"' -f4)
    echo "Process $i started - Container IP: $PROC_IP"
done

# Wait for completion
echo ""
echo "Waiting for processes to complete..."
sleep 5

# Check results
echo ""
echo "Results:"
echo "--------"

SUCCESS=true
UNIQUE_IPS=()

for i in $(seq 0 $((NUM_PROCESSES-1))); do
    echo ""
    echo "Process $i:"

    # Get IP address
    PROC_IP=$(podman inspect mp-test-$i 2>/dev/null | grep '"IPAddress"' | head -1 | cut -d'"' -f4)
    if [ -n "$PROC_IP" ]; then
        echo "  IP Address: $PROC_IP"
        UNIQUE_IPS+=($PROC_IP)
    fi

    # Get logs
    echo "  Output:"
    OUTPUT=$(podman logs mp-test-$i 2>&1 | tail -5)
    echo "$OUTPUT" | sed 's/^/    /'

    if ! echo "$OUTPUT" | grep -q "All tests passed"; then
        SUCCESS=false
    fi
done

# Check if all IPs are unique
echo ""
echo "IP Address Summary:"
echo "-------------------"
UNIQUE_COUNT=$(printf '%s\n' "${UNIQUE_IPS[@]}" | sort -u | wc -l)
echo "Total containers: $NUM_PROCESSES"
echo "Unique IP addresses: $UNIQUE_COUNT"

if [ "$UNIQUE_COUNT" -eq "$NUM_PROCESSES" ]; then
    echo "✓ Each container has a unique IP address!"
    for ip in "${UNIQUE_IPS[@]}"; do
        echo "  - $ip"
    done
else
    echo "✗ Not all containers have unique IPs"
fi

# Cleanup
echo ""
echo "Cleaning up..."
podman rm -f $(seq 0 $((NUM_PROCESSES-1)) | xargs -I{} echo mp-test-{}) 2>/dev/null || true
podman network rm $NETWORK_NAME 2>/dev/null || true

if $SUCCESS && [ "$UNIQUE_COUNT" -eq "$NUM_PROCESSES" ]; then
    echo ""
    echo "✓ SUCCESS: All processes completed with different IPs"
    exit 0
else
    echo ""
    if ! $SUCCESS; then
        echo "✗ FAILURE: Some processes failed to complete tests"
    fi
    if [ "$UNIQUE_COUNT" -ne "$NUM_PROCESSES" ]; then
        echo "✗ FAILURE: Not all processes had unique IPs"
    fi
    exit 1
fi