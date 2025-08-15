#include <boost/ut.hpp>
#include <cmath>
#include <cstdint>
#include <limits>
#include <sstream>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>

int main() {
  using namespace boost::ut;
  std::cout << "HELLO !!!" << std::endl;

  // Test 1: Explicit type pairs method
  "type pairs explicit"_test =
      []<class TypePair>() {
        using U = typename TypePair::first_type;
        using V = typename TypePair::second_type;

        expect(sizeof(U) > 0_u);
        expect(sizeof(V) > 0_u);
        expect(std::is_arithmetic_v<U>);
        expect(std::is_arithmetic_v<V>);

        // Test default construction
        U u_val{};
        V v_val{};
        expect(u_val == U{});
        expect(v_val == V{});

        // Test arithmetic operations between types
        U u{1};
        V v{2};
        auto sum = u + v;
        expect(sum > 0);

        // Test size relationships
        if constexpr (sizeof(U) > sizeof(V)) {
          expect(sizeof(U) > sizeof(V));
        } else if constexpr (sizeof(U) < sizeof(V)) {
          expect(sizeof(U) < sizeof(V));
        } else {
          expect(sizeof(U) == sizeof(V));
        }
      } |
      std::tuple<std::pair<int, char>, std::pair<int, short>,
                 std::pair<int, long>, std::pair<float, char>,
                 std::pair<float, short>, std::pair<float, long>,
                 std::pair<double, char>, std::pair<double, short>,
                 std::pair<double, long>>{};

  // Test 2: Testing conversions between types
  "type conversions"_test =
      []<class TypePair>() {
        using U = typename TypePair::first_type;
        using V = typename TypePair::second_type;

        // Test if conversion is possible
        if constexpr (std::is_convertible_v<U, V>) {
          U u_val{42};
          V v_val = static_cast<V>(u_val);
          expect(v_val == V{42});
        }

        if constexpr (std::is_convertible_v<V, U>) {
          V v_val{7};
          U u_val = static_cast<U>(v_val);
          expect(u_val == U{7});
        }

        // Test arithmetic promotions
        U u{1};
        V v{1};
        auto result = u + v;
        using ResultType = decltype(result);
        expect(std::is_arithmetic_v<ResultType>);
      } |
      std::tuple<std::pair<int, double>, std::pair<float, double>,
                 std::pair<char, int>, std::pair<short, long>>{};

  // Test 3: Nested parameterized tests approach
  "nested type matrix"_test = []<class U>() {
    "inner test"_test = []<class V>() {
      // Test type properties
      expect(std::is_arithmetic_v<U>);
      expect(std::is_arithmetic_v<V>);

      // Test specific interactions
      if constexpr (std::is_same_v<U, V>) {
        expect(true);  // Same type
        U a{5};
        V b{5};
        expect(a == b);
      } else {
        expect(not std::is_same_v<U, V>);  // Different types

        // Test mixed arithmetic
        U u{2};
        V v{3};
        std::cout << "U: " << u << ", V: " << v << std::endl;
        // expect(false);
        auto product = u * v;
        expect(product == 6);
      }

      // Test type trait combinations
      if constexpr (std::is_integral_v<U> and std::is_floating_point_v<V>) {
        U u{10};
        V v = static_cast<V>(u);
        std::cout << "U: " << u << ", V: " << v << std::endl;

        expect(v == V{10});
      }
    } | std::tuple<char, short, int, long>{};
  } | std::tuple<int, float, double>{};

  // Test 4: Complex type matrix with operations
  "complex operations matrix"_test =
      []<class TypePair>() {
        using T1 = typename TypePair::first_type;
        using T2 = typename TypePair::second_type;

        // Test min/max relationships
        T1 a = std::numeric_limits<T1>::max();
        T2 b = std::numeric_limits<T2>::max();

        if constexpr (sizeof(T1) == sizeof(T2) and
                      std::is_signed_v<T1> == std::is_signed_v<T2>) {
          // Same size and signedness
          if constexpr (std::is_integral_v<T1> and std::is_integral_v<T2>) {
            expect(a == b);
          }
        }

        // Test overflow behavior
        T1 one{1};

        if constexpr (std::is_integral_v<T1> and std::is_integral_v<T2>) {
          // Integer overflow wraps around
          T1 max_val = std::numeric_limits<T1>::max();
          T1 overflow = max_val + one;
          expect(overflow != max_val);
        }
      } |
      std::tuple<std::pair<std::uint8_t, std::uint16_t>,
                 std::pair<std::int8_t, std::int16_t>,
                 std::pair<std::uint32_t, std::uint64_t>,
                 std::pair<std::int32_t, std::int64_t>>{};

  // Test 5: Type matrix with conditional logic
  "conditional type matrix"_test =
      []<class TypePair>() {
        using T = typename TypePair::first_type;
        using U = typename TypePair::second_type;

        // Only test if both types are arithmetic
        if constexpr (std::is_arithmetic_v<T> and std::is_arithmetic_v<U>) {
          T t{1};
          U u{2};
          auto sum = t + u;
          expect(sum > T{0});
          expect(sum > U{0});
        }

        // Size-based testing
        if constexpr (sizeof(T) >= sizeof(U)) {
          expect(sizeof(T) >= sizeof(U));
          // Larger type can hold smaller type's values
          if constexpr (std::is_integral_v<T> and std::is_integral_v<U> and
                        std::is_signed_v<T> == std::is_signed_v<U>) {
            U u_max = std::numeric_limits<U>::max();
            T t_from_u = static_cast<T>(u_max);
            expect(static_cast<U>(t_from_u) == u_max);
          }
        }

        // Floating point specific tests
        if constexpr (std::is_floating_point_v<T> and
                      std::is_floating_point_v<U>) {
          T t_pi{3.14159};
          U u_pi = static_cast<U>(t_pi);
          auto diff =
              std::abs(static_cast<double>(t_pi) - static_cast<double>(u_pi));
          expect(diff < 0.01);  // Reasonable precision
        }
      } |
      std::tuple<std::pair<int, char>, std::pair<double, float>,
                 std::pair<long, short>, std::pair<float, int>>{};

  return 0;
}