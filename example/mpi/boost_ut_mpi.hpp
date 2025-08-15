//
// MPI Testing Extension for boost.ut
// Inspired by doctest's MPI implementation
//
#pragma once
#include <boost/ut.hpp>
#include <mpi.h>
#include <cstdlib>
#include <map>
#include <sstream>

namespace ut = boost::ut;

namespace ut::mpi {

// Detect MPI environment before MPI_Init
inline int detect_mpi_size() {
  // OpenMPI
  if (const char* ompi_size = std::getenv("OMPI_COMM_WORLD_SIZE")) {
    return std::atoi(ompi_size);
  }
  // Intel MPI and MPICH  
  if (const char* pmi_size = std::getenv("PMI_SIZE")) {
    return std::atoi(pmi_size);
  }
  // SLURM
  if (const char* slurm_size = std::getenv("SLURM_NTASKS")) {
    return std::atoi(slurm_size);
  }
  return 0;  // Not running under MPI
}

// Global MPI context
struct mpi_context {
  int rank = 0;
  int size = 1;
  MPI_Comm comm = MPI_COMM_WORLD;
  bool initialized = false;
  
  static mpi_context& instance() {
    static mpi_context ctx;
    return ctx;
  }
  
  void init(int* argc, char*** argv) {
    if (!initialized) {
      MPI_Init(argc, argv);
      MPI_Comm_rank(MPI_COMM_WORLD, &rank);
      MPI_Comm_size(MPI_COMM_WORLD, &size);
      initialized = true;
    }
  }
  
  void finalize() {
    if (initialized) {
      MPI_Finalize();
      initialized = false;
    }
  }
};

// MPI-aware reporter that only outputs on rank 0
template <class TReporter = ut::reporter<ut::printer>>
class mpi_console_reporter : public TReporter {
  struct rank_failure {
    int rank;
    std::string test_name;
    std::string location;
    std::string expr;
  };
  
  std::vector<rank_failure> failures_;
  int local_test_fails_ = 0;
  std::string current_test_;
  
public:
  auto on(ut::events::test_begin test_begin) -> void {
    current_test_ = test_begin.name;
    local_test_fails_ = 0;
    if (mpi_context::instance().rank == 0) {
      TReporter::on(test_begin);
    }
  }
  
  template <class TExpr>
  auto on(ut::events::assertion_fail<TExpr> assertion) -> void {
    local_test_fails_++;
    failures_.push_back({
      mpi_context::instance().rank,
      current_test_,
      std::string(assertion.location.file_name()) + ":" + 
        std::to_string(assertion.location.line()),
      std::string{}  // Could format expr here
    });
    
    if (mpi_context::instance().rank == 0) {
      // Temporarily redirect to show rank info
      std::ostringstream oss;
      oss << "[rank " << mpi_context::instance().rank << "] ";
      ut::events::log<std::string> rank_log{oss.str()};
      TReporter::on(rank_log);
      TReporter::on(assertion);
    }
  }
  
  auto on(ut::events::test_end event) -> void {
    // Gather test results from all ranks
    int total_fails = 0;
    MPI_Allreduce(&local_test_fails_, &total_fails, 1, MPI_INT, MPI_SUM, 
                  MPI_COMM_WORLD);
    
    if (mpi_context::instance().rank == 0) {
      if (total_fails > 0) {
        // Gather failure details from all ranks
        for (int r = 1; r < mpi_context::instance().size; r++) {
          int count;
          MPI_Status status;
          MPI_Probe(r, 0, MPI_COMM_WORLD, &status);
          MPI_Get_count(&status, MPI_CHAR, &count);
          if (count > 0) {
            std::vector<char> buffer(count);
            MPI_Recv(buffer.data(), count, MPI_CHAR, r, 0, 
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
            std::string failure_info(buffer.begin(), buffer.end());
            ut::events::log<std::string> log{failure_info};
            TReporter::on(log);
          }
        }
      }
      TReporter::on(event);
    } else if (local_test_fails_ > 0) {
      // Send failure info to rank 0
      std::ostringstream oss;
      for (const auto& f : failures_) {
        if (f.test_name == current_test_) {
          oss << "[rank " << f.rank << "] Failed at " << f.location << "\n";
        }
      }
      std::string msg = oss.str();
      MPI_Send(msg.c_str(), msg.size(), MPI_CHAR, 0, 0, MPI_COMM_WORLD);
    }
  }
  
  auto on(ut::events::summary event) -> void {
    if (mpi_context::instance().rank == 0) {
      TReporter::on(event);
    }
  }
  
  // Pass through other events only on rank 0
  template <class TEvent>
  auto on(TEvent event) -> void {
    if (mpi_context::instance().rank == 0) {
      TReporter::on(event);
    }
  }
};

// MPI test case registration
namespace detail {
  struct mpi_test {
    std::string name;
    int required_procs;
    std::function<void(int rank, int size, MPI_Comm comm)> test_fn;
  };
  
  inline std::vector<mpi_test>& mpi_tests() {
    static std::vector<mpi_test> tests;
    return tests;
  }
  
  inline void register_mpi_test(std::string name, int procs, 
                               std::function<void(int, int, MPI_Comm)> fn) {
    mpi_tests().push_back({name, procs, fn});
  }
}

// MPI test case macro
#define MPI_TEST_CASE(name, num_procs) \
  static void BOOST_UT_UNIQUE_NAME(test_fn)(int test_rank, int test_nb_procs, \
                                            MPI_Comm test_comm); \
  static struct BOOST_UT_UNIQUE_NAME(test_reg) { \
    BOOST_UT_UNIQUE_NAME(test_reg)() { \
      ut::mpi::detail::register_mpi_test(name, num_procs, \
        BOOST_UT_UNIQUE_NAME(test_fn)); \
    } \
  } BOOST_UT_UNIQUE_NAME(test_reg_instance); \
  static void BOOST_UT_UNIQUE_NAME(test_fn)(int test_rank, int test_nb_procs, \
                                            MPI_Comm test_comm)

// Rank-specific assertions
#define MPI_CHECK(rank_to_test, ...) \
  if (test_rank == rank_to_test) { ut::expect(__VA_ARGS__); }

#define MPI_REQUIRE(rank_to_test, ...) \
  if (test_rank == rank_to_test) { ut::expect(ut::fatal(__VA_ARGS__)); }

// Run all MPI tests
inline int run_mpi_tests(int argc, char* argv[]) {
  // Initialize MPI
  ut::mpi::mpi_context::instance().init(&argc, &argv);
  
  // Override global config to use MPI reporter
  ut::cfg<ut::override> = ut::runner<mpi_console_reporter<>>{};
  
  // Run MPI tests
  for (const auto& test : detail::mpi_tests()) {
    if (mpi_context::instance().size < test.required_procs) {
      if (mpi_context::instance().rank == 0) {
        std::cout << "Skipping \"" << test.name 
                  << "\" - requires " << test.required_procs 
                  << " processes but only " << mpi_context::instance().size 
                  << " available\n";
      }
      continue;
    }
    
    "MPI test"_test = [&] {
      test.test_fn(mpi_context::instance().rank,
                   mpi_context::instance().size,
                   mpi_context::instance().comm);
    };
  }
  
  // Run regular tests too
  int result = ut::cfg<ut::override>.run() ? 0 : 1;
  
  // Finalize MPI
  ut::mpi::mpi_context::instance().finalize();
  
  return result;
}

}  // namespace ut::mpi