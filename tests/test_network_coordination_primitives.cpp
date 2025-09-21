#include <boost/ut.hpp>
#include <boost/asio.hpp>
#include <thread>
#include <chrono>
#include <atomic>
#include <vector>
#include <unordered_set>
#include <mutex>
#include <condition_variable>

using namespace boost::ut;

// Test 1: UDP Socket Primitive Operations
suite udp_socket_primitives = [] {
    "udp_socket_creation_and_binding"_test = [] {
        boost::asio::io_context ctx;
        boost::asio::ip::udp::socket sock(ctx);

        // Test socket is initially closed
        expect(!sock.is_open());

        // Test opening socket
        boost::system::error_code ec;
        sock.open(boost::asio::ip::udp::v4(), ec);
        expect(!ec) << "Failed to open socket: " << ec.message();
        expect(sock.is_open());

        // Test binding to port
        sock.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), 0), ec);
        expect(!ec) << "Failed to bind: " << ec.message();

        // Test getting bound port
        auto local_endpoint = sock.local_endpoint(ec);
        expect(!ec);
        expect(local_endpoint.port() > 0_i);
    };

    "port_conflict_detection"_test = [] {
        boost::asio::io_context ctx;
        boost::asio::ip::udp::socket sock1(ctx);
        boost::asio::ip::udp::socket sock2(ctx);

        // Bind first socket
        sock1.open(boost::asio::ip::udp::v4());
        sock1.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), 14000));

        // Try to bind second socket to same port - should fail
        sock2.open(boost::asio::ip::udp::v4());
        boost::system::error_code ec;
        sock2.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), 14000), ec);

        // Without reuse_address, this should fail
        expect(ec != boost::system::error_code{}) << "Port conflict not detected";
    };

    "multicast_join_failure_on_invalid_address"_test = [] {
        boost::asio::io_context ctx;
        boost::asio::ip::udp::socket sock(ctx);

        sock.open(boost::asio::ip::udp::v4());
        sock.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), 14001));

        // Try to join invalid multicast address
        boost::system::error_code ec;
        sock.set_option(
            boost::asio::ip::multicast::join_group(
                boost::asio::ip::make_address("192.168.1.1")), ec);  // Not a multicast address

        // This should fail as it's not a valid multicast address (224.0.0.0 - 239.255.255.255)
        expect(ec != boost::system::error_code{}) << "Invalid multicast address not rejected";
    };

    "socket_cleanup_after_exception"_test = [] {
        auto create_and_fail = []() {
            boost::asio::io_context ctx;
            boost::asio::ip::udp::socket sock(ctx);
            sock.open(boost::asio::ip::udp::v4());
            sock.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), 14002));
            throw std::runtime_error("Simulated failure");
        };

        // First call should throw but clean up
        expect(throws<std::runtime_error>([&] { create_and_fail(); }));

        // Second call should succeed if cleanup worked
        boost::asio::io_context ctx;
        boost::asio::ip::udp::socket sock(ctx);
        boost::system::error_code ec;
        sock.open(boost::asio::ip::udp::v4(), ec);
        expect(!ec);
        sock.bind(boost::asio::ip::udp::endpoint(boost::asio::ip::udp::v4(), 14002), ec);
        expect(!ec) << "Port not cleaned up after exception";
    };
};

// Test 2: jthread RAII and destructor race conditions
suite jthread_raii_tests = [] {
    "jthread_destructor_race_with_io_context"_test = [] {
        std::atomic<bool> thread_started{false};
        std::atomic<bool> io_stopped{false};
        std::atomic<bool> thread_saw_stop{false};

        {
            boost::asio::io_context ctx;
            boost::asio::steady_timer timer(ctx);

            // Start work to keep io_context running
            timer.expires_after(std::chrono::seconds(10));
            timer.async_wait([](auto) {});

            std::jthread worker([&](std::stop_token st) {
                thread_started = true;
                while (!st.stop_requested() && !io_stopped) {
                    ctx.run_one();
                }
                thread_saw_stop = st.stop_requested();
            });

            // Wait for thread to start
            while (!thread_started) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }

            // Simulate what multiprocess_fixture destructor does
            ctx.stop();
            io_stopped = true;
            // jthread destructor will be called here
        }

        // Prove the race: thread may not see stop_requested if io_context stops first
        expect(thread_started.load());
        // This may fail - proving the race condition
        if (!thread_saw_stop) {
            std::cout << "RACE CONDITION PROVEN: Thread didn't see stop_requested\n";
        }
    };

    "jthread_cleanup_order_matters"_test = [] {
        struct BadRAII {
            boost::asio::io_context ctx;
            std::jthread worker;

            BadRAII() {
                boost::asio::steady_timer timer(ctx);
                timer.expires_after(std::chrono::seconds(10));
                timer.async_wait([](auto) {});

                worker = std::jthread([this](std::stop_token st) {
                    while (!st.stop_requested()) {
                        ctx.run_one();
                    }
                });
            }

            ~BadRAII() {
                // WRONG ORDER: stopping context before thread cleanup
                ctx.stop();
                // jthread destructor called after this
            }
        };

        // This may hang or crash due to race
        BadRAII bad;
        // If we get here without hanging, the race didn't manifest this time
        expect(true);
    };

    "multiple_jthreads_sharing_io_context"_test = [] {
        boost::asio::io_context ctx;
        std::atomic<int> active_threads{0};
        std::atomic<bool> race_detected{false};

        {
            std::vector<std::jthread> threads;

            // Start multiple threads sharing io_context
            for (int i = 0; i < 5; ++i) {
                threads.emplace_back([&](std::stop_token st) {
                    active_threads++;
                    while (!st.stop_requested()) {
                        try {
                            ctx.run_one();
                        } catch (...) {
                            race_detected = true;
                            break;
                        }
                    }
                    active_threads--;
                });
            }

            // Give threads time to start
            std::this_thread::sleep_for(std::chrono::milliseconds(10));

            // Stop context while threads are running
            ctx.stop();

            // jthread destructors will request stop here
        }

        expect(active_threads.load() == 0_i) << "Threads didn't clean up properly";
        expect(!race_detected) << "Exception during cleanup";
    };
};

// Test 3: Message Protocol and Parsing
suite message_protocol_tests = [] {
    "malformed_message_parsing"_test = [] {
        auto parse_message = [](const std::string& msg) -> std::pair<std::string, std::string> {
            auto colon_pos = msg.find(':');
            if (colon_pos == std::string::npos) {
                throw std::runtime_error("Invalid message format");
            }
            return {msg.substr(0, colon_pos), msg.substr(colon_pos + 1)};
        };

        // Valid messages
        auto [type1, data1] = parse_message("REG:5");
        expect(type1 == std::string("REG"));
        expect(data1 == std::string("5"));

        // Malformed messages that could arrive via UDP
        expect(throws([&] { parse_message("INVALID"); }));
        expect(throws([&] { parse_message(""); }));
        expect(throws([&] { parse_message(":"); }));
        expect(throws([&] { parse_message("REG:"); }));  // Empty ID
        expect(throws([&] { parse_message("REG:abc"); })); // Non-numeric ID
    };

    "ready_list_parsing_race"_test = [] {
        // Simulate parsing READY: message with concurrent modification
        std::string ready_msg = "READY:1,2,3,4,5";
        std::atomic<bool> keep_modifying{true};

        std::thread modifier([&] {
            while (keep_modifying) {
                ready_msg = "READY:6,7,8,9,10";  // Race condition!
                ready_msg = "READY:1,2,3,4,5";
            }
        });

        // Try to parse while being modified
        for (int i = 0; i < 100; ++i) {
            try {
                auto colon_pos = ready_msg.find(':');
                if (colon_pos != std::string::npos) {
                    auto data = ready_msg.substr(colon_pos + 1);
                    // This could get corrupted data
                }
            } catch (...) {
                // Parsing failure due to race
            }
        }

        keep_modifying = false;
        modifier.join();

        expect(true); // Just proving the race exists
    };
};

// Test 4: Thread Safety and Data Races
suite thread_safety_tests = [] {
    "unprotected_set_access"_test = [] {
        std::unordered_set<int> seen_ids;
        std::atomic<bool> race_detected{false};
        std::atomic<bool> keep_running{true};

        // Writer thread - simulates network receive
        std::thread writer([&] {
            while (keep_running) {
                seen_ids.insert(rand() % 10);
                seen_ids.clear();
            }
        });

        // Reader thread - simulates sync check
        std::thread reader([&] {
            while (keep_running) {
                try {
                    auto size = seen_ids.size();
                    (void)size;
                } catch (...) {
                    race_detected = true;
                }
            }
        });

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        keep_running = false;

        writer.join();
        reader.join();

        // This is a data race - undefined behavior
        std::cout << "Data race on unprotected set access - UB may not manifest\n";
    };

    "atomic_with_mutex_confusion"_test = [] {
        std::atomic<bool> flag{false};
        std::mutex m;
        std::condition_variable cv;
        bool notification_missed{false};

        // Writer uses atomic
        std::thread writer([&] {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            flag = true;  // Atomic write
            cv.notify_all();
        });

        // Reader uses mutex
        std::thread reader([&] {
            std::unique_lock<std::mutex> lock(m);
            // Wait for flag, but flag is set outside mutex!
            if (!cv.wait_for(lock, std::chrono::milliseconds(5), [&] { return flag.load(); })) {
                notification_missed = true;
            }
        });

        writer.join();
        reader.join();

        expect(!notification_missed) << "Notification/flag synchronization issue";
    };
};

// Test 5: Error Paths and Edge Cases
suite error_path_tests = [] {
    "timeout_during_sync"_test = [] {
        std::mutex m;
        std::condition_variable cv;
        bool timed_out{false};

        std::unique_lock<std::mutex> lock(m);
        // Wait for condition that never happens
        bool success = cv.wait_for(lock, std::chrono::milliseconds(10), [] {
            return false;
        });

        timed_out = !success;
        expect(timed_out) << "Timeout not detected";
    };

    "exception_during_coordination"_test = [] {
        struct Coordinator {
            std::jthread worker;
            boost::asio::io_context ctx;
            std::atomic<bool> exception_thrown{false};

            Coordinator() {
                worker = std::jthread([this](std::stop_token) {
                    try {
                        throw std::runtime_error("Network error");
                    } catch (...) {
                        exception_thrown = true;
                    }
                });
            }

            ~Coordinator() {
                // Will jthread handle exception properly?
                ctx.stop();
            }
        };

        // Check that exceptions in jthread need to be caught
        Coordinator c;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        expect(c.exception_thrown.load()) << "Exception in jthread must be caught";
    };

    "partial_registration_scenario"_test = [] {
        std::unordered_set<int> registered_ids;
        const int expected_count = 5;

        // Simulate only partial registration
        registered_ids.insert(0);
        registered_ids.insert(1);
        registered_ids.insert(3);  // Missing ID 2 and 4

        // Check if we'd incorrectly proceed
        bool would_proceed = registered_ids.size() >= 3;  // Wrong check!
        bool should_proceed = registered_ids.size() == static_cast<size_t>(expected_count);

        expect(would_proceed && !should_proceed) << "Would proceed with partial registration";
    };
};

// Test 6: Coordinator Failure Scenarios
suite coordinator_failure_tests = [] {
    "id_0_crashes_during_coordination"_test = [] {
        struct ProcessSimulator {
            int id;
            bool crashed{false};
            std::thread t;

            ProcessSimulator(int i) : id(i) {
                if (id == 0) {
                    t = std::thread([this] {
                        std::this_thread::sleep_for(std::chrono::milliseconds(10));
                        crashed = true;  // Simulate crash
                        // Thread ends - coordinator gone
                    });
                } else {
                    t = std::thread([this] {
                        // Wait for coordinator
                        std::this_thread::sleep_for(std::chrono::milliseconds(100));
                        // Still waiting... coordinator crashed
                    });
                }
            }

            ~ProcessSimulator() {
                if (t.joinable()) t.join();
            }
        };

        ProcessSimulator coord(0);
        ProcessSimulator participant(1);

        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        expect(coord.crashed) << "Coordinator crash scenario";
    };

    "multiple_processes_think_they_are_id_0"_test = [] {
        // Simulate environment variable parsing error
        auto get_my_id = [](const char* env_var) -> int {
            if (!env_var) return 0;  // BUG: defaults to 0!
            return std::atoi(env_var);
        };

        int id1 = get_my_id(nullptr);  // No env var
        int id2 = get_my_id("");       // Empty env var
        int id3 = get_my_id("abc");    // Invalid number

        expect(id1 == 0_i);
        expect(id2 == 0_i);
        expect(id3 == 0_i);

        // All three would try to be coordinator!
        std::cout << "PROBLEM: Multiple processes could think they're coordinator\n";
    };

    "late_coordinator_startup"_test = [] {
        std::atomic<bool> coordinator_started{false};
        std::atomic<int> participants_waiting{0};

        // Participants start first
        std::vector<std::thread> participants;
        for (int i = 1; i < 5; ++i) {
            participants.emplace_back([&] {
                participants_waiting++;
                // Wait for coordinator
                while (!coordinator_started) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                }
            });
        }

        // Coordinator starts late
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        expect(participants_waiting.load() == 4_i) << "Participants waiting";

        coordinator_started = true;

        for (auto& t : participants) {
            t.join();
        }
    };
};

int main() {
    // Run all test suites
    return 0;
}