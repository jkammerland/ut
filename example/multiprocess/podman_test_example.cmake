# Example: Using Podman Multiprocess Testing with boost.ut

include(PodmanMultiprocessTest)

# Build test executables
add_executable(network_test network_coordination.cpp)
target_link_libraries(network_test PRIVATE Boost::ut Boost::system)

add_executable(server server.cpp)
add_executable(client client.cpp)
add_executable(monitor monitor.cpp)

# Example 1: Same executable, multiple instances (each gets unique IP)
ut_add_podman_multiprocess_test(
  NAME basic_network_test
  TARGET network_test
  PARTICIPANTS 3
  TIMEOUT 30
)

# Example 2: Different executables (server + clients pattern)
ut_add_podman_multiprocess_test(
  NAME server_client_test
  TARGETS
    server    # Process 0: IP 10.x.0.2
    client    # Process 1: IP 10.x.0.3
    client    # Process 2: IP 10.x.0.4
    monitor   # Process 3: IP 10.x.0.5
  TIMEOUT 45
)

# Example 3: Batch testing with different participant counts
ut_add_podman_multiprocess_batch_test(
  NAME scaling_test
  TARGET network_test
  PARTICIPANT_COUNTS 2 4 6 8
  TIMEOUT 60
)

# The API is symmetric with regular multiprocess tests:
# - Just change function name from ut_add_multiprocess_test to ut_add_podman_multiprocess_test
# - Each process automatically gets a unique IP address
# - No code changes needed in your test executables