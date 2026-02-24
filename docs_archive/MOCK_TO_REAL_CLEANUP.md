> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Mock to Real Implementation Cleanup

## The Pattern We're Fixing

Working implementations live in test files while production modules contain mocks/placeholders. This document tracks ALL instances where real code needs to be moved to production.

## Found Issues

### 1. GPU Dispatch (CRITICAL)
**Working Code Location**: `examples/test_conv_cpu_vs_gpu.f90`
- Performance: [deferred throughput metric] achieved
- Uses: Direct OpenGL/EGL, proper buffer management, GPU timing

**Mock Location**: `src/sporkle_gpu_dispatch.f90`
- Contains: "MOCK: Not actually executing on GPU"
- Returns fake results

**Action Required**:
- [ ] Extract GPU initialization from test_conv_cpu_vs_gpu.c
- [ ] Extract shader compilation/execution from test 
- [ ] Replace mock in sporkle_gpu_dispatch.f90
- [ ] Update sporkle_gpu_opengl.f90 with real OpenGL calls

### 2. GPU Backend Detection
**Working Code Location**: `src/sporkle_gpu_backend.f90`
- OpenGL: Partially implemented
- Vulkan: "not implemented"
- ROCm: "not implemented"  
- CUDA: "not implemented"
- OneAPI: "not implemented"

**Action Required**:
- [ ] At minimum, complete OpenGL backend
- [ ] Remove or clearly mark others as future work

### 3. Memory Management
**Status**: ✅ GOOD - Real implementation exists
- `src/sporkle_memory.f90` has working code
- Already copied to reference/
- But device allocation shows "placeholder" message

**Action Required**:
- [ ] Implement actual device memory allocation
- [ ] Connect to GPU buffer creation

### 4. Production Convolution Interface
**Location**: `src/production/sporkle_conv2d.f90`
- CPU: Uses naive implementation ([deferred throughput metric])
- GPU: Just says "Not implemented" and stops

**Action Required**:
- [ ] Connect to real GPU dispatch once fixed
- [ ] Add im2col+GEMM CPU path when reconstructed

### 5. Shader Compilation
**Working Code**: Multiple locations
- `examples/test_conv_cpu_vs_gpu.c` - Has working shader
- `src/sporkle_glsl_generator.f90` - Can generate shaders
- `src/sporkle_shader_parser_v2.f90` - Can parse DSL

**Not Connected**: These pieces don't talk to each other!

**Action Required**:
- [ ] Create unified shader management module
- [ ] Connect parser → generator → GPU execution

### 6. GLSL Compute Module
**Location**: `src/sporkle_glsl_compute.f90`
- Has structure but missing actual OpenGL calls
- Comment: "Note: In real implementation, we'd need GL buffer objects"

**Action Required**:
- [ ] Add real OpenGL buffer management
- [ ] Connect to working code from tests

### 7. Device Implementations
**AMD Device**: `src/amd_device.f90`
- Memory allocation: "Allocate host memory as placeholder"
- Kernel execution: "Placeholder - real implementation would launch HIP/Vulkan kernel"
- Synchronization: "Placeholder - real implementation would sync device"

**CPU Device**: `src/cpu_device.f90`
- Kernel execution: "Execute kernel on CPU (placeholder for now)"
- Dispatch: "TODO: Implement kernel dispatch system"

**Action Required**:
- [ ] Connect AMD device to working AMDGPU direct implementation
- [ ] Connect CPU device to production convolution implementations

### 8. Working GPU Examples We Can Mine
Found working OpenGL code in:
- `examples/test_conv_cpu_vs_gpu.c/.f90` - [deferred throughput metric] convolution ✅
- `examples/test_gpu_minimal2.c` - Basic EGL setup
- `examples/test_glsl_debug.f90` - GLSL shader compilation
- `examples/test_simple_glsl_c.c` - Simple compute dispatch

These contain the patterns we need to extract!

### 9. Profile and Discovery Modules
**Profile**: `src/sporkle_profile.f90` - Has some placeholders
**Discovery**: `src/sporkle_discovery.f90` - Likely has detection mocks

**Action Required**:
- [ ] Check if device detection actually works
- [ ] Verify profiling gives real numbers vs fake ones

## Search Commands Used

```bash
# Find all mocks
grep -r "mock\|Mock\|MOCK\|fake\|placeholder\|not.*implemented" --include="*.f90" src/

# Find working GPU code in tests
grep -r "glCreateShader\|glDispatchCompute" --include="*.f90" --include="*.c" examples/

# Find performance claims
grep -r "GFLOPS\|TFLOPS" --include="*.f90" --include="*.md"
```

## Priority Order

1. **GPU Dispatch** - This is blocking everything
2. **Production Interface** - So conv2d_gpu actually works
3. **Memory Management** - Device allocation
4. **Shader Pipeline** - Connect parser to execution
5. **Backend Cleanup** - Remove non-OpenGL backends for now

## The Root Cause

This keeps happening because:
- We prototype in test files to get things working
- We create "proper" module structure with good intentions
- We never actually move the working code to the modules
- Tests keep working (using their local implementations)
- Production uses modules (full of mocks)

## Suggested Fix Process

For each item:
1. Locate the working implementation
2. Extract the minimal required code
3. Replace the mock with real implementation
4. Update any includes/dependencies
5. Test through production interface
6. Mark test code as "using production module"

## Verification

After cleanup, these should work:
```fortran
use sporkle_conv2d
call conv2d_gpu(...)  ! Should run at [deferred throughput metric]

use sporkle_gpu_dispatch  
call gpu_execute(...)  ! Should actually run on GPU
```

No more "MOCK: Not actually executing on GPU"!