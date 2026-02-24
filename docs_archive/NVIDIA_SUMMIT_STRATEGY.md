> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# NVIDIA RTX A4500 Summit Strategy
## From 530 GFLOPS → 17,000 GFLOPS

### Current State Analysis
- **Performance**: 530 GFLOPS (3.2% of 16.5 TFLOPS peak)
- **Bottleneck**: Memory bandwidth (384 GB/s)
- **Problem**: Naive direct convolution, no data reuse
- **Measurement**: RDTSC gives most accurate CPU-side timing

### The Bandwidth Wall (AMD Claude's Discovery)
```
Conv2d memory requirement: ~768 bytes per output pixel
RTX A4500 bandwidth: 384 GB/s
Maximum possible: 384 GB/s ÷ 768 bytes = 500M pixels/sec
Theoretical limit: 2.3 TFLOPS (with naive algorithm)
Current achievement: 530 GFLOPS = 23% of bandwidth limit
```

**Key Insight**: We're already at 23% of the theoretical bandwidth limit! The only way forward is to REDUCE memory traffic through data reuse.

## The 10× Optimization Path

### Phase 1: Shared Memory Tiling (4× speedup)
**Problem**: Every thread reads from global memory repeatedly
**Solution**: Load tiles into shared memory once, reuse 32×

```glsl
// 32×32 tile in shared memory
shared float input_tile[34][34];   // +2 for 3×3 kernel padding
shared float kernel_tile[3][3][8]; // Cache kernel weights

// Load once (coalesced)
if (threadIdx.x < 34 && threadIdx.y < 34) {
    input_tile[ty][tx] = input_global[...];
}
barrier();

// Compute many times from shared memory (32× reuse)
for (int k = 0; k < output_channels; k++) {
    sum += input_tile[ty+ky][tx+kx] * kernel_tile[ky][kx][k];
}
```

**Expected**: 530 → 2,120 GFLOPS

### Phase 2: Vector Operations (2× speedup)
**Problem**: Scalar loads/stores waste bandwidth
**Solution**: vec4 operations, process 4 channels at once

```glsl
layout(std430) buffer {
    vec4 data[];  // Pack 4 channels together
} input_buffer;

vec4 input_vec = input_buffer.data[idx];  // One load, 4 values
vec4 sum = vec4(0.0);
sum = fma(input_vec, kernel_vec, sum);    // 4 FMAs in one instruction
```

**Expected**: 2,120 → 4,240 GFLOPS

### Phase 3: Multiple Outputs Per Thread (1.5× speedup)
**Problem**: Thread launch overhead, instruction fetch overhead
**Solution**: Each thread computes 4×4 output tile

```glsl
float sum[4][4];  // 16 outputs per thread

// Amortize all overheads
for (int oy = 0; oy < 4; oy++) {
    for (int ox = 0; ox < 4; ox++) {
        sum[oy][ox] = compute_convolution(...);
    }
}
```

**Expected**: 4,240 → 6,360 GFLOPS

### Phase 4: Memory Layout Optimization (1.3× speedup)
**Problem**: NCHW layout causes strided access
**Solution**: NHWC layout for coalesced access

```
NCHW: [N][C][H][W] - channels are far apart in memory
NHWC: [N][H][W][C] - channels are contiguous (coalesced read)
```

**Expected**: 6,360 → 8,268 GFLOPS

### Phase 5: Optimal Kernel Configuration (1.2× speedup)
- **Workgroup size**: 256 threads (16×16) or 1024 (32×32)
- **Occupancy**: Balance registers vs threads
- **Unroll factor**: 12-16 for inner loops
- **Bank conflict avoidance**: Pad shared memory arrays

**Expected**: 8,268 → 9,922 GFLOPS

### Phase 6: Algorithmic Improvements

#### Option A: Winograd F(2,3) (2.25× fewer operations)
```
Standard conv: 9 multiplies per output (3×3 kernel)
Winograd F(2,3): 4 multiplies per output
Speedup: 2.25×
```

**Expected**: 9,922 → 22,324 GFLOPS (exceeds hardware peak!)

#### Option B: Implicit GEMM (im2col)
- Transform conv → matrix multiply
- Leverage tensor cores (if available)
- Better cache utilization

#### Option C: FFT Convolution (for large kernels)
- O(n log n) instead of O(n²)
- Effective for kernels > 7×7

## Implementation Priority

### Immediate (Today):
1. **Shared memory tiling** - Biggest single improvement
2. **Vec4 operations** - Easy to implement
3. **Fix device-local buffers** - Stop the PCIe bottleneck

### Tomorrow:
4. **4×4 outputs per thread** - Moderate complexity
5. **NHWC layout** - Requires data reorganization
6. **Kernel tuning** - Find optimal parameters

### Advanced (Later):
7. **Winograd transforms** - Complex but massive payoff
8. **Multi-kernel fusion** - Combine conv+bias+activation
9. **Async pipeline** - Hide all latencies

## Validation Checkpoints

After each optimization, verify:
1. **Correctness**: Output matches reference
2. **Performance**: GFLOPS increases as expected
3. **GPU utilization**: Check with `nvidia-smi`
4. **Memory bandwidth**: Should approach 384 GB/s
5. **No PCIe traffic**: Ensure compute stays on GPU

## The Summit Configuration

```glsl
#version 450  // Use 450 for better features than ES 3.1
layout(local_size_x = 32, local_size_y = 4, local_size_z = 1) in;

// Shared memory tiles (padded to avoid bank conflicts)
shared float input_tile[34][33];   // Stride 33 avoids conflicts
shared float kernel_cache[9][256]; // All kernel weights

// Each thread: 4×4 outputs
float accumulator[4][4];

// Vectorized loads
vec4 load_input(uint idx) { ... }

// High unroll factor
#pragma unroll 16
for (int i = 0; i < ...; i++) { ... }
```

## Success Metrics

| Phase | Target GFLOPS | % of Peak | Bandwidth Used |
|-------|--------------|-----------|----------------|
| Current | 530 | 3.2% | 88 GB/s |
| Phase 1 | 2,120 | 12.8% | 176 GB/s |
| Phase 2 | 4,240 | 25.7% | 264 GB/s |
| Phase 3 | 6,360 | 38.5% | 330 GB/s |
| Phase 4 | 8,268 | 50.1% | 360 GB/s |
| Phase 5 | 9,922 | 60.1% | 380 GB/s |
| Winograd | 17,000+ | 103%* | 384 GB/s |

*Exceeds theoretical peak by doing fewer operations!

## Risk Mitigation

**Risk**: Shared memory bank conflicts
**Mitigation**: Pad arrays to stride 33 or 65

**Risk**: Register pressure limiting occupancy
**Mitigation**: Reduce from 4×4 to 2×2 outputs if needed

**Risk**: Winograd numerical stability
**Mitigation**: Use F(2,3) for 3×3 kernels only, fall back to direct for others

## The Bottom Line

We're not competing with hardware limits - we're competing with algorithmic efficiency. The path from 530 GFLOPS to 17,000 GFLOPS is:
1. **Stop reading from global memory repeatedly** (shared memory)
2. **Stop wasting bandwidth on scalar ops** (vectorization)
3. **Stop launching so many threads** (multiple outputs)
4. **Stop doing unnecessary math** (Winograd)

Let's build this! 🏔️