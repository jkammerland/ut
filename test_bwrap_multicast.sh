#!/bin/bash
# Test multiprocess coordination with bwrap network isolation

echo "Testing multiprocess coordination with bwrap network namespace isolation"
echo "========================================================================="

# Build the test executable first
cd /home/ai-dev1/repos/ut/build
make boost_ut_network_coordination

# Test 1: Normal execution (should work)
echo -e "\n1. Testing WITHOUT bwrap (normal execution - should work):"
echo "-----------------------------------------------------------"
timeout 3 bash -c '
PROCESS_ID=0 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15000 ./example/multiprocess/boost_ut_network_coordination &
PID1=$!
PROCESS_ID=1 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15000 ./example/multiprocess/boost_ut_network_coordination &
PID2=$!
wait $PID1 $PID2
' && echo "✓ SUCCESS: Processes synchronized" || echo "✗ FAILED: Timeout or error"

# Test 2: With bwrap but shared network (should work)
echo -e "\n2. Testing WITH bwrap but SHARED network namespace:"
echo "----------------------------------------------------"
timeout 3 bash -c '
bwrap --ro-bind / / --dev /dev --proc /proc \
  bash -c "PROCESS_ID=0 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15001 /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination" &
PID1=$!
bwrap --ro-bind / / --dev /dev --proc /proc \
  bash -c "PROCESS_ID=1 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15001 /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination" &
PID2=$!
wait $PID1 $PID2
' && echo "✓ SUCCESS: Processes synchronized" || echo "✗ FAILED: Timeout or error"

# Test 3: With bwrap and isolated network namespaces (will fail)
echo -e "\n3. Testing WITH bwrap and ISOLATED network namespaces:"
echo "-------------------------------------------------------"
echo "Expected: This will timeout because isolated namespaces can't communicate via multicast"
timeout 3 bash -c '
bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc \
  bash -c "PROCESS_ID=0 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15002 /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination" &
PID1=$!
bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc \
  bash -c "PROCESS_ID=1 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=239.255.0.1 MULTICAST_PORT=15002 /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination" &
PID2=$!
wait $PID1 $PID2
' && echo "✓ UNEXPECTED: Processes synchronized (should have failed)" || echo "✗ EXPECTED: Timeout - isolated namespaces can't communicate"

echo -e "\n========================================================================="
echo "Analysis:"
echo "- UDP multicast doesn't work across isolated network namespaces"
echo "- Each namespace has its own network stack and routing table"
echo "- Multicast packets can't cross namespace boundaries without special setup"