# UtMultiprocess.cmake - Multiprocess testing support for boost::ut
# This module provides multiprocess testing fixtures that work with boost::ut, gtest, and doctest

include_guard(GLOBAL)

# Create the multiprocess library target
if(NOT TARGET Boost::ut_multiprocess)
    add_library(ut_multiprocess INTERFACE)
    add_library(Boost::ut_multiprocess ALIAS ut_multiprocess)

    # Find required dependencies
    find_package(Boost REQUIRED COMPONENTS system)

    # Set up the library
    target_include_directories(ut_multiprocess INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    )

    target_link_libraries(ut_multiprocess INTERFACE
        Boost::system
    )

    target_compile_features(ut_multiprocess INTERFACE
        cxx_std_20
    )
endif()

# Function to add a multiprocess test
function(ut_add_multiprocess_test)
    cmake_parse_arguments(TEST
        ""
        "NAME;PARTICIPANTS;TIMEOUT"
        "SOURCES;LIBRARIES"
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
    set(WRAPPER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}_wrapper.sh")

    file(WRITE ${WRAPPER_SCRIPT} "#!/bin/bash
# Multiprocess test wrapper for ${TEST_NAME}
PARTICIPANTS=${TEST_PARTICIPANTS}
MULTICAST_PORT=\${MULTICAST_PORT:-12345}
MULTICAST_ADDRESS=\${MULTICAST_ADDRESS:-239.255.0.1}

# Start all participants
PIDS=()
for ((i=0; i<\$PARTICIPANTS; i++)); do
    PROCESS_ID=\$i PARTICIPANT_COUNT=\$PARTICIPANTS \\
    MULTICAST_ADDRESS=\$MULTICAST_ADDRESS \\
    MULTICAST_PORT=\$MULTICAST_PORT \\
    $<TARGET_FILE:${TEST_NAME}> &
    PIDS+=(\$!)
done

# Wait for all processes
SUCCESS=0
for PID in \${PIDS[@]}; do
    if ! wait \$PID; then
        SUCCESS=1
    fi
done

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
    )
endfunction()

# Export function for installing the library
function(ut_multiprocess_install)
    cmake_parse_arguments(INSTALL
        ""
        "EXPORT_NAME"
        ""
        ${ARGN}
    )

    if(NOT INSTALL_EXPORT_NAME)
        set(INSTALL_EXPORT_NAME UtMultiprocessTargets)
    endif()

    include(GNUInstallDirs)

    # Install headers
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/include/boost/ut/multiprocess.hpp
            DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/boost/ut)

    # Install the target
    install(TARGETS ut_multiprocess
            EXPORT ${INSTALL_EXPORT_NAME}
            PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

    # Install CMake config files
    install(EXPORT ${INSTALL_EXPORT_NAME}
            FILE ${INSTALL_EXPORT_NAME}.cmake
            NAMESPACE Boost::
            DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/ut_multiprocess)
endfunction()