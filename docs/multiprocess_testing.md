# Multiprocess Testing with boost.ut

This guide explains how to test multiprocess applications using boost.ut without any framework modifications.

## Overview

The multiprocess testing support consists of:
- CMake functions for orchestrating multiple processes
- MPI test support with standard CMake FindMPI
- Network namespace isolation using bwrap
- Examples showing different testing patterns

## Basic Multiprocess Testing

### CMake Setup

Include the multiprocess testing support in your CMakeLists.txt:

```cmake
include(cmake/MultiprocessTest.cmake)
```

### Running Multiple Processes

Use `ut_add_multiprocess_test()` to run multiple executables as a single test:

```cmake
# Run processes in parallel
ut_add_multiprocess_test(
  NAME my_parallel_test
  PARALLEL
  TARGETS process1 process2 process3
  TIMEOUT 30
)

# Run processes sequentially
ut_add_multiprocess_test(
  NAME my_sequential_test
  SEQUENTIAL
  TARGETS setup_process main_process cleanup_process
  TIMEOUT 60
)
```

### Test Return Codes

The test passes only if ALL processes return 0. Any non-zero return code causes the entire test to fail.

## MPI Testing

### Setup

```cmake
include(cmake/MPITest.cmake)

# Skip if MPI not available
ut_require_mpi()

# Build MPI test executable
ut_add_mpi_executable(
  NAME my_mpi_test
  SOURCES mpi_test.cpp
)

# Add MPI test
ut_add_mpi_test(
  NAME mpi_test_4procs
  TARGET my_mpi_test
  PROCESSES 4
  TIMEOUT 30
)
```

### Writing MPI Tests

MPI tests use standard boost.ut syntax:

```cpp
#include <boost/ut.hpp>
#include <mpi.h>

int main(int argc, char* argv[]) {
  MPI_Init(&argc, &argv);
  
  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);
  
  using namespace boost::ut;
  
  "MPI test"_test = [&] {
    // Each rank runs this test
    expect(rank >= 0);
    expect(rank < size);
    
    // Rank-specific assertions
    if (rank == 0) {
      expect(size >= 2) << "Need at least 2 processes";
    }
  };
  
  MPI_Finalize();
  return 0;
}
```

## Network Isolation with bwrap

For testing applications that need separate network stacks (e.g., UDP servers with DTLS):

### Basic Network Isolation

Each process gets its own network namespace:

```bash
#!/bin/bash
# run_with_netns.sh
bwrap \
  --unshare-net \
  --ro-bind /usr /usr \
  --proc /proc \
  --dev /dev \
  "$@"
```

### Advanced: Virtual Ethernet Pairs

For processes that need to communicate:

```bash
# Create network namespaces with veth pairs
sudo ./run_with_veth.sh ns1 veth1 192.168.1.10 ./server
sudo ./run_with_veth.sh ns2 veth2 192.168.1.20 ./client
```

### CMake Integration

```cmake
find_program(BWRAP_EXECUTABLE bwrap)
if(BWRAP_EXECUTABLE)
  ut_add_multiprocess_test(
    NAME isolated_network_test
    COMMANDS 
      "${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh $<TARGET_FILE:server>"
      "${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh $<TARGET_FILE:client>"
    PARALLEL
  )
endif()
```

## Inter-Process Communication Patterns

### File-Based Coordination

Simple pattern for test coordination:

```cpp
// Write status
void write_status(const std::string& status) {
  std::ofstream file("/tmp/process_status.txt");
  file << status << std::endl;
}

// Read status with timeout
bool wait_for_status(const std::string& expected, int timeout_ms) {
  auto start = std::chrono::steady_clock::now();
  while (std::chrono::steady_clock::now() - start < 
         std::chrono::milliseconds(timeout_ms)) {
    std::ifstream file("/tmp/process_status.txt");
    std::string status;
    if (std::getline(file, status) && status == expected) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return false;
}
```

## Benefits

1. **No Framework Changes**: Works with standard boost.ut
2. **CMake Integration**: Appears as single CTest tests
3. **Portable**: CMake handles platform differences
4. **Flexible**: Support for parallel, sequential, and MPI execution
5. **Network Isolation**: True separate network stacks when needed

## Running Tests

```bash
# Run all tests
ctest

# Run only multiprocess tests
ctest -R multiprocess

# Run with verbose output
ctest -V

# Run specific MPI test
ctest -R mpi_test_4procs
```

## Debugging

For debugging multiprocess tests:

```bash
# Run with output on failure
ctest --output-on-failure

# Run single test with full output
ctest -R my_test -V

# For MPI debugging
mpirun -np 4 xterm -e gdb ./my_mpi_test
```

## Examples

See `example/multiprocess/` for complete examples:
- `mpi_test.cpp` - MPI collective operations testing
- `process1.cpp`, `process2.cpp` - Inter-process coordination
- `coordinator.cpp` - Process orchestration example
- `run_with_netns.sh` - Network isolation script