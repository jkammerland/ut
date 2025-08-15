//
// Example of MPI testing with boost.ut
// Compile: mpic++ -std=c++20 -I../../include mpi_example.cpp -o mpi_example
// Run: mpirun -np 4 ./mpi_example
//
#include "boost_ut_mpi.hpp"
#include <vector>
#include <numeric>

using namespace boost::ut;

// Simple function to test
int rank_dependent_value(int rank) {
  return 10 + rank;
}

// MPI reduction function to test
int distributed_sum(int local_value, MPI_Comm comm) {
  int global_sum;
  MPI_Allreduce(&local_value, &global_sum, 1, MPI_INT, MPI_SUM, comm);
  return global_sum;
}

// Basic MPI test
MPI_TEST_CASE("rank-dependent values", 2) {
  int value = rank_dependent_value(test_rank);
  
  MPI_CHECK(0, value == 10);  // Only checked on rank 0
  MPI_CHECK(1, value == 11);  // Only checked on rank 1
}

// Test MPI collective operations
MPI_TEST_CASE("MPI reduction", 4) {
  int local = test_rank + 1;  // 1, 2, 3, 4
  int sum = distributed_sum(local, test_comm);
  
  // All ranks should see the same sum: 1+2+3+4 = 10
  expect(sum == 10_i) << "rank " << test_rank << " got sum " << sum;
}

// Test with subcases
MPI_TEST_CASE("MPI with subcases", 2) {
  "basic properties"_test = [&] {
    expect(test_nb_procs == 2_i);
    expect(test_rank >= 0_i);
    expect(test_rank < test_nb_procs);
  };
  
  "rank-specific subcases"_test = [&] {
    if (test_rank == 0) {
      expect(test_comm != MPI_COMM_NULL);
    } else {
      expect(test_rank == 1_i);
    }
  };
}

// Test scatter/gather pattern
MPI_TEST_CASE("scatter and gather", 3) {
  std::vector<int> sendbuf;
  int recvbuf;
  
  // Root process prepares data
  if (test_rank == 0) {
    sendbuf = {100, 200, 300};
  }
  
  // Scatter data to all processes
  MPI_Scatter(sendbuf.data(), 1, MPI_INT,
              &recvbuf, 1, MPI_INT,
              0, test_comm);
  
  // Each process should receive specific value
  MPI_CHECK(0, recvbuf == 100);
  MPI_CHECK(1, recvbuf == 200); 
  MPI_CHECK(2, recvbuf == 300);
  
  // Modify the received value
  recvbuf *= 2;
  
  // Gather results back
  std::vector<int> gathered;
  if (test_rank == 0) {
    gathered.resize(test_nb_procs);
  }
  
  MPI_Gather(&recvbuf, 1, MPI_INT,
             gathered.data(), 1, MPI_INT,
             0, test_comm);
  
  // Verify gathered results on root
  if (test_rank == 0) {
    expect(gathered[0] == 200_i);
    expect(gathered[1] == 400_i);
    expect(gathered[2] == 600_i);
  }
}

// Test that demonstrates failure reporting
MPI_TEST_CASE("failure demonstration", 2) {
  // This will fail on rank 1
  expect(test_rank == 0_i) << "I'm rank " << test_rank;
  
  // This will fail on both ranks  
  expect(false) << "This always fails";
}

// Regular boost.ut tests work too
int main(int argc, char* argv[]) {
  // Regular non-MPI tests
  "regular test"_test = [] {
    expect(1 + 1 == 2_i);
  };
  
  // Run all tests (both MPI and regular)
  return mpi::run_mpi_tests(argc, argv);
}