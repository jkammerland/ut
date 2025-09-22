// Example: Using multiprocess fixtures with Google Test
#include <gtest/gtest.h>
#include <boost/ut/multiprocess.hpp>

using namespace test::multiprocess;

class MultiprocessTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Get process info from environment
        my_id = process_info::get_id();
        participant_count = process_info::get_participant_count();
        multicast_addr = process_info::get_multicast_address();
        multicast_port = process_info::get_multicast_port();

        // Create fixture
        fixture = std::make_unique<multiprocess_fixture<true>>(
            my_id, participant_count, multicast_addr, multicast_port);
    }

    void TearDown() override {
        fixture.reset();
    }

    int my_id;
    int participant_count;
    std::string multicast_addr;
    int multicast_port;
    std::unique_ptr<multiprocess_fixture<true>> fixture;
};

TEST_F(MultiprocessTest, BasicSynchronization) {
    // All processes wait for each other
    ASSERT_NO_THROW(fixture->sync_point("test_start"));
    EXPECT_EQ(fixture->get_id(), my_id);
    EXPECT_EQ(fixture->get_participant_count(), participant_count);

    // Process 0 is always the coordinator
    if (my_id == 0) {
        EXPECT_TRUE(fixture->is_coordinator());
    } else {
        EXPECT_FALSE(fixture->is_coordinator());
    }
}

TEST_F(MultiprocessTest, MultipleCheckpoints) {
    // First synchronization point
    ASSERT_NO_THROW(fixture->sync_point("checkpoint_1"));

    // Simulate some work
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // Second synchronization point
    ASSERT_NO_THROW(fixture->sync_point("checkpoint_2"));

    // Third synchronization point
    ASSERT_NO_THROW(fixture->sync_point("checkpoint_3"));
}

TEST_F(MultiprocessTest, CoordinatorPattern) {
    if (fixture->is_coordinator()) {
        // Coordinator does something special
        std::cout << "Process " << my_id << " is coordinating" << std::endl;
    }

    // All processes synchronize
    ASSERT_NO_THROW(fixture->sync_point("coordinator_test"));
}

int main(int argc, char **argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}