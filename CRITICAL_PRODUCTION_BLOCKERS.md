# Critical Production Blockers

> Historical blocker audit snapshot; re-run against the current Kronos-first runtime before using these as active evidence.

## 1. Mock GPU Implementation (FIXED)
- **File:** `src/sporkle_gpu_opengl.f90` 
- **Status:** ✅ REMOVED
- **Issue:** Entire GPU path was fake, all operations simulated on CPU

## 2. Placeholder Shader Implementations
- **File:** `src/production/gpu_dynamic_shader_cache.f90`
- **Lines:** 207, 257
- **Issue:** Returns `"// Dynamic shader placeholder"` instead of real shaders
- **Impact:** No actual GPU compute kernels can run

## 3. Hardcoded Shader Address
- **File:** `src/production/pm4_safe_submit.f90`
- **Line:** 190
- **Issue:** `params%shader_addr = int(z'1000000', i64)  ! Placeholder`
- **Impact:** GPU will try to execute code at invalid address

## 4. No Device Memory Allocation
- **Files:** 
  - `src/production/sporkle_memory.f90:164`
  - `src/production/memory_pool_reference.f90:181`
- **Issue:** "Device memory allocation not yet implemented - using placeholder"
- **Impact:** Cannot allocate GPU memory

## 5. Missing Buffer Free Functions
- **Files:**
  - `src/production/pm4_safe_submit.f90` (3 instances)
  - `src/production/gpu_ring_buffer.f90` (4 instances)
- **Issue:** Multiple "TODO: need buffer free function"
- **Impact:** Memory leaks guaranteed

## 6. Fake GPU Pointers
- **File:** `src/production/sporkle_gpu_dispatch.f90:201`
- **Issue:** `mem%gpu_ptr = int(loc(mem), int64)  ! Fake GPU pointer for now`
- **Impact:** Using CPU addresses as GPU addresses will crash

## 7. Not Implemented Functions
- **Shader Cache:** `save_cache()` and `load_cache()` just print "not implemented"
- **GPU Async:** Returns `-1.0` with "Not implemented yet"
- **Hybrid Execution:** TODO in `intelligent_device_juggling.f90`

## 8. Hardcoded Hardware Detection
- **Issue:** Returns hardcoded "AMD Ryzen 7 7700X" instead of actual detection
- **Impact:** Wrong optimizations for different hardware

## IMMEDIATE ACTIONS REQUIRED

1. ✅ Remove mock GPU implementation
2. ❌ Implement real shader compilation or load pre-compiled shaders
3. ❌ Fix hardcoded shader address - use actual shader upload
4. ❌ Implement device memory allocation
5. ❌ Add buffer free functions
6. ❌ Fix fake GPU pointers
7. ❌ Implement hardware detection

## STATUS: NOT PRODUCTION READY (historical)

The GPU path was previously non-functional due to placeholders and mocks; this file remains a historical blocker catalog and should not be treated as current project status.
