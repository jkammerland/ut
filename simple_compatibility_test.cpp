#include <boost/ut.hpp>

int main() {
    using namespace boost::ut;
    
    // Test that boost-ut still works exactly as before without any CLI usage
    "simple compatibility test"_test = [] {
        expect(1 + 1 == 2_i);
    };

    "another compatibility test"_test = [] {
        expect("hello world" == std::string("hello world"));
    };
    
    return 0;
}