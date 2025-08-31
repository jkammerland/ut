#!/bin/bash
#
# Simple bridge-based network coordination for boost.ut multiprocess testing
# Creates isolated namespaces connected via bridge for coordination
#

set -e

# Parse arguments
NS_NAME="$1"
VETH_NAME="$2" 
IP_ADDR="$3"
EXECUTABLE="$4"
shift 4

# Configuration
BRIDGE_NAME="ut_test_br0"
BRIDGE_IP="192.168.100.1/24"

# Check for required tools
for tool in ip bwrap; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool not found"
        exit 1
    fi
done

# Check if running as root (needed for network namespace operations)
if [ "$EUID" -ne 0 ]; then
    echo "This script needs to be run as root for network namespace operations"
    exit 1
fi

setup_bridge() {
    # Create bridge if it doesn't exist
    if ! ip link show "$BRIDGE_NAME" &> /dev/null; then
        echo "Creating bridge $BRIDGE_NAME"
        ip link add "$BRIDGE_NAME" type bridge
        ip addr add "$BRIDGE_IP" dev "$BRIDGE_NAME"
        ip link set "$BRIDGE_NAME" up
    fi
}

create_namespace_with_bridge() {
    # Create namespace if it doesn't exist
    if ! ip netns list | grep -q "^$NS_NAME$"; then
        echo "Creating namespace $NS_NAME with IP $IP_ADDR"
        ip netns add "$NS_NAME"
    fi
    
    # Create veth pair if it doesn't exist
    local host_veth="${VETH_NAME}_host"
    local ns_veth="${VETH_NAME}_ns"
    
    if ! ip link show "$host_veth" &> /dev/null; then
        # Create veth pair
        ip link add "$host_veth" type veth peer name "$ns_veth"
        
        # Move namespace end into namespace
        ip link set "$ns_veth" netns "$NS_NAME"
        
        # Connect host end to bridge
        ip link set "$host_veth" master "$BRIDGE_NAME"
        ip link set "$host_veth" up
        
        # Configure namespace end
        ip netns exec "$NS_NAME" ip addr add "$IP_ADDR/24" dev "$ns_veth"
        ip netns exec "$NS_NAME" ip link set "$ns_veth" up
        ip netns exec "$NS_NAME" ip link set lo up
        ip netns exec "$NS_NAME" ip route add default via "192.168.100.1"
        
        echo "Configured $NS_NAME with bridge connectivity"
    fi
}

cleanup() {
    echo "Cleaning up namespace $NS_NAME"
    ip link del "${VETH_NAME}_host" 2>/dev/null || true
    ip netns del "$NS_NAME" 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT

# Setup bridge and namespace
setup_bridge
create_namespace_with_bridge

# Run the executable in the network namespace with bwrap isolation
echo "Running $EXECUTABLE in namespace $NS_NAME"
exec ip netns exec "$NS_NAME" \
    bwrap \
        --share-net \
        --ro-bind /usr /usr \
        --ro-bind /lib /lib \
        --ro-bind /lib64 /lib64 \
        --ro-bind /bin /bin \
        --ro-bind /sbin /sbin \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --tmpfs /run \
        --setenv NETNS_NAME "$NS_NAME" \
        --setenv NETNS_IP "$IP_ADDR" \
        --setenv BRIDGE_IP "192.168.100.1" \
        --die-with-parent \
        "$EXECUTABLE" "$@"