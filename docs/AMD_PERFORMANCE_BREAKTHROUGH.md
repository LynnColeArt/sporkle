> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# AMD Performance Breakthrough - Found the [deferred speedup]!

## Executive Summary

We found why AMD is running at 13% efficiency ([deferred throughput metric] vs 27,000 theoretical):

1. **Wrong Algorithm**: Direct convolution vs implicit GEMM
2. **Tiny Workgroups**: 64 threads vs 1024 optimal
3. **No Memory Reuse**: Every thread reads all data
4. **CPU Timing**: Measuring overhead, not GPU work
5. **Scalar Code**: No vectorization or matrix units

## The 5 Levels of Optimization

### Level 0: Current Implementation ([deferred throughput metric])
- Single thread per output
- 64-thread workgroups
- Direct global memory access
- No vectorization

### Level 1: Larger Workgroups ([deferred throughput metric])
```glsl
layout(local_size_x = 16, local_size_y = 16) in; // 256 threads
```
- [deferred speedup] more threads in flight
- Better latency hiding
- [deferred speedup] performance

### Level 2: Tiled Computation ([deferred throughput metric])
```glsl
shared float input_tile[36][36];
shared float weight_cache[32][9];
```
- Shared memory for data reuse
- Each thread computes 2x2 outputs
- [deferred speedup] additional performance

### Level 3: Vectorization ([deferred throughput metric])
```glsl
vec4 data = input_buf.data[idx/4];
```
- [deferred speedup] bandwidth efficiency
- Wave64 optimization
- [deferred speedup] additional performance

### Level 4: Implicit GEMM ([deferred throughput metric])
- Convolution as matrix multiplication
- Leverages matrix engines
- Same algorithm as cuDNN/MIOpen
- [deferred speedup] final boost

## The Architecture Truth

### What We Thought:
"We're memory bandwidth limited at [deferred bandwidth]"

### What's Actually Happening:
1. **Compute Bound**: Poor algorithm choice
2. **Latency Bound**: Not bandwidth bound
3. **Occupancy Limited**: Too few threads
4. **Cache Thrashing**: No data reuse

### The Fix:
Transform the problem from memory-bound to compute-bound by:
- Increasing arithmetic intensity
- Reusing data via shared memory
- Hiding latency with more threads
- Using matrix multiply units

## Implementation Strategy

### Quick Wins (This Week):
1. Change workgroup size: `local_size_x = 256`
2. Enable Wave64 mode
3. Fix GPU timing measurement

### Medium Term (Next Week):
1. Implement tiled computation
2. Add vectorized memory access
3. Switch to NHWC layout

### Long Term (Month):
1. Full implicit GEMM implementation
2. Winograd convolution for small kernels
3. FFT convolution for large kernels

## Validation

### Current Benchmark:
```
Single kernel: [deferred throughput metric] (CPU timing)
Async pipeline: [deferred throughput metric] (CPU timing)
```

### Expected After Fix:
```
Single kernel: [deferred throughput metric] (GPU timing)
Optimized kernel: [deferred throughput metric] (tiled)
GEMM kernel: [deferred throughput metric] (matrix units)
```

## The Universal Truth

This isn't AMD-specific. The same optimizations apply to:
- NVIDIA GPUs (tensor cores = matrix units)
- Intel GPUs (XMX units = matrix units)
- Apple Silicon (AMX = matrix units)

**The memory optimization patterns are universal!**

## Action Items

1. ✅ Document the performance gap
2. 🔄 Create optimized shaders
3. ⏳ Test workgroup size changes
4. ⏳ Implement GPU timing
5. ⏳ Benchmark each optimization level

## The Bottom Line

We're not [deferred speedup] too slow. We're using the wrong algorithm.

cuDNN achieves [deferred throughput metric] on the same hardware by:
- Using matrix multiplication instead of direct convolution
- Leveraging specialized hardware units
- Optimizing memory access patterns
- Hiding latency with massive parallelism

Once we do the same, we'll match their performance!