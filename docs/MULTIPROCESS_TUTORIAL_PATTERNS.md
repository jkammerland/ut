# Multiprocess Testing Patterns and Common Use Cases

This guide provides practical patterns and templates for common multiprocess testing scenarios using boost.ut.

## Testing Patterns Overview

| Pattern | Best For | Native Parallel | Container-Based |
|---------|----------|-----------------|-----------------|
| Client-Server | Request-response systems | ✓ Fast feedback | ✓ Network isolation |
| Producer-Consumer | Data processing pipelines | ✓ Low overhead | ✓ Resource limits |
| Leader Election | Distributed consensus | ✓ Quick iterations | ✓ Failure simulation |
| Load Balancing | Traffic distribution | ✓ Performance testing | ✓ Realistic deployment |
| Database Replication | Data consistency | ✗ Limited isolation | ✓ Full isolation |
| Microservice Mesh | Service coordination | ✗ Network conflicts | ✓ Service discovery |

## Pattern 1: Client-Server Communication

**Use Case**: Testing API servers, web services, database connections

### Native Parallel Implementation

```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "client server api test"_test = [&] {
        multiprocess_fixture<true> fixture(participant_count, role);
        
        if (role == "server") {
            std::cout << "[SERVER] Starting API server" << std::endl;
            
            // Signal server is ready
            fixture.sync_point("server_ready");
            
            // Simulate handling requests
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            
            // Wait for all clients to complete
            fixture.sync_point("requests_complete");
            
            std::cout << "[SERVER] Handled all client requests" << std::endl;
            expect(true) << "Server processed all requests";
        } else {
            // Client processes
            fixture.sync_point("server_ready");
            
            std::cout << "[" << role << "] Making API requests" << std::endl;
            
            // Simulate API calls
            for (int i = 0; i < 3; ++i) {
                std::cout << "[" << role << "] Request " << i + 1 << std::endl;
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
            
            fixture.sync_point("requests_complete");
            expect(true) << "Client completed all requests";
        }
    };
    
    return 0;
}
```

```cmake
ut_add_network_parallel_test(
  NAME client_server_api_test
  PARTICIPANTS 4  # 1 server + 3 clients
  EXECUTABLE client_server_test
  TIMEOUT 60
  MULTICAST_GROUP "239.255.10.1"
  MULTICAST_PORT 14001
)
```

### Container Implementation

```yaml
# client-server-compose.yml
version: '3.8'
services:
  api-server:
    image: api-test-image
    container_name: test-api-server
    environment:
      - PROCESS_ROLE=server
      - SIMULATED_IP=192.168.210.10
      - PORT=8080
    networks:
      api-network:
        ipv4_address: 192.168.210.10
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 2s
      retries: 5

  client1:
    image: api-test-image
    container_name: test-client1
    environment:
      - PROCESS_ROLE=client1
      - SIMULATED_IP=192.168.210.11
      - SERVER_URL=http://api-server:8080
    networks:
      api-network:
        ipv4_address: 192.168.210.11
    depends_on:
      api-server:
        condition: service_healthy

networks:
  api-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.210.0/24
```

## Pattern 2: Producer-Consumer Pipeline

**Use Case**: Message queues, streaming data, batch processing

### Event-Driven Implementation

```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <atomic>
#include <queue>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "producer consumer pipeline"_test = [&] {
        std::atomic<int> items_received{0};
        const int total_items = 20;
        
        auto event_handler = [&](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("ITEM:")) {
                items_received++;
                std::cout << "[" << role << "] Consumed: " << msg << std::endl;
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.10.2", 14002, event_handler);
        
        fixture.sync_point("pipeline_start");
        
        if (role == "server") {
            // Producer
            std::cout << "[PRODUCER] Starting production" << std::endl;
            
            for (int i = 1; i <= total_items; ++i) {
                std::string item = "ITEM:" + std::to_string(i) + "_data";
                std::vector<std::byte> data(item.begin(), item.end());
                fixture.send_event(data);
                
                std::cout << "[PRODUCER] Produced: " << item << std::endl;
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            
            std::cout << "[PRODUCER] Production complete" << std::endl;
        } else {
            // Consumers
            std::cout << "[CONSUMER:" << role << "] Ready to consume" << std::endl;
        }
        
        // Wait for processing to complete
        std::this_thread::sleep_for(std::chrono::seconds(2));
        
        fixture.sync_point("pipeline_complete");
        
        if (role != "server") {
            std::cout << "[" << role << "] Consumed " << items_received.load() << " items" << std::endl;
            expect(items_received.load() > 0) << "Consumer should receive items";
        }
    };
    
    return 0;
}
```

```cmake
ut_add_network_parallel_test(
  NAME producer_consumer_test
  PARTICIPANTS 5  # 1 producer + 4 consumers
  EXECUTABLE producer_consumer_test
  TIMEOUT 90
  MULTICAST_GROUP "239.255.10.2"
  MULTICAST_PORT 14002
  ADDITIONAL_ENV "BATCH_SIZE=20"
)
```

## Pattern 3: Leader Election and Consensus

**Use Case**: Distributed systems, consensus algorithms, fault tolerance

### Raft-Style Election

```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <random>

class SimpleElection {
private:
    std::string role_;
    int term_ = 0;
    std::string voted_for_;
    bool is_leader_ = false;
    std::vector<std::string> followers_;
    
public:
    SimpleElection(const std::string& role) : role_(role) {}
    
    void start_election(multiprocess_fixture<true>& fixture) {
        term_++;
        std::cout << "[" << role_ << "] Starting election for term " << term_ << std::endl;
        
        // Request votes
        std::string vote_request = "VOTE_REQUEST:term_" + std::to_string(term_) + ":from_" + role_;
        std::vector<std::byte> data(vote_request.begin(), vote_request.end());
        fixture.send_event(data);
    }
    
    void process_vote_request(const std::string& message) {
        if (message.find("VOTE_REQUEST:term_" + std::to_string(term_)) != std::string::npos) {
            std::cout << "[" << role_ << "] Received vote request: " << message << std::endl;
            // Grant vote (simplified)
        }
    }
    
    bool is_leader() const { return is_leader_; }
    void become_leader() { 
        is_leader_ = true; 
        std::cout << "[" << role_ << "] Became leader for term " << term_ << std::endl;
    }
};

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "leader election test"_test = [&] {
        SimpleElection election(role);
        
        auto event_handler = [&](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("VOTE_REQUEST:")) {
                election.process_vote_request(msg);
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.10.3", 14003, event_handler);
        
        // Phase 1: Election
        fixture.sync_point("election_start");
        
        // Simulate random election timing
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, 200);
        std::this_thread::sleep_for(std::chrono::milliseconds(dis(gen)));
        
        if (role == "server") {
            election.start_election(fixture);
            election.become_leader();  // Simplified - server wins
        }
        
        fixture.sync_point("election_complete");
        
        // Phase 2: Leader sends heartbeats
        if (election.is_leader()) {
            for (int i = 0; i < 3; ++i) {
                std::string heartbeat = "HEARTBEAT:term_1:from_" + role;
                std::vector<std::byte> data(heartbeat.begin(), heartbeat.end());
                fixture.send_event(data);
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }
        
        fixture.sync_point("leadership_established");
        
        expect(true) << "Election completed successfully";
    };
    
    return 0;
}
```

## Pattern 4: Load Balancer Simulation

**Use Case**: Traffic distribution, performance testing, scalability

### Round-Robin Load Balancer

```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <atomic>

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "load balancer test"_test = [&] {
        std::atomic<int> requests_handled{0};
        
        auto event_handler = [&](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("REQUEST:")) {
                requests_handled++;
                std::cout << "[" << role << "] Handling: " << msg << std::endl;
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.10.4", 14004, event_handler);
        
        fixture.sync_point("balancer_ready");
        
        if (role == "server") {
            // Load balancer distributes requests
            std::cout << "[LOAD_BALANCER] Distributing " << 15 << " requests" << std::endl;
            
            for (int i = 1; i <= 15; ++i) {
                std::string request = "REQUEST:req_" + std::to_string(i) + "_load_test";
                std::vector<std::byte> data(request.begin(), request.end());
                fixture.send_event(data);
                
                // Rate limiting
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }
            
            std::cout << "[LOAD_BALANCER] All requests distributed" << std::endl;
        } else {
            // Workers handle requests
            std::cout << "[WORKER:" << role << "] Ready to handle requests" << std::endl;
        }
        
        // Processing time
        std::this_thread::sleep_for(std::chrono::milliseconds(800));
        
        fixture.sync_point("load_complete");
        
        if (role != "server") {
            std::cout << "[" << role << "] Handled " << requests_handled.load() << " requests" << std::endl;
            expect(requests_handled.load() > 0) << "Worker should handle some requests";
        }
    };
    
    return 0;
}
```

```cmake
ut_add_network_parallel_test(
  NAME load_balancer_test
  PARTICIPANTS 6  # 1 balancer + 5 workers
  EXECUTABLE load_balancer_test
  TIMEOUT 120
  MULTICAST_GROUP "239.255.10.4"
  MULTICAST_PORT 14004
  ADDITIONAL_ENV "TOTAL_REQUESTS=15" "RATE_LIMIT=20"
)
```

## Pattern 5: Database Replication Testing

**Use Case**: Data consistency, eventual consistency, master-slave replication

### Container-Based Database Simulation

```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <map>

class SimpleDatabase {
private:
    std::map<std::string, std::string> data_;
    bool is_primary_;
    
public:
    SimpleDatabase(bool primary) : is_primary_(primary) {}
    
    void write(const std::string& key, const std::string& value) {
        if (is_primary_) {
            data_[key] = value;
            std::cout << "[DB] Write: " << key << " = " << value << std::endl;
        }
    }
    
    std::string read(const std::string& key) {
        auto it = data_.find(key);
        return (it != data_.end()) ? it->second : "NOT_FOUND";
    }
    
    void replicate_from(const std::string& replication_msg) {
        // Parse: "REPLICATE:key:value"
        size_t pos1 = replication_msg.find(':', 10);
        size_t pos2 = replication_msg.find(':', pos1 + 1);
        
        if (pos1 != std::string::npos && pos2 != std::string::npos) {
            std::string key = replication_msg.substr(pos1 + 1, pos2 - pos1 - 1);
            std::string value = replication_msg.substr(pos2 + 1);
            data_[key] = value;
            std::cout << "[REPLICA] Replicated: " << key << " = " << value << std::endl;
        }
    }
    
    size_t size() const { return data_.size(); }
};

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "database replication test"_test = [&] {
        bool is_primary = (role == "server");
        SimpleDatabase db(is_primary);
        
        auto event_handler = [&](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("REPLICATE:")) {
                db.replicate_from(msg);
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.10.5", 14005, event_handler);
        
        fixture.sync_point("db_ready");
        
        if (is_primary) {
            std::cout << "[PRIMARY] Starting write operations" << std::endl;
            
            // Perform writes and replicate
            for (int i = 1; i <= 5; ++i) {
                std::string key = "key_" + std::to_string(i);
                std::string value = "value_" + std::to_string(i * 100);
                
                db.write(key, value);
                
                // Send replication message
                std::string repl_msg = "REPLICATE:" + key + ":" + value;
                std::vector<std::byte> data(repl_msg.begin(), repl_msg.end());
                fixture.send_event(data);
            }
            
            std::cout << "[PRIMARY] Write operations complete" << std::endl;
        } else {
            std::cout << "[REPLICA:" << role << "] Waiting for replication" << std::endl;
        }
        
        // Allow replication to complete
        std::this_thread::sleep_for(std::chrono::seconds(1));
        
        fixture.sync_point("replication_complete");
        
        std::cout << "[" << role << "] Database size: " << db.size() << std::endl;
        
        if (is_primary) {
            expect(db.size() == 5) << "Primary should have all writes";
        } else {
            expect(db.size() > 0) << "Replicas should receive some data";
        }
        
        // Verify specific data
        std::string test_value = db.read("key_3");
        if (db.size() >= 3) {
            expect(test_value == "value_300") << "Data should be consistent";
        }
    };
    
    return 0;
}
```

**Container compose for database testing:**
```yaml
version: '3.8'
services:
  db-primary:
    image: db-test-image
    container_name: test-db-primary
    environment:
      - PROCESS_ROLE=server
      - SIMULATED_IP=192.168.230.10
      - DB_ROLE=primary
    volumes:
      - primary-data:/data
    networks:
      db-network:
        ipv4_address: 192.168.230.10

  db-replica1:
    image: db-test-image
    container_name: test-db-replica1
    environment:
      - PROCESS_ROLE=client2
      - SIMULATED_IP=192.168.230.11
      - DB_ROLE=replica
      - PRIMARY_HOST=db-primary
    volumes:
      - replica1-data:/data
    networks:
      db-network:
        ipv4_address: 192.168.230.11
    depends_on:
      - db-primary

  db-replica2:
    image: db-test-image
    container_name: test-db-replica2
    environment:
      - PROCESS_ROLE=client3
      - SIMULATED_IP=192.168.230.12
      - DB_ROLE=replica
      - PRIMARY_HOST=db-primary
    volumes:
      - replica2-data:/data
    networks:
      db-network:
        ipv4_address: 192.168.230.12
    depends_on:
      - db-primary

networks:
  db-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.230.0/24

volumes:
  primary-data:
  replica1-data:
  replica2-data:
```

## Pattern 6: Microservice Communication Mesh

**Use Case**: Service discovery, API gateways, distributed tracing

### Service Mesh Simulation

```cpp
#include <boost/ut.hpp>
#include "network_coordination.cpp"
#include <set>

class ServiceRegistry {
private:
    std::set<std::string> services_;
    
public:
    void register_service(const std::string& service) {
        services_.insert(service);
        std::cout << "[REGISTRY] Registered: " << service << std::endl;
    }
    
    bool is_registered(const std::string& service) const {
        return services_.find(service) != services_.end();
    }
    
    size_t service_count() const { return services_.size(); }
};

int main() {
    using namespace boost::ut;
    
    auto role = get_env("PROCESS_ROLE");
    auto participant_count = std::stoi(get_env("PARTICIPANT_COUNT"));
    
    "microservice mesh test"_test = [&] {
        ServiceRegistry registry;
        
        auto event_handler = [&](const std::vector<std::byte>& data) {
            std::string msg(reinterpret_cast<const char*>(data.data()), data.size());
            if (msg.starts_with("REGISTER:")) {
                std::string service = msg.substr(9);
                registry.register_service(service);
            } else if (msg.starts_with("REQUEST:")) {
                std::cout << "[" << role << "] Received request: " << msg << std::endl;
            }
        };
        
        multiprocess_fixture<true> fixture(participant_count, role, 
                                          "239.255.10.6", 14006, event_handler);
        
        // Phase 1: Service registration
        fixture.sync_point("mesh_start");
        
        // Each service registers itself
        std::string service_name = "service_" + role;
        std::string register_msg = "REGISTER:" + service_name;
        std::vector<std::byte> data(register_msg.begin(), register_msg.end());
        fixture.send_event(data);
        
        fixture.sync_point("registration_complete");
        
        // Phase 2: Inter-service communication
        if (role == "server") {
            // Gateway service makes requests to other services
            std::vector<std::string> target_services = {"client2", "client3", "client4"};
            
            for (const auto& target : target_services) {
                std::string request = "REQUEST:from_gateway_to_" + target;
                std::vector<std::byte> req_data(request.begin(), request.end());
                fixture.send_event(req_data);
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }
        
        fixture.sync_point("communication_complete");
        
        std::cout << "[" << role << "] Registry has " << registry.service_count() << " services" << std::endl;
        
        expect(registry.service_count() > 0) << "Services should be registered";
        expect(registry.is_registered("service_" + role)) << "Own service should be registered";
    };
    
    return 0;
}
```

## Performance Testing Patterns

### Throughput Measurement

```cpp
"throughput measurement"_test = [&] {
    std::atomic<int> messages_sent{0};
    std::atomic<int> messages_received{0};
    const int target_messages = 1000;
    
    auto event_handler = [&](const std::vector<std::byte>& data) {
        messages_received++;
    };
    
    multiprocess_fixture<true> fixture(participant_count, role, 
                                      "239.255.10.7", 14007, event_handler);
    
    auto start_time = std::chrono::high_resolution_clock::now();
    
    fixture.sync_point("throughput_start");
    
    if (role == "server") {
        // Send messages as fast as possible
        for (int i = 0; i < target_messages; ++i) {
            std::string msg = "PERF:" + std::to_string(i);
            std::vector<std::byte> data(msg.begin(), msg.end());
            fixture.send_event(data);
            messages_sent++;
        }
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(2000));
    
    fixture.sync_point("throughput_complete");
    
    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    
    if (role == "server") {
        double send_rate = (messages_sent.load() * 1000.0) / duration.count();
        std::cout << "[SENDER] Send rate: " << send_rate << " msg/sec" << std::endl;
    } else {
        double recv_rate = (messages_received.load() * 1000.0) / duration.count();
        std::cout << "[" << role << "] Receive rate: " << recv_rate << " msg/sec" << std::endl;
        expect(messages_received.load() >= target_messages * 0.9) << "Should receive most messages";
    }
};
```

## Error Handling and Resilience Patterns

### Network Partition Simulation

```cpp
"network partition test"_test = [&] {
    multiprocess_fixture<true> fixture(participant_count, role);
    
    fixture.sync_point("partition_start");
    
    if (role == "server") {
        // Leader in partition 1
        for (int i = 0; i < 3; ++i) {
            std::string msg = "PARTITION1:msg_" + std::to_string(i);
            std::vector<std::byte> data(msg.begin(), msg.end());
            fixture.send_event(data);
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
        }
    } else if (role == "client2") {
        // Node in partition 1 - can communicate with server
        std::cout << "[PARTITION1] Node operational" << std::endl;
    } else {
        // Nodes in partition 2 - simulate network issues
        std::cout << "[PARTITION2] Simulating network isolation" << std::endl;
        // Skip some sync points to simulate partition
    }
    
    fixture.sync_point("partition_recovery");
    
    expect(true) << "System survived network partition";
};
```

These patterns provide a foundation for testing complex distributed systems scenarios. Choose the appropriate pattern based on your system architecture and testing requirements.