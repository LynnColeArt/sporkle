# QA Findings Summary: Historical PM4 Findings

## Good News (Historical Context)
The historical PM4 work documented in this file showed real implementations for certain legacy paths.

### Real GPU Implementations Found:
1. **PM4 Direct Submission** (`sporkle_pm4_compute.f90`)
   - ✅ Real shader compilation via `pm4_compile_shader`
   - ✅ Loads actual RDNA3 ISA shaders
   - ✅ GPU memory allocation and VA mapping
   - ✅ Direct kernel submission

2. **RDNA3 ISA Shaders** (`sporkle_rdna3_shaders.f90`)
   - ✅ `get_simple_copy_shader()` - real GPU machine code
   - ✅ `get_vector_add_shader()` - real GPU machine code
   - ❌ Missing: `get_conv2d_shader()` - needs to be added

3. **AMDGPU Direct Interface** (`sporkle_amdgpu_direct.f90`)
   - ✅ `amdgpu_allocate_buffer` - real GPU memory allocation
   - ✅ `amdgpu_map_buffer` - CPU/GPU memory mapping
   - ✅ `amdgpu_map_va` - GPU virtual address mapping
   - ✅ Direct ioctl kernel interface

## The Problem (Legacy Status)
This report predates the Kronos-first production migration.
Legacy production files were not wired to direct-driver implementations, and placeholders remained in those historical paths.

## Fixes Applied:
1. ✅ Removed mock GPU OpenGL implementation (historical hardening milestone)
2. ✅ Fixed hardcoded shader address in `pm4_safe_submit.f90` to use `pm4_compile_shader` (historical hardening milestone)

## Still TODO:
1. Wire other production files to use real PM4/AMDGPU implementations
2. Add conv2d ISA shader to RDNA3 shaders module
3. Update memory allocation to use AMDGPU direct interface
4. Replace fake GPU pointers with real VA addresses

## Conclusion
The historical PM4 findings were useful for de-risking archival paths, but PM4 is not the active production target.
