# Container image for multiprocess testing with network coordination
FROM fedora:latest

# Install required libraries
RUN dnf install -y boost-system glibc libstdc++ && dnf clean all

# Create working directory
WORKDIR /app

# The test binary will be mounted at runtime
ENTRYPOINT ["/app/test"]