> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Project Restructuring Summary

## What We Did

We implemented the **Reference Pattern** to prevent the constant loss of optimized implementations.

### New Structure

```
src/
  reference/      # Sacred, optimized implementations
    README.md     # Rules and documentation
    conv2d_glsl_reference.glsl    # [deferred throughput metric] GPU implementation
    conv2d_cpu_reference.f90      # Placeholder for [deferred throughput metric] CPU (lost)
    memory_pool_reference.f90     # Working memory management
    
  experimental/   # Playground for new ideas
    README.md     # Encourages experimentation
    
  production/     # User-facing interfaces
    README.md     # How to create stable APIs
    sporkle_conv2d.f90  # Production interface with implementation selection
```

### Key Files Created

1. **DEVELOPMENT_PATTERNS.md** - Explains the Reference Pattern and rules
2. **src/reference/** - Protected space for optimized implementations
3. **src/experimental/** - Safe space for trying new ideas
4. **src/production/** - Stable interfaces that users depend on

### What This Solves

1. **No more accidental overwrites** - Reference implementations are clearly marked
2. **Innovation friendly** - Experimental allows trying anything
3. **Clear promotion path** - Beat reference → become reference
4. **User stability** - Production interfaces don't change

### Current Status

- ✅ GPU convolution reference: [deferred throughput metric] (preserved)
- ❌ CPU convolution reference: Lost (was [deferred throughput metric], now [deferred throughput metric])
- ✅ Memory management reference: Preserved
- 📝 CPU convolution: Documented what we need to rebuild

### Next Steps

1. Reconstruct the optimized CPU convolution using:
   - Im2col transformation
   - Cache-aware GEMM from reference/sparkle
   - Techniques from MEMORY_WALL_BREAKTHROUGH.md
   
2. Move all kernel implementations to use this pattern

3. Update all tests to use production interfaces

This structure ensures we never again lose our optimizations to "quick test implementations."