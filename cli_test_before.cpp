#include <boost/ut.hpp>

int main(int argc, const char** argv) {
  using namespace boost::ut;
  
  boost::ut::detail::cfg::parse_arg_with_fallback(argc, argv);

  "simple test"_test = [] {
    expect(42 == 42_i);
  };

  "another test"_test = [] {
    expect(1 == 1_i);
  };

  "failing test"_test = [] {
    expect(1 == 2_i);
  };

  return 0;
}