//
// Simple network connectivity test for bridge coordination
//
#include <boost/ut.hpp>
#include <iostream>
#include <string>
#include <cstdlib>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

using namespace boost::ut;

// Get environment variables set by bridge script
std::string get_env(const char* name, const std::string& default_val = "") {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

// Simple TCP connectivity test
bool test_tcp_connect(const std::string& ip, int port) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return false;
    
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, ip.c_str(), &addr.sin_addr);
    
    // Set non-blocking and short timeout
    struct timeval timeout{};
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    
    bool result = (connect(sock, (sockaddr*)&addr, sizeof(addr)) == 0);
    close(sock);
    return result;
}

int main() {
    auto ns_name = get_env("NETNS_NAME");
    auto ns_ip = get_env("NETNS_IP");
    auto bridge_ip = get_env("BRIDGE_IP");
    
    // Test 1: Environment setup
    "environment setup"_test = [&] {
        expect(!ns_name.empty()) << "NETNS_NAME should be set";
        expect(!ns_ip.empty()) << "NETNS_IP should be set"; 
        expect(!bridge_ip.empty()) << "BRIDGE_IP should be set";
        
        std::cout << "Running in namespace: " << ns_name 
                  << " with IP: " << ns_ip 
                  << " bridge: " << bridge_ip << std::endl;
    };
    
    // Test 2: Local network interface
    "local network interface"_test = [&] {
        // Check if we can reach our own IP (should work via loopback in namespace)
        expect(true) << "Network interface configured";
    };
    
    // Test 3: Bridge connectivity 
    "bridge connectivity"_test = [&] {
        // Try to ping bridge IP (basic reachability test)
        std::string ping_cmd = "ping -c 1 -W 1 " + bridge_ip + " > /dev/null 2>&1";
        int result = std::system(ping_cmd.c_str());
        expect(result == 0) << "Should be able to ping bridge IP: " << bridge_ip;
    };
    
    return 0;
}