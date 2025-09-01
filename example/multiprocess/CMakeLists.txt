# Multiprocess Testing Examples

# Enable CTest for this directory
enable_testing()

# Find Boost for networking support
find_package(Boost REQUIRED COMPONENTS system)

# Include our multiprocess testing support
include(${CMAKE_SOURCE_DIR}/cmake/MultiprocessTest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/MPITest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/NetworkFixtureTest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/PodmanNetworkTest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/ParallelProcessTest.cmake)

# MPI Test Example
if(ENABLE_UT_MPI_TESTS)
  ut_require_mpi()  # Skip if MPI not available
endif()

if(MPI_FOUND)
  # Build MPI test executable
  ut_add_mpi_executable(
    NAME boost_ut_mpi_test
    SOURCES mpi_test.cpp
  )
  
  # Add MPI tests with different process counts
  ut_add_mpi_test(
    NAME mpi_test_2procs
    TARGET boost_ut_mpi_test
    PROCESSES 2
    TIMEOUT 30
  )
  
  ut_add_mpi_test(
    NAME mpi_test_4procs
    TARGET boost_ut_mpi_test  
    PROCESSES 4
    TIMEOUT 30
  )
  
  # Add scaling test
  ut_add_mpi_scaling_test(
    NAME mpi_scaling_test
    TARGET boost_ut_mpi_test
    PROCESS_COUNTS 1 2 3 4
  )
endif()

# Generic Multiprocess Test Example
add_executable(boost_ut_process1 process1.cpp)
target_link_libraries(boost_ut_process1 PRIVATE Boost::ut)

add_executable(boost_ut_process2 process2.cpp)
target_link_libraries(boost_ut_process2 PRIVATE Boost::ut)

add_executable(boost_ut_coordinator coordinator.cpp)
target_link_libraries(boost_ut_coordinator PRIVATE Boost::ut)

# Clean network coordination executable
add_executable(boost_ut_network_coordination network_coordination.cpp)
target_link_libraries(boost_ut_network_coordination PRIVATE Boost::ut Boost::system)

# Test multiple processes running in parallel
ut_add_multiprocess_test(
  NAME parallel_process_test
  PARALLEL
  TARGETS boost_ut_process1 boost_ut_process2
  TIMEOUT 20
)

# Test sequential execution
ut_add_multiprocess_test(
  NAME sequential_process_test
  SEQUENTIAL
  TARGETS boost_ut_process1 boost_ut_process2
  TIMEOUT 20
)

# Test with coordinator process
ut_add_multiprocess_test(
  NAME coordinated_test
  TARGETS boost_ut_coordinator boost_ut_process1 boost_ut_process2
  PARALLEL
  TIMEOUT 30
  ENVIRONMENT "TEST_MODE=coordinated"
)

# Network namespace example (requires bwrap)
find_program(BWRAP_EXECUTABLE bwrap)
if(BWRAP_EXECUTABLE)
  # Create wrapper script for network isolation
  configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/run_with_netns.sh.in
    ${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh
    @ONLY
  )
  
  # Add network-isolated test
  ut_add_multiprocess_test(
    NAME network_isolated_test
    COMMANDS 
      "${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh $<TARGET_FILE:boost_ut_process1>"
      "${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh $<TARGET_FILE:boost_ut_process2>"
    PARALLEL
    TIMEOUT 30
  )
endif()

# Parallel Process Tests (Fixed Approach: True Parallel Execution)
# Simple client-server test using shell background processes
ut_add_network_parallel_test(
  NAME parallel_network_test
  PARTICIPANTS 2
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 30
  MULTICAST_GROUP "239.255.0.1"
  MULTICAST_PORT 12345
)

# Multi-client network test (3 participants: 1 server + 2 clients)
ut_add_network_parallel_test(
  NAME parallel_multi_client_test
  PARTICIPANTS 3
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 45
  MULTICAST_GROUP "239.255.0.2"
  MULTICAST_PORT 12346
)

# Sequential test for ordered startup
ut_add_network_parallel_test(
  NAME sequential_network_test
  PARTICIPANTS 2
  EXECUTABLE boost_ut_network_coordination
  SEQUENTIAL
  TIMEOUT 30
  MULTICAST_GROUP "239.255.0.3"
  MULTICAST_PORT 12347
)

# Custom parallel process test
ut_add_parallel_process_test(
  NAME custom_parallel_test
  TARGETS
    "boost_ut_network_coordination --role=server --port=8080"
    "boost_ut_network_coordination --role=client --id=1"
    "boost_ut_network_coordination --role=client --id=2"
  PARALLEL
  TIMEOUT 45
  ENVIRONMENT
    "TEST_MODE=custom"
    "LOG_LEVEL=debug"
)

# Network Fixture Tests (DEPRECATED - Pipeline Bug)
# These use the old broken approach and should be replaced
# Simple client-server test using network coordination
ut_add_client_server_network_test(
  NAME network_coordination_test_old
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 30
)

# Multi-client network test (3 participants: 1 server + 2 clients)
ut_add_network_fixture_test(
  NAME multi_client_network_test_old
  PARTICIPANTS 3
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 45
  MULTICAST_GROUP "239.255.0.4"
  MULTICAST_PORT 12348
)

# Stress test with many participants
ut_add_network_fixture_test(
  NAME network_stress_test_old
  PARTICIPANTS 5
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 60
  ADDITIONAL_ENV "STRESS_MODE=1"
)

# Podman Network Tests (Approach 2: Container Testing)
# These tests provide full network isolation with each container getting its own IP/ports
if(PODMAN_FOUND)
  # Simple podman client-server test
  ut_add_podman_client_server_test(
    NAME podman_network_coordination_test
    IMAGE ut-network
    TIMEOUT 90
  )
  
  # Multi-container test with 3 participants (for testing encryption, complex protocols)
  ut_add_podman_network_test(
    NAME podman_multi_container_test
    PARTICIPANTS 3
    IMAGE ut-network
    NETWORK_SUBNET "172.21.0.0/24"
    MULTICAST_GROUP "239.255.0.3"
    MULTICAST_PORT 12347
    TIMEOUT 120
  )
  
  # Test with custom network and environment
  ut_add_podman_network_test(
    NAME podman_isolated_network_test
    PARTICIPANTS 2
    IMAGE ut-network
    NETWORK_NAME "ut-isolated-net"
    NETWORK_SUBNET "172.22.0.0/24"
    MULTICAST_GROUP "239.255.0.4"
    TIMEOUT 90
    ADDITIONAL_ENV "ENCRYPTION_MODE=1" "KEY_SIZE=256"
    CLEANUP_ON_FAILURE
  )
  
  # Build image and test in one step
  ut_add_podman_network_test_with_build(
    NAME podman_auto_build_test
    PARTICIPANTS 2
    IMAGE ut-network-auto
    DOCKERFILE "${CMAKE_CURRENT_SOURCE_DIR}/NetworkContainerfile"
    CONTEXT "${CMAKE_SOURCE_DIR}"
    TIMEOUT 150  # Extra time for building
  )
else()
  message(STATUS "Podman network tests skipped - podman not found")
endif()

# Clean podman-based network coordination  
# Use: podman-compose -f example/multiprocess/compose.yml up