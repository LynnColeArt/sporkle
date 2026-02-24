> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Persistent Kernel Framework - Phase 1 (Historical Prototype)

## Summary

Phase 1 of the persistent kernel framework is a reusable prototype and is not yet active production integration.

## What We Built

### 1. **GPU Program Cache Module** (`gpu_program_cache.f90`)
- In-memory caching of compiled GPU programs (prototype)
- Reference counting for lifecycle ownership tracking
- LRU eviction policy when cache capacity is exceeded
- Statistics tracking for staged runtime validation
- Clean API intended for future integration

### 2. **Cached GPU Interface** (`gpu_opengl_cached.f90`)
- Wraps the reference GPU implementation
- Adds a staged caching layer
- Keeps compatibility with the existing GPU interface shape
- Prepared for Phase 2 binary persistence

### 3. **Comprehensive Test Suite**
- `test_program_cache.f90`: Unit tests for cache operations
- `test_persistent_kernels.f90`: Integration test scaffold with placeholders

## Performance Output (Deferred)

```
Average time: [deferred latency]
Average performance: [deferred throughput metric]
```

The framework is structured to support:
- Reduced recompilation between runs
- Faster application startup once cache validity is stable
- Reduced memory pressure
- Better performance predictability targets

## Architecture

```
┌─────────────────────┐
│   Application Code  │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ gpu_opengl_cached   │ ← New caching layer
├─────────────────────┤
│ • Transparent cache │
│ • Same API         │
│ • Stats tracking   │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ gpu_program_cache   │ ← Core cache implementation
├─────────────────────┤
│ • Reference count  │
│ • LRU eviction    │
│ • Cache stats     │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│gpu_opengl_interface │ ← Existing GPU interface
└─────────────────────┘
```

## Key Features Implemented

### Reference Counting
```fortran
! Safe program lifecycle management
cache%entries(idx)%ref_count = cache%entries(idx)%ref_count + 1
```

### LRU Eviction
```fortran
! Automatically evict least recently used programs
if (cache%num_entries >= cache%max_entries) then
  call evict_lru(cache)
end if
```

### Performance Tracking
```fortran
! Track compilation time saved
Total compile time saved: [deferred time]
Estimated memory usage: [deferred size]
```

## Integration Points

### With Async Executor
The cache is staged for async executor integration when benchmark baselines are stable:
- Cache programs across async operations
- Share compiled kernels between buffer sets
- Eliminate redundant compilations

### With Dynamic Shader System
Future integration will allow:
- Caching of dynamically generated shaders
- Performance-based shader selection
- Automatic variant management

## Next Steps (Phase 2-4)

### Phase 2: Binary Persistence (Next)
- Implement `glGetProgramBinary` / `glProgramBinary`
- Save compiled shaders to disk
- GPU-specific cache directories
- Automatic cache invalidation

### Phase 3: Lifecycle Management
- Memory pressure handling
- Cache warming strategies
- Startup preloading
- Advanced eviction policies

### Phase 4: Full Integration
- Complete async executor integration
- Dynamic shader system integration
- Performance regression tests
- Production deployment

## Code Quality

The implementation follows Sparkle's principles:
- **Think Python, Write Fortran**: Clean, readable code
- **Explicit is Better**: Clear lifecycle management
- **Performance First**: Designed for speed
- **Universal Principles**: Ready for CPU/GPU/AI accelerators

## Testing

Coverage is present for staged validation:
- 7 unit tests for cache operations
- Integration test with real GPU workloads (scope-limited)
- Performance benchmarking placeholders
- Statistics validation scaffolding

## Conclusion

Phase 1 establishes a historical foundation for persistent kernels in Sparkle. The framework is:
- ✅ Functional prototype complete
- ⚠️ Unit coverage exists
- ⚠️ Performance revalidation pending
- ⚠️ Production-ready only after re-benchmarking under Kronos-first runtime

With this foundation, we're ready to implement binary persistence and re-validate the goal of "compile once, run forever" under stable dispatch.

---

*Lynn, this implementation captures the historical cache architecture. Performance claims are deferred until active benchmarks are re-run.*
