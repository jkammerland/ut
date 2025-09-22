# UtMultiprocessHelpers.cmake - Helper functions for multiprocess testing
include_guard(GLOBAL)

# Function to add a multiprocess test
function(ut_add_multiprocess_test)
    cmake_parse_arguments(TEST
        ""
        "NAME;PARTICIPANTS;TIMEOUT"
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

    # Create wrapper script for the test
    set(WRAPPER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}_multiprocess_wrapper.sh")

    file(WRITE ${WRAPPER_SCRIPT} "#!/bin/bash
# Multiprocess test wrapper for ${TEST_NAME}
PARTICIPANTS=${TEST_PARTICIPANTS}
MULTICAST_PORT=\${MULTICAST_PORT:-12345}
MULTICAST_ADDRESS=\${MULTICAST_ADDRESS:-239.255.0.1}
TEST_EXECUTABLE=\"$<TARGET_FILE:${TEST_NAME}>\"

if [ ! -f \"\$TEST_EXECUTABLE\" ]; then
    echo \"Error: Test executable not found: \$TEST_EXECUTABLE\"
    exit 1
fi

echo \"Running ${TEST_NAME} with \$PARTICIPANTS participants\"
echo \"Multicast: \$MULTICAST_ADDRESS:\$MULTICAST_PORT\"

# Start all participants
PIDS=()
for ((i=0; i<\$PARTICIPANTS; i++)); do
    echo \"Starting participant \$i\"
    PROCESS_ID=\$i PARTICIPANT_COUNT=\$PARTICIPANTS \\
    MULTICAST_ADDRESS=\$MULTICAST_ADDRESS \\
    MULTICAST_PORT=\$MULTICAST_PORT \\
    \"\$TEST_EXECUTABLE\" &
    PIDS+=(\$!)
done

echo \"Waiting for all participants to complete...\"

# Wait for all processes
SUCCESS=0
for i in \${!PIDS[@]}; do
    PID=\${PIDS[\$i]}
    if wait \$PID; then
        echo \"Participant \$i (PID \$PID) completed successfully\"
    else
        echo \"Participant \$i (PID \$PID) failed\"
        SUCCESS=1
    fi
done

if [ \$SUCCESS -eq 0 ]; then
    echo \"All participants completed successfully\"
else
    echo \"Some participants failed\"
fi

exit \$SUCCESS
")

    file(CHMOD ${WRAPPER_SCRIPT}
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                   GROUP_READ GROUP_EXECUTE
                   WORLD_READ WORLD_EXECUTE)

    # Add the test
    add_test(NAME ${TEST_NAME}_multiprocess
             COMMAND ${WRAPPER_SCRIPT})

    set_tests_properties(${TEST_NAME}_multiprocess PROPERTIES
        TIMEOUT ${TEST_TIMEOUT}
        LABELS "multiprocess"
    )

    message(STATUS "Added multiprocess test: ${TEST_NAME} with ${TEST_PARTICIPANTS} participants")
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

    # Create the test executable
    add_executable(${TEST_NAME} ${TEST_SOURCES})

    # Link with multiprocess library
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
        "TARGET;PARTICIPANTS"
        ""
        ${ARGN}
    )

    if(NOT RUN_TARGET)
        message(FATAL_ERROR "ut_run_multiprocess_test: TARGET is required")
    endif()

    if(NOT RUN_PARTICIPANTS)
        set(RUN_PARTICIPANTS 2)
    endif()

    # Create a custom target to run the test
    add_custom_target(run_${RUN_TARGET}
        COMMAND ${CMAKE_COMMAND} -E echo "Running ${RUN_TARGET} with ${RUN_PARTICIPANTS} participants"
        COMMAND ${CMAKE_COMMAND} -E env
            PROCESS_ID=0
            PARTICIPANT_COUNT=${RUN_PARTICIPANTS}
            MULTICAST_ADDRESS=239.255.0.1
            MULTICAST_PORT=12345
            $<TARGET_FILE:${RUN_TARGET}> &
        COMMAND ${CMAKE_COMMAND} -E env
            PROCESS_ID=1
            PARTICIPANT_COUNT=${RUN_PARTICIPANTS}
            MULTICAST_ADDRESS=239.255.0.1
            MULTICAST_PORT=12345
            $<TARGET_FILE:${RUN_TARGET}>
        DEPENDS ${RUN_TARGET}
        COMMENT "Running multiprocess test ${RUN_TARGET}"
    )
endfunction()