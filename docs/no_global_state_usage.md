# Using boost.ut Without Global State

This guide demonstrates how to use boost.ut without relying on global test registration, giving you explicit control over test execution.

## Summary

I've created three examples demonstrating different approaches:

1. **Entry/Exit Reporter** (`example/cfg/entry_exit_reporter_fixed.cpp`) - A Google Test-style reporter that shows test entry and exit
2. **Explicit Runner** (`example/cfg/explicit_runner.cpp`) - Shows how to manually create and configure a test runner
3. **No Global State** (`example/cfg/no_global_state.cpp`) - Complete elimination of global state with custom test registry

## Entry/Exit Reporter

A Google Test-style reporter that logs test entry and exit:

```cpp
#include <boost/ut.hpp>

namespace cfg {
class entry_exit_reporter {
  // ... implementation ...
public:
  auto on(ut::events::test_begin test_begin) -> void {
    std::cout << "[ RUN      ] " << test_begin.name << '\n';
  }
  
  auto on(ut::events::test_end) -> void {
    if (has_failures) {
      std::cout << "[  FAILED  ] " << current_test_name_ << '\n';
    } else {
      std::cout << "[       OK ] " << current_test_name_ << '\n';
    }
  }
};
}
```

## Explicit Runner Usage

### Basic Example

```cpp
int main(int argc, const char* argv[]) {
  using namespace ut;
  
  // Create explicit runner instance
  runner<reporter<printer>> test_runner;
  
  // Register tests directly
  test_runner.on(events::test<>{
    .type = "test",
    .name = "my test",
    .run = []() {
      expect(1 + 1 == 2_i);
    }
  });
  
  // Run tests
  return test_runner.run({.argc = argc, .argv = argv}) ? 0 : 1;
}
```

### Using Test Suites

```cpp
int main() {
  runner<reporter<printer>> test_runner;
  
  // Register a suite containing multiple tests
  test_runner.on(events::suite<>{
    []() {
      "test 1"_test = [] { expect(true); };
      "test 2"_test = [] { expect(42 == 42_i); };
    },
    "My Suite"
  });
  
  return test_runner.run() ? 0 : 1;
}
```

## Complete Control Without Any Global State

To avoid all global state:

```cpp
#define BOOST_UT_DISABLE_MODULE  // Disable global test registration

class test_registry {
  using test_fn = std::function<void()>;
  std::vector<std::pair<std::string, test_fn>> tests_;
  
public:
  void add_test(const std::string& name, test_fn test) {
    tests_.emplace_back(name, std::move(test));
  }
  
  template<class TReporter>
  bool run_all(ut::runner<TReporter>& runner) {
    for (const auto& [name, test] : tests_) {
      runner.on(ut::events::test<>{
        .type = "test",
        .name = name,
        .run = test
      });
    }
    return runner.run();
  }
};

int main() {
  test_registry registry;
  
  // Register tests
  registry.add_test("arithmetic", []() {
    ut::expect(2 + 2 == 4);
  });
  
  // Run with chosen reporter
  ut::runner<ut::reporter<ut::printer>> runner;
  return registry.run_all(runner) ? 0 : 1;
}
```

## Benefits

1. **No Global State**: Complete control over test registration and execution
2. **Multiple Runners**: Can create different runners with different configurations
3. **Dynamic Registration**: Register tests based on runtime conditions
4. **Integration**: Easy to integrate with existing test frameworks
5. **Thread Safety**: Can implement thread-safe test registration if needed

## Command Line Options

All standard boost.ut command line options work:

```bash
./my_tests --list-tests              # List all tests
./my_tests "pattern*"                # Run tests matching pattern
./my_tests --reporter junit          # Use JUnit reporter
./my_tests --abort                   # Abort on first failure
./my_tests --success                 # Show successful tests
```

## Custom Reporters

You can use any reporter with the explicit runner:

```cpp
runner<my_custom_reporter> test_runner;
runner<reporter_junit<printer>> junit_runner;
runner<entry_exit_reporter> google_style_runner;
```

See `example/cfg/entry_exit_reporter.cpp` for a complete example of a Google Test-style reporter.