# Sprint 4: Legacy Code Cleanup Plan

## Overview
Archive PM4, OpenGL, and legacy Vulkan implementations while preserving them for historical reference.

## Directory Structure
```
attic/
├── pm4_attempt/          # The PM4 native execution attempt
├── opengl_backend/       # Working OpenGL implementation (3,630 GFLOPS)
├── vulkan_stubs/         # Incomplete Vulkan implementation
└── README.md            # Explanation of archived code
```

## Files to Archive

### PM4 Implementation (~90 files)
**Core Implementation:**
- `src/sporkle_pm4_*.f90`
- `src/production/pm4_*.f90`
- `src/production/sporkle_gpu_dispatch_pm4.f90`
- `src/production/intelligent_device_juggling_pm4.f90`
- `src/core/pm4_constants.h`
- `src/production/pm4_submit_impl.c`

**Tests:**
- `tests/test_pm4_*.f90` (40+ test files)
- `examples/test_*pm4*.f90`
- `tests/test_intelligent_juggling_pm4.f90`

**Build Artifacts:**
- `*.mod` and `*.o` files for PM4 modules
- `scripts/build_pm4_test.sh`
- `scripts/debug/debug_pm4_*.sh`

### OpenGL Backend (Working implementation to preserve!)
**Core Files:**
- `src/production/gpu_opengl_interface.f90` ⭐ (main implementation)
- `src/production/gpu_opengl_interface_fence.f90`
- `src/production/gpu_opengl_cached.f90`
- `src/production/gpu_opengl_zero_copy.f90`
- `src/reference/gpu_opengl_interface.f90`
- `src/reference/gpu_opengl_reference.c`

### Vulkan Stubs
**Incomplete Implementation:**
- `src/production/gpu_vulkan_backend.c`
- `src/production/gpu_vulkan_interface.f90`
- `src/production/vulkan_buffer_utils.c`
- `src/production/vulkan_timing.c`

### GLSL Shaders
- Any GLSL shader files (to be replaced with SPIR-V)
- GLSL generator modules

## Archive Strategy

### Phase 1: Create Archive Structure
```bash
mkdir -p attic/{pm4_attempt,opengl_backend,vulkan_stubs}
```

### Phase 2: Move Files with Git
```bash
# PM4 files
git mv src/sporkle_pm4_*.f90 attic/pm4_attempt/
git mv src/production/pm4_*.f90 attic/pm4_attempt/
# ... etc

# OpenGL files (preserve carefully - this works!)
git mv src/production/gpu_opengl_*.f90 attic/opengl_backend/

# Vulkan stubs
git mv src/production/gpu_vulkan_*.* attic/vulkan_stubs/
```

### Phase 3: Update Build System
- Remove PM4 modules from Makefile
- Remove OpenGL detection/linking (to be replaced by Kronos)
- Remove Vulkan stub references

### Phase 4: Clean Build Artifacts
```bash
# Remove all .mod and .o files
find . -name "*.mod" -o -name "*.o" | grep -E "(pm4|opengl|vulkan)" | xargs rm -f
```

### Phase 5: Document the Archive
Create `attic/README.md` explaining:
- Why each implementation was archived
- What we learned from each attempt
- Performance numbers achieved
- Links to relevant commits/discussions

## Important Notes

1. **OpenGL Backend**: This is our current working implementation (3,630 GFLOPS). Archive it carefully as it's our performance baseline!

2. **PM4 Documentation**: The PM4 debugging journey taught us valuable lessons. Preserve key learnings in the archive README.

3. **Build System**: After archiving, the only GPU backend should be Kronos.

4. **Git History**: Use `git mv` to preserve file history in the archive.

## Success Criteria

After cleanup:
- [ ] No PM4 files in active source directories
- [ ] No OpenGL dependencies in build system
- [ ] No Vulkan stub files in production
- [ ] Clean build with only CPU + Kronos backends
- [ ] Comprehensive archive documentation
- [ ] All tests pass with Kronos backend

## Timeline

- Hour 1-2: Create archive structure and documentation
- Hour 3-4: Move PM4 files
- Hour 5: Move OpenGL files
- Hour 6: Move Vulkan stubs
- Hour 7: Update build system
- Hour 8: Test and verify