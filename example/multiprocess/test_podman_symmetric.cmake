# Test the new symmetric Podman API with existing network coordination tests

# Include the new symmetric API
include(${CMAKE_SOURCE_DIR}/cmake/PodmanMultiprocessTest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/PodmanMultiprocessTest2.cmake)

# The existing network coordination executable
set(NETWORK_COORD_TARGET boost_ut_network_coordination)

# Test 1: Simple symmetric test - same executable, multiple instances
ut_add_podman_multiprocess_test(
  NAME network_coord_podman_3
  TARGET ${NETWORK_COORD_TARGET}
  PARTICIPANTS 3
  TIMEOUT 30
)

ut_add_podman_multiprocess_test(
  NAME network_coord_podman_5
  TARGET ${NETWORK_COORD_TARGET}
  PARTICIPANTS 5
  TIMEOUT 45
)

# Test 2: Batch test with different participant counts
ut_add_podman_multiprocess_batch_test(
  NAME network_coord_scaling
  TARGET ${NETWORK_COORD_TARGET}
  PARTICIPANT_COUNTS 2 4 6 8
  TIMEOUT 60
)

# Test 3: Compare with regular multiprocess (for performance comparison)
if(TEST_PERFORMANCE_COMPARISON)
  # Regular multiprocess test (same host)
  ut_add_multiprocess_test(
    NAME network_coord_local
    TARGET ${NETWORK_COORD_TARGET}
    PARTICIPANTS 4
    TIMEOUT 30
  )

  # Podman version (different IPs)
  ut_add_podman_multiprocess_test(
    NAME network_coord_podman
    TARGET ${NETWORK_COORD_TARGET}
    PARTICIPANTS 4
    TIMEOUT 30
  )

  # Add performance comparison test
  add_test(
    NAME compare_performance
    COMMAND ${CMAKE_COMMAND} -E echo "Compare times of network_coord_local vs network_coord_podman"
  )
endif()

# Test 4: Test with different executables (if we had them)
if(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/server" AND EXISTS "${CMAKE_CURRENT_BINARY_DIR}/client")
  ut_add_podman_multiprocess_test(
    NAME mixed_server_client
    TARGETS
      server   # Process 0
      client   # Process 1
      client   # Process 2
      client   # Process 3
    TIMEOUT 45
  )
endif()

# Report what tests were added
message(STATUS "")
message(STATUS "Podman Symmetric API Tests Added:")
message(STATUS "  - network_coord_podman_3: 3 processes with unique IPs")
message(STATUS "  - network_coord_podman_5: 5 processes with unique IPs")
message(STATUS "  - network_coord_scaling_*: Scaling tests with 2,4,6,8 processes")
message(STATUS "")
message(STATUS "To run these tests:")
message(STATUS "  ctest -R network_coord_podman")
message(STATUS "")
message(STATUS "To run a specific test:")
message(STATUS "  ctest -R network_coord_podman_3 -V")