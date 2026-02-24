> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Persistent Kernel Framework Design

## Overview

The Persistent Kernel Framework aims to eliminate redundant shader compilation and reduce kernel launch overhead by keeping GPU compute programs resident in memory and on disk. This builds on our async executor to provide even higher performance.

## Current State Analysis

### What We Have Now
- **Single Program Model**: One global `g_compute_program` compiled at initialization
- **Per-Session Compilation**: Shaders recompiled every run
- **Async Executor**: Triple-buffered execution with [deferred speedup] speedup
- **Dynamic Shader System**: Generates variants but doesn't persist them

### Performance Impact
- **Compilation Time**: ~50-[deferred latency] per shader (one-time cost per run)
- **Program Switching**: ~[deferred latency] overhead when changing kernels
- **Memory Pressure**: Each program uses ~100KB GPU memory
- **Startup Time**: Could be reduced by 90% with cached binaries

## Design Goals

1. **Zero Recompilation**: Compile shaders once, reuse forever
2. **Fast Startup**: Load pre-compiled binaries from disk
3. **Multi-Program Support**: Keep multiple kernels ready simultaneously
4. **Automatic Management**: LRU eviction, reference counting
5. **Seamless Integration**: Works with existing async executor

## Architecture

### 1. Program Cache Layer

```fortran
type :: program_cache_entry
  integer :: program_id          ! OpenGL program object
  character(len=256) :: key      ! Unique identifier
  integer :: ref_count           ! Active references
  integer(int64) :: last_used    ! Timestamp for LRU
  integer(int64) :: compile_time ! Time taken to compile
  real(real32) :: performance    ! Measured GFLOPS
  logical :: is_binary_cached    ! Saved to disk?
end type

type :: program_cache
  type(program_cache_entry), allocatable :: entries(:)
  integer :: num_entries
  integer :: max_entries
  character(len=256) :: cache_dir
  logical :: auto_save
end type
```

### 2. Binary Cache System

```fortran
! Save compiled program to disk
subroutine save_program_binary(program_id, cache_key)
  ! Use glGetProgramBinary to extract compiled code
  ! Save to: cache_dir/GPU_MODEL/cache_key.spv
end subroutine

! Load pre-compiled program
function load_program_binary(cache_key) result(program_id)
  ! Check if binary exists for current GPU
  ! Use glProgramBinary to load
  ! Falls back to compilation if load fails
end function
```

### 3. Program Lifecycle

```
[Shader Request] → [Check Memory Cache] → [Found?]
                                            ├─Yes→ [Increment Ref] → [Return Program]
                                            └─No→ [Check Disk Cache] → [Found?]
                                                                        ├─Yes→ [Load Binary] → [Add to Memory] → [Return]
                                                                        └─No→ [Compile] → [Save Binary] → [Add to Memory] → [Return]
```

### 4. Integration Points

#### With Async Executor
```fortran
type :: gpu_async_state
  ! Existing fields...
  
  ! New persistent kernel support
  integer :: active_program      ! Currently bound program
  type(program_cache) :: cache   ! Kernel cache
end type
```

#### With Dynamic Shader System
- Dynamic shader generates source → Persistent kernel compiles & caches
- Performance data feeds back to both systems
- Shader variants map to different cache entries

## Implementation Plan

### Phase 1: In-Memory Cache (Week 1)
1. Create program_cache module
2. Implement basic cache operations (add, find, evict)
3. Add reference counting
4. Integrate with gpu_opengl_interface

### Phase 2: Binary Persistence (Week 1-2)
1. Implement glGetProgramBinary/glProgramBinary wrappers
2. Create disk cache structure
3. Add GPU model detection for cache invalidation
4. Implement save/load routines

### Phase 3: Lifecycle Management (Week 2)
1. Automatic eviction (LRU)
2. Memory pressure handling
3. Startup preloading
4. Cache warming strategies

### Phase 4: Integration (Week 2-3)
1. Update async executor
2. Modify sporkle_conv2d to use cache
3. Add performance metrics
4. Create tests

## API Design

### Basic Usage
```fortran
! Initialize cache
call init_program_cache(cache, max_programs=100, cache_dir="shader_cache/")

! Get program (loads from cache or compiles)
program_id = get_cached_program(cache, shader_source, cache_key)

! Use program
call glUseProgram(program_id)
! ... dispatch compute ...

! Release reference
call release_program(cache, program_id)

! Cleanup
call cleanup_program_cache(cache)
```

### Advanced Features
```fortran
! Preload common kernels at startup
call preload_kernel_cache(cache, ["conv2d_3x3", "conv2d_5x5", "gemm_small"])

! Save all compiled programs to disk
call persist_cache_to_disk(cache)

! Get cache statistics
call print_cache_stats(cache)
! Output: 15 programs cached, 12 on disk, 150MB saved, 95% hit rate

! Clear old/unused entries
call prune_cache(cache, max_age_days=30)
```

## Performance Targets

- **Startup Time**: < [deferred latency] (vs [deferred latency]+ currently)
- **Program Switch**: < [deferred latency] ([deferred speedup] improvement)
- **Memory Usage**: < 50MB for 100 cached programs
- **Cache Hit Rate**: > 95% after warmup
- **Binary Load Time**: < [deferred latency] per program

## File Structure

```
shader_cache/
├── AMD_RX_7900_XT/
│   ├── manifest.json
│   ├── conv2d_3x3_256x256.spv
│   ├── conv2d_3x3_256x256.meta
│   └── ...
├── NVIDIA_RTX_4090/
│   └── ...
└── cache_stats.json
```

## Error Handling

1. **Binary Format Mismatch**: Fall back to compilation
2. **Disk Cache Corruption**: Regenerate affected entries
3. **Memory Pressure**: Evict LRU entries
4. **GPU Change**: Invalidate incompatible cache
5. **Compilation Failure**: Return error, don't cache

## Testing Strategy

1. **Unit Tests**
   - Cache operations (add, find, evict)
   - Binary save/load
   - Reference counting

2. **Integration Tests**
   - With async executor
   - Performance benchmarks
   - Multi-program scenarios

3. **Stress Tests**
   - Cache thrashing
   - Memory limits
   - Concurrent access

## Success Metrics

- ✅ Zero shader recompilation across runs
- ✅ Sub-[deferred latency] startup time
- ✅ Seamless integration with existing code
- ✅ Staged performance impact target ([deferred speedup range]) under active kernel replay
- ✅ Error handling staged for active Kronos runtime verification

## Future Extensions

1. **Network Cache**: Share compiled shaders across machines
2. **Cloud Backup**: Store rare variants in cloud storage
3. **AOT Compilation**: Pre-compile for common GPUs
4. **Profile-Guided Optimization**: Use runtime data to optimize
5. **Shader Compression**: Reduce disk usage

## References

- OpenGL 4.6 Spec: `glGetProgramBinary`, `glProgramBinary`
- ARB_get_program_binary extension
- Our async executor: `gpu_async_executor.f90`
- Dynamic shader system: `sporkle_dynamic_shader_system.f90`
