> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GPU Baseline Benchmarking Results

## Date: 2025-08-16

### System Configuration
- **CPU**: AMD Ryzen 7900X
- **GPU**: AMD Radeon RX 7900 XTX (RDNA 3, Navi 31)
- **Driver**: Mesa 25.0.7, LLVM 19.1.1, DRM 3.61
- **OS**: Linux 6.14.0-27-generic

### Test Configuration
- **Convolution**: ResNet-50 first layer equivalent
- **Input**: 1x3x224x224
- **Output**: 1x64x112x112
- **Kernel**: 7x7
- **Stride**: 2
- **Padding**: 3

### GPU Performance Results
- **Execution Time**: [deferred latency] per iteration
- **GFLOPS**: 493.28
- **Memory Bandwidth**: [deferred bandwidth]
- **Arithmetic Intensity**: 61.29 FLOPS/byte
- **Total FLOPs**: 236,027,904

### Implementation Details
- Using OpenGL Compute Shaders (GLSL 4.30)
- Local work group size: 64
- Headless execution via EGL
- GPU timing via GL timestamp queries

### Notes
- This is the baseline GLSL implementation with simple nested loops
- No optimizations beyond basic coalesced memory access
- Room for improvement with:
  - Shared memory usage
  - Better work distribution
  - Vectorized loads/stores
  - Loop unrolling

### Code Reference
- Test file: `examples/test_conv_gpu_real.f90`
- Shader: Direct convolution with boundary checks