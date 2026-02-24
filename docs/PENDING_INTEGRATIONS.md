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

## 2. Automatic Device Selection ✅ Built, ✅ Integrated

### What We Built
- `sporkle_conv2d_auto_selector.f90` - Heuristic-based device selection
- Performance learning with exponential moving average
- Automatic CPU/GPU selection based on workload

### Current Status
- ✅ Fully integrated into production
- ✅ Working in sporkle_conv2d_juggling
- ✅ Tested and validated

## 3. GPU Async Executor ✅ Built, ✅ Integrated

### What We Built
- `gpu_async_executor.f90` - Triple-buffered async execution
- 6.5x pipeline speedup demonstrated
- Fence-based synchronization

### Current Status
- ✅ Integrated with sporkle_conv2d_juggling
- ✅ Enabled by default
- ✅ Production ready

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

## 5. Direct AMDGPU PM4 Interface ✅ Built, ⚠️ Not Integrated

### What We Built
- `sporkle_amdgpu_direct.f90` - Direct kernel driver interface
- PM4 packet generation
- Memory management via GEM

### Current Status
- ✅ Basic infrastructure working
- ⚠️ Complex to integrate safely
- ⚠️ OpenGL path provides good performance already

### Integration Needed
1. Extensive testing on various RDNA GPUs
2. Shader binary compilation toolchain
3. Synchronization with OpenGL contexts
4. Production hardening

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

- **Fully Integrated**: 2 components (Auto-selection, Async executor)
- **Partially Integrated**: 1 component (Persistent kernels)
- **Built but Not Integrated**: 3 components (Dynamic shaders, PM4, Thread safety)
- **Designed but Not Built**: 0 components

## Priority Order for Integration

1. **Persistent Kernel Cache** - High impact, low risk
2. **Dynamic Shader System** - High impact, medium complexity
3. **Thread Safety** - Medium impact, low complexity
4. **PM4 Direct Submission** - High complexity, uncertain benefit

## Notes

- Each unintegrated component represents working code that could provide performance benefits
- Integration should be done incrementally with thorough testing
- Some components (like PM4) might remain experimental
- The persistent kernel cache is the closest to being production-ready

---

*This document should be updated whenever we build new components or complete integrations.*