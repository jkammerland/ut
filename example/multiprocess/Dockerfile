FROM fedora:42

# Install build dependencies
RUN dnf update -y && dnf install -y \
    gcc-c++ \
    cmake \
    ninja-build \
    git \
    make \
    && dnf clean all

# Create working directory
WORKDIR /app

# Copy source code
COPY . .

# Build the project
RUN cmake -B build -G Ninja -DBOOST_UT_BUILD_EXAMPLES=ON && \
    cmake --build build

# Default command
CMD ["./build/example/multiprocess/boost_ut_coordination_test"]