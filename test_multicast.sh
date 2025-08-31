#!/bin/bash

# Test multicast functionality locally
# Run two processes that should coordinate via UDP multicast

echo "Testing multiprocess fixture with UDP multicast..."

# Run first process in background (server)
PROCESS_ROLE=server SIMULATED_IP=127.0.0.1 ./build/example/multiprocess/boost_ut_network_coordination &
SERVER_PID=$!

# Small delay to let server start
sleep 1

# Run second process (client)
PROCESS_ROLE=client SIMULATED_IP=127.0.0.2 ./build/example/multiprocess/boost_ut_network_coordination &
CLIENT_PID=$!

# Wait for both processes to complete
wait $SERVER_PID
SERVER_EXIT=$?

wait $CLIENT_PID  
CLIENT_EXIT=$?

echo "Server exit code: $SERVER_EXIT"
echo "Client exit code: $CLIENT_EXIT"

# Check results
if [ $SERVER_EXIT -eq 0 ] && [ $CLIENT_EXIT -eq 0 ]; then
    echo "SUCCESS: Both processes completed successfully"
    exit 0
else
    echo "FAILURE: One or more processes failed"
    exit 1
fi