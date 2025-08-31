#include <boost/ut.hpp>
#include <iostream>

int main(int argc, const char** argv) {
  using namespace boost::ut;
  
  boost::ut::detail::cfg::parse_arg_with_fallback(argc, argv);
  
  std::cout << "DEBUG: run_test = '" << boost::ut::detail::cfg::run_test << "'\n";
  std::cout << "DEBUG: query_pattern = '" << boost::ut::detail::cfg::query_pattern << "'\n";

  "simple test"_test = [] {
    expect(42 == 42_i);
  };

  return 0;
}