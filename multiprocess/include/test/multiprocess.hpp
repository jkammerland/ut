#pragma once
// Multiprocess Testing Framework
// A standalone header-only library for multiprocess test coordination
// Compatible with any C++ testing framework (boost::ut, gtest, doctest, etc.)
//
// Copyright (c) 2025
// Distributed under the Boost Software License, Version 1.0.

#include <boost/asio.hpp>
#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <unordered_set>
#include <thread>
#include <chrono>
#include <sstream>
#include <cstdlib>
#include <iostream>
#include <array>
#include <memory>

namespace test::multiprocess {

// Version information
constexpr const char* version() { return "1.0.0"; }

// Get environment variables
inline std::string get_env(const char* name, const std::string& default_val = "") {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

using event_handler_t = std::function<void(const std::vector<std::byte>&)>;

// ID-based multiprocess test fixture with coordinator pattern
template<bool wait_for_all = true>
class fixture {
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
    fixture(int id, int count,
            const std::string& multicast_address = "239.255.0.1",
            int multicast_port = 12345)
        : multicast_socket_(io_context_),
          my_id_(id),
          participant_count_(count) {

        // Set up multicast endpoint
        multicast_endpoint_ = boost::asio::ip::udp::endpoint(
            boost::asio::ip::make_address(multicast_address), multicast_port);

        // Open socket
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
                try {
                    io_context_.run_one();
                } catch (...) {
                    // Ignore errors in IO thread
                }
            }
        });

        // ID 0 always coordinates
        if (my_id_ == 0) {
            coordinator_thread_ = std::jthread([this](std::stop_token st) {
                coordinator_loop(st);
            });
        }
    }

    ~fixture() {
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

    // Synchronization point - waits until all participants ready
    void sync_point(const std::string& checkpoint_name = "default") {
        // Prepare registration message
        std::string reg_msg = "REG:" + std::to_string(my_id_);

        // Use jthread for registration sender
        std::jthread registration_sender([this, reg_msg](std::stop_token st) {
            while (!st.stop_requested()) {
                send_message(reg_msg);
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
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
                ss << "Sync timeout at checkpoint: " << checkpoint_name
                   << ". My ID: " << my_id_
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
    }

    // Get process ID
    int get_id() const { return my_id_; }

    // Get total participant count
    int get_participant_count() const { return participant_count_; }

    // Check if this process is the coordinator
    bool is_coordinator() const { return my_id_ == 0; }

private:
    void send_message(const std::string& msg) {
        try {
            std::vector<std::byte> data(msg.begin(), msg.end());
            multicast_socket_.send_to(boost::asio::buffer(data), multicast_endpoint_);
        } catch (...) {
            // Ignore send errors
        }
    }

    void coordinator_loop(std::stop_token st) {
        while (!st.stop_requested()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));

            // Build ready list
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

            // Broadcast ready list
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

// Helper class to get process info from environment
class environment {
public:
    static int get_id() {
        auto id_str = get_env("PROCESS_ID");
        if (!id_str.empty()) {
            try {
                int id = std::stoi(id_str);
                if (id < 0) {
                    throw std::runtime_error("PROCESS_ID must be non-negative");
                }
                return id;
            } catch (...) {
                throw std::runtime_error("Invalid PROCESS_ID");
            }
        }
        throw std::runtime_error("PROCESS_ID not set");
    }

    static int get_participant_count() {
        auto count_str = get_env("PARTICIPANT_COUNT");
        if (!count_str.empty()) {
            try {
                int count = std::stoi(count_str);
                if (count <= 0) {
                    throw std::runtime_error("PARTICIPANT_COUNT must be positive");
                }
                return count;
            } catch (...) {
                throw std::runtime_error("Invalid PARTICIPANT_COUNT");
            }
        }
        throw std::runtime_error("PARTICIPANT_COUNT not set");
    }

    static std::string get_multicast_address() {
        return get_env("MULTICAST_ADDRESS", "239.255.0.1");
    }

    static int get_multicast_port() {
        auto port_str = get_env("MULTICAST_PORT", "12345");
        try {
            return std::stoi(port_str);
        } catch (...) {
            return 12345;
        }
    }
};

// Backwards compatibility aliases
using multiprocess_fixture = fixture<true>;
using process_info = environment;

} // namespace test::multiprocess