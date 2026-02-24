> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# RDNA Architectural Optimization: Applying the SIMD Principle to GPUs

## Executive Summary

We've discovered that the same architectural principle that led to our [deferred throughput metric] CPU SIMD breakthrough applies directly to GPU optimization: **match the hardware's native execution width**. Just as AVX-512 processes 16 floats per instruction, RDNA GPUs execute 32 threads per wavefront (Wave32), and optimal performance comes from aligning our workloads to these fundamental hardware units.

## The Universal Principle

### CPU SIMD Success
- **Hardware Unit**: AVX-512 = 16 floats/instruction
- **Optimization**: Align data and operations to 16-element boundaries
- **Result**: [deferred throughput metric] ([deferred speedup] improvement over baseline)

### GPU Wave Execution
- **Hardware Unit**: RDNA Wave32 = 32 threads/wavefront
- **Optimization**: Align workgroups to multiples of 32 threads
- **Result**: [deferred throughput metric] with proper wave alignment

## Architectural Evolution: GCN to RDNA

### GCN Architecture (Pre-RDNA)
```
Wave64: 64 threads execute in lockstep
- Workgroup sizes: 64, 128, 256 threads
- Designed for throughput over latency
- Shader binaries assume Wave64
```

### RDNA Architecture (RX 5000/6000/7000)
```
Wave32: 32 threads execute in lockstep
- Better cache utilization with smaller waves
- Lower latency for divergent workloads
- RDNA3 adds dual-issue capability
```

## The Mismatch We Discovered

Our investigation revealed we were using:
1. **GCN3 shader binaries** on **RDNA3 hardware**
2. **Wave64 assumptions** on **Wave32 architecture**
3. **Generic workgroup sizes** instead of **wave-aligned sizes**

This is equivalent to using SSE code on AVX-512 hardware - it works but leaves massive performance on the table.

## Implementation: RDNA-Optimized Shaders

### Original (GCN-style)
```glsl
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
// 256 threads = 4 waves on GCN (Wave64)
// 256 threads = 8 waves on RDNA (Wave32) - suboptimal!
```

### RDNA-Optimized (Matches [deferred throughput metric] Reference)
```glsl
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
// 64 threads = 2 waves on RDNA (Wave32) - optimal!
// Matches our working reference implementation
```

### RDNA3 Dual-Issue Optimized
```glsl
// RDNA3 can dual-issue FMA with other operations
float sum = 0.0;
float sum2 = 0.0;  // Second accumulator for dual-issue

// Process two channels simultaneously
sum += input_buf.data[in_idx] * weight_buf.data[weight_idx];
sum2 += input_buf.data[in_idx2] * weight_buf.data[weight_idx2];
```

## Performance Impact

### Theoretical Analysis
- **Wave Occupancy**: Smaller workgroups = better wave scheduling
- **Cache Efficiency**: Wave32 fits better in L0/L1 caches
- **Dual-Issue**: RDNA3 can execute 2 FMAs per cycle per SIMD

### Expected Improvements
1. **Wave Alignment**: 10-20% from proper wave32 workgroups
2. **Cache Optimization**: 15-25% from better data locality
3. **Dual-Issue**: Up to [deferred speedup] on RDNA3 for FMA-heavy workloads

## Universal Memory Optimization Pattern

The same pattern applies across architectures:

```
CPU SIMD:     Process 16 floats    → Match AVX-512 width
GPU Wave32:   Process 32 threads   → Match RDNA wave width
GPU Wave64:   Process 64 threads   → Match GCN wave width
```

## Dynamic Shader Generation Strategy

Instead of hardcoding shaders, we should:
1. **Detect Architecture**: Query wave size at runtime
2. **Generate Optimal Shaders**: Match workgroup to wave size
3. **Exploit Architecture Features**: Use dual-issue on RDNA3

## Implementation Roadmap

1. **Immediate**: Use RDNA-optimized shaders for AMD GPUs
2. **Short-term**: Implement runtime architecture detection
3. **Long-term**: Full dynamic shader generation system

## Key Takeaways

1. **Hardware Alignment is Universal**: The same principle that makes CPU SIMD fast applies to GPU waves
2. **Architecture Matters**: GCN vs RDNA is as different as SSE vs AVX
3. **Dynamic Adaptation**: One-size-fits-all shaders leave performance on the table

## Conclusion

By applying the architectural primitive of matching hardware's native execution width, we can optimize across all compute devices. This discovery validates our universal memory optimization framework and shows that the principles are truly universal - from CPU SIMD lanes to GPU wavefronts.

The path forward is clear: dynamic shader generation that adapts to the underlying hardware architecture, just as we adapt our CPU code to use the available SIMD width.