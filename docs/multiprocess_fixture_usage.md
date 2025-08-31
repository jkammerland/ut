# Multiprocess Fixture Usage

## Overview

The `multiprocess_fixture` provides a simple way to coordinate multiple test processes using UDP multicast and network-based synchronization. It replaces complex file-based coordination with clean network messaging.

## Features

- **UDP Multicast Events**: Send/receive events up to 500 bytes between processes
- **Network Synchronization**: Coordinate test phases without shared filesystem
- **Template Control**: Choose between `arrive_and_wait` vs `arrive_and_drop` behavior
- **Event Handlers**: Custom lambda callbacks for network events on dedicated thread

## Basic Usage

```cpp
#include "network_coordination.cpp"

// Create fixture with 2 participants
auto event_handler = [role](const std::vector<std::byte>& data) {
    std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
    std::cout << "[" << role << "] Received: " << msg << std::endl;
};

multiprocess_fixture<true> fixture(2, role, "239.255.0.1", 12345, event_handler);

// Synchronize all processes
fixture.sync_point("test_phase_1");

// Send events to other processes  
std::string msg = "Status update from " + role;
std::vector<std::byte> event_data;
for (char c : msg) {
    event_data.push_back(static_cast<std::byte>(c));
}
fixture.send_event(event_data);
```

## Template Parameters

### `multiprocess_fixture<wait_after_arrive>`

- `wait_after_arrive = true`: Process waits at sync_point until all participants arrive
- `wait_after_arrive = false`: Process signals arrival and immediately continues

## Constructor Parameters

```cpp
multiprocess_fixture(
    int participant_count,           // Total expected processes  
    const std::string& role,         // This process's role identifier
    const std::string& multicast_address = "239.255.0.1", // Multicast group
    int multicast_port = 12345,      // UDP port
    event_handler_t handler = nullptr // Optional event callback
)
```

## Methods

### `sync_point(const std::string& barrier_name = "default")`

Network-based barrier synchronization:
- Sends arrival notification via multicast
- If `wait_after_arrive = true`, waits for all participants
- Throws `std::runtime_error` on 10-second timeout

### `send_event(const std::vector<std::byte>& data)`

Sends multicast event to all processes:
- Maximum 500 bytes per event
- Throws `std::runtime_error` if data too large
- Received by event handlers on all processes

## Integration with boost-ut Tests

```cpp
"multiprocess synchronization"_test = [&] {
    multiprocess_fixture<true> fixture(2, role, "239.255.0.1", 12345, event_handler);
    
    // Phase 1: Setup
    fixture.sync_point("setup");
    
    // Phase 2: Execute test logic
    fixture.sync_point("execute");
    
    // Phase 3: Cleanup
    fixture.sync_point("cleanup");
    
    expect(true) << "All phases synchronized successfully";
};
```

## Running Tests

### Local Testing
```bash
# Terminal 1 - Server process
PROCESS_ROLE=server SIMULATED_IP=127.0.0.1 ./build/example/multiprocess/boost_ut_network_coordination

# Terminal 2 - Client process  
PROCESS_ROLE=client SIMULATED_IP=127.0.0.2 ./build/example/multiprocess/boost_ut_network_coordination
```

### Container Testing with Podman
```bash
# Create network
podman network create --subnet=172.20.0.0/24 ut-test-net

# Run server container
podman run --rm --network ut-test-net --ip 172.20.0.2 \\
  -e PROCESS_ROLE=server -e SIMULATED_IP=172.20.0.2 ut-multiprocess

# Run client container
podman run --rm --network ut-test-net --ip 172.20.0.3 \\
  -e PROCESS_ROLE=client -e SIMULATED_IP=172.20.0.3 ut-multiprocess
```

## Event Handler Examples

### Stop Event Handling
```cpp
auto stop_handler = [&running](const std::vector<std::byte>& data) {
    std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
    if (msg == "STOP") {
        running = false;
    }
};
```

### JSON Message Handling
```cpp
auto json_handler = [](const std::vector<std::byte>& data) {
    std::string json_str(reinterpret_cast<const char*>(data.data()), data.size());
    // Parse JSON and handle structured messages
    // (requires JSON library integration)
};
```

## Limitations

- Maximum 500 bytes per multicast event
- 10-second timeout for barrier synchronization
- Requires network connectivity between processes
- UDP multicast may not work in all network environments

## Network Requirements

- Processes must be on same multicast-capable network
- Multicast address range: 224.0.0.0 to 239.255.255.255
- Default uses 239.255.0.1 (Organization-Local Scope)
- Firewall must allow UDP traffic on chosen port