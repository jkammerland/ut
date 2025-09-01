# PodmanComposeTest.cmake
# 
# Advanced multiprocess testing using podman-compose for orchestration
# Provides startup dependency management, smart log extraction, and custom compose configuration
#

include_guard()
include(CMakeParseArguments)

# Find podman-compose executable
find_program(PODMAN_COMPOSE_EXECUTABLE 
  NAMES podman-compose
  DOC "Podman Compose executable for container orchestration"
)

if(PODMAN_COMPOSE_EXECUTABLE)
  set(PODMAN_COMPOSE_FOUND TRUE)
  message(STATUS "Found podman-compose: ${PODMAN_COMPOSE_EXECUTABLE}")
else()
  set(PODMAN_COMPOSE_FOUND FALSE)
  message(STATUS "podman-compose not found - compose-based tests will be skipped")
endif()

# Generate a compose.yml file for multiprocess testing
function(ut_generate_compose_file)
  set(options ENABLE_LOGS CLEANUP_VOLUMES PRIVILEGED)
  set(oneValueArgs OUTPUT_FILE PROJECT_NAME NETWORK_NAME NETWORK_SUBNET)
  set(multiValueArgs SERVICES VOLUMES ENVIRONMENT)
  
  cmake_parse_arguments(GC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT GC_OUTPUT_FILE)
    message(FATAL_ERROR "ut_generate_compose_file: OUTPUT_FILE is required")
  endif()
  
  if(NOT GC_PROJECT_NAME)
    set(GC_PROJECT_NAME "ut-multiprocess")
  endif()
  
  if(NOT GC_NETWORK_NAME)
    set(GC_NETWORK_NAME "ut-network")
  endif()
  
  if(NOT GC_NETWORK_SUBNET)
    set(GC_NETWORK_SUBNET "192.168.200.0/24")
  endif()
  
  # Start compose file content
  set(COMPOSE_CONTENT "version: '3.8'\n\n")
  
  # Add services
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}services:\n")
  foreach(service ${GC_SERVICES})
    set(COMPOSE_CONTENT "${COMPOSE_CONTENT}${service}")
  endforeach()
  
  # Add networks
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}\nnetworks:\n")
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}  ${GC_NETWORK_NAME}:\n")
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}    driver: bridge\n")
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}    ipam:\n")
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}      config:\n")
  set(COMPOSE_CONTENT "${COMPOSE_CONTENT}        - subnet: ${GC_NETWORK_SUBNET}\n")
  
  # Add volumes if specified
  if(GC_VOLUMES)
    set(COMPOSE_CONTENT "${COMPOSE_CONTENT}\nvolumes:\n")
    foreach(volume ${GC_VOLUMES})
      set(COMPOSE_CONTENT "${COMPOSE_CONTENT}  ${volume}:\n")
    endforeach()
  endif()
  
  # Write to file
  file(WRITE ${GC_OUTPUT_FILE} "${COMPOSE_CONTENT}")
  message(STATUS "Generated compose file: ${GC_OUTPUT_FILE}")
endfunction()

# Create a service definition for compose file
function(ut_create_compose_service)
  set(options PRIVILEGED ENABLE_LOGGING)
  set(oneValueArgs NAME IMAGE HOSTNAME IP_ADDRESS WORKING_DIR RESTART_POLICY)
  set(multiValueArgs COMMAND DEPENDS_ON ENVIRONMENT VOLUMES PORTS LABELS)
  
  cmake_parse_arguments(CS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT CS_NAME OR NOT CS_IMAGE)
    message(FATAL_ERROR "ut_create_compose_service: NAME and IMAGE are required")
  endif()
  
  # Build service YAML
  set(SERVICE_YAML "  ${CS_NAME}:\n")
  set(SERVICE_YAML "${SERVICE_YAML}    image: ${CS_IMAGE}\n")
  set(SERVICE_YAML "${SERVICE_YAML}    container_name: ${CS_NAME}\n")
  
  if(CS_HOSTNAME)
    set(SERVICE_YAML "${SERVICE_YAML}    hostname: ${CS_HOSTNAME}\n")
  endif()
  
  if(CS_WORKING_DIR)
    set(SERVICE_YAML "${SERVICE_YAML}    working_dir: ${CS_WORKING_DIR}\n")
  endif()
  
  if(CS_RESTART_POLICY)
    set(SERVICE_YAML "${SERVICE_YAML}    restart: ${CS_RESTART_POLICY}\n")
  else()
    set(SERVICE_YAML "${SERVICE_YAML}    restart: \"no\"\n")
  endif()
  
  # Add command
  if(CS_COMMAND)
    set(SERVICE_YAML "${SERVICE_YAML}    command: [")
    foreach(cmd_part ${CS_COMMAND})
      set(SERVICE_YAML "${SERVICE_YAML}\"${cmd_part}\", ")
    endforeach()
    string(REGEX REPLACE ", $" "" SERVICE_YAML "${SERVICE_YAML}")
    set(SERVICE_YAML "${SERVICE_YAML}]\n")
  endif()
  
  # Add dependencies  
  if(CS_DEPENDS_ON)
    set(SERVICE_YAML "${SERVICE_YAML}    depends_on:\n")
    foreach(dep ${CS_DEPENDS_ON})
      set(SERVICE_YAML "${SERVICE_YAML}      - ${dep}\n")
    endforeach()
  endif()
  
  # Add environment variables
  if(CS_ENVIRONMENT)
    set(SERVICE_YAML "${SERVICE_YAML}    environment:\n")
    foreach(env_var ${CS_ENVIRONMENT})
      set(SERVICE_YAML "${SERVICE_YAML}      - ${env_var}\n")
    endforeach()
  endif()
  
  # Add volumes
  if(CS_VOLUMES)
    set(SERVICE_YAML "${SERVICE_YAML}    volumes:\n")
    foreach(volume ${CS_VOLUMES})
      set(SERVICE_YAML "${SERVICE_YAML}      - ${volume}\n")
    endforeach()
  endif()
  
  # Add ports
  if(CS_PORTS)
    set(SERVICE_YAML "${SERVICE_YAML}    ports:\n")
    foreach(port ${CS_PORTS})
      set(SERVICE_YAML "${SERVICE_YAML}      - \"${port}\"\n")
    endforeach()
  endif()
  
  # Add labels
  if(CS_LABELS)
    set(SERVICE_YAML "${SERVICE_YAML}    labels:\n")
    foreach(label ${CS_LABELS})
      set(SERVICE_YAML "${SERVICE_YAML}      - \"${label}\"\n")
    endforeach()
  endif()
  
  # Add networks with IP if specified  
  set(SERVICE_YAML "${SERVICE_YAML}    networks:\n")
  if(CS_IP_ADDRESS AND NETWORK_NAME)
    set(SERVICE_YAML "${SERVICE_YAML}      ${NETWORK_NAME}:\n")
    set(SERVICE_YAML "${SERVICE_YAML}        ipv4_address: ${CS_IP_ADDRESS}\n")
  elseif(NETWORK_NAME)
    set(SERVICE_YAML "${SERVICE_YAML}      - ${NETWORK_NAME}\n")
  else()
    set(SERVICE_YAML "${SERVICE_YAML}      - ut-test-network\n")
  endif()
  
  # Add logging configuration if enabled
  if(CS_ENABLE_LOGGING)
    set(SERVICE_YAML "${SERVICE_YAML}    logging:\n")
    set(SERVICE_YAML "${SERVICE_YAML}      driver: json-file\n")
    set(SERVICE_YAML "${SERVICE_YAML}      options:\n")
    set(SERVICE_YAML "${SERVICE_YAML}        max-size: \"10m\"\n")
    set(SERVICE_YAML "${SERVICE_YAML}        max-file: \"3\"\n")
  endif()
  
  if(CS_PRIVILEGED)
    set(SERVICE_YAML "${SERVICE_YAML}    privileged: true\n")
  endif()
  
  set(SERVICE_YAML "${SERVICE_YAML}\n")
  
  # Return the service YAML in parent scope
  set(COMPOSE_SERVICE_${CS_NAME} "${SERVICE_YAML}" PARENT_SCOPE)
endfunction()

# Main function to add a compose-based multiprocess test
function(ut_add_compose_multiprocess_test)
  set(options SEQUENTIAL ENABLE_LOGS CLEANUP_VOLUMES CUSTOM_COMPOSE AUTO_BUILD)
  set(oneValueArgs NAME EXECUTABLE PARTICIPANTS TIMEOUT IMAGE COMPOSE_FILE BUILD_CONTEXT DOCKERFILE 
                   NETWORK_NAME NETWORK_SUBNET MULTICAST_GROUP MULTICAST_PORT PROJECT_NAME)
  set(multiValueArgs ADDITIONAL_ENV DEPENDENCIES VOLUMES STARTUP_ORDER CUSTOM_SERVICES)
  
  cmake_parse_arguments(CT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT PODMAN_COMPOSE_FOUND)
    message(WARNING "ut_add_compose_multiprocess_test: podman-compose not found, skipping test ${CT_NAME}")
    return()
  endif()
  
  if(NOT CT_NAME)
    message(FATAL_ERROR "ut_add_compose_multiprocess_test: NAME is required")
  endif()
  
  # Set defaults
  if(NOT CT_TIMEOUT)
    set(CT_TIMEOUT 60)
  endif()
  
  if(NOT CT_PARTICIPANTS AND NOT CT_CUSTOM_SERVICES)
    set(CT_PARTICIPANTS 2)
  endif()
  
  if(NOT CT_IMAGE)
    set(CT_IMAGE "ut-multiprocess")
  endif()
  
  if(NOT CT_NETWORK_NAME)
    set(CT_NETWORK_NAME "ut-test-network")
  endif()
  
  if(NOT CT_NETWORK_SUBNET)
    set(CT_NETWORK_SUBNET "192.168.200.0/24")
  endif()
  
  if(NOT CT_PROJECT_NAME)
    set(CT_PROJECT_NAME "ut-${CT_NAME}")
  endif()
  
  if(NOT CT_MULTICAST_GROUP)
    set(CT_MULTICAST_GROUP "239.255.2.1")
  endif()
  
  if(NOT CT_MULTICAST_PORT)
    set(CT_MULTICAST_PORT 14000)
  endif()
  
  # Determine compose file path
  if(CT_CUSTOM_COMPOSE)
    if(NOT CT_COMPOSE_FILE)
      message(FATAL_ERROR "CUSTOM_COMPOSE requires COMPOSE_FILE to be specified")
    endif()
    set(COMPOSE_PATH "${CT_COMPOSE_FILE}")
  else()
    set(COMPOSE_PATH "${CMAKE_CURRENT_BINARY_DIR}/${CT_NAME}_compose.yml")
  endif()
  
  # Build image if requested
  if(CT_AUTO_BUILD)
    if(NOT CT_DOCKERFILE OR NOT CT_BUILD_CONTEXT)
      message(FATAL_ERROR "AUTO_BUILD requires DOCKERFILE and BUILD_CONTEXT")
    endif()
    
    add_custom_target(${CT_NAME}_build_image
      COMMAND ${PODMAN_COMPOSE_EXECUTABLE} -f ${COMPOSE_PATH} build
      WORKING_DIRECTORY ${CT_BUILD_CONTEXT}
      COMMENT "Building container image for ${CT_NAME}"
    )
  endif()
  
  # Generate compose file if not using custom
  if(NOT CT_CUSTOM_COMPOSE)
    set(SERVICES_LIST "")
    
    if(CT_CUSTOM_SERVICES)
      # Use custom service definitions
      foreach(service ${CT_CUSTOM_SERVICES})
        list(APPEND SERVICES_LIST "${COMPOSE_SERVICE_${service}}")
      endforeach()
    else()
      # Generate standard multiprocess services
      foreach(i RANGE 1 ${CT_PARTICIPANTS})
        if(i EQUAL 1)
          set(ROLE "server")
          set(SERVICE_NAME "server")
        else()
          set(ROLE "client${i}")
          set(SERVICE_NAME "client${i}")
        endif()
        
        # Calculate IP address
        math(EXPR IP_SUFFIX "100 + ${i}")
        set(IP_ADDRESS "192.168.200.${IP_SUFFIX}")
        
        # Build environment variables for this service
        set(SERVICE_ENV 
          "PROCESS_ROLE=${ROLE}"
          "SIMULATED_IP=${IP_ADDRESS}"
          "MULTICAST_GROUP=${CT_MULTICAST_GROUP}"
          "MULTICAST_PORT=${CT_MULTICAST_PORT}"
          "PARTICIPANT_COUNT=${CT_PARTICIPANTS}"
        )
        
        if(CT_ADDITIONAL_ENV)
          list(APPEND SERVICE_ENV ${CT_ADDITIONAL_ENV})
        endif()
        
        # Set up dependencies based on startup order
        set(DEPS "")
        if(CT_STARTUP_ORDER AND NOT i EQUAL 1)
          # Each service depends on the previous one
          if(i EQUAL 2)
            list(APPEND DEPS "server")
          else()
            math(EXPR PREV_CLIENT "${i} - 1")
            list(APPEND DEPS "client${PREV_CLIENT}")
          endif()
        endif()
        
        # Create the service (pass network name properly)
        set(NETWORK_NAME ${CT_NETWORK_NAME})
        if(CT_ENABLE_LOGS)
          ut_create_compose_service(
            NAME ${SERVICE_NAME}
            IMAGE ${CT_IMAGE}
            HOSTNAME ${SERVICE_NAME}
            IP_ADDRESS ${IP_ADDRESS}
            WORKING_DIR "/app"
            COMMAND ${CT_EXECUTABLE}
            DEPENDS_ON ${DEPS}
            ENVIRONMENT ${SERVICE_ENV}
            LABELS "ut.test=${CT_NAME}" "ut.role=${ROLE}"
            ENABLE_LOGGING
          )
        else()
          ut_create_compose_service(
            NAME ${SERVICE_NAME}
            IMAGE ${CT_IMAGE}
            HOSTNAME ${SERVICE_NAME}
            IP_ADDRESS ${IP_ADDRESS}
            WORKING_DIR "/app"
            COMMAND ${CT_EXECUTABLE}
            DEPENDS_ON ${DEPS}
            ENVIRONMENT ${SERVICE_ENV}
            LABELS "ut.test=${CT_NAME}" "ut.role=${ROLE}"
          )
        endif()
        
        list(APPEND SERVICES_LIST "${COMPOSE_SERVICE_${SERVICE_NAME}}")
      endforeach()
    endif()
    
    # Generate the compose file
    if(CT_ENABLE_LOGS)
      set(ENABLE_LOGS_FLAG "ENABLE_LOGS")
    else()
      set(ENABLE_LOGS_FLAG "")
    endif()
    
    if(CT_CLEANUP_VOLUMES)
      set(CLEANUP_VOLUMES_FLAG "CLEANUP_VOLUMES")
    else()
      set(CLEANUP_VOLUMES_FLAG "")
    endif()
    
    ut_generate_compose_file(
      OUTPUT_FILE ${COMPOSE_PATH}
      PROJECT_NAME ${CT_PROJECT_NAME}
      NETWORK_NAME ${CT_NETWORK_NAME}
      NETWORK_SUBNET ${CT_NETWORK_SUBNET}
      SERVICES ${SERVICES_LIST}
      VOLUMES ${CT_VOLUMES}
      ${ENABLE_LOGS_FLAG}
      ${CLEANUP_VOLUMES_FLAG}
    )
  endif()
  
  # Create test script for compose orchestration  
  set(TEST_SCRIPT_PATH "${CMAKE_CURRENT_BINARY_DIR}/${CT_NAME}_compose_runner.sh")
  
  set(SCRIPT_CONTENT "#!/bin/bash
# Auto-generated compose multiprocess test runner for ${CT_NAME}
# Generated by ut_add_compose_multiprocess_test

set -e  # Exit on any error
set -o pipefail  # Catch pipeline failures

# Test configuration
TEST_NAME=\"${CT_NAME}\"
TIMEOUT=${CT_TIMEOUT}
COMPOSE_FILE=\"${COMPOSE_PATH}\"
PROJECT_NAME=\"${CT_PROJECT_NAME}\"
WORKING_DIR=\"${CMAKE_CURRENT_BINARY_DIR}\"

echo \"Starting compose multiprocess test: \$TEST_NAME\"
echo \"Compose file: \$COMPOSE_FILE\"
echo \"Project: \$PROJECT_NAME\"
echo \"Timeout: \$TIMEOUT seconds\"

cd \"\$WORKING_DIR\"

# Cleanup function
cleanup() {
    echo \"Cleaning up compose project...\"
    ${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" down --remove-orphans
")

  if(CT_CLEANUP_VOLUMES)
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}    ${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" down -v
")
  endif()

  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}    ${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" rm -f
}

# Set up signal handlers for cleanup
trap cleanup EXIT INT TERM

# Start the compose stack
echo \"Starting compose stack...\"
${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" up --remove-orphans &
COMPOSE_PID=\$!

# Wait for completion with timeout
echo \"Waiting for compose stack to complete (timeout: \$TIMEOUT seconds)...\"
timeout \$TIMEOUT wait \$COMPOSE_PID
COMPOSE_EXIT_CODE=\$?

if [ \$COMPOSE_EXIT_CODE -eq 0 ]; then
    echo \"SUCCESS: All services completed successfully\"
elif [ \$COMPOSE_EXIT_CODE -eq 124 ]; then
    echo \"FAILURE: Compose stack timed out after \$TIMEOUT seconds\"
    kill -TERM \$COMPOSE_PID 2>/dev/null || true
    exit 1
else
    echo \"FAILURE: Compose stack failed with exit code \$COMPOSE_EXIT_CODE\"
    exit 1
fi

# Extract and analyze logs
echo \"Extracting service logs...\"
")

  if(CT_ENABLE_LOGS)
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
# Save logs for analysis
mkdir -p logs/\${TEST_NAME}
for service in \$(${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" ps --format \"table {{.Service}}\" | tail -n +2); do
    echo \"Extracting logs for service: \$service\"
    ${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" logs \$service > \"logs/\${TEST_NAME}/\$service.log\" 2>&1 || true
done

# Check for test failures in logs
FAILED_SERVICES=()
for log_file in logs/\${TEST_NAME}/*.log; do
    service_name=\$(basename \"\$log_file\" .log)
    if grep -q \"FAILED\" \"\$log_file\" 2>/dev/null; then
        FAILED_SERVICES+=(\"\$service_name\")
    fi
done

if [ \${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo \"FAILURE: The following services had test failures:\"
    for failed in \"\${FAILED_SERVICES[@]}\"; do
        echo \"  - \$failed\"
        echo \"    Log excerpt:\"
        grep -A 3 -B 1 \"FAILED\" \"logs/\${TEST_NAME}/\$failed.log\" | sed 's/^/      /' || true
    done
    exit 1
fi

echo \"SUCCESS: All services completed with passing tests\"
")
  else()
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}echo \"Log extraction disabled - assuming success based on compose exit code\"
")
  endif()

  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
exit 0
")
  
  # Write the script
  file(WRITE ${TEST_SCRIPT_PATH} "${SCRIPT_CONTENT}")
  
  # Make script executable
  execute_process(COMMAND chmod +x ${TEST_SCRIPT_PATH})
  
  # Add the CTest
  add_test(
    NAME ${CT_NAME}
    COMMAND /bin/bash ${TEST_SCRIPT_PATH}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  )
  
  set_tests_properties(${CT_NAME} PROPERTIES
    TIMEOUT ${CT_TIMEOUT}
    LABELS "multiprocess;compose;${CT_NAME}"
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  )
  
  # Add dependency on image build if auto-building
  if(CT_AUTO_BUILD)
    # Note: CTest doesn't directly support target dependencies, but we document this
    set_tests_properties(${CT_NAME} PROPERTIES
      DEPENDS "${CT_NAME}_build_image"
    )
  endif()
  
  message(STATUS "Added compose multiprocess test: ${CT_NAME} with ${CT_PARTICIPANTS} participants")
endfunction()

# Convenience function for network-based compose tests
function(ut_add_compose_network_test)
  set(options SEQUENTIAL ENABLE_LOGS CLEANUP_VOLUMES STARTUP_ORDER AUTO_BUILD)
  set(oneValueArgs NAME PARTICIPANTS EXECUTABLE TIMEOUT IMAGE MULTICAST_GROUP MULTICAST_PORT BUILD_CONTEXT DOCKERFILE)
  set(multiValueArgs ADDITIONAL_ENV)
  
  cmake_parse_arguments(CN "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT CN_NAME OR NOT CN_EXECUTABLE)
    message(FATAL_ERROR "ut_add_compose_network_test: NAME and EXECUTABLE are required")
  endif()
  
  # Set up arguments for main function
  set(MAIN_ARGS 
    NAME ${CN_NAME}
    EXECUTABLE ${CN_EXECUTABLE}
  )
  
  if(CN_PARTICIPANTS)
    list(APPEND MAIN_ARGS PARTICIPANTS ${CN_PARTICIPANTS})
  endif()
  
  if(CN_TIMEOUT)
    list(APPEND MAIN_ARGS TIMEOUT ${CN_TIMEOUT})
  endif()
  
  if(CN_IMAGE)
    list(APPEND MAIN_ARGS IMAGE ${CN_IMAGE})
  endif()
  
  if(CN_MULTICAST_GROUP)
    list(APPEND MAIN_ARGS MULTICAST_GROUP ${CN_MULTICAST_GROUP})
  endif()
  
  if(CN_MULTICAST_PORT)
    list(APPEND MAIN_ARGS MULTICAST_PORT ${CN_MULTICAST_PORT})
  endif()
  
  if(CN_BUILD_CONTEXT)
    list(APPEND MAIN_ARGS BUILD_CONTEXT ${CN_BUILD_CONTEXT})
  endif()
  
  if(CN_DOCKERFILE)
    list(APPEND MAIN_ARGS DOCKERFILE ${CN_DOCKERFILE})
  endif()
  
  if(CN_ADDITIONAL_ENV)
    list(APPEND MAIN_ARGS ADDITIONAL_ENV ${CN_ADDITIONAL_ENV})
  endif()
  
  if(CN_SEQUENTIAL)
    list(APPEND MAIN_ARGS SEQUENTIAL)
  endif()
  
  if(CN_ENABLE_LOGS)
    list(APPEND MAIN_ARGS ENABLE_LOGS)
  endif()
  
  if(CN_CLEANUP_VOLUMES)
    list(APPEND MAIN_ARGS CLEANUP_VOLUMES)
  endif()
  
  if(CN_STARTUP_ORDER)
    list(APPEND MAIN_ARGS STARTUP_ORDER)
  endif()
  
  if(CN_AUTO_BUILD)
    list(APPEND MAIN_ARGS AUTO_BUILD)
  endif()
  
  # Call main function
  ut_add_compose_multiprocess_test(${MAIN_ARGS})
endfunction()