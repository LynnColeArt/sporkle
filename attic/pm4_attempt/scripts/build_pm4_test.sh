#!/bin/bash
# Build PM4 Direct Submission Test

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Building PM4 Direct Submission Test...${NC}"

# Create build directory if it doesn't exist
mkdir -p build

# Build flags
FFLAGS="-O3 -march=native -ffree-line-length-none -fopenmp"
INCLUDES=""
LIBS="-L/usr/lib/x86_64-linux-gnu -lGL -lEGL -ldrm -fopenmp"

# Core modules (order matters!)
echo "Building core modules..."
gfortran $FFLAGS -c src/common/kinds.f90 -o build/kinds.o
gfortran $FFLAGS -c src/sporkle_types.f90 -o build/sporkle_types.o
gfortran $FFLAGS -c src/sporkle_utils.f90 -o build/sporkle_utils.o

# AMDGPU modules
echo "Building AMDGPU modules..."
gfortran $FFLAGS -c src/sporkle_amdgpu_drm.f90 -o build/sporkle_amdgpu_drm.o
gfortran $FFLAGS -c src/sporkle_amdgpu_ioctl.f90 -o build/sporkle_amdgpu_ioctl.o
gfortran $FFLAGS -c src/sporkle_amdgpu_direct.f90 -o build/sporkle_amdgpu_direct.o
gfortran $FFLAGS -c src/sporkle_amdgpu_memory.f90 -o build/sporkle_amdgpu_memory.o

# PM4 modules
echo "Building PM4 modules..."
gfortran $FFLAGS -c src/sporkle_pm4_packets.f90 -o build/sporkle_pm4_packets.o
gfortran $FFLAGS -c src/sporkle_gpu_va_allocator.f90 -o build/sporkle_gpu_va_allocator.o
gfortran $FFLAGS -c src/sporkle_rdna3_shaders.f90 -o build/sporkle_rdna3_shaders.o
gfortran $FFLAGS -c src/sporkle_pm4_compute.f90 -o build/sporkle_pm4_compute.o

# Production modules  
echo "Building production modules..."
gfortran $FFLAGS -c src/production/gpu_safety_guards.f90 -o build/gpu_safety_guards.o
gfortran $FFLAGS -c src/production/gpu_ring_buffer.f90 -o build/gpu_ring_buffer.o
gfortran $FFLAGS -c src/production/pm4_conv2d_builder.f90 -o build/pm4_conv2d_builder.o
gfortran $FFLAGS -c src/production/pm4_safe_submit.f90 -o build/pm4_safe_submit.o

# Build test program
echo "Building test program..."
gfortran $FFLAGS -c test_pm4_conv2d_direct.f90 -o build/test_pm4_conv2d_direct.o

# Link everything
echo "Linking..."
gfortran $FFLAGS -o test_pm4_conv2d_direct \
    build/test_pm4_conv2d_direct.o \
    build/pm4_safe_submit.o \
    build/pm4_conv2d_builder.o \
    build/gpu_ring_buffer.o \
    build/gpu_safety_guards.o \
    build/sporkle_pm4_compute.o \
    build/sporkle_rdna3_shaders.o \
    build/sporkle_gpu_va_allocator.o \
    build/sporkle_pm4_packets.o \
    build/sporkle_amdgpu_memory.o \
    build/sporkle_amdgpu_direct.o \
    build/sporkle_amdgpu_ioctl.o \
    build/sporkle_amdgpu_drm.o \
    build/sporkle_utils.o \
    build/sporkle_types.o \
    build/kinds.o \
    $LIBS

echo -e "${GREEN}Build complete!${NC}"
echo "Run with: ./test_pm4_conv2d_direct"