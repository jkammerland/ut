# Example CMakeLists.txt for multiprocess testing with different frameworks
cmake_minimum_required(VERSION 3.23)
project(multiprocess_examples VERSION 1.0.0 LANGUAGES CXX)

# Find the multiprocess library
find_package(Boost REQUIRED COMPONENTS system)
find_package(target_install_package CONFIG REQUIRED)

# Option to build with different test frameworks
option(USE_BOOST_UT "Build boost::ut example" ON)
option(USE_GTEST "Build Google Test example" OFF)
option(USE_DOCTEST "Build doctest example" OFF)

# Create the multiprocess library if not already available
if(NOT TARGET Test::multiprocess)
  add_library(ut_multiprocess INTERFACE)

  target_sources(ut_multiprocess INTERFACE
    FILE_SET HEADERS
    BASE_DIRS ${CMAKE_SOURCE_DIR}/../../include
    FILES ../../include/boost/ut/multiprocess.hpp
  )

  target_link_libraries(ut_multiprocess INTERFACE Boost::system)
  target_compile_features(ut_multiprocess INTERFACE cxx_std_20)

  add_library(Test::multiprocess ALIAS ut_multiprocess)
endif()

# Include helper functions
include(${CMAKE_SOURCE_DIR}/../../cmake/UtMultiprocess.cmake)

# Boost.UT example
if(USE_BOOST_UT)
  add_executable(multiprocess_boost_ut multiprocess_boost_ut.cpp)
  target_link_libraries(multiprocess_boost_ut PRIVATE
    Test::multiprocess
    Boost::ut
  )

  # Add as multiprocess test
  ut_add_multiprocess_test(
    NAME multiprocess_boost_ut
    PARTICIPANTS 3
    TIMEOUT 30
  )
endif()

# Google Test example
if(USE_GTEST)
  find_package(GTest REQUIRED)

  add_executable(multiprocess_gtest multiprocess_gtest.cpp)
  target_link_libraries(multiprocess_gtest PRIVATE
    Test::multiprocess
    GTest::gtest
    GTest::gtest_main
  )

  ut_add_multiprocess_test(
    NAME multiprocess_gtest
    PARTICIPANTS 4
    TIMEOUT 45
  )
endif()

# doctest example
if(USE_DOCTEST)
  find_package(doctest REQUIRED)

  add_executable(multiprocess_doctest multiprocess_doctest.cpp)
  target_link_libraries(multiprocess_doctest PRIVATE
    Test::multiprocess
    doctest::doctest
  )

  ut_add_multiprocess_test(
    NAME multiprocess_doctest
    PARTICIPANTS 2
    TIMEOUT 30
  )
endif()

# Enable testing
enable_testing()

# Custom target to run all multiprocess tests
add_custom_target(run_multiprocess_tests
  COMMAND ${CMAKE_CTEST_COMMAND} -L multiprocess --output-on-failure
  COMMENT "Running all multiprocess tests"
)