#!/bin/bash
#
# Advanced network isolation with virtual ethernet pairs
# This allows processes to communicate while having separate network stacks
#
# Usage: ./run_with_veth.sh <namespace_name> <veth_name> <ip_address> <executable> [args...]
#

set -e

NAMESPACE="$1"
VETH_NAME="$2"
IP_ADDRESS="$3"
EXECUTABLE="$4"
shift 4

# Check for required tools
for tool in ip bwrap; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: $tool not found"
        exit 1
    fi
done

# Check if running as root (needed for network namespace operations)
if [ "$EUID" -ne 0 ]; then
    echo "This script needs to be run as root for network namespace operations"
    echo "Alternatively, use run_with_netns.sh for unprivileged operation"
    exit 1
fi

# Create network namespace if it doesn't exist
if ! ip netns list | grep -q "^$NAMESPACE$"; then
    ip netns add "$NAMESPACE"
fi

# Create veth pair if it doesn't exist
VETH_PEER="${VETH_NAME}_peer"
if ! ip link show "$VETH_NAME" &> /dev/null; then
    # Create veth pair
    ip link add "$VETH_NAME" type veth peer name "$VETH_PEER"
    
    # Move one end to the namespace
    ip link set "$VETH_PEER" netns "$NAMESPACE"
    
    # Configure the host end
    ip addr add "${IP_ADDRESS%.*}.1/24" dev "$VETH_NAME"
    ip link set "$VETH_NAME" up
    
    # Configure the namespace end
    ip netns exec "$NAMESPACE" ip addr add "$IP_ADDRESS/24" dev "$VETH_PEER"
    ip netns exec "$NAMESPACE" ip link set "$VETH_PEER" up
    ip netns exec "$NAMESPACE" ip link set lo up
    
    # Add default route in namespace
    ip netns exec "$NAMESPACE" ip route add default via "${IP_ADDRESS%.*}.1"
    
    # Enable IP forwarding if needed
    echo 1 > /proc/sys/net/ipv4/ip_forward
fi

# Run the executable in the network namespace
# Using bwrap for additional isolation while sharing the network namespace
exec ip netns exec "$NAMESPACE" \
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
        --setenv NETNS_NAME "$NAMESPACE" \
        --setenv NETNS_IP "$IP_ADDRESS" \
        --die-with-parent \
        "$EXECUTABLE" "$@"

# Cleanup function (not reached due to exec)
cleanup() {
    ip link del "$VETH_NAME" 2>/dev/null || true
    ip netns del "$NAMESPACE" 2>/dev/null || true
}