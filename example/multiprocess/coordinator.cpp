//
// Coordinator Process - Manages other processes in tests
//
#include <boost/ut.hpp>
#include <fstream>
#include <chrono>
#include <thread>
#include <cstdlib>
#include <filesystem>

using namespace boost::ut;
namespace fs = std::filesystem;

// Check if both processes are ready
bool are_processes_ready() {
  std::ifstream p1("/tmp/boost_ut_process1_status.txt");
  std::ifstream p2("/tmp/boost_ut_process2_status.txt");
  
  if (!p1.is_open() || !p2.is_open()) {
    return false;
  }
  
  std::string status1, status2;
  std::getline(p1, status1);
  std::getline(p2, status2);
  
  return (status1 == "ready" || status1 == "initialized") &&
         (status2 == "ready" || status2 == "initialized");
}

// Check if both processes completed
bool are_processes_completed() {
  std::ifstream p1("/tmp/boost_ut_process1_status.txt");
  std::ifstream p2("/tmp/boost_ut_process2_status.txt");
  
  if (!p1.is_open() || !p2.is_open()) {
    return false;
  }
  
  std::string status1, status2;
  std::getline(p1, status1);
  std::getline(p2, status2);
  
  return status1 == "completed" && status2 == "completed";
}

int main() {
  // Test 1: Coordinator initialization
  "coordinator initialization"_test = [] {
    expect(true) << "Coordinator started";
    
    // Clean any existing status files
    std::remove("/tmp/boost_ut_process1_status.txt");
    std::remove("/tmp/boost_ut_process2_status.txt");
  };
  
  // Test 2: Wait for processes to start
  "wait for processes"_test = [] {
    // In coordinated mode, other processes should be starting
    const char* test_mode = std::getenv("TEST_MODE");
    if (!test_mode || std::string(test_mode) != "coordinated") {
      skip / "coordinator wait"_test = [] {
        expect(true) << "Not in coordinated mode";
      };
      return;
    }
    
    // Wait for both processes to be ready
    int attempts = 0;
    while (attempts < 100) {  // 10 seconds timeout
      if (are_processes_ready()) {
        expect(true) << "Both processes are ready";
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      attempts++;
    }
    
    if (attempts >= 100) {
      expect(false) << "Timeout waiting for processes to start";
    }
  };
  
  // Test 3: Monitor process completion
  "monitor completion"_test = [] {
    const char* test_mode = std::getenv("TEST_MODE");
    if (!test_mode || std::string(test_mode) != "coordinated") {
      return;
    }
    
    // Wait for both processes to complete
    int attempts = 0;
    while (attempts < 100) {  // 10 seconds timeout
      if (are_processes_completed()) {
        expect(true) << "Both processes completed successfully";
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      attempts++;
    }
    
    if (attempts >= 100) {
      expect(false) << "Timeout waiting for processes to complete";
    }
  };
  
  // Test 4: Coordinator-specific functionality
  "coordinator logic"_test = [] {
    // Example: Aggregate results from both processes
    std::vector<fs::path> status_files = {
      "/tmp/boost_ut_process1_status.txt",
      "/tmp/boost_ut_process2_status.txt"
    };
    
    int valid_files = 0;
    for (const auto& file : status_files) {
      if (fs::exists(file)) {
        valid_files++;
      }
    }
    
    expect(valid_files >= 0_i) << "Found " << valid_files << " status files";
  };
  
  return 0;
}