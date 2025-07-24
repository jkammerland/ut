# Multiprocess Testing Examples

# Include our multiprocess testing support
include(${CMAKE_SOURCE_DIR}/cmake/MultiprocessTest.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/MPITest.cmake)

# MPI Test Example
ut_require_mpi()  # Skip if MPI not available

if(MPI_FOUND)
  # Build MPI test executable
  ut_add_mpi_executable(
    NAME boost_ut_mpi_test
    SOURCES mpi_test.cpp
  )
  
  # Add MPI tests with different process counts
  ut_add_mpi_test(
    NAME mpi_test_2procs
    TARGET boost_ut_mpi_test
    PROCESSES 2
    TIMEOUT 30
  )
  
  ut_add_mpi_test(
    NAME mpi_test_4procs
    TARGET boost_ut_mpi_test  
    PROCESSES 4
    TIMEOUT 30
  )
  
  # Add scaling test
  ut_add_mpi_scaling_test(
    NAME mpi_scaling_test
    TARGET boost_ut_mpi_test
    PROCESS_COUNTS 1 2 3 4
  )
endif()

# Generic Multiprocess Test Example
add_executable(boost_ut_process1 process1.cpp)
target_link_libraries(boost_ut_process1 PRIVATE Boost::ut)

add_executable(boost_ut_process2 process2.cpp)
target_link_libraries(boost_ut_process2 PRIVATE Boost::ut)

add_executable(boost_ut_coordinator coordinator.cpp)
target_link_libraries(boost_ut_coordinator PRIVATE Boost::ut)

# Test multiple processes running in parallel
ut_add_multiprocess_test(
  NAME parallel_process_test
  PARALLEL
  TARGETS boost_ut_process1 boost_ut_process2
  TIMEOUT 20
)

# Test sequential execution
ut_add_multiprocess_test(
  NAME sequential_process_test
  SEQUENTIAL
  TARGETS boost_ut_process1 boost_ut_process2
  TIMEOUT 20
)

# Test with coordinator process
ut_add_multiprocess_test(
  NAME coordinated_test
  TARGETS boost_ut_coordinator boost_ut_process1 boost_ut_process2
  PARALLEL
  TIMEOUT 30
  ENVIRONMENT "TEST_MODE=coordinated"
)

# Network namespace example (requires bwrap)
find_program(BWRAP_EXECUTABLE bwrap)
if(BWRAP_EXECUTABLE)
  # Create wrapper script for network isolation
  configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/run_with_netns.sh.in
    ${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh
    @ONLY
  )
  
  # Add network-isolated test
  ut_add_multiprocess_test(
    NAME network_isolated_test
    COMMANDS 
      "${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh $<TARGET_FILE:boost_ut_process1>"
      "${CMAKE_CURRENT_BINARY_DIR}/run_with_netns.sh $<TARGET_FILE:boost_ut_process2>"
    PARALLEL
    TIMEOUT 30
  )
endif()