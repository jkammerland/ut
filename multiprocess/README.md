# Multiprocess Testing Library

A standalone header-only C++20 library for multiprocess test coordination using UDP multicast.

## Quick Start

### Installation with target_install_package

```bash
# Clone the repository
git clone https://github.com/your-org/ut_multiprocess.git
cd ut_multiprocess

# Configure and build
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build build

# Install
cmake --install build
```

### Using in Your Project

```cmake
# Find the installed package
find_package(ut_multiprocess CONFIG REQUIRED)

# Create your test
add_executable(my_test test.cpp)
target_link_libraries(my_test PRIVATE Test::multiprocess)

# Include helper functions
include(UtMultiprocessHelpers)

# Add as multiprocess test
ut_add_multiprocess_test(
  NAME my_test
  PARTICIPANTS 4
  TIMEOUT 30
)
```

### Example Test Code

```cpp
#include <test/multiprocess.hpp>
#include <iostream>

using namespace test::multiprocess;

int main() {
    try {
        // Get configuration from environment
        int id = environment::get_id();
        int count = environment::get_participant_count();

        std::cout << "Process " << id << " of " << count << " starting\n";

        // Create fixture
        fixture<true> mp(id, count);

        // Synchronize all processes
        mp.sync_point("start");
        std::cout << "Process " << id << " synchronized at start\n";

        // Do some work...
        if (mp.is_coordinator()) {
            std::cout << "Process " << id << " is coordinating\n";
        }

        // Final sync
        mp.sync_point("end");
        std::cout << "Process " << id << " completed\n";

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

### Running Tests

```bash
# Run with CTest
ctest -L multiprocess

# Or run directly
PROCESS_ID=0 PARTICIPANT_COUNT=2 ./my_test &
PROCESS_ID=1 PARTICIPANT_COUNT=2 ./my_test &
wait
```

## Integration with Test Frameworks

### Google Test

```cpp
#include <gtest/gtest.h>
#include <test/multiprocess.hpp>

class MultiprocessTest : public ::testing::Test {
protected:
    std::unique_ptr<test::multiprocess::fixture<true>> mp;

    void SetUp() override {
        int id = test::multiprocess::environment::get_id();
        int count = test::multiprocess::environment::get_participant_count();
        mp = std::make_unique<test::multiprocess::fixture<true>>(id, count);
    }
};

TEST_F(MultiprocessTest, Synchronization) {
    ASSERT_NO_THROW(mp->sync_point("test"));
}
```

### doctest

```cpp
#include <doctest/doctest.h>
#include <test/multiprocess.hpp>

TEST_CASE("Multiprocess synchronization") {
    int id = test::multiprocess::environment::get_id();
    int count = test::multiprocess::environment::get_participant_count();

    test::multiprocess::fixture<true> mp(id, count);
    CHECK_NOTHROW(mp.sync_point("test"));
}
```

### boost::ut

```cpp
#include <boost/ut.hpp>
#include <test/multiprocess.hpp>

using namespace boost::ut;

int main() {
    int id = test::multiprocess::environment::get_id();
    int count = test::multiprocess::environment::get_participant_count();

    "multiprocess test"_test = [&] {
        test::multiprocess::fixture<true> mp(id, count);
        expect(nothrow([&] { mp.sync_point("test"); }));
    };
}
```

## CMake Package Details

The library is installed as a proper CMake package using `target_install_package`:

- **Target**: `Test::multiprocess`
- **Headers**: `include/test/multiprocess.hpp`
- **Dependencies**: `Boost::system`
- **Helper Functions**: `UtMultiprocessHelpers.cmake`
  - `ut_add_multiprocess_test()` - Add multiprocess test to CTest
  - `ut_create_multiprocess_test()` - Create test executable
  - `ut_run_multiprocess_test()` - Debug helper

## Requirements

- C++20 or later
- Boost.Asio (via Boost::system)
- CMake 3.23+
- target_install_package

## License

Distributed under the Boost Software License, Version 1.0.