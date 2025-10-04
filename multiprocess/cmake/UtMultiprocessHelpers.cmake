# UtMultiprocessHelpers.cmake - Helper functions for multiprocess testing
include_guard(GLOBAL)

# Default multicast port allocation
set(_UT_MULTIPROCESS_PORT_BASE 12345)
if(NOT DEFINED UT_MULTIPROCESS_PORT_NEXT)
    set(UT_MULTIPROCESS_PORT_NEXT 0 CACHE INTERNAL "Next multiprocess port offset")
endif()

function(_ut_multiprocess_next_port OUT_VAR)
    set(_next_offset ${UT_MULTIPROCESS_PORT_NEXT})
    math(EXPR _computed_port "${_UT_MULTIPROCESS_PORT_BASE} + ${_next_offset}")
    math(EXPR _next_value "${_next_offset} + 1")
    set(UT_MULTIPROCESS_PORT_NEXT ${_next_value} CACHE INTERNAL "Next multiprocess port offset" FORCE)
    set(${OUT_VAR} ${_computed_port} PARENT_SCOPE)
endfunction()

function(_ut_multiprocess_generate_wrapper OUTPUT_PATH TARGET_NAME PARTICIPANTS DEFAULT_PORT)
    set(_script_template [=[#!/bin/bash
set -euo pipefail

PARTICIPANTS=@PARTICIPANTS@
DEFAULT_MULTICAST_PORT=@DEFAULT_PORT@
MULTICAST_PORT="${MULTICAST_PORT:-${DEFAULT_MULTICAST_PORT}}"
MULTICAST_ADDRESS="${MULTICAST_ADDRESS:-239.255.0.1}"
TEST_EXECUTABLE="@TARGET_PATH@"

if [ ! -f "$TEST_EXECUTABLE" ]; then
  echo "Error: test executable not found: $TEST_EXECUTABLE" >&2
  exit 1
fi

echo "Running @TARGET_NAME@ with $PARTICIPANTS participants"
echo "Multicast: $MULTICAST_ADDRESS:$MULTICAST_PORT"

PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

for ((i=0; i < $PARTICIPANTS; ++i)); do
  echo "Starting participant $i"
  PROCESS_ID=$i PARTICIPANT_COUNT=$PARTICIPANTS \
  MULTICAST_ADDRESS=$MULTICAST_ADDRESS \
  MULTICAST_PORT=$MULTICAST_PORT \
  "$TEST_EXECUTABLE" &
  PIDS+=($!)
done

status=0
for idx in "${!PIDS[@]}"; do
  pid=${PIDS[$idx]}
  if wait "$pid"; then
    echo "Participant $idx (PID $pid) completed successfully"
  else
    echo "Participant $idx (PID $pid) failed"
    status=1
  fi
done

exit $status
]=])

    set(PARTICIPANTS "${PARTICIPANTS}")
    set(DEFAULT_PORT "${DEFAULT_PORT}")
    set(TARGET_PATH "$<TARGET_FILE:${TARGET_NAME}>")
    set(TARGET_NAME "${TARGET_NAME}")
    string(CONFIGURE "${_script_template}" _script_content @ONLY)
    file(GENERATE OUTPUT "${OUTPUT_PATH}" CONTENT "${_script_content}")
    unset(PARTICIPANTS)
    unset(DEFAULT_PORT)
    unset(TARGET_PATH)
    unset(TARGET_NAME)
endfunction()

# Function to add a multiprocess test
function(ut_add_multiprocess_test)
    cmake_parse_arguments(TEST
        ""
        "NAME;PARTICIPANTS;TIMEOUT;PORT"
        ""
        ${ARGN}
    )

    if(NOT TEST_NAME)
        message(FATAL_ERROR "ut_add_multiprocess_test: NAME is required")
    endif()

    if(NOT TEST_PARTICIPANTS)
        set(TEST_PARTICIPANTS 2)
    endif()

    if(NOT TEST_TIMEOUT)
        set(TEST_TIMEOUT 30)
    endif()

    if(TEST_PORT)
        set(TEST_MULTICAST_PORT ${TEST_PORT})
    else()
        _ut_multiprocess_next_port(TEST_MULTICAST_PORT)
    endif()

    set(WRAPPER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}_multiprocess_wrapper_$<CONFIG>.sh")
    _ut_multiprocess_generate_wrapper("${WRAPPER_SCRIPT}" "${TEST_NAME}" "${TEST_PARTICIPANTS}" "${TEST_MULTICAST_PORT}")

    add_test(NAME ${TEST_NAME}_multiprocess
             COMMAND bash ${WRAPPER_SCRIPT})

    set_tests_properties(${TEST_NAME}_multiprocess PROPERTIES
        TIMEOUT ${TEST_TIMEOUT}
        LABELS "multiprocess"
    )

    message(STATUS "Added multiprocess test: ${TEST_NAME} with ${TEST_PARTICIPANTS} participants (multicast port ${TEST_MULTICAST_PORT})")
endfunction()

# Function to create a multiprocess test executable
function(ut_create_multiprocess_test)
    cmake_parse_arguments(TEST
        ""
        "NAME"
        "SOURCES;LIBRARIES"
        ${ARGN}
    )

    if(NOT TEST_NAME)
        message(FATAL_ERROR "ut_create_multiprocess_test: NAME is required")
    endif()

    if(NOT TEST_SOURCES)
        message(FATAL_ERROR "ut_create_multiprocess_test: SOURCES is required")
    endif()

    add_executable(${TEST_NAME} ${TEST_SOURCES})

    target_link_libraries(${TEST_NAME} PRIVATE
        Test::multiprocess
        ${TEST_LIBRARIES}
    )

    message(STATUS "Created multiprocess test executable: ${TEST_NAME}")
endfunction()

# Function to run multiprocess test directly (for debugging)
function(ut_run_multiprocess_test)
    cmake_parse_arguments(RUN
        ""
        "TARGET;PARTICIPANTS;PORT"
        ""
        ${ARGN}
    )

    if(NOT RUN_TARGET)
        message(FATAL_ERROR "ut_run_multiprocess_test: TARGET is required")
    endif()

    if(NOT RUN_PARTICIPANTS)
        set(RUN_PARTICIPANTS 2)
    endif()

    if(RUN_PORT)
        set(RUN_MULTICAST_PORT ${RUN_PORT})
    else()
        _ut_multiprocess_next_port(RUN_MULTICAST_PORT)
    endif()

    set(RUN_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/run_${RUN_TARGET}_multiprocess_$<CONFIG>.sh")
    _ut_multiprocess_generate_wrapper("${RUN_SCRIPT}" "${RUN_TARGET}" "${RUN_PARTICIPANTS}" "${RUN_MULTICAST_PORT}")

    add_custom_target(run_${RUN_TARGET}
        COMMAND bash ${RUN_SCRIPT}
        DEPENDS ${RUN_TARGET}
        COMMENT "Running multiprocess test ${RUN_TARGET}"
    )
endfunction()
