> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Dynamic Shader Generation Approach

## Problem
We've been trying to use pre-compiled GCN3 shader binaries on RDNA 2/3 GPUs. This doesn't work due to different instruction encodings between architectures.

## Solution: Fortran-Native Dynamic Shader Generation
Write shaders as annotated Fortran subroutines. At runtime, translate to GLSL/OpenCL based on detected hardware, compile, and execute. No architecture-specific binaries needed!

### Implementation Steps

1. **Device Detection** (Already implemented)
   ```fortran
   device = amdgpu_open_device("/dev/dri/renderD129")
   device_id = get_device_id(device)  ! Returns 0x164E for Raphael
   ```

2. **Architecture Mapping**
   ```fortran
   select case(device_id)
   case(z'164E')  ! Raphael
     arch = "gfx1036"
   case(z'744C')  ! Navi 31
     arch = "gfx1100"
   ! ... etc
   end select
   ```

3. **Fortran Kernel Definition**
   ```fortran
   !@kernel(local_size_x=64, out_binding=0)
   pure elemental subroutine store_deadbeef(i, out)
     use iso_fortran_env
     integer(int32), value :: i
     integer(int32)        :: out
     out = int(z'DEADBEEF', int32)
   end subroutine
   ```

4. **Runtime Translation & Compilation**
   ```fortran
   ! Parse Fortran kernel and generate GLSL
   glsl_source = fortran_to_glsl("store_deadbeef")
   
   ! Compile GLSL (using our existing OpenGL infrastructure)
   shader = compile_glsl_compute(glsl_source)
   
   ! Or generate OpenCL C for specific architecture
   opencl_source = fortran_to_opencl("store_deadbeef", arch)
   ```

5. **Execution**
   ```fortran
   ! Simple API that handles everything
   call sporkle_compile_and_dispatch( &
     kernel = "store_deadbeef", &
     global_size = N, &
     args = (/ output_buffer /) &
   )
   ```

### Advantages
- **Write once in Fortran** - No GLSL/OpenCL/assembly knowledge needed
- **No pre-compiled binaries** - Generate optimal code at runtime
- **Architecture agnostic** - GLSL/OpenCL compilers handle GPU differences
- **Integrates with existing code** - Uses our working GLSL compute path
- **Future-proof** - Can evolve to SPIR-V/MLIR later

### Implementation Strategy
1. **Phase 1**: Simple Fortran→GLSL translator for basic kernels
2. **Phase 2**: Add OpenCL C generation for PM4 path
3. **Phase 3**: SPIR-V generation for maximum portability

### Example: Generated GLSL from Fortran
```glsl
#version 310 es
layout(local_size_x = 64) in;
layout(std430, binding = 0) buffer Out { uint out[]; };
void main() {
  uint i = gl_GlobalInvocationID.x;
  out[i] = 0xDEADBEEFu;
}
```

This approach is the "Sparkle way" - elegant, adaptive, and Fortran all the way down!