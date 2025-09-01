# Multiprocess Testing Guide

boost.ut multiprocess testing framework provides three approaches for testing distributed applications:

1. **Native Parallel Process Testing** - Fast, lightweight coordination using shell scripts
2. **Container-Based Testing** - Full isolation using Podman/Docker containers  
3. **Traditional Process Testing** - Sequential and basic parallel execution

## Quick Start

### Native Parallel Process Testing (Recommended)

```cmake
include(cmake/ParallelProcessTest.cmake)

# Network-coordinated multiprocess test
ut_add_network_parallel_test(
  NAME my_multiprocess_test
  PARTICIPANTS 3
  EXECUTABLE my_test_binary
  TIMEOUT 60
  MULTICAST_GROUP "239.255.1.1"
  MULTICAST_PORT 13001
)
```

### Container-Based Testing

```cmake
include(cmake/SimpleComposeTest.cmake)

ut_add_simple_compose_test(
  NAME my_container_test
  PARTICIPANTS 2
  EXECUTABLE my_test_binary
  IMAGE my-test-image
  STARTUP_ORDER
  ENABLE_LOGS
)
```

## Testing Approaches Comparison

| Feature | Native Parallel | Container-Based | Traditional |
|---------|----------------|----------------|------------|
| Process isolation | Host-level | Container-level | Host-level |
| Network isolation | Shared host network | Dedicated networks | Shared host network |
| Startup coordination | Environment variables | Compose dependencies | Process order |
| Resource cleanup | Background process cleanup | Full container cleanup | Basic cleanup |
| Performance | Fastest | Moderate | Fast |
| Setup complexity | Low | Medium | Low |
| Network coordination | UDP multicast | UDP multicast + networking | File-based or none |

## Native Parallel Process Testing

Native parallel testing provides true concurrent process execution with network-based coordination.

### Features

- **True Parallel Execution**: Uses shell background processes (`&`) and `wait`
- **Network Coordination**: UDP multicast for inter-process synchronization
- **Environment Variable Injection**: Each process gets role-specific variables
- **Process Lifecycle Management**: Proper cleanup and exit code collection

### Basic Usage

```cmake
ut_add_network_parallel_test(
  NAME basic_coordination_test
  PARTICIPANTS 2
  EXECUTABLE network_coordination_binary
  TIMEOUT 30
  MULTICAST_GROUP "239.255.0.1"
  MULTICAST_PORT 12345
)
```

### Advanced Configuration

```cmake
ut_add_network_parallel_test(
  NAME advanced_test
  PARTICIPANTS 4
  EXECUTABLE my_binary
  TIMEOUT 120
  MULTICAST_GROUP "239.255.1.5"
  MULTICAST_PORT 13005
  ADDITIONAL_ENV "LOG_LEVEL=debug" "STRESS_MODE=1"
)
```

### Environment Variables Set Automatically

Each process receives:
- `PROCESS_ROLE`: `server`, `client2`, `client3`, etc.
- `SIMULATED_IP`: `127.0.0.2`, `127.0.0.3`, etc.
- `MULTICAST_GROUP`: Configured multicast address
- `MULTICAST_PORT`: Configured UDP port
- `PARTICIPANT_COUNT`: Total number of processes

### Writing Native Parallel Tests

```cpp
#include <boost/ut.hpp>
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
    };
    
    "role specific logic"_test = [&] {
        if (role == "server") {
            // Server-specific test logic
            expect(true) << "Server process running";
        } else {
            // Client-specific test logic  
            expect(true) << "Client process running";
        }
    };
    
    return 0;
}
```

## Container-Based Testing

Container testing provides full process isolation with network coordination.

### Features

- **Process Isolation**: Each process runs in separate container
- **Network Isolation**: Dedicated bridge networks with static IPs
- **Startup Dependencies**: Services start in specified order
- **Log Extraction**: Automatic collection and analysis of container logs
- **Volume Management**: Persistent storage and cleanup

### Template-Based Approach (Recommended)

```cmake
ut_add_simple_compose_test(
  NAME container_test
  PARTICIPANTS 3
  EXECUTABLE my_binary
  IMAGE my-test-image
  TIMEOUT 120
  MULTICAST_GROUP "239.255.5.1"
  MULTICAST_PORT 17001
  STARTUP_ORDER    # Client containers depend on server
  ENABLE_LOGS      # Extract and analyze container logs
  CLEANUP_VOLUMES  # Remove volumes after test
)
```

### Container Requirements

Your test image must:
- Contain the test executable in `/app/`
- Be configured to run as non-root user
- Support UDP multicast networking

### Building Test Images

```dockerfile
FROM fedora:41

# Install runtime dependencies
RUN dnf install -y boost-system && dnf clean all

# Copy test executable
COPY build/my_test_binary /app/
WORKDIR /app

# Create non-root user
RUN useradd -r testuser && chown testuser /app
USER testuser

CMD ["./my_test_binary"]
```

### Generated Compose Files

The framework generates Docker Compose files with:
- Static IP assignment for each container
- Environment variables for role and network configuration
- Service dependencies for startup ordering
- Logging configuration for test result extraction

Example generated compose.yml:
```yaml
version: '3.8'
services:
  server:
    image: my-test-image
    container_name: test-server
    environment:
      - PROCESS_ROLE=server
      - SIMULATED_IP=192.168.210.101
      - MULTICAST_GROUP=239.255.5.1
      - MULTICAST_PORT=17001
      - PARTICIPANT_COUNT=3
    networks:
      test-network:
        ipv4_address: 192.168.210.101
    depends_on: []
    
  client2:
    image: my-test-image
    container_name: test-client2
    environment:
      - PROCESS_ROLE=client2
      - SIMULATED_IP=192.168.210.102
      - MULTICAST_GROUP=239.255.5.1
      - MULTICAST_PORT=17001
      - PARTICIPANT_COUNT=3
    networks:
      test-network:
        ipv4_address: 192.168.210.102
    depends_on:
      - server

networks:
  test-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.210.0/24
```

## Network Coordination Framework

Both native and container approaches use UDP multicast for inter-process coordination.

### multiprocess_fixture Template

```cpp
#include "network_coordination.cpp"  // Contains multiprocess_fixture

// Template parameters:
// wait_after_arrive=true:  Process waits at barriers for all participants
// wait_after_arrive=false: Process signals arrival and continues immediately

template<bool wait_after_arrive = true>
class multiprocess_fixture {
public:
    multiprocess_fixture(int participant_count, const std::string& role,
                        const std::string& multicast_address = "239.255.0.1",
                        int multicast_port = 12345,
                        event_handler_t handler = nullptr);
                        
    void sync_point(const std::string& barrier_name = "default");
    void send_event(const std::vector<std::byte>& data);
};
```

### Network Synchronization Example

```cpp
"multiprocess coordination"_test = [&] {
    auto event_handler = [role](const std::vector<std::byte>& data) {
        std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
        std::cout << "[" << role << "] Event: " << msg << std::endl;
    };
    
    multiprocess_fixture<true> fixture(2, role, "239.255.0.1", 12345, event_handler);
    
    // Synchronization barriers
    fixture.sync_point("phase_1");  // All processes wait here
    
    // Send custom events
    std::string status = "Ready from " + role;
    std::vector<std::byte> event_data;
    for (char c : status) {
        event_data.push_back(static_cast<std::byte>(c));
    }
    fixture.send_event(event_data);
    
    fixture.sync_point("phase_2");  // Wait again
    
    expect(true) << "Coordination completed";
};
```

## Running Tests

### CTest Integration

All multiprocess tests integrate with CTest:

```bash
# Run all multiprocess tests
ctest -L multiprocess

# Run parallel process tests only  
ctest -L parallel

# Run container tests only
ctest -L compose

# Run with verbose output
ctest -V -R my_test_name

# Run with failure output
ctest --output-on-failure -R my_test_name
```

### Manual Execution

For debugging, run tests manually:

```bash
# Native parallel test
cd build/example/multiprocess
./my_test_runner.sh

# Container test
podman-compose -f my_test_compose.yml -p my-test up

# Individual process (native)
PROCESS_ROLE=server SIMULATED_IP=127.0.0.2 ./my_binary
```

## Troubleshooting

### Common Issues

**Native Tests Report Failure Despite Success**
- Symptom: Processes complete successfully but CTest reports failure
- Cause: Script exit code handling bug
- Fix: Check script generation in CMake modules for proper wait logic

**Container Tests Fail with "image not found"**
- Symptom: podman-compose fails to start containers
- Cause: Specified image doesn't exist or wrong name
- Fix: Build image or use existing image name (check with `podman images`)

**Network Coordination Timeout**
- Symptom: Processes timeout waiting at sync_point
- Cause: Multicast networking issues or process startup problems
- Fix: Check multicast group availability, verify all processes start correctly

**Port Conflicts**
- Symptom: "Address already in use" errors
- Cause: Multiple tests using same multicast port simultaneously
- Fix: Use different MULTICAST_PORT values for concurrent tests

**Container Network Subnet Conflicts**
- Symptom: Network creation fails in container tests
- Cause: Subnet already in use by other containers/networks
- Fix: Use different network subnets or clean up existing networks

### Debug Commands

```bash
# Check running containers
podman ps -a

# Check networks
podman network ls

# View container logs
podman logs container-name

# Check multicast connectivity
ss -u -a | grep :12345

# Clean up test artifacts
podman system prune -f
podman network prune -f
```

## Performance Considerations

### Native Parallel Tests
- **Startup time**: ~100ms per process
- **Resource usage**: Minimal overhead beyond actual processes
- **Scalability**: Tested up to 8 concurrent processes
- **Network overhead**: UDP multicast traffic only

### Container Tests  
- **Startup time**: ~2-5s per container
- **Resource usage**: Container overhead + image size
- **Scalability**: Limited by container runtime resources
- **Network overhead**: Bridge network setup + multicast traffic

### Recommendations

- Use **native parallel** for fast feedback during development
- Use **container testing** for integration testing and CI/CD pipelines
- Limit concurrent container tests to avoid resource exhaustion
- Use unique multicast groups to prevent test interference

## Advanced Usage

### Custom Test Scripts

Generate custom test scripts using the CMake framework:

```cmake
ut_add_parallel_process_test(
  NAME custom_test
  TARGETS 
    "my_server --port=8080 --role=server"
    "my_client --port=8080 --role=client --server=localhost"
    "my_monitor --port=8080 --role=monitor"
  PARALLEL
  TIMEOUT 60
  ENVIRONMENT "DEBUG=1" "LOG_LEVEL=trace"
)
```

### Custom Container Configuration

Use your own compose files:

```cmake
ut_add_compose_multiprocess_test(
  NAME custom_compose_test
  CUSTOM_COMPOSE
  COMPOSE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/my-custom-compose.yml"
  TIMEOUT 120
  ENABLE_LOGS
)
```

### MPI Integration

For MPI-based applications:

```cmake
include(cmake/MPITest.cmake)

ut_add_mpi_test(
  NAME mpi_collective_test
  TARGET my_mpi_binary
  PROCESSES 4
  TIMEOUT 60
)
```

## Migration Guide

### From File-Based to Network-Based Coordination

**Old approach (file-based):**
```cpp
// Write status file
std::ofstream("/tmp/ready") << "server_ready";

// Poll for status
while (!std::filesystem::exists("/tmp/client_ready")) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
}
```

**New approach (network-based):**
```cpp
multiprocess_fixture<true> fixture(2, "server");
fixture.sync_point("ready");  // Both processes wait here automatically
```

### From Sequential to Parallel Execution

**Old approach:**
```cmake
ut_add_multiprocess_test(
  NAME old_test
  SEQUENTIAL  # Processes run one after another
  TARGETS server client
)
```

**New approach:**
```cmake
ut_add_network_parallel_test(
  NAME new_test
  PARTICIPANTS 2  # Processes run simultaneously
  EXECUTABLE unified_binary
)
```