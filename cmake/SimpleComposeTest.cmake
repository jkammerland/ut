# SimpleComposeTest.cmake
# 
# Simplified multiprocess testing using podman-compose with template-based approach
# More maintainable than complex YAML generation in CMake
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
  message(STATUS "podman-compose not found - simple compose tests will be skipped")
endif()

# Function to add a simple compose-based multiprocess test
function(ut_add_simple_compose_test)
  set(options STARTUP_ORDER ENABLE_LOGS CLEANUP_VOLUMES AUTO_BUILD)
  set(oneValueArgs NAME PARTICIPANTS EXECUTABLE TIMEOUT IMAGE MULTICAST_GROUP MULTICAST_PORT
                   NETWORK_SUBNET BUILD_CONTEXT DOCKERFILE)
  set(multiValueArgs ADDITIONAL_ENV)
  
  cmake_parse_arguments(SCT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  
  if(NOT PODMAN_COMPOSE_FOUND)
    message(WARNING "ut_add_simple_compose_test: podman-compose not found, skipping test ${SCT_NAME}")
    return()
  endif()
  
  if(NOT SCT_NAME OR NOT SCT_EXECUTABLE)
    message(FATAL_ERROR "ut_add_simple_compose_test: NAME and EXECUTABLE are required")
  endif()
  
  # Set defaults
  if(NOT SCT_PARTICIPANTS)
    set(SCT_PARTICIPANTS 2)
  endif()
  
  if(NOT SCT_TIMEOUT)
    set(SCT_TIMEOUT 90)
  endif()
  
  if(NOT SCT_IMAGE)
    set(SCT_IMAGE "ut-multiprocess")
  endif()
  
  if(NOT SCT_MULTICAST_GROUP)
    set(SCT_MULTICAST_GROUP "239.255.4.1")
  endif()
  
  if(NOT SCT_MULTICAST_PORT)
    set(SCT_MULTICAST_PORT 16000)
  endif()
  
  if(NOT SCT_NETWORK_SUBNET)
    set(SCT_NETWORK_SUBNET "192.168.210.0/24")
  endif()
  
  # Extract subnet prefix (e.g., "192.168.210" from "192.168.210.0/24")
  string(REGEX MATCH "([0-9]+\\.[0-9]+\\.[0-9]+)\\." SUBNET_MATCH "${SCT_NETWORK_SUBNET}")
  set(SUBNET_PREFIX "${CMAKE_MATCH_1}")
  
  # Paths
  set(TEMPLATE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/compose-template.yml")
  set(COMPOSE_FILE "${CMAKE_CURRENT_BINARY_DIR}/${SCT_NAME}_compose.yml")
  set(SCRIPT_FILE "${CMAKE_CURRENT_BINARY_DIR}/${SCT_NAME}_compose_runner.sh")
  
  # Check if template exists
  if(NOT EXISTS "${TEMPLATE_FILE}")
    message(FATAL_ERROR "Compose template not found: ${TEMPLATE_FILE}")
  endif()
  
  # Read template
  file(READ "${TEMPLATE_FILE}" COMPOSE_CONTENT)
  
  # Basic substitutions
  string(REPLACE "@IMAGE@" "${SCT_IMAGE}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@PROJECT@" "${SCT_NAME}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@EXECUTABLE@" "${SCT_EXECUTABLE}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@TEST_NAME@" "${SCT_NAME}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@MULTICAST_GROUP@" "${SCT_MULTICAST_GROUP}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@MULTICAST_PORT@" "${SCT_MULTICAST_PORT}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@PARTICIPANT_COUNT@" "${SCT_PARTICIPANTS}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@NETWORK_NAME@" "${SCT_NAME}-network" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@NETWORK_SUBNET@" "${SCT_NETWORK_SUBNET}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  string(REPLACE "@SUBNET_PREFIX@" "${SUBNET_PREFIX}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  
  # Handle additional environment variables
  if(SCT_ADDITIONAL_ENV)
    set(ADDITIONAL_ENV_BLOCK "")
    foreach(env_var ${SCT_ADDITIONAL_ENV})
      set(ADDITIONAL_ENV_BLOCK "${ADDITIONAL_ENV_BLOCK}      - ${env_var}\n")
    endforeach()
    string(REPLACE "@ADDITIONAL_ENV@" "${ADDITIONAL_ENV_BLOCK}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  else()
    string(REPLACE "@ADDITIONAL_ENV@" "" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  endif()
  
  # Handle logging configuration
  if(SCT_ENABLE_LOGS)
    set(LOGGING_BLOCK "    logging:\n      driver: json-file\n      options:\n        max-size: \"10m\"\n        max-file: \"3\"\n")
    string(REPLACE "@LOGGING_CONFIG@" "${LOGGING_BLOCK}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  else()
    string(REPLACE "@LOGGING_CONFIG@" "" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  endif()
  
  # Generate additional services (clients)
  if(SCT_PARTICIPANTS GREATER 1)
    set(ADDITIONAL_SERVICES "")
    foreach(i RANGE 2 ${SCT_PARTICIPANTS})
      math(EXPR IP_SUFFIX "100 + ${i}")
      
      # Determine dependencies for startup order
      set(DEPENDS_BLOCK "")
      if(SCT_STARTUP_ORDER)
        if(i EQUAL 2)
          set(DEPENDS_BLOCK "    depends_on:\n      - server\n")
        else()
          math(EXPR PREV_CLIENT "${i} - 1")
          set(DEPENDS_BLOCK "    depends_on:\n      - client${PREV_CLIENT}\n")
        endif()
      endif()
      
      # Build additional environment for this client
      set(CLIENT_ADDITIONAL_ENV "")
      if(SCT_ADDITIONAL_ENV)
        foreach(env_var ${SCT_ADDITIONAL_ENV})
          set(CLIENT_ADDITIONAL_ENV "${CLIENT_ADDITIONAL_ENV}      - ${env_var}\n")
        endforeach()
      endif()
      
      # Add client service
      set(CLIENT_SERVICE "
  client${i}:
    image: ${SCT_IMAGE}
    container_name: ${SCT_NAME}-client${i}
    hostname: client${i}
    working_dir: /app
    restart: \"no\"
    command: [\"${SCT_EXECUTABLE}\"]
${DEPENDS_BLOCK}    environment:
      - PROCESS_ROLE=client${i}
      - SIMULATED_IP=${SUBNET_PREFIX}.${IP_SUFFIX}
      - MULTICAST_GROUP=${SCT_MULTICAST_GROUP}
      - MULTICAST_PORT=${SCT_MULTICAST_PORT}
      - PARTICIPANT_COUNT=${SCT_PARTICIPANTS}
${CLIENT_ADDITIONAL_ENV}    labels:
      - \"ut.test=${SCT_NAME}\"
      - \"ut.role=client${i}\"
    networks:
      ${SCT_NAME}-network:
        ipv4_address: ${SUBNET_PREFIX}.${IP_SUFFIX}
${LOGGING_BLOCK}")
      
      set(ADDITIONAL_SERVICES "${ADDITIONAL_SERVICES}${CLIENT_SERVICE}")
    endforeach()
    
    string(REPLACE "@ADDITIONAL_SERVICES@" "${ADDITIONAL_SERVICES}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  else()
    string(REPLACE "@ADDITIONAL_SERVICES@" "" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  endif()
  
  # Handle volumes section
  if(SCT_CLEANUP_VOLUMES)
    set(VOLUMES_BLOCK "volumes:\n  ${SCT_NAME}-logs:\n")
    string(REPLACE "@VOLUMES_SECTION@" "${VOLUMES_BLOCK}" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  else()
    string(REPLACE "@VOLUMES_SECTION@" "" COMPOSE_CONTENT "${COMPOSE_CONTENT}")
  endif()
  
  # Write the compose file
  file(WRITE "${COMPOSE_FILE}" "${COMPOSE_CONTENT}")
  
  # Create the test runner script
  set(SCRIPT_CONTENT "#!/bin/bash
# Auto-generated simple compose test runner for ${SCT_NAME}

set -e
set -o pipefail

TEST_NAME=\"${SCT_NAME}\"
TIMEOUT=${SCT_TIMEOUT}
COMPOSE_FILE=\"${COMPOSE_FILE}\"
PROJECT_NAME=\"${SCT_NAME}\"
WORKING_DIR=\"${CMAKE_CURRENT_BINARY_DIR}\"

echo \"Starting simple compose test: \$TEST_NAME\"
echo \"Compose file: \$COMPOSE_FILE\"
echo \"Timeout: \$TIMEOUT seconds\"

cd \"\$WORKING_DIR\"

# Cleanup function
cleanup() {
    echo \"Cleaning up compose project...\"
    ${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" down --remove-orphans --volumes 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Start compose stack
echo \"Starting compose stack...\"
${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" up --remove-orphans")

  if(SCT_ENABLE_LOGS)
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}

# Extract logs after completion
echo \"Extracting service logs...\"
mkdir -p logs/\${TEST_NAME}
for service in server")
    
    # Add client services to log extraction
    if(SCT_PARTICIPANTS GREATER 1)
      foreach(i RANGE 2 ${SCT_PARTICIPANTS})
        set(SCRIPT_CONTENT "${SCRIPT_CONTENT} client${i}")
      endforeach()
    endif()
    
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}; do
    echo \"Extracting logs for \$service...\"
    ${PODMAN_COMPOSE_EXECUTABLE} -f \"\$COMPOSE_FILE\" -p \"\$PROJECT_NAME\" logs \$service > \"logs/\${TEST_NAME}/\$service.log\" 2>&1 || true
done

# Check for test failures in logs
FAILED_SERVICES=()
for log_file in logs/\${TEST_NAME}/*.log; do
    if [ -f \"\$log_file\" ]; then
        service_name=\$(basename \"\$log_file\" .log)
        if grep -q \"FAILED\" \"\$log_file\" 2>/dev/null; then
            FAILED_SERVICES+=(\"\$service_name\")
        fi
    fi
done

if [ \${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo \"FAILURE: Services with test failures: \${FAILED_SERVICES[*]}\"
    exit 1
fi

echo \"SUCCESS: All services completed with passing tests\"")
  else()
    set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
echo \"Log extraction disabled - test completed\"")
  endif()

  set(SCRIPT_CONTENT "${SCRIPT_CONTENT}
exit 0")
  
  # Write and make executable
  file(WRITE "${SCRIPT_FILE}" "${SCRIPT_CONTENT}")
  execute_process(COMMAND chmod +x "${SCRIPT_FILE}")
  
  # Add CTest
  add_test(
    NAME ${SCT_NAME}
    COMMAND /bin/bash "${SCRIPT_FILE}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  )
  
  set_tests_properties(${SCT_NAME} PROPERTIES
    TIMEOUT ${SCT_TIMEOUT}
    LABELS "multiprocess;compose;simple;${SCT_NAME}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  )
  
  message(STATUS "Added simple compose test: ${SCT_NAME} with ${SCT_PARTICIPANTS} participants")
endfunction()