#!/bin/bash
# Test multiprocess coordination with bwrap and loopback interface

echo "Testing with loopback interface in isolated namespace"
echo "======================================================"

# First, let's see what happens when we bring up lo interface
echo -e "\nTest: Isolated namespace with loopback interface enabled"
echo "----------------------------------------------------------"

# We need to use unshare directly to configure the lo interface
# bwrap doesn't allow us to run ip commands inside

timeout 5 bash -c '
# Process 1: Coordinator in isolated namespace with lo
unshare --net bash -c "
  # Bring up loopback interface
  ip link set lo up
  ip addr add 127.0.0.1/8 dev lo 2>/dev/null
  # Now run the test
  PROCESS_ID=0 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=127.255.0.1 MULTICAST_PORT=15010 \
    /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination
" &
PID1=$!

# Process 2: Participant in same namespace
# Give coordinator time to start
sleep 0.5
unshare --net bash -c "
  # Bring up loopback interface
  ip link set lo up
  ip addr add 127.0.0.1/8 dev lo 2>/dev/null
  # Now run the test
  PROCESS_ID=1 PARTICIPANT_COUNT=2 MULTICAST_ADDRESS=127.255.0.1 MULTICAST_PORT=15010 \
    /home/ai-dev1/repos/ut/build/example/multiprocess/boost_ut_network_coordination
" &
PID2=$!

wait $PID1 $PID2
' && echo "✓ SUCCESS: Processes synchronized" || echo "✗ FAILED: Processes couldn't synchronize in isolated namespaces"

echo -e "\n======================================================"
echo "Note: Processes in DIFFERENT network namespaces cannot communicate"
echo "even with loopback, as each namespace is completely isolated."