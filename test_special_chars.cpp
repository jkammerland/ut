#include <boost/ut.hpp>

int main(int argc, const char* argv[]) {
    using namespace boost::ut;
    
    boost::ut::detail::cfg::parse_arg_with_fallback(argc, argv);
    
    "test with spaces"_test = [] {
        expect(1 == 1_i);
    };
    
    "test-with-dashes"_test = [] {
        expect(2 == 2_i);
    };
    
    "test_with_underscores"_test = [] {
        expect(3 == 3_i);
    };
    
    "test(with)parentheses"_test = [] {
        expect(4 == 4_i);
    };
    
    "test*with*asterisks"_test = [] {
        expect(5 == 5_i);
    };
    
    return 0;
}