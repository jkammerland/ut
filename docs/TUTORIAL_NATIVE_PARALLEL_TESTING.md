# Tutorial: Native Parallel Process Testing

This tutorial teaches you how to use boost.ut's native parallel process testing for fast, concurrent multiprocess tests with network coordination.

## What You'll Learn

- How to set up native parallel process tests
- Writing tests that coordinate across multiple processes
- Using network-based synchronization with barriers
- Environment variables and role-based testing
- Debugging and troubleshooting multiprocess tests

## Prerequisites

- boost.ut testing framework
- Boost.ASIO library (for network coordination)
- CMake 3.28+
- Basic understanding of multiprocess concepts

## Step 1: Your First Parallel Test

Let's start with a simple test that runs the same executable in two processes with different roles.

**Create `hello_multiprocess.cpp`:**
```cpp
#include <boost/ut.hpp>
#include <iostream>
#include <cstdlib>

std::string get_env(const char* name) {
    const char* val = std::getenv(name);
    return val ? std::string(val) : std::string();
}

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto ip = get_env("SIMULATED_IP");
    
    "environment setup"_test = [&] {
        expect(!role.empty()) << "PROCESS_ROLE must be set";
        expect(!ip.empty()) << "SIMULATED_IP must be set";
        
        std::cout << "Hello from " << role << " at " << ip << std::endl;
    };
    
    "role specific behavior"_test = [&] {
        if (role == "server") {
            std::cout << "[SERVER] Performing server tasks" << std::endl;
            expect(true) << "Server logic executed";
        } else {
            std::cout << "[CLIENT] Performing client tasks" << std::endl;
            expect(true) << "Client logic executed";
        }
    };
    
    return 0;
}
```

**Add to `CMakeLists.txt`:**
```cmake
include(cmake/ParallelProcessTest.cmake)

# Build the test executable
add_executable(hello_multiprocess hello_multiprocess.cpp)
target_link_libraries(hello_multiprocess PRIVATE Boost::ut)

# Add parallel test with 2 processes
ut_add_network_parallel_test(
  NAME hello_parallel_test
  PARTICIPANTS 2
  EXECUTABLE hello_multiprocess
  TIMEOUT 30
  MULTICAST_GROUP "239.255.1.1"
  MULTICAST_PORT 13001
)
```

**Run the test:**
```bash
cmake --build build
ctest -R hello_parallel_test --output-on-failure
```

### What Happens

1. CMake generates a shell script that runs 2 processes in parallel
2. Each process gets unique environment variables:
   - Process 1: `PROCESS_ROLE=server`, `SIMULATED_IP=127.0.0.2`
   - Process 2: `PROCESS_ROLE=client2`, `SIMULATED_IP=127.0.0.3`
3. Both processes run simultaneously using shell background processes (`&`)
4. The test waits for both processes to complete and reports combined results

## Step 2: Network Coordination with Barriers

Real multiprocess tests need synchronization. Let's add network-based barriers.

**Create `synchronized_test.cpp`:**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"  // Contains multiprocess_fixture
#include <chrono>
#include <thread>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "synchronized execution"_test = [&] {
        // Create fixture - all processes wait at barriers
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.1.1", 13001);
        
        std::cout << "[" << role << "] Phase 1: Starting" << std::endl;
        
        // All processes wait here until everyone arrives
        fixture.sync_point("phase1");
        
        std::cout << "[" << role << "] Phase 2: All processes synchronized" << std::endl;
        
        // Simulate some work
        if (role == "server") {
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            std::cout << "[SERVER] Server work completed" << std::endl;
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            std::cout << "[CLIENT] Client work completed" << std::endl;
        }
        
        // Wait again - ensures all work is done before continuing
        fixture.sync_point("phase2");
        
        std::cout << "[" << role << "] Phase 3: All work completed" << std::endl;
        
        expect(true) << "Synchronized execution successful";
    };
    
    return 0;
}
```

**Update CMakeLists.txt:**
```cmake
add_executable(synchronized_test synchronized_test.cpp)
target_link_libraries(synchronized_test PRIVATE Boost::ut Boost::system)

ut_add_network_parallel_test(
  NAME synchronized_test
  PARTICIPANTS 3  # 1 server + 2 clients
  EXECUTABLE synchronized_test
  TIMEOUT 45
  MULTICAST_GROUP "239.255.1.2"
  MULTICAST_PORT 13002
)
```

### How Network Barriers Work

1. **UDP Multicast**: All processes join the same multicast group
2. **Barrier Protocol**: Each process sends "ARRIVED" message and waits for "PROCEED"
3. **Coordination**: When all participants arrive, barrier releases all processes
4. **Template Parameter**: `multiprocess_fixture<true>` means "wait at barriers"

## Step 3: Event-Based Communication

Beyond barriers, processes can send custom events to each other.

**Create `event_communication_test.cpp`:**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "event communication"_test = [&] {
        // Event handler receives messages from other processes
        auto event_handler = [role](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            std::cout << "[" << role << "] Received: " << msg << std::endl;
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.1.3", 13003, event_handler);
        
        // Phase 1: Everyone ready
        fixture.sync_point("ready");
        
        // Send status updates
        std::string status = "Status from " + role + ": ready";
        std::vector<std::byte> event_data;
        for (char c : status) {
            event_data.push_back(static_cast<std::byte>(c));
        }
        fixture.send_event(event_data);
        
        // Small delay to receive events
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        
        // Phase 2: Coordination complete
        fixture.sync_point("complete");
        
        expect(true) << "Event communication successful";
    };
    
    return 0;
}
```

### Event System Features

- **Max 500 bytes per event**: Keep messages small
- **UDP multicast delivery**: All processes receive all events
- **Handler callback**: Process events as they arrive
- **Best effort delivery**: No guaranteed delivery (use barriers for critical sync)

## Step 4: Advanced Configuration

**Multiple environment variables:**
```cmake
ut_add_network_parallel_test(
  NAME advanced_test
  PARTICIPANTS 4
  EXECUTABLE my_test
  TIMEOUT 120
  MULTICAST_GROUP "239.255.1.4"
  MULTICAST_PORT 13004
  ADDITIONAL_ENV "LOG_LEVEL=debug" "STRESS_MODE=1" "WORKER_COUNT=3"
)
```

**Non-blocking barriers (fire-and-forget):**
```cpp
// Process signals arrival but doesn't wait
multiprocess_fixture<false> fixture(count, role);
fixture.sync_point("notification");  // Sends signal, returns immediately
```

**Custom multicast configuration:**
```cpp
// Use different network settings per test
multiprocess_fixture<true> fixture(count, role, "239.255.5.100", 15000);
```

## Step 5: Role-Based Testing Patterns

**Client-Server Pattern:**
```cpp
"client server interaction"_test = [&] {
    multiprocess_fixture<true> fixture(participant_count, role);
    
    if (role == "server") {
        // Server setup
        fixture.sync_point("server_ready");
        
        // Handle client requests
        fixture.sync_point("requests_complete");
        
        expect(true) << "Server handled all requests";
    } else {
        // Client setup
        fixture.sync_point("server_ready");
        
        // Make requests to server
        std::cout << "[" << role << "] Making request" << std::endl;
        
        fixture.sync_point("requests_complete");
        
        expect(true) << "Client completed requests";
    }
};
```

**Producer-Consumer Pattern:**
```cpp
if (role == "server") {
    // Producer
    for (int i = 0; i < 10; ++i) {
        std::string item = "item_" + std::to_string(i);
        std::vector<std::byte> data(item.begin(), item.end());
        fixture.send_event(data);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
} else {
    // Consumer - event handler processes items automatically
}
```

## Step 6: Debugging Your Tests

**Add debug output:**
```cpp
"debug multiprocess test"_test = [&] {
    std::cout << "=== DEBUG INFO ===" << std::endl;
    std::cout << "Role: " << role << std::endl;
    std::cout << "PID: " << getpid() << std::endl;
    std::cout << "Participant count: " << participant_count << std::endl;
    std::cout << "==================" << std::endl;
    
    // Your test logic...
};
```

**Run with verbose output:**
```bash
# See all test output
ctest -R your_test_name -V

# See only failures
ctest -R your_test_name --output-on-failure

# Run specific test multiple times
for i in {1..10}; do
    echo "Run $i:"
    ctest -R your_test_name --output-on-failure
done
```

**Manual execution for debugging:**
```bash
# Run individual processes manually
cd build/example/multiprocess

# Process 1 (server)
PROCESS_ROLE=server SIMULATED_IP=127.0.0.2 PARTICIPANT_COUNT=2 \
MULTICAST_GROUP=239.255.1.1 MULTICAST_PORT=13001 ./synchronized_test

# Process 2 (client) - in another terminal
PROCESS_ROLE=client2 SIMULATED_IP=127.0.0.3 PARTICIPANT_COUNT=2 \
MULTICAST_GROUP=239.255.1.1 MULTICAST_PORT=13001 ./synchronized_test
```

**Check generated scripts:**
```bash
# View the generated test runner
cat build/example/multiprocess/synchronized_test_runner.sh

# Make it executable and run directly
chmod +x build/example/multiprocess/synchronized_test_runner.sh
./build/example/multiprocess/synchronized_test_runner.sh
```

## Step 7: Common Patterns and Best Practices

**Environment Variable Validation:**
```cpp
"validate environment"_test = [&] {
    auto role = get_env("PROCESS_ROLE");
    auto ip = get_env("SIMULATED_IP");
    auto group = get_env("MULTICAST_GROUP");
    auto port = get_env("MULTICAST_PORT");
    auto count = get_env("PARTICIPANT_COUNT");
    
    expect(!role.empty()) << "PROCESS_ROLE required";
    expect(!ip.empty()) << "SIMULATED_IP required";
    expect(!group.empty()) << "MULTICAST_GROUP required";
    expect(!port.empty()) << "MULTICAST_PORT required";
    expect(!count.empty()) << "PARTICIPANT_COUNT required";
};
```

**Timeout Handling:**
```cpp
// Set reasonable timeouts for network operations
multiprocess_fixture<true> fixture(count, role, group, port);

// Use shorter waits for faster feedback
std::this_thread::sleep_for(std::chrono::milliseconds(100));

// Don't use infinite loops - always have timeouts
```

**Error Recovery:**
```cpp
"network error handling"_test = [&] {
    try {
        multiprocess_fixture<true> fixture(count, role);
        fixture.sync_point("test");
        expect(true) << "Normal execution";
    } catch (const std::exception& e) {
        std::cout << "Network error: " << e.what() << std::endl;
        // Decide if this should fail the test
        expect(false) << "Network coordination failed";
    }
};
```

## Step 8: Performance Considerations

**Fast Tests (< 30 seconds):**
- Use 2-4 participants
- Minimize sleep/delays
- Use simple barrier patterns
- Avoid complex event handling

**Longer Integration Tests:**
- Use more participants (5-8)
- Include realistic timing
- Test error conditions
- Use comprehensive event communication

**Resource Usage:**
- Each participant uses ~1MB RAM + test executable size
- UDP multicast uses minimal network bandwidth
- Process startup time: ~50-100ms per participant

## Troubleshooting Guide

**Test reports success but no output:**
- Check if executable path is correct in CMake
- Verify test builds successfully: `cmake --build build`
- Run with `-V` flag to see all output

**"Address already in use" error:**
- Each test needs unique MULTICAST_PORT
- Check no other tests use the same port simultaneously
- Ports 13000-13999 are recommended range

**Processes hang at sync_point:**
- Verify all processes use the same MULTICAST_GROUP and MULTICAST_PORT
- Check if all processes reach the same sync_point name
- Ensure PARTICIPANT_COUNT matches actual number of processes

**Script errors with exit codes:**
- Modern CMake modules fix exit code handling
- Check generated script uses proper `wait` syntax
- Verify script has proper error handling with `set -e`

## Next Steps

Now that you understand native parallel testing:

1. Try the [Container-based Testing Tutorial](TUTORIAL_CONTAINER_TESTING.md) for isolated testing
2. Read [Multiprocess Examples](MULTIPROCESS_EXAMPLES.md) for advanced patterns
3. Check [Troubleshooting Guide](MULTIPROCESS_TROUBLESHOOTING.md) for common issues
4. Explore the [CMake Reference](CMAKE_MODULES_REFERENCE.md) for all options

Native parallel testing provides the fastest multiprocess testing with minimal overhead - perfect for development workflow and quick feedback cycles.