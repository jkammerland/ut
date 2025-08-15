//
// MPI Testing Example with boost.ut
// Shows how to test MPI code using standard boost.ut syntax
//
#include <boost/ut.hpp>
#include <mpi.h>
#include <vector>
#include <numeric>

using namespace boost::ut;

// Helper to get MPI rank and size
struct mpi_info {
  int rank;
  int size;
  
  mpi_info() {
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
  }
};

// Simple function to test
int rank_dependent_value(int rank) {
  return 10 + rank;
}

// MPI collective operation to test
int distributed_sum(int local_value) {
  int global_sum;
  MPI_Allreduce(&local_value, &global_sum, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
  return global_sum;
}

// Scatter and gather operation
std::vector<int> scatter_gather_test(const std::vector<int>& data, int root = 0) {
  mpi_info mpi;
  
  // Determine send counts and displacements
  int local_size = data.size() / mpi.size;
  int remainder = data.size() % mpi.size;
  
  std::vector<int> sendcounts(mpi.size);
  std::vector<int> displs(mpi.size);
  
  for (int i = 0; i < mpi.size; ++i) {
    sendcounts[i] = local_size + (i < remainder ? 1 : 0);
    displs[i] = (i > 0) ? displs[i-1] + sendcounts[i-1] : 0;
  }
  
  // Scatter data
  int recvcount = sendcounts[mpi.rank];
  std::vector<int> local_data(recvcount);
  
  MPI_Scatterv(data.data(), sendcounts.data(), displs.data(), MPI_INT,
               local_data.data(), recvcount, MPI_INT,
               root, MPI_COMM_WORLD);
  
  // Process local data (example: double each value)
  for (auto& val : local_data) {
    val *= 2;
  }
  
  // Gather results
  std::vector<int> result;
  if (mpi.rank == root) {
    result.resize(data.size());
  }
  
  MPI_Gatherv(local_data.data(), recvcount, MPI_INT,
              result.data(), sendcounts.data(), displs.data(), MPI_INT,
              root, MPI_COMM_WORLD);
  
  return result;
}

int main(int argc, char* argv[]) {
  // Initialize MPI
  MPI_Init(&argc, &argv);
  
  // Get MPI info
  mpi_info mpi;
  
  // Test 1: Basic rank-dependent values
  "rank dependent values"_test = [&] {
    int value = rank_dependent_value(mpi.rank);
    expect(value == 10 + mpi.rank) << "rank " << mpi.rank << " value";
  };
  
  // Test 2: Collective reduction
  "MPI reduction"_test = [&] {
    int local = mpi.rank + 1;  // Each rank contributes rank+1
    int sum = distributed_sum(local);
    
    // Calculate expected sum: 1 + 2 + ... + size
    int expected = mpi.size * (mpi.size + 1) / 2;
    
    expect(sum == expected) << "rank " << mpi.rank 
                           << " expected " << expected 
                           << " got " << sum;
  };
  
  // Test 3: Broadcast
  "MPI broadcast"_test = [&] {
    int value = (mpi.rank == 0) ? 42 : 0;
    MPI_Bcast(&value, 1, MPI_INT, 0, MPI_COMM_WORLD);
    
    expect(value == 42_i) << "rank " << mpi.rank << " broadcast value";
  };
  
  // Test 4: Scatter/Gather
  if (mpi.size >= 2) {  // Only run with 2+ processes
    "scatter gather"_test = [&] {
      std::vector<int> data;
      
      // Root process creates data
      if (mpi.rank == 0) {
        data = {1, 2, 3, 4, 5, 6, 7, 8};
      } else {
        data.resize(8);  // Other processes need correct size
      }
      
      auto result = scatter_gather_test(data);
      
      // Only root checks result
      if (mpi.rank == 0) {
        expect(result.size() == 8_u);
        for (size_t i = 0; i < result.size(); ++i) {
          expect(result[i] == 2 * (i + 1)) << "element " << i;
        }
      }
    };
  }
  
  // Test 5: Point-to-point communication
  if (mpi.size >= 2) {
    "point to point"_test = [&] {
      if (mpi.rank == 0) {
        // Send to rank 1
        int msg = 123;
        MPI_Send(&msg, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);
        
        // Receive from rank 1
        int response;
        MPI_Recv(&response, 1, MPI_INT, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        expect(response == 246_i);
        
      } else if (mpi.rank == 1) {
        // Receive from rank 0
        int msg;
        MPI_Recv(&msg, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        expect(msg == 123_i);
        
        // Send response
        int response = msg * 2;
        MPI_Send(&response, 1, MPI_INT, 0, 0, MPI_COMM_WORLD);
      }
    };
  }
  
  // Test 6: Barrier synchronization
  "barrier test"_test = [&] {
    // Each process waits a different amount of time
    std::this_thread::sleep_for(std::chrono::milliseconds(mpi.rank * 10));
    
    auto start = std::chrono::steady_clock::now();
    MPI_Barrier(MPI_COMM_WORLD);
    auto end = std::chrono::steady_clock::now();
    
    // After barrier, all processes should be synchronized
    // This is hard to test precisely, but we can verify barrier completes
    expect(true) << "barrier completed on rank " << mpi.rank;
  };
  
  // Finalize MPI
  MPI_Finalize();
  
  return 0;
}