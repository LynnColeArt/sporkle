# Neo Geo Performance Audit - AMD Stack

> Historical optimization notes; behavior here reflects legacy PM4/OpenGL comparison paths and should be revalidated under the active Kronos-first runtime.

## Core Philosophy
Like the Neo Geo's direct hardware access, we eliminate unnecessary abstractions while keeping core algorithms platform-agnostic.

## Current Stack Analysis

### 1. GPU Dispatch Path (Current: ~50µs overhead)
**Current Flow:**
```
sporkle_conv2d → GPU dispatch → OpenGL/Vulkan → Driver → Kernel → Hardware
```

**Neo Geo Flow:**
```
sporkle_conv2d → PM4 packets → Ring buffer → Hardware
```

**Overhead Sources:**
- Driver validation: ~20µs
- API translation: ~15µs  
- Kernel mode switch: ~10µs
- Synchronization: ~5µs

### 2. Juggler Pattern (sporkle_conv2d_juggling)
**Good (Keep):**
- Double buffering for CPU/GPU overlap
- State machine for buffer management
- Platform-agnostic algorithm

**Improve:**
- Replace glFinish with fence-based sync
- Use persistent mapped buffers
- Eliminate per-frame allocations

### 3. Autotuner (sporkle_autotuner_enhanced)
**Good (Keep):**
- Hardware-agnostic tuning logic
- Performance measurement framework
- Parameter search algorithms

**Improve:**
- Cache tuning results per GPU
- Reduce warmup iterations
- Skip redundant measurements

## Reusable Core Components

### 1. Universal Memory Patterns
```fortran
! This pattern is intended as reusable intent across hardware classes; compatibility is still staged and runtime-specific
type :: compute_buffer
  integer :: size
  integer :: stride  
  logical :: is_ready
  ! Platform handles (union/select)
  integer(c_intptr_t) :: gpu_handle
  real(c_float), pointer :: cpu_ptr(:)
end type
```

### 2. Platform-Agnostic Dispatcher
```fortran
! Core algorithm independent of GPU API
subroutine dispatch_compute(buffers, kernel_id, workgroups)
  ! Neo Geo path
  if (use_direct_submit) then
    call build_pm4_commands(...)
    call submit_ring_buffer(...)
  ! Safe fallback  
  else
    call dispatch_via_api(...)
  end if
end subroutine
```

### 3. Unified Performance Measurement
```fortran
! Works across all platforms
type :: perf_measurement
  real(rk64) :: start_time
  real(rk64) :: end_time
  integer(i64) :: flop_count
  integer(i64) :: bytes_moved
end type
```

## Implementation Priority

### Phase 1: AMD Direct Path (Neo Geo Style)
1. ✅ PM4 packet generation
2. ⬜ Ring buffer management
3. ⬜ Fence-based synchronization
4. ⬜ Direct memory allocation

### Phase 2: Optimize Existing Components  
1. ⬜ Juggler with zero-copy buffers
2. ⬜ Autotuner with cached results
3. ⬜ Persistent shader compilation

### Phase 3: Platform Abstraction
1. ⬜ Unified buffer management
2. ⬜ Cross-platform kernel format
3. ⬜ Performance portability layer

## Expected Gains

**Current Stack:**
- OpenGL: 2,000 GFLOPS (5% efficiency)
- Vulkan: 1,800 GFLOPS (4.5% efficiency)

**With Neo Geo Optimizations:**
- Phase 1: 8,000 GFLOPS (20% efficiency) - Direct submission
- Phase 2: 12,000 GFLOPS (30% efficiency) - Zero overhead juggling
- Phase 3: 16,000 GFLOPS (40% efficiency) - Full optimization

**Realistic Target: 25-30% efficiency (10,000-12,000 GFLOPS)**

## Key Insights

1. **Driver overhead dominates** - Even 10% reduction is huge win
2. **Memory patterns are universal** - Same optimizations work everywhere  
3. **Juggling/autotuning are solid** - Just need lower-level implementation
4. **Platform differences are small** - 90% of code can be shared

## Next Steps

1. Implement fence-based sync for juggler (immediate 2x speedup)
2. Add PM4 fast path for hot kernels  
3. Create unified buffer abstraction
4. Document patterns for other platforms (Apple Metal, Intel, etc)

Remember: We're not trying to beat CUDA. We're trying to make every GPU useful!
