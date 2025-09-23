# Multiprocess Testing Library

A header-only C++20 library for coordinating multiple processes in distributed tests. Works with boost::ut, Google Test, and doctest.

> **🆕 Podman Support for Unique IPs!**
> Need each process to have a different IP address? See [PODMAN_MULTIPROCESS_TESTING.md](docs/PODMAN_MULTIPROCESS_TESTING.md) for rootless container-based testing where each process gets its own IP address.

## Features

- **ID-based coordination**: Each process has a unique ID (0 to N-1)
- **Automatic coordinator election**: Process ID 0 always coordinates
- **UDP multicast communication**: Network-based synchronization
- **Barrier synchronization**: Wait for all processes or just self
- **Framework agnostic**: Works with any C++ testing framework

## Installation

### Using CMake FetchContent

```cmake
include(FetchContent)
FetchContent_Declare(
    ut
    GIT_REPOSITORY https://github.com/boost-ext/ut
    GIT_TAG        v2.3.1
)
FetchContent_MakeAvailable(ut)

# Link to your test executable
target_link_libraries(your_test PRIVATE Boost::ut Boost::system)
```

### Using target_install_package

The library uses `target_install_package` for proper CMake integration:

```cmake
# Create the multiprocess library
add_library(ut_multiprocess INTERFACE)

target_sources(ut_multiprocess INTERFACE
  FILE_SET HEADERS
  BASE_DIRS include
  FILES include/test/multiprocess.hpp
)

target_link_libraries(ut_multiprocess INTERFACE Boost::system)
target_compile_features(ut_multiprocess INTERFACE cxx_std_20)

# Install using target_install_package
target_install_package(ut_multiprocess
  NAMESPACE Test::
  PUBLIC_DEPENDENCIES "Boost REQUIRED COMPONENTS system"
  INCLUDE_ON_FIND_PACKAGE cmake/UtMultiprocessHelpers.cmake
)
```

Consumers can then use:
```cmake
find_package(ut_multiprocess CONFIG REQUIRED)
target_link_libraries(my_test PRIVATE Test::multiprocess)
```

### Manual Installation

1. Copy `include/boost/ut/multiprocess.hpp` to your include path
2. Link against `Boost::system`
3. Require C++20 or later

## Basic Usage

### Environment Variables

Each process needs these environment variables:
- `PROCESS_ID`: Unique process ID (0 to N-1)
- `PARTICIPANT_COUNT`: Total number of processes
- `MULTICAST_ADDRESS`: (optional) Default: "239.255.0.1"
- `MULTICAST_PORT`: (optional) Default: 12345

### Simple Example

```cpp
#include <boost/ut/multiprocess.hpp>

using namespace test::multiprocess;

int main() {
    // Get configuration from environment
    int my_id = process_info::get_id();
    int count = process_info::get_participant_count();

    // Create fixture (wait_for_all = true by default)
    multiprocess_fixture<true> fixture(my_id, count);

    // Synchronize all processes
    fixture.sync_point("start");

    // Do parallel work...

    // Synchronize again
    fixture.sync_point("end");
}
```

## Integration Examples

### Google Test

```cpp
#include <gtest/gtest.h>
#include <boost/ut/multiprocess.hpp>

class MultiprocessTest : public ::testing::Test {
protected:
    void SetUp() override {
        my_id = process_info::get_id();
        count = process_info::get_participant_count();
        fixture = std::make_unique<multiprocess_fixture<true>>(my_id, count);
    }

    std::unique_ptr<multiprocess_fixture<true>> fixture;
    int my_id, count;
};

TEST_F(MultiprocessTest, Synchronization) {
    ASSERT_NO_THROW(fixture->sync_point("test"));
    EXPECT_TRUE(fixture->get_id() == my_id);
}
```

### doctest

```cpp
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include <boost/ut/multiprocess.hpp>

TEST_CASE("Multiprocess synchronization") {
    int id = process_info::get_id();
    int count = process_info::get_participant_count();

    multiprocess_fixture<true> fixture(id, count);

    CHECK_NOTHROW(fixture.sync_point("test"));
    CHECK(fixture.get_id() == id);
}
```

### boost::ut

```cpp
#include <boost/ut.hpp>
#include <boost/ut/multiprocess.hpp>

int main() {
    using namespace boost::ut;

    int id = process_info::get_id();
    int count = process_info::get_participant_count();

    "multiprocess test"_test = [&] {
        multiprocess_fixture<true> fixture(id, count);

        expect(nothrow([&] { fixture.sync_point("test"); }));
        expect(fixture.get_id() == id);
    };
}
```

## CMake Integration

### Adding Multiprocess Tests

```cmake
# Include the multiprocess module
include(UtMultiprocess)

# Build your test executable
add_executable(my_test test.cpp)
target_link_libraries(my_test PRIVATE
    Boost::ut
    Boost::system
    GTest::gtest  # or doctest, etc.
)

# Add as a multiprocess test
ut_add_multiprocess_test(
    NAME my_test
    PARTICIPANTS 4
    TIMEOUT 60
)
```

This generates a wrapper script that runs multiple instances with proper environment variables.

### Running Tests

```bash
# Run directly with environment
PROCESS_ID=0 PARTICIPANT_COUNT=2 ./my_test &
PROCESS_ID=1 PARTICIPANT_COUNT=2 ./my_test &
wait

# Or use CTest
ctest -R my_test_multiprocess
```

## Advanced Features

### Coordinator Pattern

Process ID 0 is always the coordinator:

```cpp
if (fixture.is_coordinator()) {
    // Set up shared resources
    // Broadcast configuration
} else {
    // Wait for coordinator setup
}

fixture.sync_point("setup_complete");
```

### Self-Registration Mode

Wait only for self instead of all processes:

```cpp
// Template parameter false = don't wait for all
multiprocess_fixture<false> fixture(id, count);

// This returns quickly - only waits for self-registration
fixture.sync_point("self_only");
```

### Multiple Checkpoints

```cpp
fixture.sync_point("phase1");
// Do phase 1 work...

fixture.sync_point("phase2");
// Do phase 2 work...

fixture.sync_point("phase3");
// Do phase 3 work...
```

## Network Protocol

The library uses UDP multicast for coordination:

1. **Registration**: Each process sends `REG:<id>` messages
2. **Ready List**: Coordinator broadcasts `READY:<id1>,<id2>,...`
3. **Synchronization**: Processes wait until all IDs appear in ready list

### Message Validation

The implementation validates all messages:
- Empty messages are ignored
- Messages without colons are ignored
- REG messages with empty IDs are ignored
- Non-numeric IDs are ignored
- IDs outside valid range are ignored

## Thread Safety

- All shared state protected by mutexes
- No atomic/mutex mixing
- Proper RAII with jthread
- Clean shutdown sequence

## Requirements

- C++20 or later
- Boost.Asio (via Boost::system)
- UDP multicast support
- POSIX environment (for environment variables)

## Error Handling

The library throws `std::runtime_error` for:
- Invalid environment variables
- Negative process IDs
- Synchronization timeouts (default: 30 seconds)
- Network errors

## Performance Considerations

- Registration messages sent every 200ms
- Ready list broadcast every 500ms
- Default timeout: 30 seconds (configurable)
- UDP packet size: 500 bytes max

## Troubleshooting

### Processes don't synchronize
- Check all processes have unique PROCESS_ID values
- Verify PARTICIPANT_COUNT matches actual process count
- Ensure multicast is enabled on network interface
- Check firewall rules for UDP port

### Timeout errors
- Increase timeout in wait_for condition
- Check network connectivity
- Verify multicast address is valid (224.0.0.0 - 239.255.255.255)

### Port conflicts
- Use different MULTICAST_PORT for each test suite
- Ensure no other processes use the same port

## License

Distributed under the Boost Software License, Version 1.0.

## Contributing

See main boost::ut repository for contribution guidelines.