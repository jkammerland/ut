# Example: Using symmetric Podman API for multiprocess testing
# This shows how the API mirrors the regular multiprocess test API

include(PodmanMultiprocessTest)

# Build your test executable (same as regular multiprocess)
add_executable(my_network_test network_coordination.cpp)
target_link_libraries(my_network_test PRIVATE Boost::ut Boost::system)

# Regular multiprocess test (all on same host)
ut_add_multiprocess_test(
  NAME my_test_local
  TARGET my_network_test
  PARTICIPANTS 3
  TIMEOUT 30
)

# Podman multiprocess test (each process gets unique IP)
# EXACT SAME API - just different function name!
ut_add_podman_multiprocess_test(
  NAME my_test_podman
  TARGET my_network_test
  PARTICIPANTS 3
  TIMEOUT 30
)

# That's it! Each process automatically gets:
# - Its own container with unique IP (e.g., 10.150.0.2, 10.150.0.3, 10.150.0.4)
# - PROCESS_ID environment variable (0, 1, 2)
# - PARTICIPANT_COUNT environment variable (3)
# - Multicast group configuration

# You can also test with different participant counts
ut_add_podman_multiprocess_batch_test(
  NAME scaling_test
  TARGET my_network_test
  PARTICIPANT_COUNTS 2 4 8
  TIMEOUT 60
)

# Or automatically add both local and podman versions
ut_use_podman_if_needed(
  NAME my_test
  TARGET my_network_test
  PARTICIPANTS 4
)

# The beauty: Your test code doesn't change!
# It just reads PROCESS_ID and PARTICIPANT_COUNT from environment
# and works whether running locally or in containers with unique IPs