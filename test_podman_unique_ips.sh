#!/bin/bash
# Test that demonstrates each container gets a unique IP address
# This is what enables testing multiple clients from different IPs

set -e

echo "Demonstrating unique IP addresses per container with rootless Podman"
echo "===================================================================="

# Build container image with required libraries
echo "Building container image with boost libraries..."
podman build -t multiprocess-test -f Containerfile .

# Build test executable
cd /home/ai-dev1/repos/ut/build
make boost_ut_network_coordination

# Create network
NETWORK_NAME="test-net-$$"
echo ""
echo "Creating podman network: $NETWORK_NAME"
podman network create $NETWORK_NAME

echo ""
echo "Network details:"
podman network inspect $NETWORK_NAME | jq '.[] | {name: .name, subnet: .subnets[0].subnet, gateway: .subnets[0].gateway}'

# Start 3 containers on the network
echo ""
echo "Starting 3 containers on the network..."
echo "----------------------------------------"

for i in 1 2 3; do
    podman run -d --name client-$i --network $NETWORK_NAME \
        -v $(pwd)/example/multiprocess/boost_ut_network_coordination:/app/test:ro \
        multiprocess-test
done

# Get and display IP addresses
echo ""
echo "Container IP addresses:"
echo "----------------------"

declare -a IPS
for i in 1 2 3; do
    IP=$(podman inspect client-$i | jq -r '.[0].NetworkSettings.Networks["'$NETWORK_NAME'"].IPAddress')
    IPS+=($IP)
    echo "client-$i: $IP"
done

# Check uniqueness
echo ""
UNIQUE_COUNT=$(printf '%s\n' "${IPS[@]}" | sort -u | wc -l)
TOTAL_COUNT=${#IPS[@]}

if [ "$UNIQUE_COUNT" -eq "$TOTAL_COUNT" ]; then
    echo "✓ SUCCESS: All $TOTAL_COUNT containers have unique IP addresses!"
else
    echo "✗ FAILURE: Only $UNIQUE_COUNT unique IPs out of $TOTAL_COUNT containers"
fi

# Now demonstrate a server-client scenario
echo ""
echo "Server-Client Test with Different Source IPs"
echo "--------------------------------------------"

# Create simple server that logs client IPs
cat > /tmp/server.py << 'EOF'
#!/usr/bin/env python3
import socket
import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <port>")
    sys.exit(1)

port = int(sys.argv[1])
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', port))
server.listen(5)

print(f"Server listening on 0.0.0.0:{port}")
print("Waiting for 3 clients...")

client_ips = set()
for i in range(3):
    client_sock, addr = server.accept()
    client_ips.add(addr[0])
    print(f"Client {i+1} connected from {addr[0]}:{addr[1]}")
    client_sock.send(b"Hello from server\n")
    client_sock.close()

print(f"\nUnique client IPs: {len(client_ips)}")
for ip in sorted(client_ips):
    print(f"  - {ip}")

if len(client_ips) == 3:
    print("SUCCESS: All clients had different IPs!")
else:
    print(f"FAILURE: Expected 3 different IPs, got {len(client_ips)}")

server.close()
EOF

# Start server container
echo "Starting server container..."
podman run -d --name server --network $NETWORK_NAME \
    -v /tmp/server.py:/server.py:ro \
    python:3-slim python /server.py 8080

SERVER_IP=$(podman inspect server | jq -r '.[0].NetworkSettings.Networks["'$NETWORK_NAME'"].IPAddress')
echo "Server IP: $SERVER_IP"

# Give server time to start
sleep 2

# Start client connections from different containers
echo ""
echo "Connecting clients from different containers..."
for i in 1 2 3; do
    podman run -d --name tcp-client-$i --network $NETWORK_NAME \
        python:3-slim sh -c "sleep $i; python -c \"
import socket
s = socket.socket()
s.connect(('$SERVER_IP', 8080))
print(f'Connected from {s.getsockname()}')
data = s.recv(1024)
print(f'Received: {data.decode().strip()}')
s.close()
\""
done

# Wait and show server output
sleep 5
echo ""
echo "Server output:"
podman logs server

# Cleanup
echo ""
echo "Cleaning up..."
podman rm -f client-1 client-2 client-3 server tcp-client-1 tcp-client-2 tcp-client-3 2>/dev/null
podman network rm $NETWORK_NAME 2>/dev/null

echo ""
echo "===================================================================="
echo "This demonstrates that rootless Podman gives each container a"
echo "unique IP address, enabling testing of multiple clients connecting"
echo "to the same server:port from different source IPs - exactly what"
echo "you need for realistic network testing!"