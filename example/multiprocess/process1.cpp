//
// Process 1 - Example multiprocess test component
//
#include <boost/ut.hpp>
#include <fstream>
#include <chrono>
#include <thread>
#include <cstdlib>

using namespace boost::ut;

// Simple IPC through files for demonstration
void write_status(const std::string& status) {
  std::ofstream file("/tmp/boost_ut_process1_status.txt");
  file << status << std::endl;
}

std::string read_process2_status() {
  std::ifstream file("/tmp/boost_ut_process2_status.txt");
  std::string status;
  std::getline(file, status);
  return status;
}

int main() {
  // Test 1: Process initialization
  "process1 initialization"_test = [] {
    expect(true) << "Process 1 started successfully";
    write_status("initialized");
  };
  
  // Test 2: Environment variable test
  "environment test"_test = [] {
    const char* test_mode = std::getenv("TEST_MODE");
    if (test_mode) {
      expect(std::string(test_mode) == "coordinated"_b) 
        << "TEST_MODE is " << test_mode;
    } else {
      expect(true) << "No TEST_MODE set";
    }
  };
  
  // Test 3: Inter-process coordination
  "inter process coordination"_test = [] {
    write_status("ready");
    
    // Wait for process2 to be ready
    int attempts = 0;
    while (attempts < 50) {  // 5 seconds timeout
      auto status = read_process2_status();
      if (status == "ready" || status == "initialized") {
        expect(true) << "Process 2 is ready";
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      attempts++;
    }
    
    if (attempts >= 50) {
      expect(false) << "Timeout waiting for process 2";
    }
  };
  
  // Test 4: Simulated work
  "process1 work"_test = [] {
    // Simulate some work
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    
    // Write completion marker
    write_status("completed");
    
    expect(true) << "Process 1 work completed";
  };
  
  // Clean up
  std::remove("/tmp/boost_ut_process1_status.txt");
  
  return 0;
}