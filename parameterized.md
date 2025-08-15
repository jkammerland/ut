● Parameterized and Templated Tests Guide for boost::ut

  Overview

  boost::ut provides powerful support for parameterized and templated tests, allowing you to test multiple values, types, and their combinations efficiently. This guide focuses on creating type matrices (n×m
  combinations) where you can test every combination of types U and V.

  Basic Parameterized Tests

  Value-Based Parameterization

  #include <boost/ut.hpp>
  #include <vector>

  int main() {
      using namespace boost::ut;

      // Method 1: Traditional loop syntax
      for (auto value : std::vector{1, 2, 3, 4, 5}) {
          test("positive numbers / " + std::to_string(value)) = [value] {
              expect(value > 0_i);
          };
      }

      // Method 2: Alternative syntax with pipe operator
      "positive numbers"_test = [](auto value) {
          expect(value > 0_i);
      } | std::vector{1, 2, 3, 4, 5};

      // Method 3: Using ranges (C++20)
      "range test"_test = [](auto value) {
          expect(value > 0_i);
      } | std::views::iota(1, 6);
  }

  Type-Based Parameterized Tests

  Single Type Parameter

  #include <boost/ut.hpp>
  #include <tuple>
  #include <type_traits>

  int main() {
      using namespace boost::ut;

      // Test multiple types
      "integral types"_test = []<class T>() {
          expect(std::is_integral_v<T>);
          expect(sizeof(T) > 0_u);
      } | std::tuple<int, char, long, short>{};

      // Test with type-specific logic
      "numeric limits"_test = []<class T>() {
          if constexpr (std::is_signed_v<T>) {
              expect(std::numeric_limits<T>::lowest() < 0);
          } else {
              expect(std::numeric_limits<T>::lowest() == 0);
          }
      } | std::tuple<int, unsigned int, char, unsigned char>{};
  }

  Combined Value and Type Testing

  #include <boost/ut.hpp>
  #include <tuple>

  int main() {
      using namespace boost::ut;

      // Test values with their corresponding types
      "value and type"_test = []<class T>(T value) {
          expect(std::is_same_v<decltype(value), T>);
          expect(value != T{});
      } | std::tuple{42, 3.14, 'a', true};
  }

  Type Matrices: n×m Combinations

  Method 1: Explicit Type Pairs

  #include <boost/ut.hpp>
  #include <tuple>
  #include <utility>

  int main() {
      using namespace boost::ut;

      // Define your types
      using U_types = std::tuple<int, float, double>;
      using V_types = std::tuple<char, short, long>;

      // Create explicit combinations
      "type pairs"_test = []<class TypePair>() {
          using U = typename TypePair::first_type;
          using V = typename TypePair::second_type;

          expect(sizeof(U) > 0_u);
          expect(sizeof(V) > 0_u);
          expect(std::is_arithmetic_v<U>);
          expect(std::is_arithmetic_v<V>);

          // Test specific combinations
          U u_val{};
          V v_val{};
          expect(u_val == U{});
          expect(v_val == V{});

      } | std::tuple<
          std::pair<int, char>,
          std::pair<int, short>,
          std::pair<int, long>,
          std::pair<float, char>,
          std::pair<float, short>,
          std::pair<float, long>,
          std::pair<double, char>,
          std::pair<double, short>,
          std::pair<double, long>
      >{};
  }

  Method 2: Template Metaprogramming for Automatic Combinations

  #include <boost/ut.hpp>
  #include <tuple>
  #include <utility>
  #include <type_traits>

  // Helper to generate all combinations
  template<typename Tuple1, typename Tuple2>
  struct cartesian_product;

  template<typename... Ts, typename... Us>
  struct cartesian_product<std::tuple<Ts...>, std::tuple<Us...>> {
      using type = std::tuple<std::pair<Ts, Us>...>;
  };

  // Generate all combinations
  template<typename U_tuple, typename V_tuple>
  constexpr auto make_combinations() {
      return []<typename... Us, typename... Vs>
             (std::tuple<Us...>, std::tuple<Vs...>) {
          return std::tuple<std::pair<Us, Vs>...>{};
      }(U_tuple{}, V_tuple{});
  }

  int main() {
      using namespace boost::ut;

      // Define your type sets
      using U_types = std::tuple<int, float, double>;
      using V_types = std::tuple<char, short, long>;

      // Generate all combinations programmatically
      constexpr auto combinations = std::tuple_cat(
          std::make_tuple(
              std::pair<int, char>{},
              std::pair<int, short>{},
              std::pair<int, long>{}
          ),
          std::make_tuple(
              std::pair<float, char>{},
              std::pair<float, short>{},
              std::pair<float, long>{}
          ),
          std::make_tuple(
              std::pair<double, char>{},
              std::pair<double, short>{},
              std::pair<double, long>{}
          )
      );

      "automated type matrix"_test = []<class TypePair>() {
          using U = typename TypePair::first_type;
          using V = typename TypePair::second_type;

          // Your test logic here
          static_assert(std::is_arithmetic_v<U>);
          static_assert(std::is_arithmetic_v<V>);

          expect(sizeof(U) <= sizeof(V) or sizeof(U) > sizeof(V));

          // Test conversion capabilities
          if constexpr (std::is_convertible_v<U, V>) {
              U u_val{1};
              V v_val = static_cast<V>(u_val);
              expect(v_val == V{1});
          }
      } | combinations;
  }

  Method 3: Nested Parameterized Tests

  #include <boost/ut.hpp>
  #include <tuple>
  #include <string>

  int main() {
      using namespace boost::ut;

      // Define your type sets
      using U_types = std::tuple<int, float, double>;
      using V_types = std::tuple<char, short, long>;

      // Create nested tests for cleaner organization
      "nested type matrix"_test = []<class U>() {
          std::string u_name = typeid(U).name();

          "inner test"_test = [u_name]<class V>() {
              std::string v_name = typeid(V).name();
              std::string test_name = u_name + " with " + v_name;

              // Your test logic for U and V combination
              expect(sizeof(U) > 0_u);
              expect(sizeof(V) > 0_u);

              // Test specific interactions
              if constexpr (std::is_same_v<U, V>) {
                  expect(true); // Same type
              } else {
                  expect(not std::is_same_v<U, V>); // Different types
              }
          } | V_types{};

      } | U_types{};
  }

  Advanced Type Matrix Patterns

  Generic Container Testing

  #include <boost/ut.hpp>
  #include <vector>
  #include <list>
  #include <deque>
  #include <tuple>

  int main() {
      using namespace boost::ut;

      // Test container + element type combinations
      "container matrix"_test = []<class ContainerElementPair>() {
          using Container = typename ContainerElementPair::first_type;
          using Element = typename ContainerElementPair::second_type;

          Container<Element> container;
          container.push_back(Element{});
          container.push_back(Element{});

          expect(container.size() == 2_u);
          expect(not container.empty());

      } | std::tuple<
          std::pair<std::vector, int>,
          std::pair<std::vector, double>,
          std::pair<std::list, int>,
          std::pair<std::list, double>,
          std::pair<std::deque, int>,
          std::pair<std::deque, double>
      >{};
  }

  Algorithmic Type Combinations

  #include <boost/ut.hpp>
  #include <tuple>
  #include <algorithm>
  #include <vector>

  int main() {
      using namespace boost::ut;

      // Test algorithm compatibility with different type combinations
      "algorithm compatibility"_test = []<class Types>() {
          using InputType = typename Types::first_type;
          using OutputType = typename Types::second_type;

          std::vector<InputType> input{InputType{1}, InputType{2}, InputType{3}};
          std::vector<OutputType> output(input.size());

          // Test if conversion works
          if constexpr (std::is_convertible_v<InputType, OutputType>) {
              std::transform(input.begin(), input.end(), output.begin(),
                            [](const InputType& val) { return static_cast<OutputType>(val); });
              expect(output.size() == input.size());
          }

      } | std::tuple<
          std::pair<int, int>,
          std::pair<int, double>,
          std::pair<float, int>,
          std::pair<double, float>
      >{};
  }

  Practical Examples

  Testing Mathematical Operations

  #include <boost/ut.hpp>
  #include <tuple>
  #include <cmath>

  int main() {
      using namespace boost::ut;

      "math operations matrix"_test = []<class TypePair>() {
          using T1 = typename TypePair::first_type;
          using T2 = typename TypePair::second_type;

          T1 a{2};
          T2 b{3};

          // Test addition
          auto sum = a + b;
          expect(sum > T1{0});

          // Test multiplication
          auto product = a * b;
          expect(product > sum);

          // Test type-specific operations
          if constexpr (std::is_floating_point_v<T1> and std::is_floating_point_v<T2>) {
              expect(std::abs(std::sin(a) * std::cos(b)) <= 1.0);
          }

      } | std::tuple<
          std::pair<int, int>,
          std::pair<int, double>,
          std::pair<float, float>,
          std::pair<double, float>
      >{};
  }

  Testing Serialization Compatibility

  #include <boost/ut.hpp>
  #include <tuple>
  #include <sstream>
  #include <string>

  int main() {
      using namespace boost::ut;

      "serialization matrix"_test = []<class TypePair>() {
          using SourceType = typename TypePair::first_type;
          using TargetType = typename TypePair::second_type;

          SourceType source{42};

          // Serialize to string
          std::ostringstream oss;
          oss << source;
          std::string serialized = oss.str();

          // Deserialize to target type
          std::istringstream iss(serialized);
          TargetType target;
          iss >> target;

          expect(not iss.fail());
          expect(static_cast<SourceType>(target) == source);

      } | std::tuple<
          std::pair<int, int>,
          std::pair<int, long>,
          std::pair<float, double>,
          std::pair<double, float>
      >{};
  }

  Best Practices

  1. Custom Test Names

  #include <boost/ut.hpp>
  #include <tuple>
  #include <sstream>

  namespace boost::ut {
      template<typename T, typename U>
      std::string format_test_parameter(const std::pair<T, U>&, int) {
          std::ostringstream oss;
          oss << "(" << typeid(T).name() << ", " << typeid(U).name() << ")";
          return oss.str();
      }
  }

  int main() {
      using namespace boost::ut;

      "custom named tests"_test = []<class TypePair>() {
          // Test implementation
          expect(true);
      } | std::tuple<
          std::pair<int, char>,
          std::pair<float, double>
      >{};
  }

  2. Conditional Testing

  #include <boost/ut.hpp>
  #include <tuple>
  #include <type_traits>

  int main() {
      using namespace boost::ut;

      "conditional tests"_test = []<class TypePair>() {
          using T = typename TypePair::first_type;
          using U = typename TypePair::second_type;

          // Only test if both types are arithmetic
          if constexpr (std::is_arithmetic_v<T> and std::is_arithmetic_v<U>) {
              T t{1};
              U u{2};
              expect(t + u > T{0});
          }

          // Size-based testing
          if constexpr (sizeof(T) >= sizeof(U)) {
              expect(sizeof(T) >= sizeof(U));
          }

      } | std::tuple<
          std::pair<int, char>,
          std::pair<double, float>,
          std::pair<long, short>
      >{};
  }

  3. Error Handling in Type Matrices

  #include <boost/ut.hpp>
  #include <tuple>
  #include <stdexcept>

  int main() {
      using namespace boost::ut;

      "error handling matrix"_test = []<class TypePair>() {
          using T = typename TypePair::first_type;
          using U = typename TypePair::second_type;

          // Test exception safety
          try {
              T t{};
              U u{};

              // Some operation that might throw
              if constexpr (std::is_same_v<T, U>) {
                  expect(nothrow([]{ /* safe operation */ }));
              } else {
                  expect(nothrow([&]{ auto result = t + u; }));
              }
          } catch (...) {
              expect(false) << "Unexpected exception";
          }

      } | std::tuple<
          std::pair<int, int>,
          std::pair<float, double>
      >{};
  }

  Summary

  This guide demonstrates how to create powerful type matrices (n×m combinations) in boost::ut:

  1. Basic parameterization with values and single types
  2. Type pairs for explicit n×m combinations
  3. Template metaprogramming for automatic combination generation
  4. Nested tests for cleaner organization
  5. Advanced patterns for real-world scenarios
  6. Best practices for maintainable test code

  The key insight is that boost::ut allows you to combine types in std::tuple<std::pair<U, V>...> format, giving you complete control over which combinations to test while maintaining clean, readable test code.