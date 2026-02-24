# Sprint 3: PM4 Direct Submission Path

> This sprint is archived for PM4 reference only.
> The active production path is Kronos-first, so PM4 metrics in this document are historical targets, not active guarantees.

## Goal
Historical reference goal: reduce PM4 submission overhead through direct command-path experimentation.

## Background
Historical analysis described driver overhead around 45µs with lower-latency PM4 targets.

⚠️ **SAFETY CRITICAL**: This sprint involves direct hardware access. All tasks must prioritize system stability.

---

## Task 3.1: Ring Buffer Infrastructure
**Description:** Create safe ring buffer allocation and management

**Subtasks:**
- [ ] Design ring buffer allocation strategy
- [ ] Implement GPU memory mapping for ring
- [ ] Create ring buffer write utilities
- [ ] Add overflow protection

**Acceptance Criteria:**
- Ring buffer module with safety checks
- Never overwrites unprocessed commands
- Automatic wrap-around handling
- Overflow triggers graceful recovery
- Maps to user space successfully

**Safety Requirements:**
```fortran
type :: ring_buffer_manager
  integer(i64) :: size = 65536  ! 64KB default
  integer :: write_ptr = 0
  integer :: read_ptr = 0
  logical :: is_full = .false.
  type(c_ptr) :: mapped_ptr
  
  contains
    procedure :: can_write
    procedure :: write_packet
    procedure :: update_pointers
end type
```

**Time Estimate:** 3 days

---

## Task 3.2: PM4 Command Builder for Conv2D
**Description:** Generate optimal PM4 packets for convolution

**Subtasks:**
- [ ] Extend PM4 builder for conv2d
- [ ] Optimize packet sequences
- [ ] Add shader state caching
- [ ] Minimize packet count

**Acceptance Criteria:**
- PM4 packets for complete conv2d
- <100 dwords per dispatch
- Shader state cached across calls
- Packets validated before submission
- Matches OpenGL functionality

**Packet Optimization:**
```fortran
! Current: ~200 dwords per dispatch
! Target: <100 dwords by:
! - Caching shader state
! - Combining register writes
! - Eliminating redundant barriers
```

**Time Estimate:** 2 days

---

## Task 3.3: Safe Command Submission
**Description:** Implement protected GPU command submission

**Subtasks:**
- [ ] Add submission safety checks
- [ ] Implement timeout mechanism
- [ ] Create recovery procedures
- [ ] Add debug submission mode

**Acceptance Criteria:**
- GPU hang detection < 100ms
- Automatic recovery without reboot
- Debug mode validates all packets
- Clear error reporting
- Kill switch for emergencies

**Safety Framework:**
```fortran
function submit_pm4_safe(packets, count) result(success)
  integer(i32), intent(in) :: packets(:)
  integer, intent(in) :: count
  logical :: success
  
  ! Safety checks
  if (.not. validate_packets(packets, count)) return
  if (gpu_is_hung()) call reset_gpu()
  
  ! Submit with timeout
  call submit_with_timeout(packets, count, timeout_ms=100)
  
  ! Verify completion
  success = verify_gpu_progress()
end function
```

**Time Estimate:** 3 days

---

## Task 3.4: Fence Integration for PM4
**Description:** Add fence support to PM4 submission path

**Subtasks:**
- [ ] Implement PM4 fence packets
- [ ] Integrate with fence system
- [ ] Add completion interrupts
- [ ] Test fence reliability

**Acceptance Criteria:**
- PM4 fences compatible with GL fences
- Fence signaling < 1µs after completion
- No polling required
- Works with juggler pattern
- Stress test passes

**Time Estimate:** 2 days

---

## Task 3.5: Hot Path Optimization
**Description:** Create fast path for common operations

**Subtasks:**
- [ ] Profile conv2d patterns
- [ ] Pre-build common packets
- [ ] Implement packet templates
- [ ] Add fast path selection

**Acceptance Criteria:**
- 90% of conv2d uses fast path
- Pre-built packets for common sizes
- <500ns packet preparation
- Automatic path selection
- Correctness maintained

**Optimization Example:**
```fortran
! Pre-compute packets for common cases
type :: conv2d_packet_cache
  integer(i32), allocatable :: packets_3x3(:)
  integer(i32), allocatable :: packets_1x1(:)
  integer :: packet_count_3x3
  integer :: packet_count_1x1
end type

! Runtime: just copy pre-built packets
if (kernel_size == 3 .and. stride == 1) then
  call copy_cached_packets(cache%packets_3x3)
else
  call build_packets_dynamic(...)
end if
```

**Time Estimate:** 2 days

---

## Task 3.6: Production Safety Features
**Description:** Add monitoring and failsafes for production use

**Subtasks:**
- [ ] Add performance counters
- [ ] Implement watchdog timer
- [ ] Create diagnostic tools
- [ ] Add fallback triggers

**Acceptance Criteria:**
- Real-time performance monitoring
- Automatic fallback to OpenGL
- Diagnostic data on failures
- Remote kill switch capability
- No impact on fast path

**Production Safeguards:**
```fortran
module pm4_safety
  integer :: submit_count = 0
  integer :: error_count = 0
  real :: success_rate = 1.0
  
  ! Auto-disable if error rate too high
  if (success_rate < 0.95) then
    use_pm4_direct = .false.
    call log_fallback_triggered()
  end if
end module
```

**Time Estimate:** 2 days

---

## Sprint Summary (historical scope)

**Total Time:** 14 days (2 weeks)

**Definition of Done:**
- [ ] PM4 submission works for conv2d (historical target)
- [ ] 8,000+ GFLOPS (historical target)
- [ ] Zero system hangs in extended soak (historical hardening target)
- [ ] Automatic fallback working
- [ ] Documentation complete

**Success Metrics:**
- Dispatch latency: historical target (50µs → 1µs)
- Conv2D performance: historical target (2,000 → 8,000 GFLOPS)
- System stability: No hangs
- Error recovery: < 100ms

**Critical Safety Rules:**
1. NEVER submit unvalidated packets
2. ALWAYS have timeout protection
3. ALWAYS test on expendable hardware first
4. NEVER disable safety checks in production
5. ALWAYS have emergency kill switch

**Risk Matrix:**
- GPU hang: Watchdog timer + reset
- Bad packets: Validation layer
- Memory corruption: Bounds checking
- System crash: Fallback to OpenGL

**Next Sprint Preview:** Autotuner Optimization
- Cache tuning results
- Reduce warmup time
- Share results across kernels
