# MPI Testing Support for boost.ut Provides convenient functions for testing MPI applications

if(ENABLE_UT_MPI_TESTS)

  find_package(MPI)

  # Function to add an MPI test
  function(ut_add_mpi_test)
    set(options "")
    set(oneValueArgs NAME TARGET PROCESSES TIMEOUT)
    set(multiValueArgs ARGS ENVIRONMENT)

    cmake_parse_arguments(MPI_TEST "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT MPI_TEST_NAME)
      message(FATAL_ERROR "ut_add_mpi_test: NAME is required")
    endif()

    if(NOT MPI_TEST_TARGET)
      message(FATAL_ERROR "ut_add_mpi_test: TARGET is required")
    endif()

    if(NOT MPI_TEST_PROCESSES)
      set(MPI_TEST_PROCESSES 2) # Default to 2 processes
    endif()

    if(NOT MPI_TEST_TIMEOUT)
      set(MPI_TEST_TIMEOUT 60) # Default to 60 seconds for MPI tests
    endif()

    if(NOT MPI_FOUND)
      message(WARNING "MPI not found, skipping test ${MPI_TEST_NAME}")
      return()
    endif()

    # Ensure the target is linked with MPI
    target_link_libraries(${MPI_TEST_TARGET} PRIVATE MPI::MPI_CXX)

    # Build the mpirun command
    set(MPI_COMMAND "${MPIEXEC_EXECUTABLE}")

    # Add MPI-specific arguments
    if(MPIEXEC_NUMPROC_FLAG)
      list(APPEND MPI_COMMAND ${MPIEXEC_NUMPROC_FLAG} ${MPI_TEST_PROCESSES})
    endif()

    if(MPIEXEC_PREFLAGS)
      list(APPEND MPI_COMMAND ${MPIEXEC_PREFLAGS})
    endif()

    # Add the executable
    list(APPEND MPI_COMMAND "$<TARGET_FILE:${MPI_TEST_TARGET}>")

    # Add user arguments
    if(MPI_TEST_ARGS)
      list(APPEND MPI_COMMAND ${MPI_TEST_ARGS})
    endif()

    if(MPIEXEC_POSTFLAGS)
      list(APPEND MPI_COMMAND ${MPIEXEC_POSTFLAGS})
    endif()

    # Add the test
    add_test(NAME ${MPI_TEST_NAME} COMMAND ${MPI_COMMAND})

    # Set test properties
    set_tests_properties(${MPI_TEST_NAME} PROPERTIES TIMEOUT ${MPI_TEST_TIMEOUT} PROCESSORS ${MPI_TEST_PROCESSES} # CTest uses this for parallel test scheduling
    )

    # Add environment variables
    set(MPI_ENV "")

    # Common MPI environment variables
    if(MPI_TEST_PROCESSES GREATER 4)
      # For larger process counts, we might need to oversubscribe
      list(APPEND MPI_ENV "OMPI_MCA_rmaps_base_oversubscribe=1")
    endif()

    if(MPI_TEST_ENVIRONMENT)
      list(APPEND MPI_ENV ${MPI_TEST_ENVIRONMENT})
    endif()

    if(MPI_ENV)
      set_tests_properties(${MPI_TEST_NAME} PROPERTIES ENVIRONMENT "${MPI_ENV}")
    endif()

    # Add helpful labels
    set_tests_properties(${MPI_TEST_NAME} PROPERTIES LABELS "MPI;PARALLEL")
  endfunction()

  # Function to build an MPI test executable with boost.ut
  function(ut_add_mpi_executable)
    set(options "")
    set(oneValueArgs NAME)
    set(multiValueArgs SOURCES)

    cmake_parse_arguments(MPI_EXE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT MPI_EXE_NAME)
      message(FATAL_ERROR "ut_add_mpi_executable: NAME is required")
    endif()

    if(NOT MPI_EXE_SOURCES)
      message(FATAL_ERROR "ut_add_mpi_executable: SOURCES is required")
    endif()

    if(NOT MPI_FOUND)
      message(WARNING "MPI not found, skipping executable ${MPI_EXE_NAME}")
      return()
    endif()

    # Create the executable
    add_executable(${MPI_EXE_NAME} ${MPI_EXE_SOURCES})

    # Link with MPI and boost.ut
    target_link_libraries(${MPI_EXE_NAME} PRIVATE MPI::MPI_CXX Boost::ut)

    # Set MPI compile flags if needed
    if(MPI_CXX_COMPILE_FLAGS)
      target_compile_options(${MPI_EXE_NAME} PRIVATE ${MPI_CXX_COMPILE_FLAGS})
    endif()

    if(MPI_CXX_LINK_FLAGS)
      target_link_options(${MPI_EXE_NAME} PRIVATE ${MPI_CXX_LINK_FLAGS})
    endif()
  endfunction()

  # Convenience macro to check if we're in an MPI environment
  macro(ut_require_mpi)
    if(NOT MPI_FOUND)
      message(STATUS "MPI tests require MPI to be installed")
      return()
    endif()
  endmacro()

  # Function to add multiple MPI tests with different process counts
  function(ut_add_mpi_scaling_test)
    set(options "")
    set(oneValueArgs NAME TARGET)
    set(multiValueArgs PROCESS_COUNTS ARGS TIMEOUT)

    cmake_parse_arguments(SCALE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT SCALE_NAME OR NOT SCALE_TARGET)
      message(FATAL_ERROR "ut_add_mpi_scaling_test: NAME and TARGET are required")
    endif()

    if(NOT SCALE_PROCESS_COUNTS)
      set(SCALE_PROCESS_COUNTS 1 2 4 8) # Default scaling
    endif()

    foreach(nproc ${SCALE_PROCESS_COUNTS})
      ut_add_mpi_test(
        NAME
        "${SCALE_NAME}_${nproc}procs"
        TARGET
        ${SCALE_TARGET}
        PROCESSES
        ${nproc}
        ARGS
        ${SCALE_ARGS}
        TIMEOUT
        ${SCALE_TIMEOUT})
    endforeach()
  endfunction()

endif(ENABLE_UT_MPI_TESTS)
