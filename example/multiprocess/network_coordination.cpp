//
// Simple multiprocess test fixture with UDP multicast events
// Uses Boost.ASIO and std::barrier for coordination
//
#include <boost/ut.hpp>
#include <boost/asio.hpp>
#include <iostream>
#include <string>
#include <cstdlib>
#include <vector>
#include <thread>
#include <barrier>
#include <functional>
#include <atomic>

using namespace boost::ut;

// Get environment variables
std::string get_env(const char* name, const std::string& default_val = "") {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

using event_handler_t = std::function<void(const std::vector<std::byte>&)>;

// Simple multiprocess test fixture with UDP multicast coordination
template<bool wait_after_arrive = true>
class multiprocess_fixture {
    boost::asio::io_context io_context_;
    boost::asio::ip::udp::socket multicast_socket_;
    boost::asio::ip::udp::endpoint multicast_endpoint_;
    int participant_count_;
    std::atomic<int> arrived_count_{0};
    event_handler_t event_handler_;
    std::thread io_thread_;
    std::atomic<bool> running_{true};
    std::array<std::byte, 500> receive_buffer_;
    std::string my_role_;
    
public:
    multiprocess_fixture(int participant_count, 
                        const std::string& role,
                        const std::string& multicast_address = "239.255.0.1",
                        int multicast_port = 12345,
                        event_handler_t handler = nullptr)
        : multicast_socket_(io_context_)
        , multicast_endpoint_(boost::asio::ip::make_address(multicast_address), multicast_port)
        , participant_count_(participant_count)
        , event_handler_(std::move(handler))
        , my_role_(role)
    {
        // Setup multicast socket
        multicast_socket_.open(boost::asio::ip::udp::v4());
        multicast_socket_.set_option(boost::asio::ip::udp::socket::reuse_address(true));
        multicast_socket_.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), multicast_port));
        
        // Join multicast group
        multicast_socket_.set_option(
            boost::asio::ip::multicast::join_group(
                boost::asio::ip::make_address(multicast_address)));
        
        // Start async receive if handler provided
        if (event_handler_) {
            start_receive();
            io_thread_ = std::thread([this]() { io_context_.run(); });
        }
    }
    
    ~multiprocess_fixture() {
        running_ = false;
        io_context_.stop();
        if (io_thread_.joinable()) {
            io_thread_.join();
        }
    }
    
    // Network-based synchronization point
    void sync_point(const std::string& barrier_name = "default") {
        // Send arrival notification
        std::string arrive_msg = "ARRIVE:" + barrier_name + ":" + my_role_;
        std::vector<std::byte> arrive_data;
        arrive_data.reserve(arrive_msg.size());
        for (char c : arrive_msg) {
            arrive_data.push_back(static_cast<std::byte>(c));
        }
        send_event(arrive_data);
        
        if constexpr (wait_after_arrive) {
            // Wait for all participants to arrive
            std::atomic<bool> barrier_released{false};
            int expected_arrivals = participant_count_;
            std::atomic<int> seen_arrivals{0};
            
            // Set up temporary event handler for barrier coordination
            auto old_handler = event_handler_;
            event_handler_ = [&](const std::vector<std::byte>& data) {
                std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
                if (msg.starts_with("ARRIVE:" + barrier_name + ":")) {
                    int count = ++seen_arrivals;
                    if (count >= expected_arrivals) {
                        barrier_released = true;
                    }
                }
                if (old_handler) old_handler(data);
            };
            
            // Wait for barrier release with timeout
            auto timeout = std::chrono::steady_clock::now() + std::chrono::seconds(10);
            while (!barrier_released && std::chrono::steady_clock::now() < timeout) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
            
            // Restore original handler
            event_handler_ = old_handler;
            
            if (!barrier_released) {
                throw std::runtime_error("Barrier timeout waiting for " + 
                                        std::to_string(expected_arrivals) + " participants");
            }
        }
    }
    
    // Send multicast event (max 500 bytes)
    void send_event(const std::vector<std::byte>& data) {
        if (data.size() > 500) {
            throw std::runtime_error("Event data too large (max 500 bytes)");
        }
        
        multicast_socket_.send_to(
            boost::asio::buffer(data.data(), data.size()),
            multicast_endpoint_);
    }
    
private:
    void start_receive() {
        multicast_socket_.async_receive(
            boost::asio::buffer(receive_buffer_),
            [this](const boost::system::error_code& error, std::size_t bytes_received) {
                if (!error && running_ && event_handler_) {
                    std::vector<std::byte> event_data(receive_buffer_.begin(), 
                                                     receive_buffer_.begin() + bytes_received);
                    event_handler_(event_data);
                }
                
                if (running_) {
                    start_receive();  // Continue receiving
                }
            });
    }
};

int main() {
    auto role = get_env("PROCESS_ROLE");
    auto my_ip = get_env("SIMULATED_IP");
    
    "environment setup"_test = [&] {
        expect(!role.empty()) << "Role should be set";
        expect(!my_ip.empty()) << "IP should be set";
        
        std::cout << "Process: " << role << " at " << my_ip << std::endl;
    };
    
    // Test multiprocess fixture with 2 participants (server + client)
    if (role != "coordinator") {
        "multiprocess synchronization"_test = [&] {
            // Event handler for network events
            auto event_handler = [role](const std::vector<std::byte>& data) {
                std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
                std::cout << "[" << role << "] Received event: " << msg << std::endl;
            };
            
            // Create fixture with 2 participants
            multiprocess_fixture<true> fixture(2, role, "239.255.0.1", 12345, event_handler);
            
            std::cout << "[" << role << "] Waiting at sync point..." << std::endl;
            fixture.sync_point();  // Wait for both processes
            
            // Send a test event
            std::string test_msg = "Hello from " + role;
            std::vector<std::byte> event_data;
            event_data.reserve(test_msg.size());
            for (char c : test_msg) {
                event_data.push_back(static_cast<std::byte>(c));
            }
            
            fixture.send_event(event_data);
            
            // Small delay to receive events
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            
            expect(true) << "Multiprocess fixture synchronization successful";
        };
    }
    
    // Test arrive-only mode
    if (role == "server") {
        "arrive only test"_test = [&] {
            multiprocess_fixture<false> fixture(2, role);  // arrive_and_drop mode
            
            std::cout << "[" << role << "] Arriving at sync point (no wait)..." << std::endl;
            fixture.sync_point();  // Don't wait, just arrive and continue
            
            expect(true) << "Arrive-only synchronization successful";
        };
    }
    
    return 0;
}