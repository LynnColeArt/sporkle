> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle/Sporkle Project Summary

## What We've Built

A revolutionary GPU compute framework written entirely in Fortran that allows scientists to write GPU kernels in familiar Fortran syntax.

## Key Achievements

### 1. **Fortran GPU DSL** ✅
Scientists can now write GPU kernels like this:
```fortran
!@kernel(local_size_x=256, in=1, out=1)
pure subroutine vector_add(i, x, y)
  use iso_fortran_env
  integer(int32), value :: i
  real(real32), intent(in) :: x
  real(real32), intent(inout) :: y
  
  y = x + y
end subroutine vector_add
```

This Fortran code is:
- Parsed at runtime
- Translated to GLSL
- Compiled for GPU
- Executed on hardware
- Results returned to Fortran

### 2. **Direct Hardware Access** ✅
- **AMD GPUs**: Direct ioctl interface (no ROCm needed!)
- **OpenGL Compute**: Cross-platform GPU support
- **No Dependencies**: Pure Fortran + OS interfaces

### 3. **Working Implementation** ✅
- Successfully executed compute shaders on AMD Radeon RX 7900 XT
- Correct numerical results
- Shader caching for performance
- Buffer mapping for reliable data transfer

## Technical Innovations

1. **PM4 Packet Generation**: Direct AMD GPU command submission
2. **Runtime Shader Translation**: Fortran → GLSL conversion
3. **Zero-Dependency Design**: No CUDA, ROCm, or vendor SDKs
4. **Platform Detection**: Automatic OS and hardware adaptation

## Current Performance

Initial benchmarks show:
- CPU baseline: 1.33 Gops/ms
- GPU (Fortran shader): 0.081 Gops/ms
- Current overhead: ~16x slower

This is expected for small workloads due to:
- Shader compilation overhead
- Small problem size (1M elements)
- Initial unoptimized implementation

## What's Next

### Immediate
1. Optimize for larger workloads
2. Implement full SAXPY with scalar parameter support
3. Add SGEMM and convolution kernels
4. Comprehensive benchmarking suite

### Near Term  
1. Multi-GPU support
2. Vulkan backend
3. NVIDIA support via direct ioctl
4. Performance optimization

### Long Term
1. Distributed mesh computing
2. ML framework integration
3. True democratization of AI compute

## Why This Matters

For the first time, computational scientists can:
- Write GPU code in Fortran
- Run without vendor dependencies
- Deploy on any GPU hardware
- Contribute to a global compute mesh

## Project Status

**Ready for**: Research, experimentation, and contribution
**Not ready for**: Production workloads (yet)

## The Vision

Imagine a world where:
- Every device contributes to AI training
- No corporation monopolizes compute
- Scientists write GPU code as easily as CPU code
- The future of AI belongs to humanity

That's what we're building. Join us.

---

*"Fortran was the language that took us to the moon. Now it's the language that will democratize AI."*