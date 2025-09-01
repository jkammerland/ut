# Multiprocess Testing Troubleshooting Guide

This guide covers common issues and solutions for boost.ut multiprocess testing.

## Quick Diagnostic Commands

```bash
# Check test status
ctest -L multiprocess --output-on-failure

# View generated scripts
ls build/example/multiprocess/*_runner.sh

# Check container status
podman ps -a
podman images | grep ut

# Check network status
podman network ls
ss -u -a | grep :12345  # Check UDP multicast ports

# View logs
podman logs container-name
ctest -R test_name -V
```

## Native Parallel Process Issues

### Issue: Tests Report Failure Despite Successful Process Execution

**Symptoms:**
- Process output shows "Suite 'global': all tests passed"
- CTest reports test failure (exit code 1)
- All processes appear to coordinate correctly

**Diagnosis:**
```bash
# Run test script manually
cd build/example/multiprocess
chmod +x parallel_network_test_runner.sh
./parallel_network_test_runner.sh
echo "Exit code: $?"
```

**Root Causes:**
1. **Script exit code handling bug** - Script doesn't properly wait for all processes
2. **Early cleanup** - EXIT trap called before processes complete
3. **Bash arithmetic errors** - `((count++))` fails with `set -e`

**Solutions:**
```bash
# Check for arithmetic expression issues in wait logic
grep -n "((count" build/example/multiprocess/*_runner.sh

# Fix: Replace ((count++)) with count=$((count + 1))
sed -i 's/((count++))/count=$((count + 1))/g' script_name.sh

# Check wait logic structure
grep -A 10 -B 10 "wait_with_timeout" script_name.sh
```

**Prevention:**
- Use modern CMake modules (ParallelProcessTest.cmake) with fixed wait logic
- Avoid deprecated NetworkFixtureTest.cmake module

### Issue: Process Coordination Timeout

**Symptoms:**
- "Barrier timeout waiting for N participants"
- Processes start but don't synchronize
- Some processes complete while others wait

**Diagnosis:**
```bash
# Check if all processes start
ps aux | grep your_test_binary

# Verify multicast connectivity
ss -u -a | grep :12345
netstat -g | grep 239.255  # Check multicast group membership

# Check environment variables
echo $PROCESS_ROLE
echo $SIMULATED_IP
echo $PARTICIPANT_COUNT
```

**Root Causes:**
1. **Environment variables not set** - Processes don't get role/IP configuration
2. **Network connectivity issues** - Multicast blocked by firewall
3. **Process count mismatch** - PARTICIPANT_COUNT doesn't match actual processes
4. **Multicast address conflicts** - Multiple tests using same group

**Solutions:**
```bash
# Fix environment variable injection in CMake
grep -n "PROCESS_ROLE" cmake/ParallelProcessTest.cmake

# Test multicast connectivity manually
# Terminal 1:
socat UDP4-RECVFROM:12345,ip-add-membership=239.255.0.1:eth0,fork -

# Terminal 2:
echo "test message" | socat - UDP4-SENDTO:239.255.0.1:12345

# Use different multicast groups for concurrent tests
ut_add_network_parallel_test(
  NAME test1
  MULTICAST_GROUP "239.255.1.1"
  MULTICAST_PORT 13001
)
ut_add_network_parallel_test(
  NAME test2
  MULTICAST_GROUP "239.255.1.2"  # Different group
  MULTICAST_PORT 13002            # Different port
)
```

### Issue: "Permission denied" on Test Scripts

**Symptoms:**
- "./test_runner.sh: Permission denied"
- Scripts exist but aren't executable

**Solution:**
```bash
# Make scripts executable
find build -name "*_runner.sh" -exec chmod +x {} \;

# Check CMake script generation
grep -n "execute_process.*chmod" cmake/ParallelProcessTest.cmake
```

## Container-Based Testing Issues

### Issue: "Error: short-name resolution enforced but cannot prompt without a TTY"

**Symptoms:**
- Container tests fail immediately during image pull
- podman-compose reports TTY error

**Root Causes:**
1. **Image doesn't exist** - Specified image name not found
2. **Image registry issues** - Can't resolve short names like "fedora:41"

**Solutions:**
```bash
# Check if image exists
podman images | grep image-name

# Use fully qualified image names
ut_add_simple_compose_test(
  NAME test_name
  IMAGE "registry.fedoraproject.org/fedora:41"  # Full name
)

# Build image first
podman build -t ut-multiprocess -f Containerfile .

# List available images for testing
podman images --format "table {{.Repository}}:{{.Tag}}"
```

### Issue: Container Network Creation Failures

**Symptoms:**
- "network with name X already exists"
- "subnet X overlaps with other networks"
- Network creation fails with exit status 125

**Diagnosis:**
```bash
# Check existing networks
podman network ls

# Inspect network details
podman network inspect network-name

# Check subnet conflicts
podman network ls --format "{{.Name}} {{.Subnets}}"
```

**Solutions:**
```bash
# Clean up old networks
podman network prune -f

# Remove specific network
podman network rm network-name

# Use different subnets for different tests
ut_add_simple_compose_test(
  NAME test1
  NETWORK_SUBNET "192.168.210.0/24"
)
ut_add_simple_compose_test(
  NAME test2
  NETWORK_SUBNET "192.168.220.0/24"  # Different subnet
)

# Auto-cleanup networks after tests
ut_add_simple_compose_test(
  NAME test_name
  CLEANUP_VOLUMES  # Enables network cleanup
)
```

### Issue: Container Command Not Found

**Symptoms:**
- "container_name: command not found"
- Containers start but exit immediately
- "no such file or directory" errors

**Diagnosis:**
```bash
# Check container contents
podman run --rm -it image-name ls -la /app
podman run --rm -it image-name which executable-name

# Check container logs
podman logs container-name
```

**Root Causes:**
1. **Executable not in container** - Binary not copied during build
2. **Wrong executable path** - Path doesn't match compose file
3. **Missing dependencies** - Runtime libraries not installed

**Solutions:**
```dockerfile
# Fix Containerfile to include executable
COPY build/test_binary /app/
RUN chmod +x /app/test_binary

# Install runtime dependencies
RUN dnf install -y boost-system && dnf clean all
```

```cmake
# Use correct executable path in compose file
ut_add_simple_compose_test(
  EXECUTABLE "./test_binary"  # Must match path in container
)
```

### Issue: Container Log Analysis Failures

**Symptoms:**
- "no container with name X found" in log extraction
- Tests pass but logs show failures
- Log files empty or not created

**Solutions:**
```bash
# Check container names and status
podman ps -a --format "table {{.Names}} {{.Status}}"

# Manually extract logs
podman-compose -f test_compose.yml logs service-name

# Enable proper logging in compose test
ut_add_simple_compose_test(
  NAME test_name
  ENABLE_LOGS      # Required for log analysis
)

# Check log directory creation
ls -la build/example/multiprocess/logs/
```

## MPI Testing Issues

### Issue: MPI Not Found

**Symptoms:**
- "Could NOT find MPI"
- MPI tests skipped

**Solutions:**
```bash
# Install MPI implementation
# Fedora/RHEL:
sudo dnf install openmpi-devel
# Ubuntu:
sudo apt install libopenmpi-dev

# Load MPI module (on HPC systems)
module load openmpi

# Set MPI paths explicitly in CMake
cmake -DMPI_C_COMPILER=mpicc -DMPI_CXX_COMPILER=mpicxx
```

### Issue: MPI Process Count Mismatch

**Symptoms:**
- "MPI_Init: could not start processes"
- Tests fail with wrong number of processes

**Solutions:**
```cmake
# Check available processors
ut_add_mpi_test(
  NAME mpi_test
  PROCESSES 2  # Don't exceed available cores
)

# Use processor count detection
include(ProcessorCount)
ProcessorCount(N)
if(N GREATER 4)
  set(MPI_PROCESSES 4)
else()
  set(MPI_PROCESSES 2)
endif()
```

## Network and Firewall Issues

### Issue: UDP Multicast Blocked

**Symptoms:**
- Processes start but never coordinate
- No multicast traffic visible in network monitoring

**Diagnosis:**
```bash
# Check multicast routes
ip route show | grep 224.0.0.0

# Test multicast reception
tcpdump -i any host 239.255.0.1

# Check firewall rules
sudo iptables -L | grep -E "(DROP|REJECT)"
sudo firewall-cmd --list-all  # On systems using firewalld
```

**Solutions:**
```bash
# Allow multicast traffic (temporary)
sudo iptables -I INPUT -d 224.0.0.0/4 -j ACCEPT
sudo iptables -I OUTPUT -d 224.0.0.0/4 -j ACCEPT

# Permanent firewall configuration
sudo firewall-cmd --permanent --add-port=12345/udp
sudo firewall-cmd --reload

# Use different multicast scope
# Organization-local scope (239.192.0.0/14) instead of site-local
MULTICAST_GROUP "239.192.1.1"
```

### Issue: Port Already in Use

**Symptoms:**
- "Address already in use"
- Tests fail when run concurrently

**Solutions:**
```bash
# Check port usage
ss -tulpn | grep :12345
lsof -i :12345

# Use port auto-assignment
MULTICAST_PORT 0  # Let system choose available port

# Use systematic port allocation
ut_add_network_parallel_test(
  NAME test1
  MULTICAST_PORT 13001
)
ut_add_network_parallel_test(
  NAME test2  
  MULTICAST_PORT 13002  # Different port
)
```

## Performance and Scalability Issues

### Issue: Tests Timeout with Many Participants

**Symptoms:**
- Tests fail with timeout when participant count > 4
- High CPU usage during tests
- Memory exhaustion

**Solutions:**
```cmake
# Increase timeout for large tests
ut_add_network_parallel_test(
  NAME large_test
  PARTICIPANTS 8
  TIMEOUT 120  # Increased from default 30
)

# Limit concurrent execution
add_custom_target(large_multiprocess_tests
  COMMAND ${CMAKE_CTEST_COMMAND} -R "large_.*" -j1  # Sequential execution
)

# Use container tests for better isolation
ut_add_simple_compose_test(
  NAME scalability_test
  PARTICIPANTS 8
  TIMEOUT 180
)
```

### Issue: Resource Exhaustion in CI

**Symptoms:**
- Tests pass locally but fail in CI
- "Cannot allocate memory" errors
- Container startup failures

**Solutions:**
```yaml
# CI configuration example (.github/workflows/test.yml)
jobs:
  multiprocess-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Run multiprocess tests
        run: |
          # Limit concurrent tests
          ctest -L multiprocess -j2 --timeout 120
          
          # Run container tests separately with lower parallelism
          ctest -L compose -j1 --timeout 300
```

```cmake
# Reduce resource usage in CI
if(DEFINED ENV{CI})
  set(MAX_PARTICIPANTS 4)  # Limit participants in CI
else()
  set(MAX_PARTICIPANTS 8)  # Allow more locally
endif()
```

## Debugging Strategies

### Debug Process Startup Issues

```bash
# Add debug output to test scripts
export UT_DEBUG=1

# Run with bash debug mode
bash -x ./test_runner.sh

# Check process environment
cat /proc/PID/environ | tr '\0' '\n'

# Monitor process creation
strace -e clone,execve -f ./test_runner.sh
```

### Debug Network Coordination

```cpp
// Add debug output to test code
std::cout << "Process " << role << " starting at " << ip << std::endl;
std::cout << "Participant count: " << participant_count << std::endl;
std::cout << "Multicast: " << multicast_group << ":" << multicast_port << std::endl;

// Enable verbose network fixture logging
#define UT_MULTIPROCESS_DEBUG 1
```

### Debug Container Issues

```bash
# Run container interactively
podman run --rm -it --entrypoint /bin/bash image-name

# Check container filesystem
podman run --rm image-name find /app -type f -executable

# Debug container networking
podman run --rm --network test-network image-name ip addr show

# Export container for examination
podman export container-name > container.tar
tar -tf container.tar | grep app/
```

## Prevention Best Practices

### Avoid Common Issues

1. **Use unique test identifiers**
   ```cmake
   # Generate unique multicast groups
   ut_add_network_parallel_test(
     NAME ${test_name}
     MULTICAST_GROUP "239.255.${test_id}.1"
     MULTICAST_PORT $((13000 + ${test_id}))
   )
   ```

2. **Implement proper cleanup**
   ```cmake
   ut_add_simple_compose_test(
     NAME test_name
     CLEANUP_VOLUMES  # Always clean up
   )
   ```

3. **Set appropriate timeouts**
   ```cmake
   # Scale timeout with participant count
   math(EXPR TIMEOUT "30 + ${PARTICIPANTS} * 10")
   ut_add_network_parallel_test(
     TIMEOUT ${TIMEOUT}
   )
   ```

4. **Test with minimal configurations first**
   ```cmake
   # Start with 2 participants, scale up gradually
   ut_add_network_parallel_test(
     PARTICIPANTS 2  # Minimal viable test
   )
   ```

### Monitoring and Logging

```cmake
# Enable comprehensive logging
ut_add_simple_compose_test(
  NAME monitored_test
  ENABLE_LOGS
  ADDITIONAL_ENV 
    "LOG_LEVEL=debug"
    "NETWORK_DEBUG=1"
    "TRACE_EVENTS=1"
)
```

This troubleshooting guide covers the most common issues encountered in multiprocess testing. Most problems stem from configuration mismatches, network connectivity, or resource constraints rather than fundamental framework issues.