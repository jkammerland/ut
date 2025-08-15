//
// Process 2 - Example multiprocess test component
//
#include <boost/ut.hpp>
#include <fstream>
#include <chrono>
#include <thread>
#include <cstdlib>

using namespace boost::ut;

// Simple IPC through files for demonstration
void write_status(const std::string& status) {
  std::ofstream file("/tmp/boost_ut_process2_status.txt");
  file << status << std::endl;
}

std::string read_process1_status() {
  std::ifstream file("/tmp/boost_ut_process1_status.txt");
  std::string status;
  std::getline(file, status);
  return status;
}

int main() {
  // Test 1: Process initialization
  "process2 initialization"_test = [] {
    expect(true) << "Process 2 started successfully";
    write_status("initialized");
  };
  
  // Test 2: Different behavior than process1
  "process2 specific test"_test = [] {
    // This process performs different operations
    int result = 0;
    for (int i = 1; i <= 100; ++i) {
      result += i;
    }
    expect(result == 5050_i) << "Sum of 1-100";
  };
  
  // Test 3: Inter-process coordination
  "inter process coordination"_test = [] {
    write_status("ready");
    
    // Wait for process1 to be ready
    int attempts = 0;
    while (attempts < 50) {  // 5 seconds timeout
      auto status = read_process1_status();
      if (status == "ready" || status == "initialized") {
        expect(true) << "Process 1 is ready";
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      attempts++;
    }
    
    if (attempts >= 50) {
      expect(false) << "Timeout waiting for process 1";
    }
  };
  
  // Test 4: Simulated work (different from process1)
  "process2 work"_test = [] {
    // Simulate different work
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    
    // Check if process1 completed
    auto status = read_process1_status();
    if (status == "completed") {
      expect(true) << "Process 1 completed before us";
    }
    
    // Write our completion
    write_status("completed");
    
    expect(true) << "Process 2 work completed";
  };
  
  // Test 5: Failure demonstration (can be commented out)
  if (std::getenv("FORCE_PROCESS2_FAIL")) {
    "intentional failure"_test = [] {
      expect(false) << "Process 2 forced to fail for testing";
    };
  }
  
  // Clean up
  std::remove("/tmp/boost_ut_process2_status.txt");
  
  return 0;
}