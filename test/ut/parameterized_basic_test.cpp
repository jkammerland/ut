#include <boost/ut.hpp>
#include <vector>
#include <ranges>

int main() {
    using namespace boost::ut;

    // Test 1: Traditional loop syntax
    for (auto value : std::vector{1, 2, 3, 4, 5}) {
        test("positive numbers / " + std::to_string(value)) = [value] {
            expect(value > 0_i);
            expect(value <= 5_i);
            expect(value * value > 0_i);
        };
    }

    // Test 2: Alternative syntax with pipe operator
    "positive numbers pipe"_test = [](auto value) {
        expect(value > 0_i);
        expect(value <= 5_i);
        expect(value * value == value * value);
    } | std::vector{1, 2, 3, 4, 5};

    // Test 3: Using ranges (C++20)
    "range test"_test = [](auto value) {
        expect(value > 0_i);
        expect(value < 10_i);
        expect(value % 1 == 0_i);
    } | std::views::iota(1, 6);

    // Test 4: Testing with different data types
    "mixed types int"_test = [](auto value) {
        expect(value != decltype(value){});
    } | std::vector{1, 2, 3, 100};
    
    "mixed types double"_test = [](auto value) {
        expect(value != decltype(value){});
    } | std::vector{1.0, 2.5, 3.14, 100.0};

    // Test 5: Testing with strings
    "string test"_test = [](const std::string& str) {
        expect(not str.empty());
        expect(str.length() > 0_u);
    } | std::vector<std::string>{"hello", "world", "boost", "ut"};

    // Test 6: Testing with pairs
    "pair test"_test = [](const auto& pair) {
        expect(pair.first < pair.second);
        expect(pair.second - pair.first > 0);
    } | std::vector<std::pair<int, int>>{{1, 2}, {3, 5}, {10, 20}};

    // Test 7: Nested loops for multi-dimensional testing
    for (auto x : std::vector{1, 2, 3}) {
        for (auto y : std::vector{4, 5, 6}) {
            test("multiplication / " + std::to_string(x) + " * " + std::to_string(y)) = [x, y] {
                auto result = x * y;
                expect(result >= x);
                expect(result >= y);
                expect(result == y * x);
            };
        }
    }

    return 0;
}