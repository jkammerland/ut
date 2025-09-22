# Enhanced Podman Multiprocess Testing with support for different executables
# Symmetric API with regular multiprocess tests

find_program(PODMAN_EXECUTABLE podman)

if(NOT PODMAN_EXECUTABLE)
  message(STATUS "Podman not found - podman multiprocess tests will be skipped")
  return()
endif()

# Enhanced function - supports different executables per participant
function(ut_add_podman_multiprocess_test)
  set(options "")
  set(oneValueArgs NAME TARGET PARTICIPANTS TIMEOUT)
  set(multiValueArgs TARGETS)  # New: list of different targets

  cmake_parse_arguments(PM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Validate parameters
  if(NOT PM_NAME)
    message(FATAL_ERROR "ut_add_podman_multiprocess_test: NAME is required")
  endif()

  # Support both single TARGET and multiple TARGETS
  if(PM_TARGET AND PM_TARGETS)
    message(FATAL_ERROR "ut_add_podman_multiprocess_test: Use either TARGET or TARGETS, not both")
  endif()

  if(NOT PM_TARGET AND NOT PM_TARGETS)
    message(FATAL_ERROR "ut_add_podman_multiprocess_test: Either TARGET or TARGETS is required")
  endif()

  # If single TARGET provided, use it for all participants
  if(PM_TARGET)
    if(NOT PM_PARTICIPANTS)
      set(PM_PARTICIPANTS 2)
    endif()
    # Create list with same target repeated
    set(EXEC_TARGETS)
    foreach(i RANGE 1 ${PM_PARTICIPANTS})
      list(APPEND EXEC_TARGETS ${PM_TARGET})
    endforeach()
  else()
    # Multiple TARGETS provided
    set(EXEC_TARGETS ${PM_TARGETS})
    list(LENGTH EXEC_TARGETS PM_PARTICIPANTS)
  endif()

  if(NOT PM_TIMEOUT)
    set(PM_TIMEOUT 30)
  endif()

  # Build list of executable paths
  set(EXEC_PATHS "")
  foreach(target ${EXEC_TARGETS})
    list(APPEND EXEC_PATHS "$<TARGET_FILE:${target}>")
  endforeach()

  # Create test script
  set(TEST_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${PM_NAME}_podman.sh")

  # Generate script with array of executables
  string(REPLACE ";" " " EXEC_PATHS_STR "${EXEC_PATHS}")

  file(GENERATE OUTPUT "${TEST_SCRIPT}" CONTENT "#!/bin/bash
# Auto-generated podman multiprocess test with different executables
set -e

# Array of executables
EXEC_PATHS=(${EXEC_PATHS_STR})
PARTICIPANTS=${PM_PARTICIPANTS}
TEST_NAME='${PM_NAME}'
TIMEOUT=${PM_TIMEOUT}

# Verify all executables exist
for ((i=0; i<PARTICIPANTS; i++)); do
  if [ ! -f \"\${EXEC_PATHS[\$i]}\" ]; then
    echo \"Error: Executable not found: \${EXEC_PATHS[\$i]}\"
    exit 1
  fi
done

# Create unique network
NETWORK_NAME=\"\${TEST_NAME}-net-\$\$\"
SUBNET=\"10.\$((RANDOM % 100 + 100)).0.0/24\"

echo \"Creating network \$NETWORK_NAME with subnet \$SUBNET\"
podman network create \$NETWORK_NAME --subnet \$SUBNET || exit 1

cleanup() {
  echo \"Cleaning up...\"
  for ((i=0; i<PARTICIPANTS; i++)); do
    podman rm -f \${TEST_NAME}-\$i 2>/dev/null || true
  done
  podman network rm \$NETWORK_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Start containers with different executables
echo \"Starting \$PARTICIPANTS processes with different executables...\"
CONTAINER_IDS=()

for ((i=0; i<PARTICIPANTS; i++)); do
  EXEC=\"\${EXEC_PATHS[\$i]}\"
  echo \"  Starting process \$i with executable: \$(basename \$EXEC)\"

  CID=\$(podman run -d --name \${TEST_NAME}-\$i --network \$NETWORK_NAME \\
    -v \"\$EXEC:/test:ro\" \\
    -v /usr/lib64:/hostlib:ro \\
    -e LD_LIBRARY_PATH=/hostlib \\
    -e PROCESS_ID=\$i \\
    -e PARTICIPANT_COUNT=\$PARTICIPANTS \\
    -e MULTICAST_ADDRESS=239.255.0.1 \\
    -e MULTICAST_PORT=\$((15000 + \$\$)) \\
    fedora:latest /test)

  CONTAINER_IDS+=(\$CID)

  # Get IP
  sleep 0.2
  IP=\$(podman inspect \${TEST_NAME}-\$i 2>/dev/null | \\
       grep '\"IPAddress\"' | head -1 | cut -d'\"' -f4)
  echo \"    Process \$i IP: \$IP (running \$(basename \$EXEC))\"
done

# Wait for completion
echo \"Waiting for processes (timeout: \${TIMEOUT}s)...\"
SUCCESS=true

for ((i=0; i<PARTICIPANTS; i++)); do
  if timeout \$TIMEOUT podman wait \${TEST_NAME}-\$i >/dev/null 2>&1; then
    EXIT_CODE=\$(podman inspect \${TEST_NAME}-\$i --format='{{.State.ExitCode}}')
    if [ \"\$EXIT_CODE\" != \"0\" ]; then
      echo \"Process \$i failed with exit code \$EXIT_CODE\"
      podman logs \${TEST_NAME}-\$i | tail -10
      SUCCESS=false
    else
      echo \"Process \$i completed successfully\"
    fi
  else
    echo \"Process \$i timed out\"
    podman logs \${TEST_NAME}-\$i | tail -10
    SUCCESS=false
  fi
done

if \$SUCCESS; then
  echo \"✓ All processes completed successfully\"
  exit 0
else
  echo \"✗ Some processes failed\"
  exit 1
fi
")

  # Make script executable
  file(CHMOD "${TEST_SCRIPT}"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

  # Add CTest test
  add_test(
    NAME ${PM_NAME}
    COMMAND bash "${TEST_SCRIPT}"
  )

  set_tests_properties(${PM_NAME} PROPERTIES
    TIMEOUT ${PM_TIMEOUT}
    LABELS "podman;multiprocess;network"
  )

  # Report what was added
  list(LENGTH EXEC_TARGETS num_targets)
  if(PM_TARGET)
    message(STATUS "Added podman multiprocess test: ${PM_NAME} with ${PM_PARTICIPANTS} instances of ${PM_TARGET}")
  else()
    message(STATUS "Added podman multiprocess test: ${PM_NAME} with ${num_targets} different executables")
  endif()
endfunction()

# Convenience function for mixed executable scenarios
function(ut_add_podman_mixed_test)
  set(options "")
  set(oneValueArgs NAME SERVER_TARGET CLIENT_TARGET NUM_CLIENTS TIMEOUT)
  set(multiValueArgs EXTRA_TARGETS)

  cmake_parse_arguments(PMM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT PMM_SERVER_TARGET OR NOT PMM_CLIENT_TARGET)
    message(FATAL_ERROR "ut_add_podman_mixed_test: SERVER_TARGET and CLIENT_TARGET required")
  endif()

  if(NOT PMM_NUM_CLIENTS)
    set(PMM_NUM_CLIENTS 2)
  endif()

  # Build target list: 1 server + N clients + any extras
  set(ALL_TARGETS ${PMM_SERVER_TARGET})
  foreach(i RANGE 1 ${PMM_NUM_CLIENTS})
    list(APPEND ALL_TARGETS ${PMM_CLIENT_TARGET})
  endforeach()
  if(PMM_EXTRA_TARGETS)
    list(APPEND ALL_TARGETS ${PMM_EXTRA_TARGETS})
  endif()

  ut_add_podman_multiprocess_test(
    NAME ${PMM_NAME}
    TARGETS ${ALL_TARGETS}
    TIMEOUT ${PMM_TIMEOUT}
  )
endfunction()