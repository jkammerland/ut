# Multiprocess Testing Support for boost.ut
# Allows running multiple test executables as a single CTest test

# Function to run multiple processes and collect their return codes
# Returns 0 only if all processes succeed
function(ut_add_multiprocess_test)
  set(options PARALLEL SEQUENTIAL)
  set(oneValueArgs NAME TIMEOUT WORKING_DIRECTORY)
  set(multiValueArgs TARGETS COMMANDS ENVIRONMENT)
  
  cmake_parse_arguments(MP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT MP_NAME)
    message(FATAL_ERROR "ut_add_multiprocess_test: NAME is required")
  endif()
  
  if(NOT MP_TARGETS AND NOT MP_COMMANDS)
    message(FATAL_ERROR "ut_add_multiprocess_test: Either TARGETS or COMMANDS must be specified")
  endif()
  
  # Default to parallel execution
  if(NOT MP_SEQUENTIAL AND NOT MP_PARALLEL)
    set(MP_PARALLEL TRUE)
  endif()
  
  # Default timeout is 30 seconds
  if(NOT MP_TIMEOUT)
    set(MP_TIMEOUT 30)
  endif()
  
  # Create the test runner script
  set(RUNNER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${MP_NAME}_runner.cmake")
  
  # Build the list of commands to run
  set(COMMANDS_LIST "")
  
  if(MP_TARGETS)
    foreach(target ${MP_TARGETS})
      list(APPEND COMMANDS_LIST "$<TARGET_FILE:${target}>")
    endforeach()
  endif()
  
  if(MP_COMMANDS)
    foreach(cmd ${MP_COMMANDS})
      list(APPEND COMMANDS_LIST "${cmd}")
    endforeach()
  endif()
  
  # Generate the runner script content
  set(SCRIPT_CONTENT "# Auto-generated multiprocess test runner\n")
  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}set(COMMANDS \"${COMMANDS_LIST}\")\n")
  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}set(PARALLEL ${MP_PARALLEL})\n")
  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}set(TIMEOUT ${MP_TIMEOUT})\n")
  
  if(MP_WORKING_DIRECTORY)
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}set(WORKING_DIR \"${MP_WORKING_DIRECTORY}\")\n")
  else()
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}set(WORKING_DIR \"${CMAKE_CURRENT_BINARY_DIR}\")\n")
  endif()
  
  if(MP_ENVIRONMENT)
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}set(ENV_VARS \"${MP_ENVIRONMENT}\")\n")
  endif()
  
  # Add the actual runner logic
  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
# Set environment variables
if(DEFINED ENV_VARS)
  foreach(env_var \${ENV_VARS})
    if(env_var MATCHES \"^([^=]+)=(.*)$\")
      set(ENV{\${CMAKE_MATCH_1}} \"\${CMAKE_MATCH_2}\")
    endif()
  endforeach()
endif()

set(ALL_SUCCESS TRUE)
set(FAILED_PROCESSES \"\")

if(PARALLEL)
  # Run all processes in parallel
  set(HANDLES \"\")
  set(INDEX 0)
  
  foreach(cmd \${COMMANDS})
    math(EXPR INDEX \"\${INDEX} + 1\")
    execute_process(
      COMMAND \${cmd}
      WORKING_DIRECTORY \${WORKING_DIR}
      TIMEOUT \${TIMEOUT}
      RESULT_VARIABLE RESULT_\${INDEX}
      OUTPUT_VARIABLE OUTPUT_\${INDEX}
      ERROR_VARIABLE ERROR_\${INDEX}
      COMMAND_ECHO STDOUT
    )
    
    if(NOT RESULT_\${INDEX} EQUAL 0)
      set(ALL_SUCCESS FALSE)
      list(APPEND FAILED_PROCESSES \"Process \${INDEX} (\${cmd}): exit code \${RESULT_\${INDEX}}\")
      if(OUTPUT_\${INDEX})
        message(\"Process \${INDEX} output:\\n\${OUTPUT_\${INDEX}}\")
      endif()
      if(ERROR_\${INDEX})
        message(\"Process \${INDEX} error:\\n\${ERROR_\${INDEX}}\")
      endif()
    endif()
  endforeach()
else()
  # Run processes sequentially
  set(INDEX 0)
  
  foreach(cmd \${COMMANDS})
    math(EXPR INDEX \"\${INDEX} + 1\")
    message(\"Running process \${INDEX}: \${cmd}\")
    
    execute_process(
      COMMAND \${cmd}
      WORKING_DIRECTORY \${WORKING_DIR}
      TIMEOUT \${TIMEOUT}
      RESULT_VARIABLE RESULT
      COMMAND_ECHO STDOUT
    )
    
    if(NOT RESULT EQUAL 0)
      set(ALL_SUCCESS FALSE)
      list(APPEND FAILED_PROCESSES \"Process \${INDEX} (\${cmd}): exit code \${RESULT}\")
      # In sequential mode, we might want to stop on first failure
      # Uncomment the following line to enable fail-fast behavior:
      # break()
    endif()
  endforeach()
endif()

if(NOT ALL_SUCCESS)
  message(FATAL_ERROR \"Multiprocess test failed:\\n\${FAILED_PROCESSES}\")
endif()
")
  
  # Write the runner script
  file(GENERATE OUTPUT "${RUNNER_SCRIPT}" CONTENT "${SCRIPT_CONTENT}")
  
  # Add the test
  add_test(
    NAME ${MP_NAME}
    COMMAND ${CMAKE_COMMAND} -P "${RUNNER_SCRIPT}"
  )
  
  # Set test properties
  set_tests_properties(${MP_NAME} PROPERTIES
    TIMEOUT ${MP_TIMEOUT}
  )
  
  if(MP_ENVIRONMENT)
    set_tests_properties(${MP_NAME} PROPERTIES
      ENVIRONMENT "${MP_ENVIRONMENT}"
    )
  endif()
  
  # If targets were specified, add dependencies
  if(MP_TARGETS)
    set_tests_properties(${MP_NAME} PROPERTIES
      FIXTURES_REQUIRED "build_complete"
    )
  endif()
endfunction()

# Convenience function for client-server testing
function(ut_add_client_server_test)
  set(options "")
  set(oneValueArgs NAME SERVER CLIENT TIMEOUT)
  set(multiValueArgs SERVER_ARGS CLIENT_ARGS ENVIRONMENT)
  
  cmake_parse_arguments(CS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT CS_NAME OR NOT CS_SERVER OR NOT CS_CLIENT)
    message(FATAL_ERROR "ut_add_client_server_test: NAME, SERVER, and CLIENT are required")
  endif()
  
  # Build command lists
  set(SERVER_CMD "${CS_SERVER}")
  if(CS_SERVER_ARGS)
    list(APPEND SERVER_CMD ${CS_SERVER_ARGS})
  endif()
  
  set(CLIENT_CMD "${CS_CLIENT}")
  if(CS_CLIENT_ARGS)
    list(APPEND CLIENT_CMD ${CS_CLIENT_ARGS})
  endif()
  
  # Use the multiprocess test function
  ut_add_multiprocess_test(
    NAME ${CS_NAME}
    PARALLEL
    COMMANDS "${SERVER_CMD}" "${CLIENT_CMD}"
    TIMEOUT ${CS_TIMEOUT}
    ENVIRONMENT ${CS_ENVIRONMENT}
  )
endfunction()