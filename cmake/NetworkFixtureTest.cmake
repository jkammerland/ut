# Network Fixture Testing Support for boost.ut
# Provides automated multiprocess testing with UDP multicast coordination
# Uses the multiprocess_fixture class with network-based synchronization

# Function to add a network fixture test with automatic role/IP assignment
function(ut_add_network_fixture_test)
  set(options "")
  set(oneValueArgs NAME PARTICIPANTS EXECUTABLE TIMEOUT MULTICAST_GROUP MULTICAST_PORT)
  set(multiValueArgs ADDITIONAL_ENV)
  
  cmake_parse_arguments(NF "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  # Validate required parameters
  if(NOT NF_NAME)
    message(FATAL_ERROR "ut_add_network_fixture_test: NAME is required")
  endif()
  
  if(NOT NF_PARTICIPANTS)
    message(FATAL_ERROR "ut_add_network_fixture_test: PARTICIPANTS is required")
  endif()
  
  if(NOT NF_EXECUTABLE)
    message(FATAL_ERROR "ut_add_network_fixture_test: EXECUTABLE is required")
  endif()
  
  # Set defaults
  if(NOT NF_TIMEOUT)
    set(NF_TIMEOUT 30)
  endif()
  
  if(NOT NF_MULTICAST_GROUP)
    set(NF_MULTICAST_GROUP "239.255.0.1")
  endif()
  
  if(NOT NF_MULTICAST_PORT)
    set(NF_MULTICAST_PORT 12345)
  endif()
  
  # Build the list of commands with environment variables
  set(COMMANDS_LIST "")
  set(ENV_LIST "")
  
  # Assign roles and IPs to each participant
  # First participant is server, rest are clients
  foreach(i RANGE 1 ${NF_PARTICIPANTS})
    if(i EQUAL 1)
      set(ROLE "server")
    else()
      set(ROLE "client${i}")
    endif()
    
    # Use loopback IPs for native testing (127.0.0.x)
    math(EXPR IP_SUFFIX "${i} + 1")
    set(IP "127.0.0.${IP_SUFFIX}")
    
    # Add to environment list
    list(APPEND ENV_LIST 
      "PROCESS_ROLE=${ROLE}"
      "SIMULATED_IP=${IP}"
      "MULTICAST_GROUP=${NF_MULTICAST_GROUP}"
      "MULTICAST_PORT=${NF_MULTICAST_PORT}"
      "PARTICIPANT_COUNT=${NF_PARTICIPANTS}"
    )
    
    # Add any additional environment variables
    if(NF_ADDITIONAL_ENV)
      list(APPEND ENV_LIST ${NF_ADDITIONAL_ENV})
    endif()
  endforeach()
  
  # Create commands for each participant
  foreach(i RANGE 1 ${NF_PARTICIPANTS})
    if(i EQUAL 1)
      set(ROLE "server")
    else()
      set(ROLE "client${i}")
    endif()
    
    math(EXPR IP_SUFFIX "${i} + 1")
    set(IP "127.0.0.${IP_SUFFIX}")
    
    # Build environment string for this process
    set(PROCESS_ENV 
      "PROCESS_ROLE=${ROLE}"
      "SIMULATED_IP=${IP}"
      "MULTICAST_GROUP=${NF_MULTICAST_GROUP}"
      "MULTICAST_PORT=${NF_MULTICAST_PORT}"
      "PARTICIPANT_COUNT=${NF_PARTICIPANTS}"
    )
    
    if(NF_ADDITIONAL_ENV)
      list(APPEND PROCESS_ENV ${NF_ADDITIONAL_ENV})
    endif()
    
    # For targets, use generator expression
    if(TARGET ${NF_EXECUTABLE})
      list(APPEND COMMANDS_LIST "$<TARGET_FILE:${NF_EXECUTABLE}>")
    else()
      list(APPEND COMMANDS_LIST "${NF_EXECUTABLE}")
    endif()
  endforeach()
  
  # Use the existing multiprocess test infrastructure
  # We need to run each command with its own environment variables
  # This requires creating a wrapper script for each process
  
  set(TEST_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${NF_NAME}_network_test.cmake")
  
  # Generate the test script content
  set(SCRIPT_CONTENT "# Auto-generated network fixture test runner
set(TIMEOUT ${NF_TIMEOUT})
set(PARTICIPANT_COUNT ${NF_PARTICIPANTS})
set(MULTICAST_GROUP \"${NF_MULTICAST_GROUP}\")
set(MULTICAST_PORT ${NF_MULTICAST_PORT})

# Function to run a process with specific environment
function(run_process ROLE IP INDEX EXECUTABLE)
  set(ENV{PROCESS_ROLE} \${ROLE})
  set(ENV{SIMULATED_IP} \${IP})
  set(ENV{MULTICAST_GROUP} \${MULTICAST_GROUP})
  set(ENV{MULTICAST_PORT} \${MULTICAST_PORT})
  set(ENV{PARTICIPANT_COUNT} \${PARTICIPANT_COUNT})
  
  execute_process(
    COMMAND \${EXECUTABLE}
    TIMEOUT \${TIMEOUT}
    RESULT_VARIABLE RESULT
    OUTPUT_VARIABLE OUTPUT
    ERROR_VARIABLE ERROR
  )
  
  if(NOT RESULT EQUAL 0)
    message(FATAL_ERROR \"Process \${ROLE} at \${IP} failed with exit code \${RESULT}\\nOutput: \${OUTPUT}\\nError: \${ERROR}\")
  else()
    message(\"Process \${ROLE} at \${IP} completed successfully\")
  endif()
  
  return(PROPAGATE RESULT)
endfunction()

# Run all processes in parallel using CMake's execute_process
set(PROCESSES)
")

  # Add process commands
  foreach(i RANGE 1 ${NF_PARTICIPANTS})
    if(i EQUAL 1)
      set(ROLE "server")
    else()
      set(ROLE "client${i}")
    endif()
    
    math(EXPR IP_SUFFIX "${i} + 1")
    set(IP "127.0.0.${IP_SUFFIX}")
    
    if(TARGET ${NF_EXECUTABLE})
      set(EXEC_PATH "$<TARGET_FILE:${NF_EXECUTABLE}>")
    else()
      set(EXEC_PATH "${NF_EXECUTABLE}")
    endif()
    
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
# Process ${i}: ${ROLE}
list(APPEND PROCESSES 
  COMMAND \${CMAKE_COMMAND} -E env 
    PROCESS_ROLE=${ROLE}
    SIMULATED_IP=${IP}
    MULTICAST_GROUP=\${MULTICAST_GROUP}
    MULTICAST_PORT=\${MULTICAST_PORT}
    PARTICIPANT_COUNT=\${PARTICIPANT_COUNT}
    ${EXEC_PATH}
)
")
  endforeach()
  
  # Add parallel execution
  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
# Run all processes in parallel
execute_process(\${PROCESSES}
  TIMEOUT \${TIMEOUT}
  RESULTS_VARIABLE RESULTS
  OUTPUT_VARIABLE OUTPUTS
  ERROR_VARIABLE ERRORS
)

# Check results
set(ALL_SUCCESS TRUE)
set(INDEX 0)
list(LENGTH RESULTS NUM_RESULTS)

foreach(RESULT IN LISTS RESULTS)
  math(EXPR INDEX \"\${INDEX} + 1\")
  if(NOT RESULT EQUAL 0)
    set(ALL_SUCCESS FALSE)
    message(\"Process \${INDEX} failed with exit code \${RESULT}\")
  endif()
endforeach()

if(NOT ALL_SUCCESS)
  message(FATAL_ERROR \"Network fixture test failed - one or more processes returned non-zero\")
endif()

message(\"All \${PARTICIPANT_COUNT} processes completed successfully\")
")
  
  # Write the test script
  file(GENERATE OUTPUT "${TEST_SCRIPT}" CONTENT "${SCRIPT_CONTENT}")
  
  # Add the CTest test
  add_test(
    NAME ${NF_NAME}
    COMMAND ${CMAKE_COMMAND} -P "${TEST_SCRIPT}"
  )
  
  # Set test properties
  set_tests_properties(${NF_NAME} PROPERTIES
    TIMEOUT ${NF_TIMEOUT}
    LABELS "network;multiprocess"
  )
  
  # If executable is a target, add dependency
  if(TARGET ${NF_EXECUTABLE})
    set_tests_properties(${NF_NAME} PROPERTIES
      FIXTURES_REQUIRED "${NF_EXECUTABLE}_built"
    )
  endif()
  
  message(STATUS "Added network fixture test: ${NF_NAME} with ${NF_PARTICIPANTS} participants")
endfunction()

# Convenience function for simple client-server network tests
function(ut_add_client_server_network_test)
  set(options "")
  set(oneValueArgs NAME EXECUTABLE TIMEOUT)
  set(multiValueArgs ADDITIONAL_ENV)
  
  cmake_parse_arguments(CS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT CS_NAME OR NOT CS_EXECUTABLE)
    message(FATAL_ERROR "ut_add_client_server_network_test: NAME and EXECUTABLE are required")
  endif()
  
  # Use network fixture test with 2 participants (server + client)
  ut_add_network_fixture_test(
    NAME ${CS_NAME}
    PARTICIPANTS 2
    EXECUTABLE ${CS_EXECUTABLE}
    TIMEOUT ${CS_TIMEOUT}
    ADDITIONAL_ENV ${CS_ADDITIONAL_ENV}
  )
endfunction()