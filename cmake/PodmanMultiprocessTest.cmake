# Simplified Podman Multiprocess Testing
# Symmetric API with regular multiprocess tests - just add executables and go

find_program(PODMAN_EXECUTABLE podman)

if(NOT PODMAN_EXECUTABLE)
  message(STATUS "Podman not found - podman multiprocess tests will be skipped")
  return()
endif()

# Main function - symmetric with ut_add_multiprocess_test
function(ut_add_podman_multiprocess_test)
  set(options "")
  set(oneValueArgs NAME TARGET PARTICIPANTS TIMEOUT)
  set(multiValueArgs "")

  cmake_parse_arguments(PM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Validate required parameters
  if(NOT PM_NAME)
    message(FATAL_ERROR "ut_add_podman_multiprocess_test: NAME is required")
  endif()

  if(NOT PM_TARGET)
    message(FATAL_ERROR "ut_add_podman_multiprocess_test: TARGET is required")
  endif()

  if(NOT PM_PARTICIPANTS)
    set(PM_PARTICIPANTS 2)
  endif()

  if(NOT PM_TIMEOUT)
    set(PM_TIMEOUT 30)
  endif()

  # Get target's executable path
  set(EXEC_PATH "$<TARGET_FILE:${PM_TARGET}>")

  # Create test script that runs containers with unique IPs
  set(TEST_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${PM_NAME}_podman.sh")

  file(GENERATE OUTPUT "${TEST_SCRIPT}" CONTENT "#!/bin/bash
# Auto-generated podman multiprocess test
set -e

EXEC_PATH='${EXEC_PATH}'
PARTICIPANTS=${PM_PARTICIPANTS}
TEST_NAME='${PM_NAME}'
TIMEOUT=${PM_TIMEOUT}

# Ensure executable exists
if [ ! -f \"\$EXEC_PATH\" ]; then
  echo \"Error: Executable not found: \$EXEC_PATH\"
  exit 1
fi

# Create unique network for this test
NETWORK_NAME=\"\${TEST_NAME}-net-\$\$\"
SUBNET=\"10.\$((RANDOM % 100 + 100)).0.0/24\"

echo \"Creating network \$NETWORK_NAME with subnet \$SUBNET\"
podman network create \$NETWORK_NAME --subnet \$SUBNET || exit 1

# Function to cleanup on exit
cleanup() {
  echo \"Cleaning up...\"
  for ((i=0; i<PARTICIPANTS; i++)); do
    podman rm -f \${TEST_NAME}-\$i 2>/dev/null || true
  done
  podman network rm \$NETWORK_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Start containers - each gets unique IP automatically
CONTAINER_IDS=()
echo \"Starting \$PARTICIPANTS processes in containers with unique IPs...\"

for ((i=0; i<PARTICIPANTS; i++)); do
  # Use fedora for glibc compatibility
  CID=\$(podman run -d --name \${TEST_NAME}-\$i --network \$NETWORK_NAME \\
    -v \"\$EXEC_PATH:/test:ro,Z\" \\
    -v /usr/lib64:/hostlib:ro \\
    -e LD_LIBRARY_PATH=/hostlib \\
    -e PROCESS_ID=\$i \\
    -e PARTICIPANT_COUNT=\$PARTICIPANTS \\
    -e MULTICAST_ADDRESS=239.255.0.1 \\
    -e MULTICAST_PORT=\$((15000 + \$\$)) \\
    fedora:latest /test)

  CONTAINER_IDS+=(\$CID)

  # Get and display IP
  sleep 0.2
  IP=\$(podman inspect \${TEST_NAME}-\$i 2>/dev/null | \\
       grep '\"IPAddress\"' | head -1 | cut -d'\"' -f4)
  echo \"  Process \$i started with IP: \$IP\"
done

# Wait for completion with timeout
echo \"Waiting for processes to complete (timeout: \${TIMEOUT}s)...\"
SUCCESS=true

for ((i=0; i<PARTICIPANTS; i++)); do
  if timeout \$TIMEOUT podman wait \${TEST_NAME}-\$i >/dev/null 2>&1; then
    EXIT_CODE=\$(podman inspect \${TEST_NAME}-\$i --format='{{.State.ExitCode}}')
    if [ \"\$EXIT_CODE\" != \"0\" ]; then
      echo \"Process \$i failed with exit code \$EXIT_CODE\"
      podman logs \${TEST_NAME}-\$i | tail -20
      SUCCESS=false
    else
      echo \"Process \$i completed successfully\"
    fi
  else
    echo \"Process \$i timed out\"
    podman logs \${TEST_NAME}-\$i | tail -20
    SUCCESS=false
  fi
done

if \$SUCCESS; then
  echo \"✓ All processes completed successfully with unique IPs\"
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
    ENVIRONMENT "PODMAN_TEST=1"
  )

  message(STATUS "Added podman multiprocess test: ${PM_NAME} with ${PM_PARTICIPANTS} participants")
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

# Helper to check if target should use podman (e.g., needs unique IPs)
function(ut_use_podman_if_needed)
  set(oneValueArgs TARGET NAME PARTICIPANTS)
  cmake_parse_arguments(UPN "" "${oneValueArgs}" "" ${ARGN})

  # Check if test requires unique IPs (you can add detection logic here)
  # For now, provide both versions and let user choose

  if(PODMAN_EXECUTABLE)
    # Add podman version
    ut_add_podman_multiprocess_test(
      NAME "${UPN_NAME}_podman"
      TARGET ${UPN_TARGET}
      PARTICIPANTS ${UPN_PARTICIPANTS}
    )
  endif()

  # Add regular version
  ut_add_multiprocess_test(
    NAME "${UPN_NAME}_local"
    TARGET ${UPN_TARGET}
    PARTICIPANTS ${UPN_PARTICIPANTS}
  )
endfunction()