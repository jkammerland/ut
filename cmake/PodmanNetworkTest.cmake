# Podman Network Testing Support for boost.ut
# Provides containerized multiprocess testing with full network isolation
# Each container gets its own IP address and network stack
#
# NOTE: For simple multiprocess tests, use PodmanMultiprocessTest.cmake instead!
# This file provides advanced features for complex network scenarios.
#
# Simple symmetric API (recommended):
#   include(PodmanMultiprocessTest)
#   ut_add_podman_multiprocess_test(NAME test TARGET exe PARTICIPANTS 3)
#
# This file is for advanced use cases requiring:
# - Custom network configurations
# - Specific IP assignments
# - Complex client-server roles
# - Custom Docker image builds

# Check if podman is available
find_program(PODMAN_EXECUTABLE podman)

if(NOT PODMAN_EXECUTABLE)
  message(STATUS "Podman not found - podman network tests will be skipped")
  set(PODMAN_FOUND FALSE)
else()
  set(PODMAN_FOUND TRUE)
  message(STATUS "Found podman: ${PODMAN_EXECUTABLE}")
endif()

# Function to add a podman-based network test
function(ut_add_podman_network_test)
  set(options CLEANUP_ON_FAILURE)
  set(oneValueArgs NAME PARTICIPANTS IMAGE NETWORK_NAME NETWORK_SUBNET TIMEOUT MULTICAST_GROUP MULTICAST_PORT)
  set(multiValueArgs ADDITIONAL_ENV BUILD_CONTEXT)
  
  cmake_parse_arguments(PN "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  # Skip if podman not available
  if(NOT PODMAN_FOUND)
    message(STATUS "Skipping podman test ${PN_NAME} - podman not available")
    return()
  endif()
  
  # Validate required parameters
  if(NOT PN_NAME)
    message(FATAL_ERROR "ut_add_podman_network_test: NAME is required")
  endif()
  
  if(NOT PN_PARTICIPANTS)
    message(FATAL_ERROR "ut_add_podman_network_test: PARTICIPANTS is required")
  endif()
  
  if(NOT PN_IMAGE)
    message(FATAL_ERROR "ut_add_podman_network_test: IMAGE is required")
  endif()
  
  # Set defaults
  if(NOT PN_TIMEOUT)
    set(PN_TIMEOUT 60)  # Longer timeout for container setup
  endif()
  
  if(NOT PN_NETWORK_NAME)
    set(PN_NETWORK_NAME "${PN_NAME}-net")
  endif()
  
  if(NOT PN_NETWORK_SUBNET)
    set(PN_NETWORK_SUBNET "192.168.100.0/24")  # Use RFC1918 private range to avoid conflicts
  endif()
  
  if(NOT PN_MULTICAST_GROUP)
    set(PN_MULTICAST_GROUP "239.255.0.1")
  endif()
  
  if(NOT PN_MULTICAST_PORT)
    set(PN_MULTICAST_PORT 12345)
  endif()
  
  # Generate the test script
  set(TEST_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${PN_NAME}_podman_test.cmake")
  
  # Calculate base IP from subnet (assumes /24)
  string(REGEX MATCH "([0-9]+\\.[0-9]+\\.[0-9]+)\\." BASE_IP_MATCH "${PN_NETWORK_SUBNET}")
  if(CMAKE_MATCH_1)
    set(BASE_IP "${CMAKE_MATCH_1}")
  else()
    set(BASE_IP "192.168.100")  # Fallback
  endif()
  
  set(SCRIPT_CONTENT "# Auto-generated podman network test runner
set(PODMAN_EXECUTABLE \"${PODMAN_EXECUTABLE}\")
set(NETWORK_NAME \"${PN_NETWORK_NAME}\")
set(NETWORK_SUBNET \"${PN_NETWORK_SUBNET}\")
set(IMAGE_NAME \"${PN_IMAGE}\")
set(PARTICIPANT_COUNT ${PN_PARTICIPANTS})
set(TIMEOUT ${PN_TIMEOUT})
set(BASE_IP \"${BASE_IP}\")
set(MULTICAST_GROUP \"${PN_MULTICAST_GROUP}\")
set(MULTICAST_PORT ${PN_MULTICAST_PORT})
set(TEST_NAME \"${PN_NAME}\")
set(CLEANUP_ON_FAILURE ${PN_CLEANUP_ON_FAILURE})

# Function to execute podman command with error handling
function(podman_exec COMMAND_VAR RESULT_VAR)
  execute_process(
    COMMAND \${PODMAN_EXECUTABLE} \${COMMAND_VAR}
    RESULT_VARIABLE \${RESULT_VAR}
    OUTPUT_VARIABLE OUTPUT
    ERROR_VARIABLE ERROR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
  )
  
  if(NOT \${RESULT_VAR} EQUAL 0 AND OUTPUT)
    message(\"\${OUTPUT}\")
  endif()
  if(NOT \${RESULT_VAR} EQUAL 0 AND ERROR)
    message(\"\${ERROR}\")
  endif()
  
  return(PROPAGATE \${RESULT_VAR})
endfunction()

# Cleanup function
function(cleanup_test)
  message(\"Cleaning up podman test resources...\")
  
  # Stop and remove any running containers with our test label
  execute_process(
    COMMAND \${PODMAN_EXECUTABLE} ps -aq --filter \"label=ut-test=\${TEST_NAME}\"
    OUTPUT_VARIABLE CONTAINER_IDS
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  
  if(CONTAINER_IDS)
    string(REPLACE \"\\n\" \";\" CONTAINER_LIST \"\${CONTAINER_IDS}\")
    foreach(CONTAINER_ID IN LISTS CONTAINER_LIST)
      if(CONTAINER_ID)
        execute_process(COMMAND \${PODMAN_EXECUTABLE} stop \${CONTAINER_ID} OUTPUT_QUIET ERROR_QUIET)
        execute_process(COMMAND \${PODMAN_EXECUTABLE} rm \${CONTAINER_ID} OUTPUT_QUIET ERROR_QUIET)
      endif()
    endforeach()
  endif()
  
  # Remove network if it exists
  execute_process(
    COMMAND \${PODMAN_EXECUTABLE} network rm \${NETWORK_NAME}
    OUTPUT_QUIET ERROR_QUIET
  )
endfunction()

# Setup test environment
message(\"Setting up podman network test: \${TEST_NAME}\")

# Cleanup any existing resources
cleanup_test()

# Create network
message(\"Creating network: \${NETWORK_NAME} with subnet \${NETWORK_SUBNET}\")
execute_process(
  COMMAND \${PODMAN_EXECUTABLE} network create --subnet=\${NETWORK_SUBNET} \${NETWORK_NAME}
  RESULT_VARIABLE RESULT
  OUTPUT_VARIABLE OUTPUT
  ERROR_VARIABLE ERROR
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_STRIP_TRAILING_WHITESPACE
)
if(NOT RESULT EQUAL 0)
  if(OUTPUT)
    message(\"\${OUTPUT}\")
  endif()
  if(ERROR)
    message(\"\${ERROR}\")
  endif()
endif()
if(NOT RESULT EQUAL 0)
  message(FATAL_ERROR \"Failed to create podman network\")
endif()

# Start containers
set(CONTAINER_IDS \"\")
set(ALL_SUCCESS TRUE)

foreach(i RANGE 1 \${PARTICIPANT_COUNT})
  if(i EQUAL 1)
    set(ROLE \"server\")
  else()
    set(ROLE \"client\${i}\")
  endif()
  
  # Calculate IP address
  math(EXPR IP_SUFFIX \"\${i} + 1\")
  set(CONTAINER_IP \"\${BASE_IP}.\${IP_SUFFIX}\")
  
  # Container name
  set(CONTAINER_NAME \"\${TEST_NAME}-\${ROLE}\")
  
  message(\"Starting container: \${CONTAINER_NAME} with IP \${CONTAINER_IP}\")
  
  # Run container in background
  execute_process(
    COMMAND \${PODMAN_EXECUTABLE} run --rm --detach 
      --network=\${NETWORK_NAME} --ip=\${CONTAINER_IP} --name=\${CONTAINER_NAME} 
      --label=ut-test=\${TEST_NAME}
      -e PROCESS_ROLE=\${ROLE}
      -e SIMULATED_IP=\${CONTAINER_IP}
      -e MULTICAST_GROUP=\${MULTICAST_GROUP}
      -e MULTICAST_PORT=\${MULTICAST_PORT}
      -e PARTICIPANT_COUNT=\${PARTICIPANT_COUNT}
      \${IMAGE_NAME}
    RESULT_VARIABLE RESULT
    OUTPUT_VARIABLE OUTPUT
    ERROR_VARIABLE ERROR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
  )
  
  if(NOT RESULT EQUAL 0)
    if(OUTPUT)
      message(\"\${OUTPUT}\")
    endif()
    if(ERROR)
      message(\"\${ERROR}\")
    endif()
  endif()
  
  if(NOT RESULT EQUAL 0)
    message(\"Failed to start container \${CONTAINER_NAME}\")
    set(ALL_SUCCESS FALSE)
    break()
  else()
    list(APPEND CONTAINER_IDS \${CONTAINER_NAME})
  endif()
endforeach()

# If setup failed, cleanup and exit
if(NOT ALL_SUCCESS)
  cleanup_test()
  message(FATAL_ERROR \"Failed to start all containers\")
endif()

# Wait for containers to complete
message(\"Waiting for \${PARTICIPANT_COUNT} containers to complete...\")
set(ALL_SUCCESS TRUE)
set(FAILED_CONTAINERS \"\")

foreach(CONTAINER_NAME IN LISTS CONTAINER_IDS)
  message(\"Waiting for container: \${CONTAINER_NAME}\")
  
  # Wait for container with timeout
  execute_process(
    COMMAND \${PODMAN_EXECUTABLE} wait \${CONTAINER_NAME}
    TIMEOUT \${TIMEOUT}
    RESULT_VARIABLE WAIT_RESULT
    OUTPUT_VARIABLE EXIT_CODE
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  
  if(WAIT_RESULT EQUAL 0)
    # Container finished, check exit code
    if(NOT EXIT_CODE EQUAL 0)
      set(ALL_SUCCESS FALSE)
      list(APPEND FAILED_CONTAINERS \"\${CONTAINER_NAME} (exit code: \${EXIT_CODE})\")
      
      # Get container logs for debugging
      execute_process(
        COMMAND \${PODMAN_EXECUTABLE} logs \${CONTAINER_NAME}
        OUTPUT_VARIABLE LOGS
        ERROR_VARIABLE LOGS
      )
      message(\"Container \${CONTAINER_NAME} logs:\\n\${LOGS}\")
    else()
      message(\"Container \${CONTAINER_NAME} completed successfully\")
    endif()
  else()
    # Wait timed out or failed
    set(ALL_SUCCESS FALSE)
    list(APPEND FAILED_CONTAINERS \"\${CONTAINER_NAME} (timeout or wait failed)\")
    
    # Get container logs
    execute_process(
      COMMAND \${PODMAN_EXECUTABLE} logs \${CONTAINER_NAME}
      OUTPUT_VARIABLE LOGS
      ERROR_VARIABLE LOGS
    )
    message(\"Container \${CONTAINER_NAME} logs:\\n\${LOGS}\")
  endif()
endforeach()

# Cleanup
cleanup_test()

# Report results
if(ALL_SUCCESS)
  message(\"All \${PARTICIPANT_COUNT} containers completed successfully\")
else()
  list(JOIN FAILED_CONTAINERS \", \" FAILED_LIST)
  message(FATAL_ERROR \"Podman network test failed. Failed containers: \${FAILED_LIST}\")
endif()
")
  
  # Write the test script
  file(GENERATE OUTPUT "${TEST_SCRIPT}" CONTENT "${SCRIPT_CONTENT}")
  
  # Add the CTest test
  add_test(
    NAME ${PN_NAME}
    COMMAND ${CMAKE_COMMAND} -P "${TEST_SCRIPT}"
  )
  
  # Set test properties
  set_tests_properties(${PN_NAME} PROPERTIES
    TIMEOUT ${PN_TIMEOUT}
    LABELS "podman;network;multiprocess;container"
  )
  
  message(STATUS "Added podman network test: ${PN_NAME} with ${PN_PARTICIPANTS} containers")
endfunction()

# Convenience function for simple podman client-server tests
function(ut_add_podman_client_server_test)
  set(options CLEANUP_ON_FAILURE)
  set(oneValueArgs NAME IMAGE TIMEOUT)
  set(multiValueArgs ADDITIONAL_ENV)
  
  cmake_parse_arguments(PCS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT PCS_NAME OR NOT PCS_IMAGE)
    message(FATAL_ERROR "ut_add_podman_client_server_test: NAME and IMAGE are required")
  endif()
  
  # Use podman network test with 2 participants (server + client)
  ut_add_podman_network_test(
    NAME ${PCS_NAME}
    PARTICIPANTS 2
    IMAGE ${PCS_IMAGE}
    TIMEOUT ${PCS_TIMEOUT}
    ADDITIONAL_ENV ${PCS_ADDITIONAL_ENV}
    $<$<BOOL:${PCS_CLEANUP_ON_FAILURE}>:CLEANUP_ON_FAILURE>
  )
endfunction()

# Convenience function to build image and add test
function(ut_add_podman_network_test_with_build)
  set(options CLEANUP_ON_FAILURE)
  set(oneValueArgs NAME PARTICIPANTS IMAGE DOCKERFILE CONTEXT TIMEOUT)
  set(multiValueArgs ADDITIONAL_ENV BUILD_ARGS)
  
  cmake_parse_arguments(PNB "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT PODMAN_FOUND)
    return()
  endif()
  
  if(NOT PNB_NAME OR NOT PNB_IMAGE OR NOT PNB_DOCKERFILE)
    message(FATAL_ERROR "ut_add_podman_network_test_with_build: NAME, IMAGE, and DOCKERFILE are required")
  endif()
  
  if(NOT PNB_CONTEXT)
    set(PNB_CONTEXT "${CMAKE_SOURCE_DIR}")
  endif()
  
  # Add custom target to build the image
  set(BUILD_TARGET "${PNB_NAME}_build_image")
  
  set(BUILD_ARGS_LIST "")
  if(PNB_BUILD_ARGS)
    foreach(arg ${PNB_BUILD_ARGS})
      list(APPEND BUILD_ARGS_LIST "--build-arg" "${arg}")
    endforeach()
  endif()
  
  add_custom_target(${BUILD_TARGET}
    COMMAND ${PODMAN_EXECUTABLE} build 
      -f "${PNB_DOCKERFILE}"
      -t "${PNB_IMAGE}"
      ${BUILD_ARGS_LIST}
      "${PNB_CONTEXT}"
    COMMENT "Building podman image: ${PNB_IMAGE}"
    VERBATIM
  )
  
  # Add the network test
  ut_add_podman_network_test(
    NAME ${PNB_NAME}
    PARTICIPANTS ${PNB_PARTICIPANTS}
    IMAGE ${PNB_IMAGE}
    TIMEOUT ${PNB_TIMEOUT}
    ADDITIONAL_ENV ${PNB_ADDITIONAL_ENV}
    $<$<BOOL:${PNB_CLEANUP_ON_FAILURE}>:CLEANUP_ON_FAILURE>
  )
  
  # Make test depend on image build
  set_tests_properties(${PNB_NAME} PROPERTIES
    FIXTURES_REQUIRED "${BUILD_TARGET}_complete"
  )
  
  # Add fixture setup test to build image
  add_test(
    NAME ${BUILD_TARGET}_setup
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target ${BUILD_TARGET}
  )
  
  set_tests_properties(${BUILD_TARGET}_setup PROPERTIES
    FIXTURES_SETUP "${BUILD_TARGET}_complete"
    LABELS "podman;setup"
  )
endfunction()