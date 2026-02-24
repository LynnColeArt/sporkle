# Sprint 2: Zero-Copy Buffer Management

> This sprint documentation is historical and archived while the project follows the Kronos-first production path.
> Numeric targets are retained as historical reference and are not active production guarantees.

## Goal
Historically, this sprint targeted reduced CPU↔GPU copy overhead and memory churn using zero-copy buffers.

## Background
Currently copying data to staging buffers. With persistent mapped buffers, CPU can write directly to GPU memory.

---

## Task 2.1: Research Persistent Mapped Buffers
**Description:** Study platform-specific persistent mapping mechanisms

**Subtasks:**
- [ ] Research GL_ARB_buffer_storage
- [ ] Investigate AMD pinned memory
- [ ] Study Vulkan host-visible memory
- [ ] Analyze cache coherency implications

**Acceptance Criteria:**
- Technical report on mapping strategies
- Platform capability detection code
- Decision matrix for buffer types
- Cache performance measurements

**Time Estimate:** 1 day

---

## Task 2.2: Design Unified Buffer Abstraction
**Description:** Create platform-agnostic buffer interface

**Subtasks:**
- [ ] Design buffer allocation API
- [ ] Define mapping strategies
- [ ] Plan fallback mechanisms
- [ ] Create buffer lifecycle docs

**Acceptance Criteria:**
- buffer_abstraction_design.md complete
- API handles all platforms elegantly
- Clear ownership semantics
- Migration path from current buffers

**Interface Example:**
```fortran
type :: unified_buffer
  integer(i64) :: size
  integer :: usage_flags
  type(c_ptr) :: cpu_ptr
  integer(c_intptr_t) :: gpu_handle
  logical :: is_coherent
  logical :: is_mapped
end type

abstract interface
  function create_unified_buffer(size, flags) result(buffer)
    integer(i64), intent(in) :: size
    integer, intent(in) :: flags
    type(unified_buffer) :: buffer
  end function
end interface
```

**Time Estimate:** 1 day

---

## Task 2.3: Implement Persistent Mapped Buffers
**Description:** Create zero-copy buffer implementation for OpenGL

**Subtasks:**
- [ ] Implement buffer storage creation
- [ ] Add persistent mapping support
- [ ] Handle coherent vs non-coherent
- [ ] Create memory barrier utilities

**Acceptance Criteria:**
- New module: gpu_zero_copy_buffers.f90
- Supports PERSISTENT|COHERENT flags
- Automatic fallback if unsupported
- Memory barriers where needed
- Benchmarks show zero copy overhead

**Code Example:**
```fortran
function create_persistent_buffer(size) result(buffer)
  integer(i64), intent(in) :: size
  type(unified_buffer) :: buffer
  
  ! Try persistent+coherent first
  buffer = try_create_buffer(size, &
    GL_MAP_WRITE_BIT + GL_MAP_PERSISTENT_BIT + GL_MAP_COHERENT_BIT)
  
  if (.not. buffer%is_mapped) then
    ! Fallback to traditional
    buffer = create_staging_buffer(size)
  end if
end function
```

**Time Estimate:** 2 days

---

## Task 2.4: Update Conv2D to Use Zero-Copy
**Description:** Modify convolution to use unified buffers

**Subtasks:**
- [ ] Replace staging buffers
- [ ] Update data writing patterns
- [ ] Add memory barriers
- [ ] Optimize for cache lines

**Acceptance Criteria:**
- sporkle_conv2d.f90 uses unified buffers
- Zero memcpy calls in hot path
- Cache-aligned write patterns
- Performance improvement measured
- Correctness tests still pass

**Performance Target:**
```
Before: CPU write → staging → GPU copy → compute
After:  CPU write → compute (direct to GPU memory)
Expected: 1.5x speedup on small buffers
```

**Time Estimate:** 2 days

---

## Task 2.5: Platform-Specific Optimizations
**Description:** Add vendor-specific improvements

**Subtasks:**
- [ ] AMD: Use VRAM with CPU access
- [ ] Intel: Optimize for shared memory
- [ ] Mobile: Handle limited mappings
- [ ] Add platform detection

**Acceptance Criteria:**
- Platform optimizations documented
- Automatic selection of best path
- Graceful degradation
- No performance regressions
- Works on 5+ GPU models

**Time Estimate:** 1 day

---

## Task 2.6: Stress Testing and Validation
**Description:** Ensure zero-copy is robust under load

**Subtasks:**
- [ ] Create memory pressure tests
- [ ] Test with multiple contexts
- [ ] Verify under fragmentation
- [ ] Profile actual vs theoretical

**Acceptance Criteria:**
- 24-hour stress test passes
- No memory leaks detected
- Performance stable under pressure
- Handles OOM gracefully
- Profile shows zero copies

**Test Suite:**
```fortran
! Must handle memory pressure
call test_zero_copy_under_memory_pressure()
! Must work with many buffers
call test_zero_copy_fragmentation()
! Must show performance gain
call benchmark_zero_copy_performance()
```

**Time Estimate:** 1 day

---

## Sprint Summary

**Total Time:** 8 days

**Definition of Done:**
- [ ] Zero memcpy in conv2d hot path (historical target)
- [ ] 1.5x performance gain (historical target)
- [ ] Works on AMD, Intel, NVIDIA (historical target)
- [ ] No stability regressions
- [ ] Documentation complete

**Success Metrics (historical target):**
- Memory bandwidth: 50% reduction
- Small buffer latency: 10µs → 2µs
- Cache misses: 80% reduction
- Total speedup: 3x with fences (historical estimate)

**Risk Mitigation:**
- Non-coherent memory: Add explicit flushes
- Limited mappings: Use buffer pool
- Platform issues: Automatic fallback
- Cache problems: Align to 64 bytes

**Next Sprint Preview:** PM4 Direct Submission
- Build on fence + zero-copy foundation
- Bypass driver completely
- Expected 4x additional speedup (historical estimate)
