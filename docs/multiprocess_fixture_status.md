# Multiprocess Fixture Status

## Purpose and Design Intent

The multiprocess fixture was introduced to provide a test-framework-agnostic barrier for coordinating multiple cooperating processes. The intended flow is:

- Each participant repeatedly transmits its process ID over a multicast channel assumed to be available on the LAN or test network.
- A designated manager (ID 0) relays the set of IDs it has seen, so that late joiners learn about other peers even if their initial announcements were missed.
- Tests can choose to wait for the full participant set (strict barrier) or unblock as soon as their own ID is acknowledged, enabling staged start-up sequences.

The design goal is to ensure that distributed test components can confirm peer visibility ("everyone is up and running") before executing scenario-specific logic, without coupling to boost.ut, gtest, or any specific harness.

## Working Pieces Today

- **Framework neutrality:** The header-only fixture compiles (after addressing the `std::byte` issue noted below) without depending on boost.ut internals, so it can be embedded in any C++ test binary.
- **Environment-driven configuration:** Process ID, participant count, and multicast settings are conveyed via environment variables, matching the generated wrapper scripts and CLI workflows.
- **Basic coordination loop:** The manager thread tracks announced IDs and redistributes the ready set, giving participants a shared view of who has successfully registered.
- **CMake integration scaffolding:** Helper functions generate wrapper scripts, add `ctest` entries, and expose a nominal `ut_run_multiprocess_test` target for manual runs.

## Gaps That Need Attention

- **Barrier state reset:** `sync_point()` never clears `my_id_registered_`, `seen_ready_ids_`, or the manager’s `registered_ids_`, so any checkpoint after the first returns immediately. Introduce per-checkpoint epochs and reset the tracking containers at the start of each call.
- **Socket concurrency:** Multiple threads call `send_message()` concurrently; Boost.Asio’s synchronous `send_to` is not thread-safe. Serialize access via a mutex or migrate sends onto the I/O context with `post()` + `async_send_to`.
- **Compilation defect:** `std::vector<std::byte> data(msg.begin(), msg.end())` fails to build; cast each character to `std::byte` explicitly (or store as `std::uint8_t`).
- **Wrapper isolation:** Every generated shell wrapper defaults to `239.255.0.1:12345`, so running two multiprocess tests in parallel produces cross-talk. Auto-allocate unique ports per test or mark tests as serial.
- **Custom run target:** `ut_run_multiprocess_test` appends `&` in a `COMMAND`, which CMake does not treat as a background operator, so subsequent participants never launch. Wrap the launch sequence in an actual script or call a helper executable that spawns all processes.
- **Timeout ergonomics:** `sync_point` hardcodes a 30s wait and silently swallows coordinator-side anomalies. Exposing per-checkpoint timeouts and logging unexpected messages would aid debugging.
- **Manager lifecycle:** The manager thread is created for every fixture instance with ID 0 and runs until destruction. Consider a scoped RAII coordinator or explicit `start/stop` hooks so tests can control when registration opens.

Addressing these items will align the implementation with the original goal: a reliable, reusable barrier primitive for cross-process test orchestration that works under multicast-friendly network topologies.
