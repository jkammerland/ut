// Example: Using multiprocess fixtures with doctest
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include <boost/ut/multiprocess.hpp>
#include <memory>

using namespace test::multiprocess;

// Global fixture for all tests in this file
struct MultiprocessFixture {
    int my_id;
    int participant_count;
    std::string multicast_addr;
    int multicast_port;
    std::unique_ptr<multiprocess_fixture<true>> fixture;

    MultiprocessFixture() {
        // Get process info from environment
        my_id = process_info::get_id();
        participant_count = process_info::get_participant_count();
        multicast_addr = process_info::get_multicast_address();
        multicast_port = process_info::get_multicast_port();

        // Create fixture
        fixture = std::make_unique<multiprocess_fixture<true>>(
            my_id, participant_count, multicast_addr, multicast_port);
    }

    ~MultiprocessFixture() {
        fixture.reset();
    }
};

TEST_CASE("Multiprocess basic synchronization") {
    MultiprocessFixture mp;

    SUBCASE("All processes synchronize") {
        CHECK_NOTHROW(mp.fixture->sync_point("test_start"));
        CHECK(mp.fixture->get_id() == mp.my_id);
        CHECK(mp.fixture->get_participant_count() == mp.participant_count);
    }

    SUBCASE("Coordinator identification") {
        if (mp.my_id == 0) {
            CHECK(mp.fixture->is_coordinator());
        } else {
            CHECK_FALSE(mp.fixture->is_coordinator());
        }
    }
}

TEST_CASE("Multiprocess checkpoints") {
    MultiprocessFixture mp;

    // First checkpoint
    CHECK_NOTHROW(mp.fixture->sync_point("checkpoint_1"));

    // Simulate some work
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // Second checkpoint
    CHECK_NOTHROW(mp.fixture->sync_point("checkpoint_2"));

    // Third checkpoint
    CHECK_NOTHROW(mp.fixture->sync_point("checkpoint_3"));
}

TEST_CASE("Coordinator pattern") {
    MultiprocessFixture mp;

    if (mp.fixture->is_coordinator()) {
        // Coordinator-specific logic
        MESSAGE("Process ", mp.my_id, " is the coordinator");
        // Coordinator could set up resources, etc.
    } else {
        MESSAGE("Process ", mp.my_id, " is a participant");
    }

    // All processes must reach this point
    CHECK_NOTHROW(mp.fixture->sync_point("coordinator_test"));
}

TEST_CASE("Self-registration mode") {
    // Test with wait_for_all=false - only wait for self registration
    int my_id = process_info::get_id();
    int participant_count = process_info::get_participant_count();
    auto multicast_addr = process_info::get_multicast_address();
    auto multicast_port = process_info::get_multicast_port();

    multiprocess_fixture<false> self_only_fixture(
        my_id, participant_count, multicast_addr, multicast_port);

    // This should succeed quickly as we only wait for ourselves
    CHECK_NOTHROW(self_only_fixture.sync_point("self_only"));
}