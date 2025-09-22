# Example: Using Podman with different executables per process

include(PodmanMultiprocessTest2)

# Build different executables
add_executable(server server.cpp)
add_executable(client client.cpp)
add_executable(monitor monitor.cpp)
add_executable(worker worker.cpp)
add_executable(coordinator coordinator.cpp)

# Link them all with required libraries
foreach(target server client monitor worker coordinator)
  target_link_libraries(${target} PRIVATE Boost::ut Boost::system)
endforeach()

# Example 1: Run 5 DIFFERENT executables, each with unique IP
ut_add_podman_multiprocess_test(
  NAME heterogeneous_test
  TARGETS
    server       # Process 0, IP: 10.150.0.2
    client       # Process 1, IP: 10.150.0.3
    monitor      # Process 2, IP: 10.150.0.4
    worker       # Process 3, IP: 10.150.0.5
    coordinator  # Process 4, IP: 10.150.0.6
  TIMEOUT 60
)

# Example 2: One server, multiple different clients
ut_add_podman_multiprocess_test(
  NAME mixed_clients
  TARGETS
    server    # Process 0
    client    # Process 1
    client    # Process 2 (same executable, different instance)
    monitor   # Process 3
    worker    # Process 4
)

# Example 3: Using convenience function for common pattern
ut_add_podman_mixed_test(
  NAME server_client_test
  SERVER_TARGET server
  CLIENT_TARGET client
  NUM_CLIENTS 3         # Creates 1 server + 3 clients
  EXTRA_TARGETS monitor  # Plus a monitor
  TIMEOUT 45
)

# Example 4: Mix of same and different executables
ut_add_podman_multiprocess_test(
  NAME complex_topology
  TARGETS
    coordinator  # Process 0: Coordinator
    worker       # Process 1: Worker 1
    worker       # Process 2: Worker 2
    worker       # Process 3: Worker 3
    monitor      # Process 4: Monitor
    client       # Process 5: External client
)

# Example 5: Still works with single executable (backward compatible)
ut_add_podman_multiprocess_test(
  NAME homogeneous_test
  TARGET worker        # All participants run same executable
  PARTICIPANTS 5       # 5 instances of worker
)

# The beauty of this approach:
# - Each process gets unique IP automatically
# - PROCESS_ID tells each executable its role (0, 1, 2, ...)
# - PARTICIPANT_COUNT tells total number
# - Executables can discover each other via multicast or known ports
# - No hardcoded server/client assumptions