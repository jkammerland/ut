# Podman Multiprocess Testing - Symmetric API with regular multiprocess tests
# Each container gets a unique IP address for testing distributed systems

find_program(PODMAN_EXECUTABLE podman)

if(NOT PODMAN_EXECUTABLE)
  message(STATUS "Podman not found - podman multiprocess tests will be skipped")
  return()
endif()

# Main function - supports both single TARGET and multiple TARGETS
function(ut_add_podman_multiprocess_test)
  set(options "")
  set(oneValueArgs NAME TARGET PARTICIPANTS TIMEOUT)
  set(multiValueArgs TARGETS)

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
# Auto-generated podman multiprocess test
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

# Create unique network with retry on conflict
NETWORK_NAME=\"\${TEST_NAME}-net-\$\$\"
for attempt in {1..5}; do
  SUBNET=\"10.\$((RANDOM % 200 + 50)).0.0/24\"
  if podman network create \$NETWORK_NAME --subnet \$SUBNET 2>/dev/null; then
    echo \"Created network \$NETWORK_NAME with subnet \$SUBNET\"
    break
  fi
  if [ \$attempt -eq 5 ]; then
    echo \"Failed to create network after 5 attempts\"
    exit 1
  fi
done

cleanup() {
  echo \"Cleaning up...\"
  for ((i=0; i<PARTICIPANTS; i++)); do
    podman rm -f \${TEST_NAME}-\$i 2>/dev/null || true
  done
  podman network rm \$NETWORK_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Detect library path for different distros
if [ -d \"/usr/lib64\" ]; then
  HOST_LIB_PATH=\"/usr/lib64\"
elif [ -d \"/usr/lib/x86_64-linux-gnu\" ]; then
  HOST_LIB_PATH=\"/usr/lib/x86_64-linux-gnu\"
else
  HOST_LIB_PATH=\"/usr/lib\"
fi

# Start containers with different executables
echo \"Starting \$PARTICIPANTS processes...\"
CONTAINER_IDS=()

for ((i=0; i<PARTICIPANTS; i++)); do
  EXEC=\"\${EXEC_PATHS[\$i]}\"
  EXEC_NAME=\$(basename \$EXEC)

  CID=\$(podman run -d --name \${TEST_NAME}-\$i --network \$NETWORK_NAME \\
    -v \"\$EXEC:/test:ro,Z\" \\
    -v \"\$HOST_LIB_PATH:/hostlib:ro\" \\
    -e LD_LIBRARY_PATH=/hostlib \\
    -e PROCESS_ID=\$i \\
    -e PARTICIPANT_COUNT=\$PARTICIPANTS \\
    -e MULTICAST_ADDRESS=239.255.0.1 \\
    -e MULTICAST_PORT=\$((15000 + \$\$)) \\
    fedora:latest /test)

  CONTAINER_IDS+=(\$CID)

  # Get IP with retry
  for retry in {1..3}; do
    sleep 0.3
    IP=\$(podman inspect \${TEST_NAME}-\$i 2>/dev/null | \\
         grep '\"IPAddress\"' | head -1 | cut -d'\"' -f4)
    if [ -n \"\$IP\" ]; then
      echo \"  Process \$i (\$EXEC_NAME): IP=\$IP\"
      break
    fi
  done
done

# Wait for completion
echo \"Waiting for processes (timeout: \${TIMEOUT}s)...\"
SUCCESS=true

for ((i=0; i<PARTICIPANTS; i++)); do
  if timeout \$TIMEOUT podman wait \${TEST_NAME}-\$i >/dev/null 2>&1; then
    EXIT_CODE=\$(podman inspect \${TEST_NAME}-\$i --format='{{.State.ExitCode}}')
    if [ \"\$EXIT_CODE\" = \"0\" ]; then
      echo \"  Process \$i: ✓ Success\"
    else
      echo \"  Process \$i: ✗ Failed (exit code \$EXIT_CODE)\"
      podman logs \${TEST_NAME}-\$i 2>&1 | tail -5
      SUCCESS=false
    fi
  else
    echo \"  Process \$i: ✗ Timeout\"
    podman logs \${TEST_NAME}-\$i 2>&1 | tail -5
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
  if(PM_TARGET)
    message(STATUS "Added podman multiprocess test: ${PM_NAME} with ${PM_PARTICIPANTS} instances of ${PM_TARGET}")
  else()
    list(LENGTH EXEC_TARGETS num_targets)
    message(STATUS "Added podman multiprocess test: ${PM_NAME} with ${num_targets} different executables")
  endif()
endfunction()

# Batch version - run multiple tests with different participant counts
function(ut_add_podman_multiprocess_batch_test)
  set(options "")
  set(oneValueArgs NAME TARGET TIMEOUT)
  set(multiValueArgs PARTICIPANT_COUNTS)

  cmake_parse_arguments(PMB "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT PMB_PARTICIPANT_COUNTS)
    set(PMB_PARTICIPANT_COUNTS 2 3 4)
  endif()

  foreach(count ${PMB_PARTICIPANT_COUNTS})
    ut_add_podman_multiprocess_test(
      NAME "${PMB_NAME}_${count}procs"
      TARGET ${PMB_TARGET}
      PARTICIPANTS ${count}
      TIMEOUT ${PMB_TIMEOUT}
    )
  endforeach()
endfunction()