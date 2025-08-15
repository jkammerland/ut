#include <algorithm>
#include <boost/ut.hpp>
#include <cmath>
#include <deque>
#include <list>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <type_traits>
#include <vector>

int main() {
  using namespace boost::ut;

  // Test 1: Generic Container Testing with explicit types
  "vector container test"_test = []<class Element>() {
    std::vector<Element> container;

    // Test empty container
    expect(container.empty());
    expect(container.size() == 0_u);

    // Add elements
    container.push_back(Element{1});
    container.push_back(Element{2});
    container.push_back(Element{3});

    expect(container.size() == 3_u);
    expect(not container.empty());

    // Test iteration
    Element sum{};
    for (const auto& elem : container) {
      sum = sum + elem;
    }
    expect(sum == Element{6});

    // Test front/back access
    expect(container.front() == Element{1});
    expect(container.back() == Element{3});

    // Test clear
    container.clear();
    expect(container.empty());
  } | std::tuple<int, double, float>{};

  "list container test"_test = []<class Element>() {
    std::list<Element> container;

    // Test empty container
    expect(container.empty());
    expect(container.size() == 0_u);

    // Add elements
    container.push_back(Element{1});
    container.push_back(Element{2});
    container.push_back(Element{3});

    expect(container.size() == 3_u);
    expect(not container.empty());

    // Test front/back access
    expect(container.front() == Element{1});
    expect(container.back() == Element{3});

    // Test clear
    container.clear();
    expect(container.empty());
  } | std::tuple<int, double, float>{};

  // Test 2: Algorithm Compatibility
  "algorithm compatibility"_test =
      []<class Types>() {
        using InputType = typename Types::first_type;
        using OutputType = typename Types::second_type;

        std::vector<InputType> input{InputType{1}, InputType{2}, InputType{3},
                                     InputType{4}, InputType{5}};
        std::vector<OutputType> output(input.size());

        // Test transform with conversion
        if constexpr (std::is_convertible_v<InputType, OutputType>) {
          std::transform(input.begin(), input.end(), output.begin(),
                         [](const InputType& val) {
                           return static_cast<OutputType>(val);
                         });
          expect(output.size() == input.size());
          expect(output[0] == OutputType{1});
          expect(output[4] == OutputType{5});
        }

        // Test accumulate
        InputType sum =
            std::accumulate(input.begin(), input.end(), InputType{0});
        expect(sum == InputType{15});

        // Test find
        auto it = std::find(input.begin(), input.end(), InputType{3});
        expect(it != input.end());
        expect(*it == InputType{3});

        // Test sort (make a copy)
        std::vector<InputType> sorted = input;
        std::reverse(sorted.begin(), sorted.end());
        std::sort(sorted.begin(), sorted.end());
        expect(sorted == input);
      } |
      std::tuple<std::pair<int, int>, std::pair<int, double>,
                 std::pair<float, double>, std::pair<short, int>>{};

  // Test 3: Mathematical Operations Matrix
  "math operations matrix"_test =
      []<class TypePair>() {
        using T1 = typename TypePair::first_type;
        using T2 = typename TypePair::second_type;

        T1 a{2};
        T2 b{3};

        // Basic arithmetic
        auto sum = a + b;
        expect(sum == 5);

        auto product = a * b;
        expect(product == 6);

        auto diff = b - a;
        expect(diff == 1);

        // Division
        if constexpr (std::is_floating_point_v<T1> or
                      std::is_floating_point_v<T2>) {
          auto quotient = b / a;
          expect(quotient > 1);
          expect(quotient < 2);
        } else {
          auto quotient = b / a;
          expect(quotient == 1);  // Integer division
        }

        // Power operations (if floating point)
        if constexpr (std::is_floating_point_v<T1> and
                      std::is_floating_point_v<T2>) {
          T1 base{2.0};
          T2 exp{3.0};
          auto power = std::pow(base, exp);
          expect(std::abs(power - 8.0) < 0.001);

          // Trigonometric functions
          T1 angle{0.5};
          auto sin_val = std::sin(angle);
          auto cos_val = std::cos(angle);
          auto identity = sin_val * sin_val + cos_val * cos_val;
          expect(std::abs(identity - 1.0) < 0.001);
        }

        // Comparison operations
        expect(a < b);
        expect(b > a);
        expect(a != b);
      } |
      std::tuple<std::pair<int, int>, std::pair<int, double>,
                 std::pair<float, float>, std::pair<double, float>,
                 std::pair<double, double>>{};

  // Test 4: Serialization Compatibility
  "serialization matrix"_test =
      []<class TypePair>() {
        using SourceType = typename TypePair::first_type;
        using TargetType = typename TypePair::second_type;

        SourceType source{42};

        // Serialize to string
        std::ostringstream oss;
        oss << source;
        std::string serialized = oss.str();
        expect(not serialized.empty());

        // Deserialize to target type
        std::istringstream iss(serialized);
        TargetType target;
        iss >> target;

        expect(not iss.fail());

        // Verify round-trip if possible
        if constexpr (std::is_convertible_v<TargetType, SourceType>) {
          SourceType round_trip = static_cast<SourceType>(target);
          expect(round_trip == source);
        }

        // Test multiple values
        std::ostringstream oss2;
        SourceType values[] = {SourceType{1}, SourceType{2}, SourceType{3}};
        for (const auto& val : values) {
          oss2 << val << " ";
        }

        std::istringstream iss2(oss2.str());
        for (int i = 0; i < 3; ++i) {
          TargetType t;
          iss2 >> t;
          expect(not iss2.fail());
          if constexpr (std::is_same_v<SourceType, TargetType>) {
            expect(t == values[i]);
          }
        }
      } |
      std::tuple<std::pair<int, int>, std::pair<int, long>,
                 std::pair<float, double>, std::pair<double, float>,
                 std::pair<short, int>>{};

  // Test 5: Complex Container Operations with explicit types
  "complex vector ops"_test = []<class ValueType>() {
    std::vector<ValueType> c1;
    std::vector<ValueType> c2;

    // Fill containers
    for (int i = 1; i <= 5; ++i) {
      c1.push_back(static_cast<ValueType>(i));
      c2.push_back(static_cast<ValueType>(i * 2));
    }

    expect(c1.size() == 5_u);
    expect(c2.size() == 5_u);

    // Test copy
    std::vector<ValueType> c3 = c1;
    expect(c3.size() == c1.size());
    expect(c3.front() == c1.front());
    expect(c3.back() == c1.back());

    // Test swap
    auto c1_front = c1.front();
    auto c2_front = c2.front();
    c1.swap(c2);
    expect(c1.front() == c2_front);
    expect(c2.front() == c1_front);

    // Test algorithms on containers
    auto sum1 = std::accumulate(c1.begin(), c1.end(), ValueType{0});
    auto sum2 = std::accumulate(c2.begin(), c2.end(), ValueType{0});
    expect(sum1 == ValueType{30});  // 2+4+6+8+10
    expect(sum2 == ValueType{15});  // 1+2+3+4+5
  } | std::tuple<int, float, double>{};

  "complex deque ops"_test = []<class ValueType>() {
    std::deque<ValueType> c1;
    std::deque<ValueType> c2;

    // Fill containers
    for (int i = 1; i <= 5; ++i) {
      c1.push_back(static_cast<ValueType>(i));
      c2.push_back(static_cast<ValueType>(i * 2));
    }

    expect(c1.size() == 5_u);
    expect(c2.size() == 5_u);

    // Test copy and algorithms
    std::deque<ValueType> c3 = c1;
    expect(c3.size() == c1.size());

    auto sum1 = std::accumulate(c1.begin(), c1.end(), ValueType{0});
    expect(sum1 == ValueType{15});  // 1+2+3+4+5
  } | std::tuple<int, double>{};

  // Test 6: Error Handling in Type Matrices
  "error handling matrix"_test =
      []<class TypePair>() {
        using T = typename TypePair::first_type;
        using U = typename TypePair::second_type;

        // Test exception safety for basic operations
        expect(nothrow([] { [[maybe_unused]] T t{}; }));
        expect(nothrow([] { [[maybe_unused]] U u{}; }));

        T t{1};
        U u{2};

        // Arithmetic operations should not throw
        expect(nothrow([&] { [[maybe_unused]] auto result = t + u; }));
        expect(nothrow([&] { [[maybe_unused]] auto result = t * u; }));

        // Test container operations
        expect(nothrow([&] {
          std::vector<T> vec;
          vec.push_back(t);
          vec.clear();
        }));

        // Test conversions (may throw in some cases)
        if constexpr (std::is_convertible_v<T, U>) {
          expect(nothrow(
              [&] { [[maybe_unused]] U converted = static_cast<U>(t); }));
        }

        // Test string stream operations
        expect(nothrow([&] {
          std::ostringstream oss;
          oss << t;
        }));
      } |
      std::tuple<std::pair<int, int>, std::pair<float, double>,
                 std::pair<char, int>, std::pair<double, double>>{};

  // Test 7: Custom test names formatting
  "custom named type tests"_test =
      []<class TypePair>() {
        using T = typename TypePair::first_type;
        using U = typename TypePair::second_type;

        // Create descriptive test output
        std::ostringstream oss;
        oss << "Type pair test with T=" << typeid(T).name()
            << " and U=" << typeid(U).name();
        auto test_name = oss.str();

        T t{10};
        U u{20};

        // Test with custom expectations
        expect(t < u) << test_name << ": t should be less than u";
        expect(sizeof(T) > 0_u) << test_name << ": T size check";
        expect(sizeof(U) > 0_u) << test_name << ": U size check";
      } |
      std::tuple<std::pair<int, char>, std::pair<float, double>,
                 std::pair<long, short>>{};

  return 0;
}
