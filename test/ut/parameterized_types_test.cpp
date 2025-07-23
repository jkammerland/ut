#include <boost/ut.hpp>
#include <tuple>
#include <type_traits>
#include <limits>
#include <typeinfo>
#include <cstdint>

int main() {
    using namespace boost::ut;

    // Test 1: Single type parameter - integral types
    "integral types"_test = []<class T>() {
        expect(std::is_integral_v<T>);
        expect(sizeof(T) > 0_u);
        expect(sizeof(T) <= sizeof(long long));
        
        T min_val = std::numeric_limits<T>::min();
        T max_val = std::numeric_limits<T>::max();
        expect(min_val <= max_val);
    } | std::tuple<int, char, long, short, unsigned int, std::int64_t>{};

    // Test 2: Floating point types
    "floating point types"_test = []<class T>() {
        expect(std::is_floating_point_v<T>);
        expect(std::numeric_limits<T>::has_infinity);
        expect(std::numeric_limits<T>::is_iec559);
        
        T zero{0};
        T one{1};
        T half = one / T{2};
        expect(half > zero);
        expect(half < one);
    } | std::tuple<float, double, long double>{};

    // Test 3: Type-specific logic with numeric limits
    "numeric limits"_test = []<class T>() {
        if constexpr (std::is_signed_v<T>) {
            expect(std::numeric_limits<T>::lowest() < 0);
            expect(std::numeric_limits<T>::min() <= 0);
            T neg{-1};
            expect(neg < T{0});
        } else {
            expect(std::numeric_limits<T>::lowest() == 0);
            expect(std::numeric_limits<T>::min() >= 0);
        }
        
        expect(std::numeric_limits<T>::max() > T{0});
    } | std::tuple<int, unsigned int, char, unsigned char, short, unsigned short>{};

    // Test 4: Testing type traits
    "type traits"_test = []<class T>() {
        expect(std::is_arithmetic_v<T>);
        expect(std::is_default_constructible_v<T>);
        expect(std::is_copy_constructible_v<T>);
        expect(std::is_move_constructible_v<T>);
        expect(std::is_assignable_v<T&, T>);
        
        if constexpr (std::is_integral_v<T>) {
            expect(not std::is_floating_point_v<T>);
        }
    } | std::tuple<int, float, double, char, long>{};

    // Test 5: Combined value and type testing
    "value and type"_test = []<class T>(T value) {
        expect(std::is_same_v<decltype(value), T>);
        expect(value != T{});
        
        // Test arithmetic operations
        if constexpr (std::is_arithmetic_v<T> and not std::is_same_v<T, char>) {
            T doubled = value + value;
            expect(doubled == value * T{2});
        }
        
        // Test comparison
        expect(value == value);
        expect(not (value < value));
    } | std::tuple{42, 3.14, 'a', 100L, 2.5f};

    // Test 6: Testing with custom operations per type
    "type operations"_test = []<class T>() {
        T a{1};
        T b{2};
        T c = a + b;
        
        expect(c > a);
        expect(c > b);
        expect(c == T{3});
        
        if constexpr (std::is_floating_point_v<T>) {
            T d = a / b;
            expect(d < a);
            expect(d > T{0});
        }
        
        if constexpr (std::is_integral_v<T>) {
            T d = b % a;
            expect(d == T{0});
        }
    } | std::tuple<int, float, double, long>{};

    // Test 7: Size relationships
    "type sizes"_test = []<class T>() {
        constexpr size_t size = sizeof(T);
        expect(size > 0_u);
        
        if constexpr (std::is_same_v<T, char>) {
            expect(size == 1_u);
        } else if constexpr (std::is_same_v<T, short>) {
            expect(size >= sizeof(char));
            expect(size <= sizeof(int));
        } else if constexpr (std::is_same_v<T, int>) {
            expect(size >= sizeof(short));
            expect(size <= sizeof(long));
        } else if constexpr (std::is_same_v<T, long>) {
            expect(size >= sizeof(int));
        }
    } | std::tuple<char, short, int, long, long long>{};

    return 0;
}