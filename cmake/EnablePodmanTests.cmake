# Simple CMake integration for Podman multiprocess tests
# Minimal shell scripting - uses CMake and CTest directly

option(ENABLE_PODMAN_TESTS "Enable Podman-based multiprocess tests" OFF)

if(ENABLE_PODMAN_TESTS)
  find_program(PODMAN_EXECUTABLE podman)

  if(NOT PODMAN_EXECUTABLE)
    message(WARNING "ENABLE_PODMAN_TESTS=ON but podman not found")
    return()
  endif()

  # Check Podman is functional
  execute_process(
    COMMAND ${PODMAN_EXECUTABLE} --version
    RESULT_VARIABLE PODMAN_CHECK
    OUTPUT_QUIET ERROR_QUIET
  )

  if(NOT PODMAN_CHECK EQUAL 0)
    message(WARNING "Podman found but not functional")
    return()
  endif()

  message(STATUS "Podman tests enabled")

  # Function to add Podman test directly to CTest
  function(add_podman_multiprocess_ctest)
    set(oneValueArgs NAME TARGET PARTICIPANTS)
    cmake_parse_arguments(APM "" "${oneValueArgs}" "" ${ARGN})

    # Generate test driver as CMake script (no shell!)
    set(TEST_DRIVER "${CMAKE_CURRENT_BINARY_DIR}/${APM_NAME}_podman_driver.cmake")

    file(WRITE "${TEST_DRIVER}" "
# CMake-based Podman test driver (no shell scripting)
set(PODMAN \"${PODMAN_EXECUTABLE}\")
set(EXECUTABLE \"$<TARGET_FILE:${APM_TARGET}>\")
set(PARTICIPANTS ${APM_PARTICIPANTS})
set(TEST_NAME \"${APM_NAME}\")

# Generate unique network name
string(RANDOM LENGTH 8 ALPHABET \"0123456789\" RANDOM_ID)
set(NETWORK_NAME \"test-\${RANDOM_ID}\")

# Create network
execute_process(
  COMMAND \${PODMAN} network create \${NETWORK_NAME} --subnet 10.99.0.0/24
  RESULT_VARIABLE NET_RESULT
  OUTPUT_QUIET ERROR_QUIET
)

if(NOT NET_RESULT EQUAL 0)
  message(FATAL_ERROR \"Failed to create network\")
endif()

# Function to cleanup
function(cleanup_test)
  foreach(i RANGE 0 \${PARTICIPANTS})
    execute_process(
      COMMAND \${PODMAN} rm -f \${TEST_NAME}-\${i}
      OUTPUT_QUIET ERROR_QUIET
    )
  endforeach()
  execute_process(
    COMMAND \${PODMAN} network rm \${NETWORK_NAME}
    OUTPUT_QUIET ERROR_QUIET
  )
endfunction()

# Start containers
set(ALL_SUCCESS TRUE)
foreach(i RANGE 0 \$<MATH:EXPR:\${PARTICIPANTS}-1>)
  execute_process(
    COMMAND \${PODMAN} run -d --name \${TEST_NAME}-\${i} --network \${NETWORK_NAME}
      -v \${EXECUTABLE}:/test:ro,Z
      -e PROCESS_ID=\${i}
      -e PARTICIPANT_COUNT=\${PARTICIPANTS}
      -e MULTICAST_ADDRESS=239.255.0.1
      -e MULTICAST_PORT=15000
      multiprocess-test /test
    RESULT_VARIABLE RUN_RESULT
    OUTPUT_VARIABLE CONTAINER_ID
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT RUN_RESULT EQUAL 0)
    set(ALL_SUCCESS FALSE)
    break()
  endif()
endforeach()

# Wait for containers
if(ALL_SUCCESS)
  foreach(i RANGE 0 \$<MATH:EXPR:\${PARTICIPANTS}-1>)
    execute_process(
      COMMAND \${PODMAN} wait \${TEST_NAME}-\${i}
      TIMEOUT 30
      RESULT_VARIABLE WAIT_RESULT
      OUTPUT_VARIABLE EXIT_CODE
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if(NOT EXIT_CODE EQUAL 0)
      message(\"Container \${i} failed with exit code \${EXIT_CODE}\")
      set(ALL_SUCCESS FALSE)
    endif()
  endforeach()
endif()

# Cleanup
cleanup_test()

if(NOT ALL_SUCCESS)
  message(FATAL_ERROR \"Podman multiprocess test failed\")
endif()
")

    # Add as CTest test
    add_test(
      NAME ${APM_NAME}_podman
      COMMAND ${CMAKE_COMMAND} -P "${TEST_DRIVER}"
    )

    set_tests_properties(${APM_NAME}_podman PROPERTIES
      LABELS "podman;multiprocess"
      TIMEOUT 60
    )
  endfunction()

  # Automatically add Podman tests for existing multiprocess executables
  if(TARGET boost_ut_network_coordination)
    add_podman_multiprocess_ctest(
      NAME network_coordination
      TARGET boost_ut_network_coordination
      PARTICIPANTS 3
    )

    add_podman_multiprocess_ctest(
      NAME network_coordination_large
      TARGET boost_ut_network_coordination
      PARTICIPANTS 5
    )
  endif()

endif()