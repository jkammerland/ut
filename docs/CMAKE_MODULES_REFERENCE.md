# CMake Modules Reference

This document provides complete reference for all multiprocess testing CMake modules in boost.ut.

## Module Overview

| Module | Purpose | Use Case | Status |
|--------|---------|----------|---------|
| `ParallelProcessTest.cmake` | Native parallel process execution | Fast development testing | **Recommended** |
| `SimpleComposeTest.cmake` | Template-based container orchestration | Container testing with minimal config | **Recommended** |
| `PodmanComposeTest.cmake` | Full-featured container orchestration | Complex container scenarios | Stable |
| `MultiprocessTest.cmake` | Basic sequential/parallel process execution | Simple process coordination | Legacy |
| `MPITest.cmake` | MPI application testing | HPC and distributed computing | Stable |
| `NetworkFixtureTest.cmake` | Network-based process coordination | Process coordination testing | **Deprecated** |
| `PodmanNetworkTest.cmake` | Direct podman container management | Low-level container testing | Stable |

## ParallelProcessTest.cmake

**Purpose**: Provides true parallel process execution with network-based coordination using shell scripts.

### Functions

#### `ut_add_network_parallel_test()`

Creates a test that runs multiple instances of the same executable in parallel with network coordination.

**Parameters:**
```cmake
ut_add_network_parallel_test(
  NAME test_name                    # Required: Test name for CTest
  PARTICIPANTS count                # Required: Number of processes (2-8 recommended)
  EXECUTABLE binary_name            # Required: Executable to run
  TIMEOUT seconds                   # Optional: Test timeout (default: 30)
  MULTICAST_GROUP address           # Optional: UDP multicast group (default: 239.255.0.1)
  MULTICAST_PORT port               # Optional: UDP port (default: 12345)
  ADDITIONAL_ENV "VAR1=val1" "VAR2=val2"  # Optional: Extra environment variables
  SEQUENTIAL                        # Optional: Run processes sequentially instead of parallel
)
```

**Generated Environment Variables:**
- `PROCESS_ROLE`: `server`, `client2`, `client3`, etc.
- `SIMULATED_IP`: `127.0.0.2`, `127.0.0.3`, etc.
- `MULTICAST_GROUP`: Configured multicast address
- `MULTICAST_PORT`: Configured UDP port
- `PARTICIPANT_COUNT`: Total number of processes

**Example:**
```cmake
include(cmake/ParallelProcessTest.cmake)

ut_add_network_parallel_test(
  NAME multiprocess_coordination
  PARTICIPANTS 3
  EXECUTABLE network_test_binary
  TIMEOUT 60
  MULTICAST_GROUP "239.255.1.1"
  MULTICAST_PORT 13001
  ADDITIONAL_ENV "LOG_LEVEL=debug" "STRESS_MODE=1"
)
```

#### `ut_add_parallel_process_test()`

Lower-level function for custom process configurations.

**Parameters:**
```cmake
ut_add_parallel_process_test(
  NAME test_name
  TARGETS "executable1 args" "executable2 args"  # List of command lines
  PARALLEL                          # Optional: Run in parallel (default)
  SEQUENTIAL                        # Optional: Run sequentially
  TIMEOUT seconds                   # Optional: Test timeout
  ENVIRONMENT "VAR=val"             # Optional: Environment variables
)
```

**Generated Files:**
- `${test_name}_runner.sh`: Shell script with proper parallel execution
- CTest configuration with appropriate labels and timeouts

## SimpleComposeTest.cmake

**Purpose**: Template-based container orchestration using podman-compose with minimal configuration.

### Functions

#### `ut_add_simple_compose_test()`

Creates a container-based test using compose template substitution.

**Parameters:**
```cmake
ut_add_simple_compose_test(
  NAME test_name                    # Required: Test name
  PARTICIPANTS count                # Optional: Number of containers (default: 2)
  EXECUTABLE binary_name            # Required: Executable path in container
  IMAGE image_name                  # Optional: Container image (default: ut-multiprocess)
  TIMEOUT seconds                   # Optional: Test timeout (default: 90)
  MULTICAST_GROUP address           # Optional: Multicast group
  MULTICAST_PORT port               # Optional: UDP port
  NETWORK_SUBNET subnet             # Optional: Container network subnet
  STARTUP_ORDER                     # Optional: Add container dependencies
  ENABLE_LOGS                       # Optional: Extract and analyze logs
  CLEANUP_VOLUMES                   # Optional: Remove volumes after test
  ADDITIONAL_ENV "VAR=val"          # Optional: Environment variables
)
```

**Generated Files:**
- `${test_name}_compose.yml`: Docker Compose file from template
- `${test_name}_compose_runner.sh`: Test execution script
- CTest configuration with compose-specific labels

**Example:**
```cmake
include(cmake/SimpleComposeTest.cmake)

ut_add_simple_compose_test(
  NAME container_coordination_test
  PARTICIPANTS 4
  EXECUTABLE "./network_test"
  IMAGE my-test-image
  TIMEOUT 120
  MULTICAST_GROUP "239.255.5.1"
  MULTICAST_PORT 17001
  STARTUP_ORDER
  ENABLE_LOGS
  CLEANUP_VOLUMES
  ADDITIONAL_ENV "DEBUG=1" "TIMEOUT=30"
)
```

**Requirements:**
- Template file: `compose-template.yml` in source directory
- Container image with test executable in `/app/`
- podman-compose installed and available

## PodmanComposeTest.cmake

**Purpose**: Full-featured container orchestration with dynamic compose file generation.

### Functions

#### `ut_add_compose_multiprocess_test()`

Advanced compose test with full configuration options.

**Parameters:**
```cmake
ut_add_compose_multiprocess_test(
  NAME test_name
  EXECUTABLE binary_name
  PARTICIPANTS count                # Optional: Auto-generated services
  CUSTOM_SERVICES service_list      # Optional: Use custom service definitions
  TIMEOUT seconds
  IMAGE image_name
  COMPOSE_FILE path                 # Optional: Custom compose file path
  BUILD_CONTEXT path                # Optional: Docker build context
  DOCKERFILE path                   # Optional: Container build file
  NETWORK_NAME name                 # Optional: Custom network name
  NETWORK_SUBNET subnet             # Optional: Custom subnet
  PROJECT_NAME name                 # Optional: Compose project name
  MULTICAST_GROUP address
  MULTICAST_PORT port
  DEPENDENCIES dep1 dep2            # Optional: Service dependencies
  VOLUMES vol1 vol2                 # Optional: Volume definitions
  STARTUP_ORDER                     # Optional: Sequential startup
  ENABLE_LOGS                       # Optional: Log extraction
  CLEANUP_VOLUMES                   # Optional: Volume cleanup
  CUSTOM_COMPOSE                    # Optional: Use provided compose file
  AUTO_BUILD                        # Optional: Build image during test
  ADDITIONAL_ENV "VAR=val"
)
```

#### `ut_add_compose_network_test()`

Convenience wrapper for network-based compose tests.

**Example:**
```cmake
include(cmake/PodmanComposeTest.cmake)

ut_add_compose_network_test(
  NAME advanced_container_test
  PARTICIPANTS 6
  EXECUTABLE network_coordinator
  IMAGE ut-multiprocess
  TIMEOUT 180
  MULTICAST_GROUP "239.255.3.1"
  MULTICAST_PORT 15001
  AUTO_BUILD
  BUILD_CONTEXT "${CMAKE_SOURCE_DIR}"
  DOCKERFILE "${CMAKE_CURRENT_SOURCE_DIR}/TestContainerfile"
  STARTUP_ORDER
  ENABLE_LOGS
  CLEANUP_VOLUMES
  ADDITIONAL_ENV "SCALE_MODE=1" "WORKER_COUNT=4"
)
```

## MultiprocessTest.cmake

**Purpose**: Basic multiprocess testing with sequential or simple parallel execution.

### Functions

#### `ut_add_multiprocess_test()`

Traditional multiprocess test execution.

**Parameters:**
```cmake
ut_add_multiprocess_test(
  NAME test_name
  TARGETS executable1 executable2   # List of executables
  COMMANDS "cmd1" "cmd2"            # Alternative: custom commands
  PARALLEL                          # Optional: Run in parallel
  SEQUENTIAL                        # Optional: Run sequentially (default)
  TIMEOUT seconds
  ENVIRONMENT "VAR=val"
)
```

**Limitations:**
- No network coordination
- Basic parallel execution (may have race conditions)
- Limited error handling

## MPITest.cmake

**Purpose**: MPI application testing with mpirun integration.

### Functions

#### `ut_add_mpi_executable()`

Configure an executable for MPI testing.

**Parameters:**
```cmake
ut_add_mpi_executable(
  NAME target_name
  SOURCES source1.cpp source2.cpp
  LIBRARIES lib1 lib2              # Optional: Additional libraries
)
```

#### `ut_add_mpi_test()`

Create MPI test with specified process count.

**Parameters:**
```cmake
ut_add_mpi_test(
  NAME test_name
  TARGET executable_target
  PROCESSES count                   # Number of MPI processes
  TIMEOUT seconds
  ARGUMENTS "--arg1" "--arg2"       # Optional: Command arguments
)
```

#### `ut_add_mpi_scaling_test()`

Test with multiple process counts.

**Parameters:**
```cmake
ut_add_mpi_scaling_test(
  NAME base_test_name
  TARGET executable_target
  PROCESS_COUNTS 1 2 4 8           # List of process counts to test
  TIMEOUT seconds
)
```

**Example:**
```cmake
include(cmake/MPITest.cmake)

# Check MPI availability
ut_require_mpi()

# Build MPI executable
ut_add_mpi_executable(
  NAME collective_operations_test
  SOURCES mpi_collective_test.cpp
  LIBRARIES MPI::MPI_CXX
)

# Add scaling tests
ut_add_mpi_scaling_test(
  NAME mpi_collective_scaling
  TARGET collective_operations_test
  PROCESS_COUNTS 2 4 8 16
  TIMEOUT 120
)
```

## PodmanNetworkTest.cmake

**Purpose**: Direct podman container management without compose.

### Functions

#### `ut_add_podman_network_test()`

Container test with manual podman commands.

**Parameters:**
```cmake
ut_add_podman_network_test(
  NAME test_name
  PARTICIPANTS count
  IMAGE image_name
  NETWORK_NAME name                 # Optional: Custom network name
  NETWORK_SUBNET subnet             # Optional: Custom subnet
  MULTICAST_GROUP address
  MULTICAST_PORT port
  TIMEOUT seconds
  ADDITIONAL_ENV "VAR=val"
  CLEANUP_ON_FAILURE               # Optional: Clean up on test failure
)
```

#### `ut_add_podman_client_server_test()`

Two-container client-server test.

**Parameters:**
```cmake
ut_add_podman_client_server_test(
  NAME test_name
  IMAGE image_name
  TIMEOUT seconds
  SERVER_ARGS "--port=8080"         # Optional: Server arguments
  CLIENT_ARGS "--server=server"     # Optional: Client arguments
)
```

## Usage Patterns

### Development Testing (Fast Feedback)

```cmake
# Use native parallel for rapid development
include(cmake/ParallelProcessTest.cmake)

ut_add_network_parallel_test(
  NAME dev_test
  PARTICIPANTS 2
  EXECUTABLE quick_test
  TIMEOUT 30
)
```

### Integration Testing (Isolation)

```cmake
# Use simple compose for integration tests  
include(cmake/SimpleComposeTest.cmake)

ut_add_simple_compose_test(
  NAME integration_test
  PARTICIPANTS 4
  EXECUTABLE integration_binary
  IMAGE integration-test-image
  TIMEOUT 120
  STARTUP_ORDER
  ENABLE_LOGS
)
```

### CI/CD Pipeline Testing

```cmake
# Use full compose features for CI
include(cmake/PodmanComposeTest.cmake)

ut_add_compose_network_test(
  NAME ci_test
  PARTICIPANTS 6
  EXECUTABLE ci_test_binary
  AUTO_BUILD
  DOCKERFILE "${CMAKE_CURRENT_SOURCE_DIR}/CIContainerfile"
  BUILD_CONTEXT "${CMAKE_SOURCE_DIR}"
  TIMEOUT 300
  ENABLE_LOGS
  CLEANUP_VOLUMES
)
```

### MPI/HPC Testing

```cmake
# Use MPI module for distributed computing
include(cmake/MPITest.cmake)

ut_add_mpi_scaling_test(
  NAME hpc_scaling_test
  TARGET distributed_algorithm
  PROCESS_COUNTS 1 2 4 8 16 32
  TIMEOUT 600
)
```

## Best Practices

### Choosing the Right Module

1. **Development/Debug**: Use `ParallelProcessTest` for fastest feedback
2. **Integration Testing**: Use `SimpleComposeTest` for container isolation  
3. **Complex Scenarios**: Use `PodmanComposeTest` for advanced container features
4. **MPI Applications**: Use `MPITest` for distributed computing tests
5. **Legacy Code**: Use `MultiprocessTest` for existing simple process tests

### Performance Optimization

- **Parallel over Sequential**: Use parallel execution when processes can run concurrently
- **Unique Multicast Groups**: Prevent interference between concurrent tests
- **Appropriate Timeouts**: Balance test reliability with execution speed
- **Resource Limits**: Limit concurrent container tests to prevent resource exhaustion

### Maintainability

- **Consistent Naming**: Use descriptive test names with consistent patterns
- **Environment Variables**: Use ADDITIONAL_ENV for test-specific configuration
- **Image Management**: Build test images separately from test execution when possible
- **Documentation**: Document complex test scenarios in code comments