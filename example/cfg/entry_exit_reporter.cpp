//
// Copyright (c) 2019-2020 Kris Jusiak (kris at jusiak dot net)
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
// http://www.boost.org/LICENSE_1_0.txt)
//
#include <boost/ut.hpp>
#include <iostream>
#include <string>
#include <string_view>

namespace ut = boost::ut;

// Override the global configuration to prevent default test registration
template <>
auto ut::cfg<ut::override> =
    ut::runner<ut::reporter<ut::printer>>{};  // Dummy runner

namespace cfg {
class entry_exit_reporter {
  struct test_colors {
    std::string pass{"\033[32m"};
    std::string fail{"\033[31m"};
    std::string skip{"\033[33m"};
    std::string suite{"\033[34m"};
    std::string none{"\033[0m"};
  };

  test_colors colors_{};
  std::size_t test_count_{};
  std::size_t pass_count_{};
  std::size_t fail_count_{};
  std::size_t skip_count_{};
  std::size_t assertion_count_{};
  std::size_t assertion_fails_{};
  std::size_t current_test_fails_{};
  std::string current_test_name_{};
  std::string current_suite_name_{};
  int indent_level_{0};

  auto indent() const { return std::string(indent_level_ * 2, ' '); }

 public:
  auto on(ut::events::run_begin) const -> void {
    std::cout << colors_.suite << "[==========] " << colors_.none
              << "Running tests...\n";
  }

  auto on(ut::events::suite_begin suite) -> void {
    current_suite_name_ = suite.name;
    std::cout << colors_.suite << "[----------] " << colors_.none
              << "Test suite \"" << suite.name << "\"\n";
    ++indent_level_;
  }

  auto on(ut::events::suite_end) -> void {
    --indent_level_;
    std::cout << colors_.suite << "[----------] " << colors_.none
              << "Test suite \"" << current_suite_name_ << "\" finished\n\n";
    current_suite_name_.clear();
  }

  auto on(ut::events::test_begin test_begin) -> void {
    current_test_name_ = test_begin.name;
    current_test_fails_ = assertion_fails_;
    std::cout << indent() << colors_.suite << "[ RUN      ] " << colors_.none
              << test_begin.name << '\n';
    ++test_count_;
    ++indent_level_;
  }

  auto on(ut::events::test_run test_run) -> void {
    std::cout << indent() << colors_.suite << "[ SUBTEST  ] " << colors_.none
              << test_run.name << '\n';
    ++indent_level_;
  }

  auto on(ut::events::test_skip test_skip) -> void {
    std::cout << indent() << colors_.skip << "[   SKIP   ] " << colors_.none
              << test_skip.name << '\n';
    ++skip_count_;
  }

  auto on(ut::events::test_end) -> void {
    --indent_level_;
    if (assertion_fails_ > current_test_fails_) {
      std::cout << indent() << colors_.fail << "[  FAILED  ] " << colors_.none
                << current_test_name_ << '\n';
      ++fail_count_;
    } else {
      std::cout << indent() << colors_.pass << "[       OK ] " << colors_.none
                << current_test_name_ << '\n';
      ++pass_count_;
    }
  }

  auto on(ut::events::test_finish) -> void { --indent_level_; }

  template <class TMsg>
  auto on(ut::events::log<TMsg> log) -> void {
    std::cout << indent() << log.msg;
  }

  template <class TExpr>
  auto on(ut::events::assertion_pass<TExpr>) -> void {
    ++assertion_count_;
  }

  template <class TExpr>
  auto on(ut::events::assertion_fail<TExpr> assertion) -> void {
    std::cout << indent() << assertion.location.file_name() << ':'
              << assertion.location.line() << ": " << colors_.fail << "Failure"
              << colors_.none << '\n';
    std::cout << indent() << "  Condition: " << assertion.expr << '\n';
    ++assertion_count_;
    ++assertion_fails_;
  }

  auto on(ut::events::exception exception) -> void {
    std::cout << indent() << colors_.fail
              << "Unexpected exception: " << exception.what() << colors_.none
              << '\n';
    ++assertion_fails_;
  }

  auto on(ut::events::fatal_assertion) -> void {}

  auto on(ut::events::summary) -> void {
    std::cout << colors_.suite << "[==========] " << colors_.none << test_count_
              << " test(s) ran\n";

    if (pass_count_ > 0) {
      std::cout << colors_.pass << "[  PASSED  ] " << colors_.none
                << pass_count_ << " test(s)\n";
    }

    if (skip_count_ > 0) {
      std::cout << colors_.skip << "[  SKIPPED ] " << colors_.none
                << skip_count_ << " test(s)\n";
    }

    if (fail_count_ > 0) {
      std::cout << colors_.fail << "[  FAILED  ] " << colors_.none
                << fail_count_ << " test(s)\n";
    }

    std::cout << "\nTotal assertions: " << assertion_count_
              << " | Failed: " << assertion_fails_ << '\n';
  }
};
}  // namespace cfg

// Example usage - demonstrating explicit runner instantiation
int main() {
  using namespace ut;

  // Create explicit runner instance with entry/exit reporter
  ut::runner<cfg::entry_exit_reporter> runner;

  // Register tests with the runner
  auto test_fn = []() {
    "basic test"_test = [] {
      expect(42 == 42_i);
      expect(true);
    };

    "nested test"_test = [] {
      "subtest 1"_test = [] { expect(1 + 1 == 2_i); };

      "subtest 2"_test = [] { expect(2 + 2 == 4_i); };
    };

    "failing test"_test = [] { expect(1 == 2_i) << "This should fail"; };

    skip / "skipped test"_test = [] { expect(false) << "This should not run"; };
  };
  runner.on(ut::events::test<decltype(test_fn)>{.type = "test",
                                                .name = "example test",
                                                .tag = {},
                                                .location = {},
                                                .arg = {},
                                                .run = test_fn});

  // Run the tests
  return runner.run() ? 0 : 1;
}
