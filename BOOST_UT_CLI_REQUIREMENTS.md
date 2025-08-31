# boost-ext/ut CLI Requirements for VSCode Integration

This document specifies the command-line interface requirements needed for seamless integration of boost-ext/ut with the VSCode C++ TestMate extension.

## Overview

To integrate boost-ext/ut with the vscode-catch2-test-adapter extension, the framework needs to provide standardized command-line interface features similar to other supported testing frameworks (Catch2, GoogleTest, doctest).

## Required Features

### 1. Framework Detection via --help

**Requirement**: Test executables must respond to `--help` with identifiable output.

**Implementation**:
```bash
./test_executable --help
```

**Expected Output** (must include this pattern):
```
boost-ext/ut v[MAJOR].[MINOR].[PATCH]
[Optional additional help text]
```

**Examples**:
```
boost-ext/ut v1.1.9
Modern C++ unit testing framework

Usage: ./test_executable [options]
  --help              Show this help message
  --list-tests        List all available tests
  --run-test=<name>   Run specific test by name
  --filter=<pattern>  Run tests matching pattern
```

**Detection Regex**: `/boost-ext\/ut v(\d+)\.(\d+)\.(\d+)/`

### 2. Test Discovery via --list-tests

**Requirement**: Test executables must enumerate all available test cases.

**Implementation**:
```bash
./test_executable --list-tests
```

**Expected Output Format**:
- One test name per line
- Test names exactly as they appear in source code (from `"test name"_test`)
- No additional formatting, prefixes, or metadata
- Empty lines should be ignored

**Example**:
```
basic test
string test
unit test example
integration test example
performance test example
```

**For BDD-style tests**:
```
vector
vector/size
vector/size/I have a vector
vector/size/I have a vector/I resize bigger
vector/size/I have a vector/I resize bigger/The size should increase
```

### 3. Individual Test Execution

**Requirement**: Test executables must support running individual tests or filtered sets of tests.

#### Option A: Exact Test Name (Recommended)
```bash
./test_executable --run-test="test name"
```

**Behavior**:
- Run only the specified test
- Test name must match exactly (case-sensitive)
- Exit with code 0 if test passes, non-zero if fails
- Output results for only that test

#### Option B: Pattern Filtering (Alternative)
```bash
./test_executable --filter="pattern"
```

**Behavior**:
- Support wildcards: `*` (any characters), `?` (single character)
- Examples: `--filter="unit*"`, `--filter="*test*"`, `--filter="basic test"`
- Run all tests matching the pattern

#### Option C: Both (Ideal)
Support both `--run-test` for exact matches and `--filter` for pattern matching.

### 4. Consistent Output Format

**Requirement**: Test execution output must be parseable to determine pass/fail status.

**Success Output**:
```
Running "test name"...
All tests passed (X asserts in Y tests)
```

**Failure Output**:
```
Running "test name"...
  file.cpp:line:FAILED [condition]
FAILED
===============================================================================
tests:   1 | 1 failed
asserts: 2 | 1 passed | 1 failed
```

**Exit Codes**:
- `0`: All tests passed
- Non-zero: One or more tests failed

## Integration Points

### Configuration Integration

The boost-ext/ut implementation should respect the configuration pattern used by the framework:

```cpp
// Allow runtime configuration for CLI support
int main(int argc, const char* argv[]) {
    using namespace boost::ut;
    
    // Process command line arguments
    return cfg<>.run({.argc = argc, .argv = argv});
}
```

### Backward Compatibility

The CLI features should be:
- **Optional**: Existing boost-ext/ut code continues to work unchanged
- **Opt-in**: Enable via configuration or compilation flags if needed
- **Non-breaking**: Default behavior remains the same

## Implementation Suggestions

### Command Line Parsing

```cpp
// Pseudo-code for CLI argument handling
if (args.contains("--help")) {
    print_help();
    return 0;
}

if (args.contains("--list-tests")) {
    list_all_tests();
    return 0;
}

if (args.contains("--run-test")) {
    std::string test_name = args.get_value("--run-test");
    return run_specific_test(test_name);
}

if (args.contains("--filter")) {
    std::string pattern = args.get_value("--filter");
    return run_filtered_tests(pattern);
}

// Default: run all tests
return run_all_tests();
```

### Test Registry

The framework would need to maintain a registry of test names for enumeration:

```cpp
// Internal registry for test discovery
class test_registry {
    static std::vector<std::string> test_names;
    static std::map<std::string, test_function> test_map;
    
public:
    static void register_test(const std::string& name, test_function func);
    static std::vector<std::string> list_tests();
    static bool run_test(const std::string& name);
};
```

## Benefits for boost-ext/ut Users

1. **IDE Integration**: Full VSCode test explorer support
2. **Individual Test Debugging**: Debug specific tests in IDE
3. **Selective Test Execution**: Run only failing tests or specific subsets
4. **CI/CD Integration**: Better integration with build systems and continuous integration
5. **Tool Ecosystem**: Compatibility with other C++ testing tools

## Reference Implementations

For comparison, here are the CLI patterns from other frameworks:

**Catch2**:
```bash
./test --help                    # Shows version and help
./test --list-tests             # Lists all tests  
./test "test name"              # Runs specific test
./test -t "tag"                 # Runs tests with tag
```

**GoogleTest**:
```bash
./test --help                           # Shows help
./test --gtest_list_tests              # Lists tests
./test --gtest_filter="TestCase.Test"  # Runs filtered tests
```

**doctest**:
```bash
./test --help                    # Shows version and help
./test --list-tests             # Lists all tests
./test --test-case="name"       # Runs specific test
```

This CLI interface would make boost-ext/ut a first-class citizen in the VSCode testing ecosystem while maintaining its core philosophy of simplicity and modern C++ design.