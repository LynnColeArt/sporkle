> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# AMD 10x Performance Optimization Plan

## Current Performance: 3,630 GFLOPS (13.4% of theoretical)
## Target Performance: 36,000+ GFLOPS (>100% via better algorithms)

## The 5 Critical Fixes

### 1. **Tile-Based Computation with Shared Memory**
```glsl
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 4) in;

// 16x16 output tile, 4 channels processed together
shared float tile_input[20][20][4];  // 18x18 for 3x3 kernel + padding
shared float tile_weights[4][3][3][4]; // K_tile x 3x3 x C_tile

void main() {
    // Each workgroup computes 16x16x4 outputs
    // 1024 threads total (16*16*4)
    // Massive data reuse via shared memory
}
```

### 2. **Wave64 Optimization + Vectorization**
```glsl
// Read float4 instead of float
vec4 input_vec = vec4(
    input_buf.data[idx],
    input_buf.data[idx+1],
    input_buf.data[idx+2], 
    input_buf.data[idx+3]
);

// Process 4 channels at once
vec4 sum = vec4(0.0);
```

### 3. **Coalesced Memory Access Pattern**
Instead of NCHW layout (strided access), use NHWC or tiled layout:
- Threads in same warp access contiguous memory
- 32 threads read 128 bytes in one transaction
- Full memory bandwidth utilization

### 4. **Multiple Outputs Per Thread**
```glsl
// Each thread computes 2x2 or 4x4 output tile
const int OUTPUTS_PER_THREAD = 4;
float sums[OUTPUTS_PER_THREAD];

// Amortize instruction overhead
// Better instruction/memory ratio
```

### 5. **Proper Grid Configuration**
```fortran
! Current (BAD):
grid_x = (W_out + 15) / 16  ! Too small

! Optimized:
grid_x = (W_out + 63) / 64  ! Tile size
grid_y = (H_out + 63) / 64
grid_z = (N * K + 3) / 4    ! Process 4 channels together
workgroup_size = [16, 16, 4] ! 1024 threads
```

## Memory Bandwidth Analysis

**7900 XT Specs:**
- Memory bandwidth: 960 GB/s
- Compute: 61.4 TFLOPS (FP32)
- Compute/Bandwidth ratio: 64 FLOPS/byte

**Conv2d Requirements (3x3 kernel):**
- Input read: H*W*C*4 bytes
- Weight read: K*C*9*4 bytes  
- Output write: H*W*K*4 bytes
- Total: ~(2*C + K)*H*W*4 bytes

For typical conv (C=256, K=256):
- ~768 bytes per output pixel
- Need 768 GB/s for 1 TFLOP
- **We're memory bandwidth limited!**

## The Real Solution: Winograd/FFT Convolution

Traditional conv2d: 2*K*K*C FLOPs per output
Winograd F(2,3): 2.25x fewer multiplies
FFT convolution: O(log N) for large kernels

**This is how we exceed theoretical FLOPS:**
- Reduce arithmetic operations
- Better memory access patterns
- Leverage tensor cores (matrix multiply units)

## Implementation Priority

1. **Quick Win**: Increase workgroup size to 256 or 1024
2. **Medium**: Implement tiled computation with shared memory
3. **Big Win**: NHWC memory layout + vectorization
4. **Ultimate**: Winograd or implicit GEMM algorithm

## Expected Results

- Step 1: 3,630 → 7,000 GFLOPS (2x)
- Step 2: 7,000 → 15,000 GFLOPS (2x)
- Step 3: 15,000 → 25,000 GFLOPS (1.7x)
- Step 4: 25,000 → 40,000+ GFLOPS (1.6x)

**Total: 11x improvement to 40,000 GFLOPS!**

## The Dirty Secret

NVIDIA's cuDNN and AMD's MIOpen don't use direct convolution. They use:
- Implicit GEMM (im2col)
- Winograd transforms
- FFT convolution
- Tensor core operations

We're comparing our naive algorithm to their optimized ones. Once we implement the same algorithms, we'll match or exceed their performance!