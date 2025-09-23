# Podman Multiprocess Testing Guide

## Overview

This guide explains how to use rootless Podman for multiprocess testing where each process needs a unique IP address. This is essential for testing distributed systems, IP-based rate limiting, load balancing, and other network-aware features.

## Why Podman?

Traditional approaches like `bwrap` can only isolate processes but cannot create network configurations:
- **bwrap limitations**: Cannot create network devices (veth pairs, bridges, tap devices) without root
- **Podman solution**: Uses slirp4netns to emulate networking in userspace - no root required!

Each container automatically gets:
- Unique IP address (e.g., 10.150.0.2, 10.150.0.3, etc.)
- Full network stack
- Ability to communicate with other containers
- Support for UDP multicast

## Quick Start

### Prerequisites
```bash
# Install podman (no root required)
sudo apt-get install podman  # Ubuntu/Debian
sudo dnf install podman       # Fedora
```

### Basic Usage - Same Executable

```cmake
# In your CMakeLists.txt
include(${CMAKE_SOURCE_DIR}/cmake/PodmanMultiprocessTest.cmake)

# Build your test executable
add_executable(my_test test.cpp)
target_link_libraries(my_test PRIVATE Boost::ut Boost::system)

# Add podman multiprocess test - each process gets unique IP
ut_add_podman_multiprocess_test(
  NAME my_test_distributed
  TARGET my_test
  PARTICIPANTS 5  # 5 processes, each with unique IP
  TIMEOUT 30
)
```

### Advanced Usage - Different Executables

```cmake
# In your CMakeLists.txt
include(${CMAKE_SOURCE_DIR}/cmake/PodmanMultiprocessTest2.cmake)

# Build different executables
add_executable(server server.cpp)
add_executable(client client.cpp)
add_executable(monitor monitor.cpp)

# Run different executables, each with unique IP
ut_add_podman_multiprocess_test(
  NAME complex_test
  TARGETS
    server    # Process 0, IP: 10.x.0.2
    client    # Process 1, IP: 10.x.0.3
    client    # Process 2, IP: 10.x.0.4
    monitor   # Process 3, IP: 10.x.0.5
  TIMEOUT 60
)
```

## How It Works

1. **Network Creation**: Creates isolated network with unique subnet
2. **Container Launch**: Each executable runs in a container with unique IP
3. **Environment Variables**: Each process receives:
   - `PROCESS_ID`: Its index (0, 1, 2, ...)
   - `PARTICIPANT_COUNT`: Total number of processes
   - `MULTICAST_ADDRESS`: For coordination (default: 239.255.0.1)
   - `MULTICAST_PORT`: For coordination

4. **Automatic Cleanup**: Network and containers removed after test

## Writing Test Code

Your test code reads environment variables to determine its role:

```cpp
#include <cstdlib>
#include <iostream>

int main() {
    int process_id = std::atoi(std::getenv("PROCESS_ID"));
    int total = std::atoi(std::getenv("PARTICIPANT_COUNT"));

    std::cout << "Process " << process_id << " of " << total << std::endl;

    if (process_id == 0) {
        // I'm the coordinator/server
        run_server();
    } else {
        // I'm a client/worker
        run_client();
    }

    return 0;
}
```

## API Comparison

### Traditional Multiprocess (Same Host)
```cmake
ut_add_multiprocess_test(
  NAME test_local
  TARGET my_app
  PARTICIPANTS 3
)
```
- All processes share host IP
- Different ephemeral ports only
- Fast, simple

### Podman Multiprocess (Different IPs)
```cmake
ut_add_podman_multiprocess_test(
  NAME test_distributed
  TARGET my_app      # or TARGETS for different executables
  PARTICIPANTS 3
)
```
- Each process gets unique IP
- Simulates real distributed system
- Tests IP-based features

## Real-World Examples

### 1. Load Balancer Testing
```cmake
ut_add_podman_multiprocess_test(
  NAME load_balancer_test
  TARGETS
    load_balancer  # Gets IP .2
    web_server     # Gets IP .3
    web_server     # Gets IP .4
    web_server     # Gets IP .5
    client         # Gets IP .6
)
```

### 2. Database Cluster Testing
```cmake
ut_add_podman_multiprocess_test(
  NAME database_cluster
  TARGETS
    db_primary     # Process 0: Primary database
    db_replica     # Process 1: Replica 1
    db_replica     # Process 2: Replica 2
    db_arbiter     # Process 3: Arbiter
)
```

### 3. Microservices Testing
```cmake
ut_add_podman_multiprocess_test(
  NAME microservices
  TARGETS
    api_gateway
    auth_service
    user_service
    payment_service
    notification_service
)
```

## Debugging

### View Container IPs
```bash
# During test execution
podman ps  # List running containers
podman inspect <container> | grep IPAddress
```

### Check Logs
```bash
podman logs <test-name>-0  # Logs from process 0
podman logs <test-name>-1  # Logs from process 1
```

### Manual Testing
```bash
# Create network manually
podman network create test-net --subnet 10.99.0.0/24

# Run containers
podman run -d --network test-net --name proc0 fedora sleep 60
podman run -d --network test-net --name proc1 fedora sleep 60

# Check IPs
podman exec proc0 hostname -i  # 10.99.0.2
podman exec proc1 hostname -i  # 10.99.0.3

# Cleanup
podman rm -f proc0 proc1
podman network rm test-net
```

## File Locations

- **Simple API**: `/home/ai-dev1/repos/ut/cmake/PodmanMultiprocessTest.cmake`
- **Advanced API**: `/home/ai-dev1/repos/ut/cmake/PodmanMultiprocessTest2.cmake`
- **Examples**: `/home/ai-dev1/repos/ut/example/multiprocess/podman_*.cmake`
- **This Guide**: `/home/ai-dev1/repos/ut/docs/PODMAN_MULTIPROCESS_TESTING.md`

## Limitations & Notes

1. **Performance**: Container startup adds ~1-2s overhead vs native processes
2. **Library Dependencies**: Containers need access to shared libraries (handled automatically)
3. **Multicast**: Works within pod network, not across different networks
4. **Root Not Required**: Everything works with rootless podman
5. **SELinux**: Volume mounts use `:Z` flag for proper context (handled automatically)

## Migration Guide

### From bwrap
```bash
# Before: bwrap doesn't support networking
bwrap --unshare-net ./test  # Isolated but can't communicate

# After: Podman with networking
ut_add_podman_multiprocess_test(TARGET test PARTICIPANTS 3)
```

### From Same-Host Testing
```cmake
# Before: All on same IP
ut_add_multiprocess_test(NAME test TARGET app PARTICIPANTS 3)

# After: Each gets unique IP (just change function name!)
ut_add_podman_multiprocess_test(NAME test TARGET app PARTICIPANTS 3)
```

## Troubleshooting

### Podman not found
```bash
sudo apt-get install podman  # or dnf install podman
```

### Network conflicts
The cmake scripts automatically generate random subnets to avoid conflicts.

### Container fails to start
Check that the executable and required libraries are accessible:
```bash
ldd your_executable  # Check dependencies
```

### Tests timeout
Increase timeout in cmake:
```cmake
ut_add_podman_multiprocess_test(
  NAME test
  TARGET app
  PARTICIPANTS 5
  TIMEOUT 120  # Increase to 2 minutes
)
```

## Summary

Podman multiprocess testing provides:
- ✅ Unique IP per process without root
- ✅ Symmetric API with regular multiprocess tests
- ✅ Support for different executables
- ✅ Automatic network configuration
- ✅ Real distributed system simulation

Perfect for testing:
- IP-based rate limiting
- Load balancing
- Connection limits per IP
- Distributed algorithms
- Network protocols
- Microservices