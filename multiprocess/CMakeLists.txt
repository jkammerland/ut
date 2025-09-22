# Multiprocess Testing Library - Standalone CMake configuration
cmake_minimum_required(VERSION 3.23)
project(ut_multiprocess VERSION 1.0.0 LANGUAGES CXX)

# Find required dependencies
find_package(Boost REQUIRED COMPONENTS system)
find_package(target_install_package CONFIG REQUIRED)

# Create the library as INTERFACE (header-only)
add_library(ut_multiprocess INTERFACE)

# Add headers using FILE_SET
target_sources(ut_multiprocess INTERFACE
  FILE_SET HEADERS
  BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include
  FILES
    include/test/multiprocess.hpp
)

# Link dependencies
target_link_libraries(ut_multiprocess INTERFACE
  Boost::system
)

# Require C++20
target_compile_features(ut_multiprocess INTERFACE cxx_std_20)

# Install using target_install_package
target_install_package(ut_multiprocess
  NAMESPACE Test::
  # Dependencies that consumers need
  PUBLIC_DEPENDENCIES "Boost REQUIRED COMPONENTS system"
  # Include CMake helper functions on find_package
  INCLUDE_ON_FIND_PACKAGE
    cmake/UtMultiprocessHelpers.cmake
)

# Also create an alias for build tree usage
add_library(Test::multiprocess ALIAS ut_multiprocess)