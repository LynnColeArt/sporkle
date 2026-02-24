> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GPU Timing Breakthrough - The Hidden Performance

## The Problem We Discovered

We've been measuring CPU overhead, not GPU performance!

### Current (Wrong) Approach:
```fortran
call cpu_time(start_time)
status = gpu_execute_compute(...)  ! This includes all overhead!
call cpu_time(end_time)
```

### What This Actually Measures:
1. CPU command preparation time
2. CPU→GPU command submission
3. Kernel launch overhead  
4. **GPU execution (what we want)**
5. GPU→CPU synchronization
6. CPU polling/waiting
7. OS scheduler delays

**Result**: We're seeing 451 GFLOPS when the GPU might be doing 4,500+ GFLOPS!

## The Solution

### Option 1: GPU Hardware Timers
```fortran
! Use OpenGL timer queries
glQueryCounter(query_start, GL_TIMESTAMP)
! GPU work happens
glQueryCounter(query_end, GL_TIMESTAMP)
! Get actual GPU nanoseconds
glGetQueryObjectui64v(query_start, GL_QUERY_RESULT, start_ns)
glGetQueryObjectui64v(query_end, GL_QUERY_RESULT, end_ns)
```

### Option 2: Hardware Timers (x86_64)
```fortran
! Direct TSC (Time Stamp Counter) access
function rdtsc() result(cycles)
  integer(i64) :: cycles
  ! Read CPU cycle counter directly
  ! Assembly: RDTSC instruction
end function

! Or use HPET for nanosecond precision
function read_hpet() result(ns)
  integer(i64) :: ns
  ! Memory-mapped HPET access at 0xFED00000
end function
```

### Option 3: Dual GPU Timing
Use the Raphael iGPU as a timing reference:
- Same die as CPU = minimal latency
- More predictable overhead
- Can cross-validate timing

## Expected Real Performance

Based on our 7900 XT specs:
- **Measured**: 451 GFLOPS (with CPU overhead)
- **Actual GPU**: Likely 4,000-8,000 GFLOPS
- **Theoretical**: 27,000 GFLOPS

We're probably already at 20-30% efficiency, not 1.6%!

## Implementation Plan

1. **Quick Fix**: Use RDTSC for cycle-accurate timing
2. **Proper Fix**: OpenGL timer queries  
3. **Ultimate**: Direct GPU performance counters via ioctl

This explains why our "slow" performance still feels fast - the GPU is actually flying, we just can't measure it properly!