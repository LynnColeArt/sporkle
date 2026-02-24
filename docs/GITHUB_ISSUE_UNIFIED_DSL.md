> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GitHub Issue: Extend Fortran DSL to Support Metal/Neural Engine

## Title
Feature: Unified Fortran DSL with Metal Shading Language and Neural Engine Support

## Labels
- enhancement
- metal
- neural-engine  
- fortran-dsl
- performance

## Description

### Summary
Extend our Fortran GPU DSL (currently generating GLSL for AMD GPUs) to also generate Metal Shading Language (MSL) and Neural Engine patterns, creating a unified compute abstraction across all platforms.

### Background
We've successfully implemented:
- Fortran kernel parser that generates GLSL
- Adaptive parameter passing optimization 
- Working GPU compute on AMD via OpenGL

We previously achieved [deferred throughput metric] (90% theoretical) on Apple Silicon through manual optimization. This feature would bring those optimizations into our unified framework.

### Proposed Solution
1. Extend the shader parser to support multiple backend targets
2. Add MSL generation alongside existing GLSL generation
3. Apply adaptive optimization framework to Metal-specific features
4. Create Neural Engine pattern generation for compatible kernels

### Example Usage
```fortran
!@kernel(local_size_x=32, backend=auto)
pure subroutine convolution_kernel(idx, input, output, weights, ...)
  ! Single Fortran implementation
  ! Compiles to optimal code for detected hardware
end subroutine
```

### Benefits
- Write once, run optimally everywhere
- Leverage platform-specific optimizations automatically
- Maintain single kernel source for all platforms
- Easier testing and benchmarking across platforms

### Technical Details
See [PROPOSAL_UNIFIED_FORTRAN_DSL.md](docs/PROPOSAL_UNIFIED_FORTRAN_DSL.md) for full technical proposal.

### Checklist
- [ ] Extend parser to support backend selection
- [ ] Implement MSL generator
- [ ] Add Metal-specific optimizations
- [ ] Create Neural Engine pattern templates
- [ ] Integrate with existing Metal backend
- [ ] Benchmark against hand-optimized kernels
- [ ] Document platform-specific features

### Related Issues
- Related to adaptive parameter passing (#[previous-issue])
- Builds on Fortran DSL work (#[previous-issue])

### Timeline
Estimated 4-6 weeks for full implementation

### Questions for Discussion
1. Should we support runtime backend selection or compile-time only?
2. How much platform-specific syntax should we allow in kernels?
3. Should Neural Engine be a separate backend or integrated with Metal?

/cc @anthropics/sparkle-team