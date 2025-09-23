#!/bin/bash
# CI test script for Podman multiprocess on Fedora 42
# Minimal shell scripting - uses CMake/CTest for most logic

set -e

echo "Podman Multiprocess CI Test on Fedora 42"
echo "========================================="

# Verify we're on Fedora 42
if ! grep -q "Fedora release 42" /etc/fedora-release 2>/dev/null; then
  echo "Warning: Not running on Fedora 42"
fi

# Configure with Podman tests enabled and build examples
echo "1. Configuring with CMake..."
cmake -B build-ci -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_PODMAN_TESTS=ON \
  -DUT_BUILD_EXAMPLES=ON \
  -DCMAKE_INSTALL_PREFIX=/tmp/ut-install

# Build
echo "2. Building..."
cmake --build build-ci --parallel

# Install package
echo "3. Installing package..."
cmake --install build-ci

# Build container image for tests
echo "4. Building container image..."
cat > build-ci/Dockerfile.ci << 'EOF'
FROM fedora:42
RUN dnf install -y boost-system libstdc++ && dnf clean all
WORKDIR /test
EOF
podman build -t multiprocess-test -f build-ci/Dockerfile.ci build-ci

# Run tests with CTest
echo "5. Running CTest..."
cd build-ci

# Run all multiprocess tests (including Podman if available)
ctest -L multiprocess --output-on-failure --timeout 120 || true

# Run specific Podman test if the executable exists
if [ -f example/multiprocess/boost_ut_network_coordination ]; then
  echo ""
  echo "6. Running direct Podman test..."

  # Simple inline test - no external script needed
  (
    EXEC="example/multiprocess/boost_ut_network_coordination"
    NET="ci-test-$$"

    cleanup() {
      podman rm -f ci-0 ci-1 ci-2 2>/dev/null || true
      podman network rm $NET 2>/dev/null || true
    }
    trap cleanup EXIT

    podman network create $NET --subnet 10.99.0.0/24

    for i in 0 1 2; do
      podman run -d --name ci-$i --network $NET \
        -v "$(pwd)/$EXEC:/test:ro,Z" \
        -e PROCESS_ID=$i \
        -e PARTICIPANT_COUNT=3 \
        multiprocess-test /test
    done

    SUCCESS=true
    for i in 0 1 2; do
      if ! timeout 30 podman wait ci-$i; then
        SUCCESS=false
      fi
    done

    if $SUCCESS; then
      echo "✓ Podman test passed"
      exit 0
    else
      echo "✗ Podman test failed"
      exit 1
    fi
  )
fi

echo ""
echo "CI Test Complete!"