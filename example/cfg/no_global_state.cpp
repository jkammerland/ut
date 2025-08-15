//
// Copyright (c) 2019-2020 Kris Jusiak (kris at jusiak dot net)
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
// http://www.boost.org/LICENSE_1_0.txt)
//
#include <boost/ut.hpp>
#include <iostream>
#include <memory>

namespace ut = boost::ut;

// Override the global configuration to prevent default test registration
template <>
auto ut::cfg<ut::override> = ut::runner<ut::reporter<ut::printer>>{};  // Dummy runner

// Custom test registry to completely avoid global state
class test_registry {
 public:
  using test_fn = std::function<void()>;
  
  void add_test(const std::string& name, test_fn test) {
    tests_.emplace_back(name, std::move(test));
  }
  
  template<class TReporter>
  bool run_all(ut::runner<TReporter>& runner) {
    for (const auto& [name, test] : tests_) {
      runner.on(ut::events::test<test_fn>{
        .type = "test",
        .name = name,
        .tag = {},
        .location = {},
        .arg = {},
        .run = test
      });
    }
    return runner.run();
  }
  
 private:
  std::vector<std::pair<std::string, test_fn>> tests_;
};

// Example test functions that can be defined anywhere
void test_arithmetic(test_registry& registry) {
  registry.add_test("arithmetic operations", []() {
    ut::expect(1 + 1 == 2);
    ut::expect(10 - 5 == 5);
    ut::expect(3 * 4 == 12);
    ut::expect(20 / 4 == 5);
  });
}

void test_strings(test_registry& registry) {
  registry.add_test("string operations", []() {
    std::string hello = "Hello";
    std::string world = "World";
    ut::expect(hello + " " + world == "Hello World");
    ut::expect(hello.length() == 5u);
  });
}

// Test suite as a class
class math_test_suite {
 public:
  static void register_tests(test_registry& registry) {
    registry.add_test("math::abs", []() {
      ut::expect(ut::math::abs(-5) == 5);
      ut::expect(ut::math::abs(5) == 5);
      ut::expect(ut::math::abs(0) == 0);
    });
    
    registry.add_test("math::min_value", []() {
      ut::expect(ut::math::min_value(3, 5) == 3);
      ut::expect(ut::math::min_value(10, 2) == 2);
    });
  }
};

// Main function with complete control
int main(int argc, const char* argv[]) {
  // Create our test registry
  test_registry registry;
  
  // Register all tests
  test_arithmetic(registry);
  test_strings(registry);
  math_test_suite::register_tests(registry);
  
  // Create runner with chosen reporter
  ut::runner<ut::reporter<ut::printer>> runner;
  
  // Could also use a custom reporter:
  // ut::runner<my_custom_reporter> runner;
  
  // Run all tests
  bool success = registry.run_all(runner);
  
  return success ? 0 : 1;
}

/*
Benefits of this approach:

1. No global state whatsoever
2. Complete control over test registration order
3. Easy to integrate with existing test frameworks
4. Can conditionally register tests based on runtime conditions
5. Can create multiple test runners with different configurations
6. Thread-safe test registration (if needed)
7. Easy to implement test filtering, tags, priorities, etc.

You can extend this pattern to support:
- Test fixtures
- Setup/teardown functions  
- Test dependencies
- Parallel test execution
- Custom test discovery mechanisms
*/
