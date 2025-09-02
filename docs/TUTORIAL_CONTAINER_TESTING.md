# Tutorial: Container-Based Multiprocess Testing

This tutorial teaches you how to use boost.ut's container-based testing for isolated, realistic multiprocess testing with Podman/Docker containers.

## What You'll Learn

- How to set up container-based multiprocess tests
- Building and configuring test container images
- Using Docker Compose/Podman Compose for orchestration
- Network isolation and container coordination
- Log extraction and debugging container tests
- Custom compose configurations

## Prerequisites

- boost.ut testing framework
- Boost.ASIO library (for network coordination)
- Podman or Docker installed and working
- podman-compose or docker-compose
- CMake 3.28+
- Basic understanding of containers

## Step 1: Your First Container Test

Let's create a simple test that runs in containers with network isolation.

**Create `container_hello.cpp`:**
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
    
    "container environment"_test = [&] {
        expect(!role.empty()) << "PROCESS_ROLE must be set";
        expect(!ip.empty()) << "SIMULATED_IP must be set";
        
        std::cout << "Container " << role << " running at " << ip << std::endl;
        std::cout << "Hostname: " << get_env("HOSTNAME") << std::endl;
        std::cout << "Container: " << get_env("container") << std::endl;
    };
    
    "isolation verification"_test = [&] {
        // Each container has isolated filesystem, network, process space
        std::cout << "Process ID: " << getpid() << std::endl;
        
        if (role == "server") {
            std::cout << "[SERVER] Container server logic" << std::endl;
            expect(ip.find("192.168.") == 0) << "Server should have container network IP";
        } else {
            std::cout << "[CLIENT] Container client logic" << std::endl;
            expect(ip.find("192.168.") == 0) << "Client should have container network IP";
        }
    };
    
    return 0;
}
```

**Create `Containerfile`:**
```dockerfile
FROM fedora:41

# Install runtime dependencies
RUN dnf install -y boost-system && dnf clean all

# Create app directory
RUN mkdir /app
WORKDIR /app

# Copy test executable (will be built outside container)
COPY build/container_hello /app/
RUN chmod +x /app/container_hello

# Create non-root user for security
RUN useradd -r testuser && chown testuser:testuser /app
USER testuser

CMD ["./container_hello"]
```

**Add to `CMakeLists.txt`:**
```cmake
include(cmake/SimpleComposeTest.cmake)

# Build the test executable
add_executable(container_hello container_hello.cpp)
target_link_libraries(container_hello PRIVATE Boost::ut)

# Build container image
add_custom_target(build_container_hello_image
  COMMAND podman build -f ${CMAKE_CURRENT_SOURCE_DIR}/Containerfile -t container-hello-image .
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  DEPENDS container_hello
  COMMENT "Building container test image"
)

# Add container-based test
ut_add_simple_compose_test(
  NAME container_hello_test
  PARTICIPANTS 2
  EXECUTABLE "./container_hello"
  IMAGE container-hello-image
  TIMEOUT 60
  MULTICAST_GROUP "239.255.5.1"
  MULTICAST_PORT 17001
  STARTUP_ORDER
  ENABLE_LOGS
)
```

**Build and run:**
```bash
# Build test executable
cmake --build build

# Build container image
cmake --build build --target build_container_hello_image

# Run container test
ctest -R container_hello_test --output-on-failure
```

### What Happens

1. CMake builds your test executable
2. Podman builds a container image containing the executable
3. CMake generates a Docker Compose file with:
   - Isolated bridge network (192.168.X.0/24)
   - Static IP addresses for each container
   - Environment variables for role and coordination
   - Service dependencies (clients wait for server)
4. podman-compose starts containers in order and waits for completion
5. Logs are extracted and results reported to CTest

## Step 2: Network Coordination in Containers

Container tests can use the same network coordination as native tests.

**Create `container_coordination.cpp`:**
```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"  // Network fixture
#include <chrono>
#include <thread>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto ip = get_env("SIMULATED_IP");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "container network coordination"_test = [&] {
        std::cout << "[" << role << "] Starting at " << ip << std::endl;
        
        // Create fixture with container network settings
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.5.1", 17001);
        
        // Phase 1: Initialization barrier
        std::cout << "[" << role << "] Phase 1: Initializing" << std::endl;
        fixture.sync_point("init");
        
        // Container-specific work
        if (role == "server") {
            std::cout << "[SERVER] Server initialization complete" << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
        } else {
            std::cout << "[CLIENT] Client connecting to server" << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
        }
        
        // Phase 2: Work completion barrier
        std::cout << "[" << role << "] Phase 2: Work complete" << std::endl;
        fixture.sync_point("complete");
        
        std::cout << "[" << role << "] Container test completed" << std::endl;
        
        expect(true) << "Container coordination successful";
    };
    
    return 0;
}
```

**Update Containerfile:**
```dockerfile
FROM fedora:41

# Install runtime dependencies (including Boost.ASIO)
RUN dnf install -y boost-system boost-devel && dnf clean all

# Create app directory
RUN mkdir /app
WORKDIR /app

# Copy both executables
COPY build/container_hello /app/
COPY build/container_coordination /app/
RUN chmod +x /app/container_*

# Create non-root user
RUN useradd -r testuser && chown -R testuser:testuser /app
USER testuser

# Default to coordination test
CMD ["./container_coordination"]
```

**Add coordination test:**
```cmake
add_executable(container_coordination container_coordination.cpp)
target_link_libraries(container_coordination PRIVATE Boost::ut Boost::system)

ut_add_simple_compose_test(
  NAME container_coordination_test
  PARTICIPANTS 3  # 1 server + 2 clients
  EXECUTABLE "./container_coordination"
  IMAGE container-hello-image
  TIMEOUT 90
  MULTICAST_GROUP "239.255.5.2"
  MULTICAST_PORT 17002
  STARTUP_ORDER
  ENABLE_LOGS
  CLEANUP_VOLUMES
)
```

### Container Network Features

- **Isolated Networks**: Each test gets its own bridge network
- **Static IPs**: Containers get predictable IP addresses (192.168.X.101, 192.168.X.102, etc.)
- **Multicast Support**: UDP multicast works within the container network
- **DNS Resolution**: Containers can resolve each other by service name
- **Port Isolation**: No port conflicts between different tests

## Step 3: Advanced Container Configuration

**Multi-stage container builds:**
```dockerfile
# Build stage
FROM fedora:41 AS builder
RUN dnf install -y gcc-c++ cmake boost-devel && dnf clean all
COPY . /src
WORKDIR /src
RUN cmake -B build && cmake --build build

# Runtime stage
FROM fedora:41
RUN dnf install -y boost-system && dnf clean all
COPY --from=builder /src/build/my_test /app/
RUN useradd -r testuser && chown testuser /app
USER testuser
WORKDIR /app
CMD ["./my_test"]
```

**Custom environment variables:**
```cmake
ut_add_simple_compose_test(
  NAME advanced_container_test
  PARTICIPANTS 4
  EXECUTABLE "./advanced_test"
  IMAGE advanced-test-image
  TIMEOUT 120
  MULTICAST_GROUP "239.255.5.3"
  MULTICAST_PORT 17003
  STARTUP_ORDER
  ENABLE_LOGS
  ADDITIONAL_ENV 
    "LOG_LEVEL=debug"
    "PERFORMANCE_MODE=1"
    "WORKER_THREADS=4"
)
```

**Volume persistence:**
```cmake
ut_add_simple_compose_test(
  NAME persistent_data_test
  PARTICIPANTS 2
  EXECUTABLE "./data_test"
  IMAGE data-test-image
  TIMEOUT 60
  ENABLE_LOGS
  CLEANUP_VOLUMES  # Remove volumes after test
)
```

## Step 4: Custom Docker Compose Files

For complex scenarios, use custom compose files instead of generated ones.

**Create `custom-test-compose.yml`:**
```yaml
version: '3.8'

services:
  database:
    image: my-db-test-image
    container_name: test-database
    hostname: database
    environment:
      - PROCESS_ROLE=database
      - SIMULATED_IP=192.168.220.10
      - DB_MODE=primary
    networks:
      test-network:
        ipv4_address: 192.168.220.10
    volumes:
      - db-data:/data
      - test-logs:/logs
    healthcheck:
      test: ["CMD", "./health_check.sh"]
      interval: 5s
      retries: 3
      
  app-server:
    image: my-app-test-image
    container_name: test-app-server
    hostname: app-server
    environment:
      - PROCESS_ROLE=server
      - SIMULATED_IP=192.168.220.11
      - DATABASE_URL=database:5432
    networks:
      test-network:
        ipv4_address: 192.168.220.11
    depends_on:
      database:
        condition: service_healthy
    volumes:
      - test-logs:/logs
      
  client:
    image: my-client-test-image
    container_name: test-client
    hostname: client
    environment:
      - PROCESS_ROLE=client
      - SIMULATED_IP=192.168.220.12
      - SERVER_URL=http://app-server:8080
    networks:
      test-network:
        ipv4_address: 192.168.220.12
    depends_on:
      - app-server
    volumes:
      - test-logs:/logs

networks:
  test-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.220.0/24

volumes:
  db-data:
  test-logs:
```

**Use custom compose in CMake:**
```cmake
ut_add_compose_multiprocess_test(
  NAME custom_integration_test
  CUSTOM_COMPOSE
  COMPOSE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/custom-test-compose.yml"
  TIMEOUT 180
  ENABLE_LOGS
  CLEANUP_VOLUMES
)
```

### Custom Compose Features

- **Health Checks**: Wait for services to be ready before starting dependents
- **Multiple Images**: Different services can use different container images
- **Custom Networks**: Define your own network topology and IP ranges
- **Volume Management**: Persistent data and shared storage between containers
- **Service Dependencies**: Complex startup ordering with conditions

## Step 5: Log Extraction and Debugging

Container tests provide excellent debugging capabilities through log extraction.

**Enable comprehensive logging:**
```cmake
ut_add_simple_compose_test(
  NAME logged_test
  PARTICIPANTS 3
  EXECUTABLE "./debug_test"
  IMAGE debug-test-image
  TIMEOUT 120
  ENABLE_LOGS      # Extract container logs
  CLEANUP_VOLUMES  # Clean up after test
)
```

**Add logging to your test:**
```cpp
"detailed logging test"_test = [&] {
    // Log to stdout - will be captured in container logs
    std::cout << "=== TEST START ===" << std::endl;
    std::cout << "Role: " << role << std::endl;
    std::cout << "IP: " << ip << std::endl;
    std::cout << "Container ID: " << get_env("HOSTNAME") << std::endl;
    
    multiprocess_fixture<true> fixture(participant_count, role);
    
    std::cout << "Barrier 1: Starting coordination" << std::endl;
    fixture.sync_point("start");
    
    if (role == "server") {
        std::cout << "SERVER: Processing requests" << std::endl;
        // Server logic
    } else {
        std::cout << "CLIENT: Making requests" << std::endl;
        // Client logic
    }
    
    std::cout << "Barrier 2: Work complete" << std::endl;
    fixture.sync_point("complete");
    
    std::cout << "=== TEST END ===" << std::endl;
};
```

**Manual log inspection:**
```bash
# View live logs during test
podman-compose -f test_compose.yml logs -f

# View logs for specific service
podman logs test-server
podman logs test-client

# Extract logs to files
podman logs test-server > server.log
podman logs test-client > client.log

# Follow logs in real-time
podman logs -f test-server
```

## Step 6: Performance and Scaling

**Multi-participant scaling tests:**
```cmake
# Test with different participant counts
ut_add_simple_compose_test(
  NAME scaling_test_2
  PARTICIPANTS 2
  EXECUTABLE "./scaling_test"
  IMAGE scaling-test-image
  TIMEOUT 60
)

ut_add_simple_compose_test(
  NAME scaling_test_4
  PARTICIPANTS 4
  EXECUTABLE "./scaling_test"
  IMAGE scaling-test-image
  TIMEOUT 90
)

ut_add_simple_compose_test(
  NAME scaling_test_8
  PARTICIPANTS 8
  EXECUTABLE "./scaling_test"
  IMAGE scaling-test-image
  TIMEOUT 150
)
```

**Resource limits:**
```yaml
# In custom compose file
services:
  memory-limited-service:
    image: my-test-image
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
        reservations:
          memory: 256M
          cpus: '0.5'
```

**Performance monitoring in tests:**
```cpp
"performance measurement"_test = [&] {
    auto start = std::chrono::high_resolution_clock::now();
    
    multiprocess_fixture<true> fixture(participant_count, role);
    fixture.sync_point("perf_start");
    
    // Measured operation
    for (int i = 0; i < 1000; ++i) {
        std::string msg = "perf_test_" + std::to_string(i);
        std::vector<std::byte> data(msg.begin(), msg.end());
        fixture.send_event(data);
    }
    
    fixture.sync_point("perf_complete");
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    
    std::cout << "Performance: " << duration.count() << "ms for 1000 operations" << std::endl;
    expect(duration.count() < 5000) << "Should complete within 5 seconds";
};
```

## Step 7: Integration with CI/CD

**Build images in CI:**
```yaml
# .github/workflows/test.yml
- name: Build test images
  run: |
    cmake --build build --target build_container_hello_image
    cmake --build build --target build_advanced_test_image

- name: Run container tests
  run: |
    ctest -L compose --output-on-failure --parallel 2
```

**Multi-platform images:**
```dockerfile
# Use multi-arch base image
FROM --platform=$BUILDPLATFORM fedora:41

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "Building for $TARGETPLATFORM on $BUILDPLATFORM"
```

**Test isolation in CI:**
```cmake
# Use unique network subnets for CI
ut_add_simple_compose_test(
  NAME ci_safe_test
  PARTICIPANTS 3
  EXECUTABLE "./test"
  IMAGE test-image
  MULTICAST_GROUP "239.255.100.1"  # Unique range for CI
  MULTICAST_PORT 20001
  CLEANUP_VOLUMES
)
```

## Step 8: Troubleshooting Container Tests

**Common issues and solutions:**

**"Image not found" errors:**
```bash
# Check available images
podman images

# Build missing image
cmake --build build --target build_my_test_image

# Pull base image if needed
podman pull fedora:41
```

**Network connectivity issues:**
```bash
# Check container network
podman network ls
podman network inspect test-network

# Test multicast within container
podman run --rm -it --network test-network fedora:41 ping 239.255.5.1
```

**Container startup failures:**
```bash
# Check container logs
podman logs container-name

# Run container interactively for debugging
podman run --rm -it --network test-network my-test-image /bin/bash
```

**Volume permission issues:**
```dockerfile
# Ensure proper ownership in Containerfile
RUN useradd -r testuser && chown -R testuser:testuser /app
USER testuser
```

**Cleanup stuck containers:**
```bash
# Stop and remove all test containers
podman ps -a --filter name=test- --format="{{.ID}}" | xargs podman rm -f

# Clean up test networks
podman network prune -f

# Clean up test volumes
podman volume prune -f
```

## Step 9: Best Practices

**Container Image Optimization:**
```dockerfile
# Multi-stage build for smaller images
FROM fedora:41 AS build
# ... build steps ...

FROM fedora:41
# Only copy necessary runtime files
COPY --from=build /app/my_test /app/
RUN dnf install -y boost-system && dnf clean all
```

**Resource Management:**
- Limit concurrent container tests (use CTest `-j` flag)
- Clean up volumes with `CLEANUP_VOLUMES`
- Use appropriate timeouts (containers take longer to start)
- Monitor disk space usage with many container tests

**Security:**
- Always run containers as non-root user
- Don't copy sensitive data into images
- Use specific image tags instead of `latest`
- Keep base images updated

**Development Workflow:**
```bash
# Fast iteration cycle
cmake --build build                           # Build executable
cmake --build build --target build_image     # Rebuild container
ctest -R my_test --output-on-failure         # Run test
```

## Next Steps

Now that you understand container-based testing:

1. Combine with [Native Parallel Testing](TUTORIAL_NATIVE_PARALLEL_TESTING.md) for comprehensive testing
2. Read [Multiprocess Examples](MULTIPROCESS_EXAMPLES.md) for advanced container patterns
3. Check [Troubleshooting Guide](MULTIPROCESS_TROUBLESHOOTING.md) for container-specific issues
4. Explore [CMake Reference](CMAKE_MODULES_REFERENCE.md) for all container testing options

Container-based testing provides the most realistic testing environment with full isolation - perfect for integration tests and CI/CD pipelines where test isolation is critical.