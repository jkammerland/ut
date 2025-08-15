//
// Copyright (c) 2019-2020 Kris Jusiak (kris at jusiak dot net)
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
// http://www.boost.org/LICENSE_1_0.txt)
//
#include <boost/ut.hpp>
#include <iostream>

namespace ut = boost::ut;

// Override the global configuration to prevent default test registration
template <>
auto ut::cfg<ut::override> = ut::runner<ut::reporter<ut::printer>>{};  // Dummy runner

// Example showing how to use the runner without global state
// This gives you explicit control over test registration and execution
int main(int argc, const char* argv[]) {
  using namespace ut;
  
  // Create explicit runner instance with default reporter
  // You can use any reporter here:
  //   - reporter<printer> (default console reporter)
  //   - reporter_junit<printer> (JUnit XML reporter)
  //   - Your custom reporter (see entry_exit_reporter.cpp)
  runner<reporter<printer>> test_runner;
  
  // Option 1: Register individual tests directly
  auto test1 = []() {
    expect(1 + 1 == 2_i);
    expect(2 * 3 == 6_i);
  };
  test_runner.on(events::test<decltype(test1)>{
    .type = "test",
    .name = "basic arithmetic",
    .tag = {},
    .location = {},
    .arg = {},
    .run = test1
  });
  
  // Option 2: Register a test suite containing multiple tests
  auto suite_fn = []() {
    "string operations"_test = [] {
      std::string s = "hello";
      expect(s.size() == 5_u);
      expect(s + " world" == "hello world");
    };
    
    "vector operations"_test = [] {
      std::vector<int> v{1, 2, 3};
      expect(v.size() == 3_u);
      expect(v[0] == 1_i);
    };
    
    "nested tests"_test = [] {
      "inner test 1"_test = [] {
        expect(true);
      };
      
      "inner test 2"_test = [] {
        expect(42 == 42_i);
      };
    };
  };
  test_runner.on(events::suite<decltype(suite_fn)>{
    .run = suite_fn,
    .name = "My Test Suite"
  });
  
  // Option 3: You can also run test code inline
  auto test2 = []() {
    auto result = 10 / 2;
    expect(result == 5_i);
  };
  test_runner.on(events::test<decltype(test2)>{
    .type = "test",
    .name = "inline test",
    .tag = {},
    .location = {},
    .arg = {},
    .run = test2
  });
  
  // Run all registered tests
  // Pass command line arguments for test filtering, reporters, etc.
  auto success = test_runner.run({.argc = argc, .argv = argv});
  
  // Return 0 on success, 1 on failure
  return success ? 0 : 1;
}

/*
Usage examples:

1. Run all tests:
   ./explicit_runner

2. Run tests matching a pattern:
   ./explicit_runner "string*"

3. List all tests:
   ./explicit_runner --list-tests

4. Use different reporter:
   ./explicit_runner --reporter junit

5. Show successful tests:
   ./explicit_runner --success

6. Abort on first failure:
   ./explicit_runner --abort

For more options:
   ./explicit_runner --help
*/
