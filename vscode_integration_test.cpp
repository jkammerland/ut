#include <boost/ut.hpp>

int main(int argc, const char* argv[]) {
    using namespace boost::ut;
    
    // Parse CLI args first before defining tests
    boost::ut::detail::cfg::parse_arg_with_fallback(argc, argv);
    
    // Define tests
    "basic test"_test = [] {
        expect(42 == 42_i);
    };

    "string test"_test = [] {
        std::string hello = "hello";
        expect(hello == "hello");
    };

    "unit test example"_test = [] {
        expect(1 + 1 == 2_i);
    };

    "integration test example"_test = [] {
        auto result = 5 * 10;
        expect(result == 50_i);
    };

    "performance test example"_test = [] {
        // Simulate some work
        int sum = 0;
        for(int i = 0; i < 1000; ++i) {
            sum += i;
        }
        expect(sum > 0_i);
    };
    
    return 0;
}