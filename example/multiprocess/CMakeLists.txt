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
include(${CMAKE_SOURCE_DIR}/cmake/PodmanComposeTest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/SimpleComposeTest.cmake)

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

# Extensive Native Parallel Process Tests
# Large scale test with 5 participants (1 server + 4 clients)
ut_add_network_parallel_test(
  NAME parallel_large_scale_test
  PARTICIPANTS 5
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 60
  MULTICAST_GROUP "239.255.1.1"
  MULTICAST_PORT 13001
)

# High frequency test with rapid barrier crossing
ut_add_network_parallel_test(
  NAME parallel_rapid_barriers_test
  PARTICIPANTS 3
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 45
  MULTICAST_GROUP "239.255.1.2"
  MULTICAST_PORT 13002
  ADDITIONAL_ENV "RAPID_BARRIERS=1" "BARRIER_COUNT=10"
)

# Stress test with large event payloads
ut_add_network_parallel_test(
  NAME parallel_large_events_test
  PARTICIPANTS 4
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 50
  MULTICAST_GROUP "239.255.1.3"
  MULTICAST_PORT 13003
  ADDITIONAL_ENV "LARGE_EVENTS=1" "EVENT_SIZE=400"
)

# Timeout recovery test - one process delays
ut_add_network_parallel_test(
  NAME parallel_timeout_recovery_test
  PARTICIPANTS 3
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 35
  MULTICAST_GROUP "239.255.1.4"
  MULTICAST_PORT 13004
  ADDITIONAL_ENV "SIMULATE_DELAY=1" "DELAY_PROCESS=client2" "DELAY_SECONDS=5"
)

# Mixed sequential and parallel barriers test
ut_add_network_parallel_test(
  NAME parallel_mixed_sync_test
  PARTICIPANTS 4
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 55
  MULTICAST_GROUP "239.255.1.5"
  MULTICAST_PORT 13005
  ADDITIONAL_ENV "MIXED_BARRIERS=1" "SEQUENTIAL_FIRST=1"
)

# Error injection test - network failures
ut_add_network_parallel_test(
  NAME parallel_network_resilience_test
  PARTICIPANTS 3
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 40
  MULTICAST_GROUP "239.255.1.6"
  MULTICAST_PORT 13006
  ADDITIONAL_ENV "ERROR_INJECTION=1" "DROP_PROBABILITY=0.1"
)

# High participant count stress test
ut_add_network_parallel_test(
  NAME parallel_high_participant_test
  PARTICIPANTS 8
  EXECUTABLE boost_ut_network_coordination
  TIMEOUT 80
  MULTICAST_GROUP "239.255.1.7"
  MULTICAST_PORT 13007
  ADDITIONAL_ENV "HIGH_PARTICIPANT_MODE=1"
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

# Advanced Podman Compose Tests (Approach 3: Full Orchestration)
# These tests use podman-compose for advanced orchestration with dependency management,
# smart log extraction, and custom configuration support

if(PODMAN_COMPOSE_FOUND)
  # Basic compose test with startup dependencies
  ut_add_compose_network_test(
    NAME compose_basic_test
    PARTICIPANTS 2
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 90
    MULTICAST_GROUP "239.255.3.1"
    MULTICAST_PORT 15001
    STARTUP_ORDER  # Server starts first, then clients
    ENABLE_LOGS    # Extract logs for analysis
    CLEANUP_VOLUMES
  )
  
  # Multi-client compose test with complex dependencies
  ut_add_compose_network_test(
    NAME compose_multi_client_test
    PARTICIPANTS 4
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 120
    MULTICAST_GROUP "239.255.3.2"
    MULTICAST_PORT 15002
    STARTUP_ORDER
    ENABLE_LOGS
    ADDITIONAL_ENV "COMPLEX_SYNC=1" "CLIENT_DELAY=2"
  )
  
  # Auto-build and test with custom Containerfile
  ut_add_compose_network_test(
    NAME compose_auto_build_test
    PARTICIPANTS 3
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess-auto
    TIMEOUT 180  # Extra time for build
    MULTICAST_GROUP "239.255.3.3"
    MULTICAST_PORT 15003
    AUTO_BUILD
    BUILD_CONTEXT "${CMAKE_SOURCE_DIR}"
    DOCKERFILE "${CMAKE_CURRENT_SOURCE_DIR}/MultiprocessContainerfile"
    ENABLE_LOGS
    CLEANUP_VOLUMES
  )
  
  # High-scale compose test with many participants
  ut_add_compose_network_test(
    NAME compose_large_scale_test
    PARTICIPANTS 6
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 150
    MULTICAST_GROUP "239.255.3.4"
    MULTICAST_PORT 15004
    ENABLE_LOGS
    ADDITIONAL_ENV "LARGE_SCALE_MODE=1" "HEARTBEAT_INTERVAL=1"
  )
  
  # Sequential compose test (services start one by one)
  ut_add_compose_network_test(
    NAME compose_sequential_test
    PARTICIPANTS 3
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    SEQUENTIAL      # Forces sequential startup
    TIMEOUT 100
    MULTICAST_GROUP "239.255.3.5"
    MULTICAST_PORT 15005
    STARTUP_ORDER   # Each service depends on previous
    ENABLE_LOGS
  )
  
  # Resilience test with error injection
  ut_add_compose_network_test(
    NAME compose_resilience_test
    PARTICIPANTS 4
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 120
    MULTICAST_GROUP "239.255.3.6"
    MULTICAST_PORT 15006
    ENABLE_LOGS
    ADDITIONAL_ENV "ERROR_INJECTION=1" "FAILURE_RATE=0.05" "RECOVERY_TIMEOUT=10"
  )
  
else()
  message(STATUS "Podman compose tests skipped - podman-compose not found")
endif()

# Custom Compose Configuration Example
# Users can provide their own compose files for advanced scenarios
if(PODMAN_COMPOSE_FOUND)
  # Example of using a custom compose file (if it exists)
  set(CUSTOM_COMPOSE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/custom-compose.yml")
  if(EXISTS "${CUSTOM_COMPOSE_FILE}")
    ut_add_compose_multiprocess_test(
      NAME compose_custom_config_test
      CUSTOM_COMPOSE
      COMPOSE_FILE "${CUSTOM_COMPOSE_FILE}"
      TIMEOUT 120
      ENABLE_LOGS
      CLEANUP_VOLUMES
    )
    message(STATUS "Added custom compose test using: ${CUSTOM_COMPOSE_FILE}")
  endif()
endif()

# Simple Template-Based Compose Tests (Recommended Approach)
# These use a cleaner template-based approach for easier maintenance

if(PODMAN_COMPOSE_FOUND)
  # Basic template-based compose test
  ut_add_simple_compose_test(
    NAME simple_compose_test
    PARTICIPANTS 2
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 90
    MULTICAST_GROUP "239.255.5.1"
    MULTICAST_PORT 17001
    STARTUP_ORDER
    ENABLE_LOGS
    CLEANUP_VOLUMES
  )
  
  # Multi-participant test with dependencies
  ut_add_simple_compose_test(
    NAME simple_multi_test
    PARTICIPANTS 4
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 120
    MULTICAST_GROUP "239.255.5.2"
    MULTICAST_PORT 17002
    STARTUP_ORDER
    ENABLE_LOGS
    ADDITIONAL_ENV "COMPLEX_BARRIERS=1" "BARRIER_TIMEOUT=15"
  )
  
  # Large scale test
  ut_add_simple_compose_test(
    NAME simple_large_test
    PARTICIPANTS 6
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 150
    MULTICAST_GROUP "239.255.5.3"
    MULTICAST_PORT 17003
    ENABLE_LOGS
    ADDITIONAL_ENV "LARGE_SCALE=1" "EVENT_FREQUENCY=high"
  )
  
  # Fast parallel test (no startup order)
  ut_add_simple_compose_test(
    NAME simple_fast_test
    PARTICIPANTS 3
    EXECUTABLE boost_ut_network_coordination
    IMAGE ut-multiprocess
    TIMEOUT 60
    MULTICAST_GROUP "239.255.5.4"
    MULTICAST_PORT 17004
    ENABLE_LOGS
    ADDITIONAL_ENV "FAST_MODE=1"
  )
endif()

# Documentation for compose usage
# Users can run compose tests manually with:
# cd build/example/multiprocess
# podman-compose -f simple_compose_test_compose.yml -p simple-compose-test up