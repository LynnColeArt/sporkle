> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle GPU Architecture 🎮

## Overview

Sparkle's GPU support is built on OpenGL Compute Shaders (OpenGL 4.3+), providing vendor-neutral GPU execution that works on:
- ✅ AMD GPUs (via Mesa/AMDGPU)
- ✅ NVIDIA GPUs (via proprietary or Nouveau drivers)  
- ✅ Intel GPUs (via Mesa)
- ✅ Any GPU with OpenGL 4.3+ support

## Why OpenGL Compute?

1. **No SDK Required**: Uses drivers already on the system
2. **Cross-vendor**: Same code runs on AMD, NVIDIA, Intel
3. **Mature**: OpenGL has been around for decades
4. **Headless**: EGL allows compute without a display

## Architecture

### 1. GPU Context (`sporkle_gpu_opengl.f90`)
```fortran
type :: gl_context
  type(c_ptr) :: display      ! EGL display
  type(c_ptr) :: context      ! OpenGL context
  logical :: initialized
  integer :: version_major
  integer :: version_minor
end type
```

### 2. Compute Shaders (`sporkle_gpu_kernels.f90`)
Pre-written GLSL compute shaders for common operations:
- Vector addition
- SAXPY
- Tiled GEMM (matrix multiplication)
- Parallel reduction
- Complex operations

### 3. GPU Buffers
```fortran
type :: gl_buffer
  integer(c_int) :: buffer_id    ! OpenGL buffer ID
  integer(c_size_t) :: size_bytes ! Buffer size
  integer :: binding_point        ! Shader binding
end type
```

## Usage Example

```fortran
! Create context
ctx = create_gl_context()

! Compile shader
shader = create_compute_shader(get_vector_add_shader())

! Create GPU buffers
x_buffer = create_gl_buffer(size, 0)
y_buffer = create_gl_buffer(size, 1)
z_buffer = create_gl_buffer(size, 2)

! Upload data
call update_gl_buffer(x_buffer, c_loc(x_data), size)
call update_gl_buffer(y_buffer, c_loc(y_data), size)

! Run on GPU!
call dispatch_compute(shader, num_groups, 1, 1)

! Read results
call read_gl_buffer(z_buffer, c_loc(z_data), size)
```

## Performance Expectations

### RX 7900 XT Specifications:
- 84 Compute Units
- [deferred throughput metric] (FP32)
- [deferred bandwidth] memory bandwidth
- 24 GB VRAM

### Expected Performance:
- Vector ops: 500-[deferred bandwidth] (vs [deferred bandwidth] CPU)
- GEMM: 10-[deferred throughput metric] (vs [deferred throughput metric] CPU)
- Speedup: [deferred speedup range] over CPU

## Compilation

```bash
# With OpenGL/EGL libraries
gfortran -O3 -o sporkle_gpu \
  src/sporkle_gpu_opengl.f90 \
  src/sporkle_gpu_kernels.f90 \
  examples/test_gpu.f90 \
  -lGL -lEGL

# On Linux with Mesa
export MESA_LOADER_DRIVER_OVERRIDE=radeonsi  # For AMD
export __GLX_VENDOR_LIBRARY_NAME=mesa
```

## Implementation Status

### Complete ✅
- OpenGL context creation
- Compute shader compilation
- Buffer management
- GLSL kernel sources
- Basic dispatch

### TODO 🔨
- [ ] Buffer readback (glGetBufferSubData)
- [ ] Uniform setting (shader parameters)
- [ ] Error checking and reporting
- [ ] Performance benchmarking
- [ ] Integration with Sparkle scheduler

## The Sporkle Way

No CUDA. No ROCm. No vendor lock-in.

Just pure OpenGL that runs on any modern GPU. Your grandmother's laptop with Intel graphics? It'll run Sparkle. Your friend's ancient NVIDIA card? Sparkle's got it. That beast RX 7900 XT? Sparkle will make it sing.

**Democratizing compute, one shader at a time!** ✨