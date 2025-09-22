#!/bin/bash
# Test multiple clients with different IPs connecting to same server:port
# Uses rootless podman to create a network where each container gets its own IP

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

echo ""
echo "Starting test scenario:"
echo "----------------------"
echo "Server will run on first container IP (typically .2 in the subnet)"
echo "Clients will connect from different IPs (.3, .4, etc.)"
echo ""

# Test 1: Simple TCP server/client test
cat > /tmp/tcp_server.cpp << 'EOF'
#include <iostream>
#include <boost/asio.hpp>
#include <thread>
#include <vector>
#include <set>

using boost::asio::ip::tcp;

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <port> <expected_clients>\n";
        return 1;
    }

    int port = std::atoi(argv[1]);
    int expected_clients = std::atoi(argv[2]);

    try {
        boost::asio::io_context io_context;
        tcp::acceptor acceptor(io_context, tcp::endpoint(tcp::v4(), port));

        std::cout << "Server listening on port " << port << "\n";
        std::cout << "Waiting for " << expected_clients << " clients...\n";

        std::set<std::string> client_ips;

        for (int i = 0; i < expected_clients; ++i) {
            tcp::socket socket(io_context);
            acceptor.accept(socket);

            std::string client_ip = socket.remote_endpoint().address().to_string();
            int client_port = socket.remote_endpoint().port();

            client_ips.insert(client_ip);

            std::cout << "Client " << (i+1) << " connected from "
                      << client_ip << ":" << client_port << "\n";

            // Send acknowledgment
            std::string msg = "Hello from server\n";
            boost::asio::write(socket, boost::asio::buffer(msg));
        }

        std::cout << "\nUnique client IPs: " << client_ips.size() << "\n";
        for (const auto& ip : client_ips) {
            std::cout << "  - " << ip << "\n";
        }

        if (client_ips.size() == expected_clients) {
            std::cout << "SUCCESS: All clients had different IPs!\n";
            return 0;
        } else {
            std::cout << "FAILURE: Expected " << expected_clients
                      << " different IPs, got " << client_ips.size() << "\n";
            return 1;
        }

    } catch (std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}
EOF

cat > /tmp/tcp_client.cpp << 'EOF'
#include <iostream>
#include <boost/asio.hpp>
#include <thread>

using boost::asio::ip::tcp;

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <server_ip> <port> <client_id>\n";
        return 1;
    }

    std::string server_ip = argv[1];
    int port = std::atoi(argv[2]);
    int client_id = std::atoi(argv[3]);

    // Small delay to ensure server is ready
    std::this_thread::sleep_for(std::chrono::milliseconds(500 + client_id * 100));

    try {
        boost::asio::io_context io_context;

        tcp::socket socket(io_context);
        tcp::resolver resolver(io_context);

        std::cout << "Client " << client_id << " connecting to "
                  << server_ip << ":" << port << "\n";

        boost::asio::connect(socket,
            resolver.resolve(server_ip, std::to_string(port)));

        // Get our local IP
        std::string local_ip = socket.local_endpoint().address().to_string();
        std::cout << "Client " << client_id << " connected from "
                  << local_ip << "\n";

        // Read server response
        boost::asio::streambuf buf;
        boost::asio::read_until(socket, buf, "\n");

        std::cout << "Client " << client_id << " received: "
                  << &buf << std::endl;

        return 0;

    } catch (std::exception& e) {
        std::cerr << "Client " << client_id << " error: " << e.what() << "\n";
        return 1;
    }
}
EOF

# Compile test programs
echo "Compiling test programs..."
g++ -o /tmp/tcp_server /tmp/tcp_server.cpp -lboost_system -pthread
g++ -o /tmp/tcp_client /tmp/tcp_client.cpp -lboost_system -pthread

echo ""
echo "Test 1: Multiple clients with different IPs"
echo "--------------------------------------------"

# Start server container (will get IP 10.88.0.2)
echo "Starting server container..."
podman run -d --name test-server --network $NETWORK_NAME \
    -v /tmp/tcp_server:/tcp_server:ro \
    alpine:latest sh -c "/tcp_server 8080 3 && sleep 2"

# Get server IP
SERVER_IP=$(podman inspect test-server | grep -m1 '"IPAddress"' | cut -d'"' -f4)
echo "Server IP: $SERVER_IP"

# Start client containers (each will get a different IP)
echo "Starting client containers..."
for i in 1 2 3; do
    podman run -d --name test-client-$i --network $NETWORK_NAME \
        -v /tmp/tcp_client:/tcp_client:ro \
        alpine:latest /tcp_client $SERVER_IP 8080 $i

    CLIENT_IP=$(podman inspect test-client-$i | grep -m1 '"IPAddress"' | cut -d'"' -f4)
    echo "Client $i IP: $CLIENT_IP"
done

# Wait and show results
sleep 3
echo ""
echo "Server output:"
podman logs test-server

echo ""
echo "Client outputs:"
for i in 1 2 3; do
    echo "Client $i:"
    podman logs test-client-$i
done

# Cleanup
echo ""
echo "Cleaning up..."
podman rm -f test-server test-client-1 test-client-2 test-client-3 2>/dev/null || true

echo ""
echo "Test 2: Multiprocess coordination with unique IPs"
echo "-------------------------------------------------"

# Now test our multiprocess coordination with each process having unique IP
NUM_PROCESSES=3

echo "Starting $NUM_PROCESSES processes, each with its own IP..."

for i in $(seq 0 $((NUM_PROCESSES-1))); do
    podman run -d --name mp-test-$i --network $NETWORK_NAME \
        -v $(pwd)/example/multiprocess/boost_ut_network_coordination:/test:ro \
        -e PROCESS_ID=$i \
        -e PARTICIPANT_COUNT=$NUM_PROCESSES \
        -e MULTICAST_ADDRESS=239.255.0.1 \
        -e MULTICAST_PORT=15000 \
        alpine:latest /test

    PROC_IP=$(podman inspect mp-test-$i | grep -m1 '"IPAddress"' | cut -d'"' -f4)
    echo "Process $i IP: $PROC_IP"
done

# Check results
sleep 5
echo ""
echo "Multiprocess test results:"
SUCCESS=true
for i in $(seq 0 $((NUM_PROCESSES-1))); do
    echo "Process $i:"
    OUTPUT=$(podman logs mp-test-$i 2>&1 | tail -3)
    echo "$OUTPUT"
    if ! echo "$OUTPUT" | grep -q "All tests passed"; then
        SUCCESS=false
    fi
done

# Cleanup
podman rm -f $(seq 0 $((NUM_PROCESSES-1)) | xargs -I{} echo mp-test-{}) 2>/dev/null || true
podman network rm $NETWORK_NAME

if $SUCCESS; then
    echo ""
    echo "✓ SUCCESS: All processes completed with different IPs"
else
    echo ""
    echo "✗ FAILURE: Some processes failed"
fi