# Multiprocess Testing Examples

This document provides practical examples for common multiprocess testing scenarios using boost.ut.

## Basic Examples

### Simple Client-Server Coordination

**Test Code (`client_server_test.cpp`):**
```cpp
#include <boost/ut.hpp>
#include <iostream>
#include <cstdlib>
#include <chrono>
#include <thread>

std::string get_env(const char* name) {
    const char* val = std::getenv(name);
    return val ? std::string(val) : std::string();
}

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto ip = get_env("SIMULATED_IP");
    
    "process identification"_test = [&] {
        expect(!role.empty()) << "PROCESS_ROLE must be set by test framework";
        expect(!ip.empty()) << "SIMULATED_IP must be set by test framework";
        
        std::cout << "Process: " << role << " at " << ip << std::endl;
    };
    
    "role-specific behavior"_test = [&] {
        if (role == "server") {
            // Server test logic
            std::cout << "[SERVER] Starting server operations" << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            expect(true) << "Server operations completed";
        } else {
            // Client test logic
            std::cout << "[CLIENT] Starting client operations" << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            expect(true) << "Client operations completed";
        }
    };
    
    return 0;
}
```

**CMake Configuration:**
```cmake
# Build the test executable
add_executable(client_server_test client_server_test.cpp)
target_link_libraries(client_server_test PRIVATE Boost::ut)

# Add parallel process test
ut_add_network_parallel_test(
  NAME basic_client_server_test
  PARTICIPANTS 2
  EXECUTABLE client_server_test
  TIMEOUT 30
  MULTICAST_GROUP "239.255.1.1"
  MULTICAST_PORT 13001
)
```

### Network Coordination with Barriers

**Test Code (`barrier_coordination_test.cpp`):**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"  // Include fixture

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    
    "barrier synchronization"_test = [&] {
        // Event handler to log received messages
        auto event_handler = [role](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            std::cout << "[" << role << "] Received event: " << msg << std::endl;
        };
        
        // Create fixture with 3 participants
        multiprocess_fixture<true> fixture(3, role, "239.255.1.2", 13002, event_handler);
        
        std::cout << "[" << role << "] Phase 1: Initialization" << std::endl;
        fixture.sync_point("initialize");  // All processes wait here
        
        // Send status update
        std::string status = "Ready from " + role;
        std::vector<std::byte> event_data;
        for (char c : status) {
            event_data.push_back(static_cast<std::byte>(c));
        }
        fixture.send_event(event_data);
        
        std::cout << "[" << role << "] Phase 2: Processing" << std::endl;
        fixture.sync_point("process");     // Wait again
        
        std::cout << "[" << role << "] Phase 3: Cleanup" << std::endl;
        fixture.sync_point("cleanup");     // Final synchronization
        
        expect(true) << "All phases completed successfully";
    };
    
    return 0;
}
```

**CMake Configuration:**
```cmake
add_executable(barrier_coordination_test barrier_coordination_test.cpp)
target_link_libraries(barrier_coordination_test PRIVATE Boost::ut Boost::system)

ut_add_network_parallel_test(
  NAME barrier_sync_test
  PARTICIPANTS 3
  EXECUTABLE barrier_coordination_test
  TIMEOUT 45
  MULTICAST_GROUP "239.255.1.2"
  MULTICAST_PORT 13002
)
```

## Container-Based Examples

### Simple Container Test

**Containerfile:**
```dockerfile
FROM fedora:41

# Install runtime dependencies
RUN dnf install -y boost-system && dnf clean all

# Create app directory and user
RUN mkdir /app && useradd -r testuser && chown testuser /app
WORKDIR /app

# Copy test executable (built outside container)
COPY build/container_test /app/
RUN chown testuser:testuser /app/container_test

USER testuser
CMD ["./container_test"]
```

**Build and Test Configuration:**
```cmake
# Build test executable
add_executable(container_test container_test.cpp)
target_link_libraries(container_test PRIVATE Boost::ut Boost::system)

# Add container build target
add_custom_target(build_container_test_image
  COMMAND podman build -f ${CMAKE_CURRENT_SOURCE_DIR}/Containerfile -t container-test-image .
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  DEPENDS container_test
  COMMENT "Building container test image"
)

# Add container test
ut_add_simple_compose_test(
  NAME container_coordination_test
  PARTICIPANTS 2
  EXECUTABLE "./container_test"
  IMAGE container-test-image
  TIMEOUT 90
  MULTICAST_GROUP "239.255.5.1"
  MULTICAST_PORT 17001
  STARTUP_ORDER
  ENABLE_LOGS
  CLEANUP_VOLUMES
)
```

### Advanced Container Test with Custom Services

**Custom Compose File (`custom-test-compose.yml`):**
```yaml
version: '3.8'

services:
  coordinator:
    image: my-test-image
    container_name: test-coordinator
    hostname: coordinator
    environment:
      - PROCESS_ROLE=coordinator
      - SIMULATED_IP=192.168.220.10
      - WORKER_COUNT=3
    networks:
      test-network:
        ipv4_address: 192.168.220.10
    volumes:
      - test-logs:/app/logs
    
  worker1:
    image: my-test-image
    container_name: test-worker1
    hostname: worker1
    environment:
      - PROCESS_ROLE=worker
      - WORKER_ID=1
      - COORDINATOR_IP=192.168.220.10
      - SIMULATED_IP=192.168.220.11
    networks:
      test-network:
        ipv4_address: 192.168.220.11
    depends_on:
      - coordinator
      
  worker2:
    image: my-test-image
    container_name: test-worker2
    hostname: worker2
    environment:
      - PROCESS_ROLE=worker
      - WORKER_ID=2
      - COORDINATOR_IP=192.168.220.10
      - SIMULATED_IP=192.168.220.12
    networks:
      test-network:
        ipv4_address: 192.168.220.12
    depends_on:
      - coordinator

networks:
  test-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.220.0/24

volumes:
  test-logs:
```

**CMake Configuration for Custom Compose:**
```cmake
ut_add_compose_multiprocess_test(
  NAME custom_coordinator_test
  CUSTOM_COMPOSE
  COMPOSE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/custom-test-compose.yml"
  TIMEOUT 120
  ENABLE_LOGS
  CLEANUP_VOLUMES
)
```

## MPI Testing Examples

### Basic MPI Collective Operations Test

**Test Code (`mpi_collective_test.cpp`):**
```cpp
#include <boost/ut.hpp>
#include <mpi.h>
#include <vector>
#include <numeric>

int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);
    
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    
    using namespace boost::ut;
    
    "MPI environment"_test = [&] {
        expect(rank >= 0) << "Rank should be non-negative";
        expect(rank < size) << "Rank should be less than size";
        expect(size >= 2) << "Need at least 2 MPI processes";
    };
    
    "broadcast operation"_test = [&] {
        int broadcast_value = 0;
        
        if (rank == 0) {
            broadcast_value = 42;  // Root process sets value
        }
        
        MPI_Bcast(&broadcast_value, 1, MPI_INT, 0, MPI_COMM_WORLD);
        
        expect(broadcast_value == 42) << "All processes should receive broadcast value";
    };
    
    "reduce operation"_test = [&] {
        int local_value = rank + 1;  // Each process contributes rank+1
        int sum_result = 0;
        
        MPI_Reduce(&local_value, &sum_result, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);
        
        if (rank == 0) {
            int expected_sum = size * (size + 1) / 2;  // Sum of 1+2+...+size
            expect(sum_result == expected_sum) << "Sum should equal expected value";
        }
    };
    
    "allgather operation"_test = [&] {
        int local_data = rank * 10;
        std::vector<int> gathered_data(size);
        
        MPI_Allgather(&local_data, 1, MPI_INT, gathered_data.data(), 1, MPI_INT, MPI_COMM_WORLD);
        
        // Verify all processes received all data
        for (int i = 0; i < size; ++i) {
            expect(gathered_data[i] == i * 10) << "Gathered data should match";
        }
    };
    
    MPI_Finalize();
    return 0;
}
```

**CMake Configuration:**
```cmake
# Find MPI
ut_require_mpi()

# Build MPI executable
ut_add_mpi_executable(
  NAME mpi_collective_test
  SOURCES mpi_collective_test.cpp
  LIBRARIES MPI::MPI_CXX
)

# Add scaling tests
ut_add_mpi_scaling_test(
  NAME mpi_collective_scaling
  TARGET mpi_collective_test
  PROCESS_COUNTS 2 4 8
  TIMEOUT 60
)

# Add specific process count tests
ut_add_mpi_test(
  NAME mpi_collective_4procs
  TARGET mpi_collective_test
  PROCESSES 4
  TIMEOUT 30
)
```

## Advanced Scenarios

### Load Balancer Simulation

**Test Code (`load_balancer_test.cpp`):**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <random>
#include <chrono>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "load balancer simulation"_test = [&] {
        auto event_handler = [role](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("LOAD:")) {
                std::cout << "[" << role << "] Load report: " << msg << std::endl;
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, "239.255.1.3", 13003, event_handler);
        
        if (role == "server") {
            // Load balancer logic
            std::cout << "[BALANCER] Starting load balancer" << std::endl;
            fixture.sync_point("balancer_ready");
            
            // Simulate load distribution
            for (int i = 1; i <= 5; ++i) {
                std::string load_msg = "LOAD:request_" + std::to_string(i);
                std::vector<std::byte> event_data(load_msg.begin(), load_msg.end());
                fixture.send_event(event_data);
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
            
            fixture.sync_point("load_complete");
        } else {
            // Worker logic
            std::cout << "[WORKER:" << role << "] Starting worker" << std::endl;
            fixture.sync_point("balancer_ready");
            
            // Simulate variable processing time
            std::random_device rd;
            std::mt19937 gen(rd());
            std::uniform_int_distribution<> dis(50, 200);
            
            std::this_thread::sleep_for(std::chrono::milliseconds(dis(gen)));
            
            // Report completion
            std::string complete_msg = "COMPLETE:" + role;
            std::vector<std::byte> event_data(complete_msg.begin(), complete_msg.end());
            fixture.send_event(event_data);
            
            fixture.sync_point("load_complete");
        }
        
        expect(true) << "Load balancer simulation completed";
    };
    
    return 0;
}
```

**CMake Configuration:**
```cmake
add_executable(load_balancer_test load_balancer_test.cpp)
target_link_libraries(load_balancer_test PRIVATE Boost::ut Boost::system)

ut_add_network_parallel_test(
  NAME load_balancer_simulation
  PARTICIPANTS 5  # 1 load balancer + 4 workers
  EXECUTABLE load_balancer_test
  TIMEOUT 60
  MULTICAST_GROUP "239.255.1.3"
  MULTICAST_PORT 13003
  ADDITIONAL_ENV "SIMULATION_MODE=1"
)
```

### Database Replication Test

**Container Test with Volume Persistence:**
```cmake
ut_add_simple_compose_test(
  NAME database_replication_test
  PARTICIPANTS 3  # 1 primary + 2 replicas
  EXECUTABLE "./db_replication_test"
  IMAGE database-test-image
  TIMEOUT 180
  MULTICAST_GROUP "239.255.5.5"
  MULTICAST_PORT 17005
  STARTUP_ORDER  # Primary starts before replicas
  ENABLE_LOGS
  CLEANUP_VOLUMES
  ADDITIONAL_ENV 
    "DB_SYNC_TIMEOUT=30"
    "REPLICATION_FACTOR=2"
    "CONSISTENCY_LEVEL=eventual"
)
```

### Distributed Consensus Algorithm

**Test Code for Raft Algorithm Simulation:**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <random>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "raft consensus simulation"_test = [&] {
        std::random_device rd;
        std::mt19937 gen(rd());
        
        auto event_handler = [role](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("VOTE:") || msg.starts_with("HEARTBEAT:")) {
                std::cout << "[" << role << "] " << msg << std::endl;
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, "239.255.1.4", 13004, event_handler);
        
        // Phase 1: Leader election
        fixture.sync_point("election_start");
        
        if (role == "server") {
            // Server becomes candidate
            std::string vote_request = "VOTE:candidate_server_term_1";
            std::vector<std::byte> event_data(vote_request.begin(), vote_request.end());
            fixture.send_event(event_data);
        }
        
        fixture.sync_point("election_complete");
        
        // Phase 2: Normal operation with heartbeats
        if (role == "server") {
            // Send heartbeats as leader
            for (int i = 0; i < 3; ++i) {
                std::string heartbeat = "HEARTBEAT:leader_term_1_" + std::to_string(i);
                std::vector<std::byte> event_data(heartbeat.begin(), heartbeat.end());
                fixture.send_event(event_data);
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
            }
        }
        
        fixture.sync_point("consensus_complete");
        expect(true) << "Consensus algorithm simulation completed";
    };
    
    return 0;
}
```

## Performance Testing Examples

### Throughput Measurement

**Test Code (`throughput_test.cpp`):**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <chrono>
#include <atomic>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    
    "network throughput test"_test = [&] {
        std::atomic<int> message_count{0};
        const int target_messages = 1000;
        
        auto event_handler = [&](const std::vector<std::byte>& data) {
            message_count++;
        };
        
        multiprocess_fixture<true> fixture(2, role, "239.255.1.5", 13005, event_handler);
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        fixture.sync_point("throughput_start");
        
        if (role == "server") {
            // Server sends messages as fast as possible
            for (int i = 0; i < target_messages; ++i) {
                std::string msg = "MSG:" + std::to_string(i);
                std::vector<std::byte> event_data(msg.begin(), msg.end());
                fixture.send_event(event_data);
            }
        }
        
        // Wait for message processing
        std::this_thread::sleep_for(std::chrono::seconds(2));
        
        fixture.sync_point("throughput_complete");
        
        auto end_time = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
        
        if (role == "client2") {
            double messages_per_sec = (message_count.load() * 1000.0) / duration.count();
            std::cout << "Throughput: " << messages_per_sec << " messages/second" << std::endl;
            std::cout << "Received: " << message_count.load() << "/" << target_messages << " messages" << std::endl;
            
            expect(message_count.load() >= target_messages * 0.95) << "Should receive at least 95% of messages";
        }
    };
    
    return 0;
}
```

### Latency Measurement

**CMake Configuration with Performance Testing:**
```cmake
add_executable(throughput_test throughput_test.cpp)
target_link_libraries(throughput_test PRIVATE Boost::ut Boost::system)

# Multiple performance test configurations
ut_add_network_parallel_test(
  NAME throughput_test_2proc
  PARTICIPANTS 2
  EXECUTABLE throughput_test
  TIMEOUT 30
  MULTICAST_GROUP "239.255.1.5"
  MULTICAST_PORT 13005
  ADDITIONAL_ENV "TARGET_MESSAGES=1000"
)

ut_add_network_parallel_test(
  NAME throughput_test_4proc
  PARTICIPANTS 4
  EXECUTABLE throughput_test
  TIMEOUT 45
  MULTICAST_GROUP "239.255.1.6"
  MULTICAST_PORT 13006
  ADDITIONAL_ENV "TARGET_MESSAGES=2000"
)

ut_add_network_parallel_test(
  NAME throughput_test_8proc
  PARTICIPANTS 8
  EXECUTABLE throughput_test
  TIMEOUT 60
  MULTICAST_GROUP "239.255.1.7"
  MULTICAST_PORT 13007
  ADDITIONAL_ENV "TARGET_MESSAGES=4000"
)
```

## Running Examples

### Basic Test Execution

```bash
# Build all test executables
cmake --build build

# Run specific multiprocess test
ctest -R basic_client_server_test --output-on-failure

# Run all barrier coordination tests
ctest -R barrier --output-on-failure

# Run container-based tests
ctest -L compose --output-on-failure

# Run MPI tests (requires MPI runtime)
ctest -L mpi --output-on-failure

# Run performance tests with verbose output
ctest -R throughput -V
```

### Debug and Development

```bash
# Run single test with maximum verbosity
ctest -R load_balancer_simulation -VV

# Run specific container test manually
cd build/example/multiprocess
podman-compose -f container_coordination_test_compose.yml up

# Debug MPI test with debugger
mpirun -np 4 xterm -e gdb ./mpi_collective_test

# Check generated test scripts
ls -la build/example/multiprocess/*_runner.sh
cat build/example/multiprocess/basic_client_server_test_runner.sh
```

### Continuous Integration

```bash
# Run all multiprocess tests in CI pipeline
ctest -L multiprocess --output-on-failure --parallel 4

# Generate test reports
ctest -L multiprocess -T Test --output-junit test_results.xml

# Run only fast tests (< 30 seconds)
ctest -L multiprocess -LE slow --timeout 30
```

These examples demonstrate the full range of multiprocess testing capabilities from simple coordination to complex distributed system simulations.