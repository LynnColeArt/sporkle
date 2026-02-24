> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Action Plan: Resolve Circular Dependencies & Build Issues

## Priority 1: Circular Dependencies (MUST FIX)

### 1. Map the Dependency Graph
```bash
# Create a dependency visualization
grep -h "^\s*use " src/**/*.f90 | sort | uniq > module_dependencies.txt
```

**Expected circular patterns:**
- `sporkle_types` ↔ `sporkle_memory` 
- `gpu_dispatch` ↔ `gpu_async_executor`
- `universal_memory_optimization` ↔ `cpu_conv2d_reference`

### 2. Break Circular Dependencies

**Strategy A: Extract Common Types**
```fortran
! Before: sporkle_types depends on sporkle_memory
! After: Both depend on sporkle_base_types

module sporkle_base_types
  ! Only fundamental types, no dependencies
  type :: memory_handle
  type :: device_info
end module

module sporkle_types
  use sporkle_base_types  ! One-way dependency
  ! Higher level types
end module

module sporkle_memory
  use sporkle_base_types  ! One-way dependency
  ! Memory operations
end module
```

**Strategy B: Use Interfaces**
```fortran
! Define interfaces in separate module
module sporkle_interfaces
  abstract interface
    ! Function signatures only
  end interface
end module
```

**Strategy C: Dependency Inversion**
- Move implementations to separate modules
- Keep interfaces minimal
- Use dependency injection patterns

## Priority 2: Module Organization

### Current Problems:
1. **Duplicate modules** (production/ vs src/)
2. **Missing module hierarchy**
3. **Unclear dependencies**

### Solution: Layered Architecture
```
Layer 0: Base (no dependencies)
  - kinds.f90
  - constants.f90
  - base_types.f90

Layer 1: Core (depends only on Layer 0)
  - error_handling.f90
  - memory_base.f90
  - time_utils.f90

Layer 2: Platform (depends on 0-1)
  - gpu_types.f90
  - cpu_types.f90
  - platform_detect.f90

Layer 3: Implementation (depends on 0-2)
  - memory_cpu.f90
  - memory_gpu.f90
  - kernels_cpu.f90
  - kernels_gpu.f90

Layer 4: High-level (depends on 0-3)
  - conv2d.f90
  - gemm.f90
  - optimizations.f90
```

## Priority 3: Build System Fix

### Create Proper Makefile with Dependency Tracking
```makefile
# Auto-generate dependencies
%.d: %.f90
	@$(FC) -MM -cpp $< > $@

# Include all dependency files
-include $(DEPS)

# Build in correct order
all: layer0 layer1 layer2 layer3 layer4
```

## Morning Action Items

### Hour 1: Dependency Analysis
1. Run dependency mapping script
2. Create visual dependency graph
3. Identify all circular dependencies
4. Document which modules are entangled

### Hour 2: Extract Base Types
1. Create `sporkle_base_types.f90` with zero dependencies
2. Move fundamental types from other modules
3. Update dependent modules to use base types
4. Verify no circular refs in base layer

### Hour 3: Fix One Circular Dependency
1. Start with the simplest cycle
2. Apply extraction/interface pattern
3. Test compilation of affected modules
4. Document the fix pattern

### Hour 4: Build System
1. Create layered Makefile
2. Add automatic dependency generation
3. Test incremental builds
4. Ensure correct build order

## Quick Wins for Tomorrow

1. **Find duplicate modules**
   ```bash
   find . -name "*.f90" -exec basename {} \; | sort | uniq -d
   ```

2. **Create module hierarchy diagram**
   ```bash
   # List all modules with their dependencies
   for f in src/**/*.f90; do
     echo "=== $f ==="
     grep "^\s*use " "$f" | grep -v "intrinsic"
   done
   ```

3. **Identify standalone modules** (can compile independently)
   - These become Layer 0/1
   - Build these first
   - Others depend on them

## Success Criteria

✅ No circular dependencies (verified by build order)
✅ Clean module hierarchy (documented in ARCHITECTURE.md)
✅ All modules compile in dependency order
✅ Performance tests run without stubs
✅ CI/CD can build everything

## Notes

The circular dependency problem is architectural debt that's been hidden by the build system. The refactoring exposed it, which is actually good - now we can fix it properly.

Remember: **Every module should have a clear "level" in the hierarchy**. If Module A is level 2, it can only depend on modules in levels 0-1, never on level 2+ modules.

---

*Rest well, Lynn! Tomorrow we'll untangle this spaghetti and make it clean. The refactoring work we did today was solid - these dependency issues existed before, we just exposed them.* 🌙