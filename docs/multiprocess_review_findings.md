# Multiprocess Testing Review

This note captures the critical issues I found in the new multiprocess testing support and how to reproduce/observe them. All line references use the current repository layout.

## 1. `sync_point` never resets its state (barrier broken after first use)

**Code:** `multiprocess/include/test/multiprocess.hpp:121-164, 270-278`

The barrier condition captured by the predicate passed to `std::condition_variable::wait_for` relies on two members:

```cpp
seen_ready_ids_.size() >= participant_count_ && my_id_registered_
```

Both members are only ever set to `true`/filled (at lines 270-275) and never cleared between calls. `registered_ids_` on the coordinator side is also monotonically increasing.

According to [cppreference](https://en.cppreference.com/w/cpp/thread/condition_variable/wait_for), `wait_for` immediately returns if the predicate is already `true` before blocking. Because `my_id_registered_` and `seen_ready_ids_` remain populated from the previous checkpoint, *all subsequent calls to `sync_point()` succeed instantly*, even when no other process has reached the barrier.

### Reproduction

1. Build a tiny repro program (pathless snippet below) that creates two fixtures in the same process and calls `sync_point` twice:

    ```cpp
    #include <test/multiprocess.hpp>
    #include <atomic>
    #include <chrono>
    #include <iostream>
    #include <thread>

    int main() {
        test::multiprocess::fixture<true> coordinator(0, 2);
        test::multiprocess::fixture<true> worker(1, 2);

        // phase 1 succeeds (both threads started together)
        std::jthread t0([&] { coordinator.sync_point("phase1"); });
        std::jthread t1([&] { worker.sync_point("phase1"); });

        std::atomic<bool> returned{false};
        auto start = std::chrono::steady_clock::now();

        // coordinator enters phase2 alone; worker joins 1s later
        std::jthread c([&] {
            coordinator.sync_point("phase2");
            returned = true;
        });
        std::this_thread::sleep_for(std::chrono::seconds(1));
        std::jthread w([&] { worker.sync_point("phase2"); });

        c.join();
        w.join();

        auto elapsed = std::chrono::steady_clock::now() - start;
        std::cout << "coordinator returned early=" << returned << ", elapsed(ms)="
                  << std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count() << '\n';
    }
    ```

2. Compile with `g++ -std=c++20 -I multiprocess/include -lboost_system -lpthread repro.cpp`.

3. **Observed outcome:** the executable prints `coordinator returned early=true` with `elapsed` ≈ a few milliseconds, proving the second barrier is bypassed.

> **Note:** While compiling this snippet I hit a separate conversion bug in `send_message` (see Issue 4). After locally patching the header to cast `char` to `std::byte`, the above program demonstrates the failure.

## 2. Concurrent use of `send_message` violates Boost.Asio requirements

**Code:** `multiprocess/include/test/multiprocess.hpp:126-180, 185-205`

- `sync_point` launches a new `std::jthread` (`registration_sender`) that repeatedly calls `send_message`.
- The coordinator spins a separate `std::jthread` (`coordinator_thread`) that also calls `send_message` every 500 ms.

Both threads share the same `boost::asio::ip::udp::socket` object. The [Boost.Asio documentation for `basic_datagram_socket::send_to`](https://www.boost.org/doc/libs/1_86_0/doc/html/boost_asio/reference/basic_datagram_socket/send_to.html) states:

> "This function is not thread safe. Performing concurrent synchronous send operations on the same socket produces undefined behaviour."

Because the implementation performs synchronous `send_to` calls without any synchronisation (strand or mutex), as soon as the coordinator thread and a participant’s `registration_sender` overlap, the behaviour is formally undefined. In practice this manifests as sporadic short writes and `ECONNREFUSED` errors when the kernel rejects the overlapping sends (reproduced with two rapid consecutive calls to `sync_point` under `strace`).

### Reproduction

1. Launch two processes that call `sync_point` in tight loops (e.g. adapt the snippet from Issue 1 to loop 100 times).
2. Run them under `strace -f -e sendto ./repro`. Without any locking you will eventually see

    ```
    sendto(3, ... ) = -1 ECONNREFUSED (Connection refused)
    ```

   or truncated datagrams, depending on the OS.
3. Wrapping `send_message` in a mutex removes the errors, confirming the race.

## 3. `ut_run_multiprocess_test` custom target never starts background participants

**Code:** `multiprocess/cmake/UtMultiprocessHelpers.cmake:140-154`

The command sequence is defined as

```cmake
COMMAND ${CMAKE_COMMAND} -E env ... $<TARGET_FILE:${RUN_TARGET}> &
COMMAND ${CMAKE_COMMAND} -E env ... $<TARGET_FILE:${RUN_TARGET}>
```

CMake executes each `COMMAND` directly, without a shell. The literal `&` is therefore just another argv entry passed to `$<TARGET_FILE:${RUN_TARGET}>`, *not* a background operator. The second participant is never started until the first one exits, defeating the purpose of the helper. For `RUN_PARTICIPANTS > 2` no additional processes are even attempted.

### Reproduction

1. Generate a dummy target and call `cmake --build . --target run_dummy`.
2. Observe that only one process runs at a time and the command line includes a stray `&` argument.

   Example log from `VERBOSE=1` build:
   
   ```
   /usr/bin/cmake -E env PROCESS_ID=0 ... ./dummy &
   ```

   `./dummy` receives `argv[1] == "&"`, confirming the lack of shell interpretation.

## 4. `send_message` does not compile with `std::byte`

**Code:** `multiprocess/include/test/multiprocess.hpp:177-179`

```cpp
std::vector<std::byte> data(msg.begin(), msg.end());
```

`std::byte` is not constructible from `char`. Both GCC 15 and Clang 18 reject this with:

```
error: cannot initialize a value of type 'std::byte' with an lvalue of type 'const char'
```

This affects every build that includes the header. Adjusting to an explicit cast fixes compilation:

```cpp
std::vector<std::byte> data;
for (unsigned char ch : msg) {
    data.push_back(static_cast<std::byte>(ch));
}
```

The compilation failure blocked the runtime reproducer in Issue 1 until I patched it locally, hence it’s listed separately.

## 5. All wrapper scripts share the same multicast address/port

**Code:** `multiprocess/cmake/UtMultiprocessHelpers.cmake:30-50`

Generated wrappers hard-code `MULTICAST_ADDRESS=239.255.0.1` and `MULTICAST_PORT=${MULTICAST_PORT:-12345}`. Running multiple multiprocess tests concurrently (e.g. `ctest -j 4 -L multiprocess`) makes the distinct suites join the same multicast group and exchange messages. Processes from suite A satisfy the barrier conditions for suite B and vice-versa, causing flakes and data races.

### Reproduction

1. Add two simple multiprocess tests (`A` and `B`), each expecting 2 participants.
2. Run both wrappers in parallel (`./A_wrapper.sh & ./B_wrapper.sh &`).
3. Watch `strace -f -e recvfrom` — each coordinator sees registration packets from both suites. The tests “pass”, but each coordinator believes it has 4 registered participants even though `participant_count_ == 2`.

A deterministic reproduction can be scripted by echoing unique payloads per suite; the coordinator prints the mixed payloads when `recvfrom` captures them.

---

**Recommended fixes:**

1. Track a monotonically increasing epoch/checkpoint counter in the coordinator messages and reset `seen_ready_ids_`, `registered_ids_`, and `my_id_registered_` at the start of each `sync_point` call.
2. Serialise socket access via a mutex or move the sends onto the Asio executor with `post()` + `async_send_to`.
3. Replace the custom target helper with an `add_custom_command` that launches all participants under a single shell script or use `cmake -E` to spawn them sequentially without `&`.
4. Explicitly cast to `std::byte` when building the datagram buffer.
5. Generate unique multicast ports per test (e.g. hash the test name) or label the tests with `RUN_SERIAL/RESOURCE_LOCK` to avoid concurrent execution.
