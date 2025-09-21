//
// ID-based multiprocess test coordination with UDP multicast
// Each process has ID [0, N-1], ID 0 acts as coordinator
//
#include <boost/ut.hpp>
#include <boost/asio.hpp>
#include <iostream>
#include <string>
#include <cstdlib>
#include <vector>
#include <thread>
#include <functional>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <unordered_set>
#include <chrono>
#include <sstream>

using namespace boost::ut;

// Get environment variables
std::string get_env(const char* name, const std::string& default_val = "") {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

using event_handler_t = std::function<void(const std::vector<std::byte>&)>;

// ID-based multiprocess test fixture with coordinator pattern
template<bool wait_for_all = true>
class multiprocess_fixture {
    boost::asio::io_context io_context_;
    boost::asio::ip::udp::socket multicast_socket_;
    boost::asio::ip::udp::endpoint multicast_endpoint_;
    
    int my_id_;
    int participant_count_;
    
    // Coordinator state (ID 0 only)
    std::mutex coord_mutex_;
    std::unordered_set<int> registered_ids_;
    std::jthread coordinator_thread_;
    
    // Participant state
    std::mutex sync_mutex_;
    std::condition_variable sync_cv_;
    std::unordered_set<int> seen_ready_ids_;
    bool my_id_registered_{false};  // Protected by sync_mutex_
    
    // Common state
    std::jthread io_thread_;
    std::array<std::byte, 500> receive_buffer_;
    
public:
    multiprocess_fixture(int my_id, 
                        int participant_count,
                        const std::string& multicast_address = "239.255.0.1",
                        int multicast_port = 12345)
        : multicast_socket_(io_context_)
        , multicast_endpoint_(boost::asio::ip::make_address(multicast_address), multicast_port)
        , my_id_(my_id)
        , participant_count_(participant_count)
    {
        // Setup multicast socket
        multicast_socket_.open(boost::asio::ip::udp::v4());
        multicast_socket_.set_option(boost::asio::ip::udp::socket::reuse_address(true));
        multicast_socket_.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), multicast_port));
        
        // Join multicast group
        multicast_socket_.set_option(
            boost::asio::ip::multicast::join_group(
                boost::asio::ip::make_address(multicast_address)));
        
        // Start receiving
        start_receive();
        io_thread_ = std::jthread([this](std::stop_token st) { 
            while (!st.stop_requested()) {
                io_context_.run_one();
            }
        });
        
        // ID 0 always coordinates
        if (my_id_ == 0) {
            std::cout << "[ID 0] Starting coordinator thread" << std::endl;
            coordinator_thread_ = std::jthread([this](std::stop_token st) { 
                coordinator_loop(st); 
            });
        }
    }
    
    ~multiprocess_fixture() {
        // First request stop on all threads
        if (coordinator_thread_.joinable()) {
            coordinator_thread_.request_stop();
        }
        if (io_thread_.joinable()) {
            io_thread_.request_stop();
        }

        // Then stop io_context to break any blocking operations
        io_context_.stop();

        // jthread destructors will now join safely
    }
    
    // Synchronization point - waits until all participants ready (or just self if !wait_for_all)
    void sync_point(const std::string& checkpoint_name = "default") {
        // Prepare registration message
        std::string reg_msg = "REG:" + std::to_string(my_id_);
        
        // Use jthread for registration sender
        std::jthread registration_sender([this, reg_msg](std::stop_token st) {
            while (!st.stop_requested()) {
                send_message(reg_msg);
                std::this_thread::sleep_for(std::chrono::milliseconds(200));  // Send every 200ms
            }
        });
        
        if constexpr (wait_for_all) {
            // Wait until we see our ID in the ready list AND all IDs are ready
            std::unique_lock<std::mutex> lock(sync_mutex_);
            bool success = sync_cv_.wait_for(lock, std::chrono::seconds(30), [this] {
                return my_id_registered_ && 
                       seen_ready_ids_.size() >= static_cast<size_t>(participant_count_);
            });
            
            if (!success) {
                std::stringstream ss;
                ss << "Sync timeout at checkpoint. My ID: " << my_id_ 
                   << ", Registered: " << my_id_registered_
                   << ", Seen ready: ";
                for (int id : seen_ready_ids_) {
                    ss << id << " ";
                }
                throw std::runtime_error(ss.str());
            }
        } else {
            // Just wait until we see our own ID registered
            std::unique_lock<std::mutex> lock(sync_mutex_);
            bool success = sync_cv_.wait_for(lock, std::chrono::seconds(10), [this] {
                return my_id_registered_;
            });
            
            if (!success) {
                throw std::runtime_error("Timeout waiting for self-registration. ID: " + 
                                       std::to_string(my_id_));
            }
        }
        
        std::cout << "[ID " << my_id_ << "] Synchronized at checkpoint: " << checkpoint_name << std::endl;
        // registration_sender jthread automatically stops and joins when it goes out of scope
    }
    
    // Send arbitrary data (for testing)
    void send_event(const std::vector<std::byte>& data) {
        if (data.size() > 500) {
            throw std::runtime_error("Event data too large (max 500 bytes)");
        }
        
        multicast_socket_.send_to(
            boost::asio::buffer(data.data(), data.size()),
            multicast_endpoint_);
    }
    
private:
    void send_message(const std::string& msg) {
        std::vector<std::byte> data;
        data.reserve(msg.size());
        for (char c : msg) {
            data.push_back(static_cast<std::byte>(c));
        }
        send_event(data);
    }
    
    void coordinator_loop(std::stop_token st) {
        // Only ID 0 runs this - continuously broadcast ready list
        // Register coordinator itself first
        {
            std::lock_guard<std::mutex> lock(coord_mutex_);
            registered_ids_.insert(0);  // Coordinator must register itself
        }
        
        while (!st.stop_requested()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            
            // Build and send ready list
            std::stringstream ss;
            ss << "READY:";
            {
                std::lock_guard<std::mutex> lock(coord_mutex_);
                bool first = true;
                for (int id : registered_ids_) {
                    if (!first) ss << ",";
                    ss << id;
                    first = false;
                }
            }
            
            send_message(ss.str());
        }
    }
    
    void handle_message(const std::vector<std::byte>& data) {
        // Validate we have data
        if (data.empty()) {
            return;  // Ignore empty messages
        }

        std::string msg(reinterpret_cast<const char*>(data.data()), data.size());

        // Find colon separator for message type validation
        auto colon_pos = msg.find(':');
        if (colon_pos == std::string::npos || colon_pos == 0) {
            return;  // Invalid format - no colon or starts with colon
        }

        std::string msg_type = msg.substr(0, colon_pos);
        std::string msg_data = msg.substr(colon_pos + 1);

        if (msg_type == "REG") {
            // Registration message from a participant
            if (msg_data.empty()) {
                return;  // Empty ID not allowed
            }

            try {
                int id = std::stoi(msg_data);

                if (id < 0 || id >= participant_count_) {
                    // Invalid ID, ignore
                    return;
                }

                if (my_id_ == 0) {
                    // Coordinator records the registration
                    std::lock_guard<std::mutex> lock(coord_mutex_);
                    registered_ids_.insert(id);
                    std::cout << "[Coordinator] Registered ID " << id
                             << " (total: " << registered_ids_.size() << ")" << std::endl;
                }
            } catch (const std::exception&) {
                // Non-numeric ID, ignore
                return;
            }
        }
        else if (msg_type == "READY") {
            // Ready list from coordinator
            std::unordered_set<int> ready_ids;

            // Parse comma-separated IDs
            if (!msg_data.empty()) {
                std::stringstream ss(msg_data);
                std::string id_str;
                while (std::getline(ss, id_str, ',')) {
                    if (!id_str.empty()) {
                        try {
                            ready_ids.insert(std::stoi(id_str));
                        } catch (const std::exception&) {
                            // Malformed ID, skip it
                        }
                    }
                }
            }

            // Update our view of ready participants
            {
                std::lock_guard<std::mutex> lock(sync_mutex_);
                seen_ready_ids_ = ready_ids;

                // Check if our ID is in the ready list
                if (ready_ids.count(my_id_) > 0) {
                    my_id_registered_ = true;
                }

                // Wake up any waiters
                sync_cv_.notify_all();
            }
        }
    }
    
    void start_receive() {
        multicast_socket_.async_receive(
            boost::asio::buffer(receive_buffer_),
            [this](const boost::system::error_code& error, std::size_t bytes_received) {
                if (!error) {
                    std::vector<std::byte> event_data(receive_buffer_.begin(), 
                                                     receive_buffer_.begin() + bytes_received);
                    handle_message(event_data);
                }
                
                if (!io_context_.stopped()) {
                    start_receive();
                }
            });
    }
};

int main() {
    // Get process ID from environment
    auto id_str = get_env("PROCESS_ID");
    auto role = get_env("PROCESS_ROLE");  // Optional, for backward compatibility
    auto my_ip = get_env("SIMULATED_IP");
    
    int my_id = -1;
    
    // First try PROCESS_ID (new way)
    if (!id_str.empty()) {
        try {
            my_id = std::stoi(id_str);
            if (my_id < 0) {
                std::cerr << "PROCESS_ID must be non-negative: " << id_str << std::endl;
                return 1;
            }
        } catch (...) {
            std::cerr << "Invalid PROCESS_ID (must be a number): " << id_str << std::endl;
            return 1;
        }
    }
    // Fall back to role mapping (backward compatibility)
    else if (!role.empty()) {
        if (role == "coordinator" || role == "server") {
            my_id = 0;
        } else if (role == "client") {
            my_id = 1;
        } else if (role == "worker") {
            my_id = 2;
        } else {
            // Try to parse ID from role if it's numeric
            try {
                my_id = std::stoi(role);
            } catch (...) {
                std::cerr << "Cannot determine ID from role: " << role << std::endl;
                return 1;
            }
        }
    } else {
        std::cerr << "Neither PROCESS_ID nor PROCESS_ROLE is set" << std::endl;
        return 1;
    }
    
    "environment setup"_test = [&] {
        expect(my_id >= 0) << "ID should be valid";
        
        if (!role.empty()) {
            std::cout << "Process: " << role << " (ID " << my_id << ")";
        } else {
            std::cout << "Process ID " << my_id;
        }
        if (!my_ip.empty()) {
            std::cout << " at " << my_ip;
        }
        std::cout << std::endl;
    };
    
    // Get multicast configuration from environment
    auto port_str = get_env("MULTICAST_PORT", "12345");
    auto addr_str = get_env("MULTICAST_ADDRESS", "239.255.0.1");
    auto count_str = get_env("PARTICIPANT_COUNT", "2");
    
    int multicast_port = std::stoi(port_str);
    int participant_count = std::stoi(count_str);
    
    // Test with configured participants
    if (my_id >= 0 && my_id < participant_count) {
        "id-based synchronization"_test = [&] {
            // Create fixture - it will auto-detect coordinator mode
            multiprocess_fixture<true> fixture(my_id, participant_count, addr_str, multicast_port);
            
            std::cout << "[ID " << my_id << "] Waiting at sync point..." << std::endl;
            fixture.sync_point("test_start");
            
            // All participants are ready here
            std::cout << "[ID " << my_id << "] All participants ready!" << std::endl;
            
            // Send a test message
            std::string test_msg = "Test from ID " + std::to_string(my_id);
            std::vector<std::byte> event_data;
            for (char c : test_msg) {
                event_data.push_back(static_cast<std::byte>(c));
            }
            fixture.send_event(event_data);
            
            // Small delay for message exchange
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            
            expect(true) << "ID-based synchronization successful";
        };
        
        "self-registration only"_test = [&] {
            // Create fixture that only waits for self-registration
            multiprocess_fixture<false> fixture(my_id, participant_count, addr_str, multicast_port);
            
            std::cout << "[ID " << my_id << "] Checking self-registration..." << std::endl;
            fixture.sync_point("self_check");
            
            // We're registered but may not have all participants
            std::cout << "[ID " << my_id << "] Self registered successfully!" << std::endl;
            
            expect(true) << "Self-registration check successful";
        };
    }
    
    return 0;
}