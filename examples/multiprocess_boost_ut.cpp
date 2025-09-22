// Example: Using multiprocess fixtures with boost::ut
#include <boost/ut.hpp>
#include <boost/ut/multiprocess.hpp>

using namespace boost::ut;
using namespace test::multiprocess;

int main() {
    // Get process info from environment
    int my_id = process_info::get_id();
    int participant_count = process_info::get_participant_count();
    auto multicast_addr = process_info::get_multicast_address();
    auto multicast_port = process_info::get_multicast_port();

    "multiprocess basic synchronization"_test = [&] {
        multiprocess_fixture<true> fixture(my_id, participant_count,
                                          multicast_addr, multicast_port);

        // All processes synchronize
        expect(nothrow([&] { fixture.sync_point("test_start"); }));
        expect(fixture.get_id() == my_id);
        expect(fixture.get_participant_count() == participant_count);

        // Check coordinator
        if (my_id == 0) {
            expect(fixture.is_coordinator());
        } else {
            expect(!fixture.is_coordinator());
        }
    };

    "multiprocess multiple checkpoints"_test = [&] {
        multiprocess_fixture<true> fixture(my_id, participant_count,
                                          multicast_addr, multicast_port);

        // First synchronization point
        expect(nothrow([&] { fixture.sync_point("checkpoint_1"); }));

        // Simulate some work
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        // Second synchronization point
        expect(nothrow([&] { fixture.sync_point("checkpoint_2"); }));

        // Third synchronization point
        expect(nothrow([&] { fixture.sync_point("checkpoint_3"); }));
    };

    "coordinator pattern"_test = [&] {
        multiprocess_fixture<true> fixture(my_id, participant_count,
                                          multicast_addr, multicast_port);

        if (fixture.is_coordinator()) {
            std::cout << "Process " << my_id << " is coordinating\n";
            // Coordinator can perform special setup
        } else {
            std::cout << "Process " << my_id << " is a participant\n";
        }

        // All processes must synchronize
        expect(nothrow([&] { fixture.sync_point("coordinator_test"); }));
    };

    "self registration mode"_test = [&] {
        // Test with wait_for_all=false
        multiprocess_fixture<false> self_only_fixture(my_id, participant_count,
                                                      multicast_addr, multicast_port);

        // Should succeed quickly as we only wait for self
        expect(nothrow([&] { self_only_fixture.sync_point("self_only"); }));
    };

    "distributed computation pattern"_test = [&] {
        multiprocess_fixture<true> fixture(my_id, participant_count,
                                          multicast_addr, multicast_port);

        // Phase 1: All processes prepare
        fixture.sync_point("prepare");

        // Each process does its part of the computation
        int local_result = my_id * 10;  // Simple example
        std::cout << "Process " << my_id << " computed: " << local_result << "\n";

        // Phase 2: Synchronize before collection
        fixture.sync_point("compute_done");

        // In a real scenario, process 0 might collect results
        if (fixture.is_coordinator()) {
            std::cout << "Coordinator would collect results here\n";
        }

        // Phase 3: Final synchronization
        fixture.sync_point("complete");
    };

    return 0;
}