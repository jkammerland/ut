#include <boost/ut.hpp>

int main(int argc, const char* argv[]) {
    using namespace boost::ut;
    
    // Test the claimed cfg<>.run() pattern from requirements
    return cfg<>.run({.argc = argc, .argv = argv});
}