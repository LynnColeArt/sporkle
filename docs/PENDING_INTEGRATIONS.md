> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Pending Integrations Tracker

This document tracks components that have been built but not yet fully integrated into the production pipeline. Each entry includes what was built, why it's not integrated, and what's needed for integration.

## 1. Persistent Kernel Framework - Phase 1 & 2 ✅ Built, ⚠️ Partial Integration

### What We Built
- `gpu_program_cache.f90` - In-memory program caching with LRU eviction
- `gpu_program_cache_v2.f90` - Enhanced with binary persistence
- `gpu_binary_cache.f90` - OpenGL binary save/load operations
- `gpu_opengl_cached.f90` - Wrapper for transparent caching

### Current Status
- ✅ Infrastructure complete and tested
- ✅ Binary save/load working with 6KB files
- ✅ GPU model detection functioning
- ⚠️ Not connected to actual shader compilation
- ⚠️ Using reference implementation passthrough

### Integration Needed
1. Modify `gpu_opengl_interface.f90` to use cache for shader compilation
2. Update async executor to leverage cached programs
3. Connect `compile_func` callbacks to real OpenGL shader compilation
4. Test with production workloads

### Code Location
```fortran
! Currently in gpu_opengl_cached.f90:
gpu_execute_conv2d_cached = gpu_execute_conv2d_ref(...)  ! Just passthrough!

! Should be:
program_id = get_cached_program_v2(cache, shader_source, cache_key, compile_real_shader)
```

## 2. Automatic Device Selection ✅ Built, ⚠️ Recovery-Phased Integration

### What We Built
- `sporkle_conv2d_auto_selector.f90` - Heuristic-based device selection
- Performance learning with exponential moving average
- Automatic CPU/GPU selection based on workload

### Current Status
- ⚠️ Integrated into orchestration path, with recovery-mode verification pending
- ✅ Working in `sporkle_conv2d_juggling`
- ⚠️ Tested and validated under active Kronos telemetry only

## 3. GPU Async Executor ✅ Built, ⚠️ Recovery-Phased Integration

### What We Built
- `gpu_async_executor.f90` - Triple-buffered async execution
- [deferred speedup] pipeline throughput target
- Fence-based synchronization

### Current Status
- ✅ Integrated with `sporkle_conv2d_juggling`
- ⚠️ Enabled by default under recovery policy
- ⚠️ Production readiness is staged behind revalidated benchmarks

## 4. Dynamic Shader System ✅ Built, ⚠️ Not Integrated

### What We Built
- `sporkle_dynamic_shader_system.f90` - Runtime shader generation
- `sporkle_rdna_shader_generator.f90` - RDNA-optimized shaders
- Performance-based variant selection

### Current Status
- ✅ Infrastructure complete
- ⚠️ Not connected to GPU execution pipeline
- ⚠️ Would benefit from persistent kernel cache

### Integration Needed
1. Connect to GPU execution pipeline
2. Use program cache for generated variants
3. Add performance feedback loop
4. Test variant selection logic

## 5. Direct AMDGPU Interface (PM4 lineage) ✅ Built, ⚠️ Archived

### What We Built
- `sporkle_amdgpu_direct.f90` - Direct kernel driver interface used for research and archaeology
- PM4 packet-generation experiments
- Memory management via GEM

### Current Status
- ✅ Kernel driver access and PM4 experiments remain useful as historical reference
- ⚠️ Not in active production path after Kronos-first pivot
- ⚠️ Core PM4 stack is archived; no hardening/benchmark claims are active

### Integration Needed
1. Keep PM4 references as historical notes only
2. Document what, if anything, can be safely reused for diagnostics
3. Prioritize Kronos-native AMD/NVIDIA path verification

## 6. Thread Safety Enhancements ✅ Built, ⚠️ Not Integrated

### What We Built
- `gpu_program_cache_threadsafe.f90` - Thread-safe version with OpenMP
- Critical sections for cache modifications
- Atomic reference counting and statistics
- Thread-aware logging and diagnostics

### Current Status
- ✅ Implementation complete and tested
- ✅ OpenMP critical sections working
- ✅ Atomic operations for counters
- ⚠️ Not integrated with production pipeline
- ⚠️ Original cache still used in sporkle_conv2d

### Integration Needed
1. Replace gpu_program_cache_v2 usage with thread-safe version
2. Update async executor for thread safety
3. Test with production multi-threaded workloads
4. Benchmark performance impact

## Summary Statistics

- **Fully Integrated**: 0 components with final production validation complete
- **Partially Integrated**: 3 components (Auto-selection, Async executor, Persistent kernels)
- **Built but Not Integrated**: 2 active components (Dynamic shaders, Thread safety)
- **Designed but Not Built**: 0 components

## Priority Order for Integration

1. **Persistent Kernel Cache** - High impact, low risk
2. **Dynamic Shader System** - High impact, medium complexity
3. **Thread Safety** - Medium impact, low complexity
4. **Kronos-native NVIDIA path** - High priority once AMD and Apple paths are stable

## Notes

- Each unintegrated component represents working code that could provide performance benefits
- Integration should be done incrementally with thorough testing
- PM4 components are archived and non-production
- The persistent kernel cache is the closest to Kronos-first integration readiness

---

*This document should be updated whenever we build new components or complete integrations.*
