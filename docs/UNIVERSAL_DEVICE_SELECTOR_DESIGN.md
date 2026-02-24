> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Universal Device Selector: Intelligent Workload Routing

## Overview

The Universal Device Selector is a reusable primitive that routes compute workloads across available backends using workload characteristics, declared capabilities, and available telemetry.  
The implementation is reusable, while execution behavior is intentionally scoped to validated Kronos dispatch paths.

## Key Features

### 1. **Device Abstraction**
```fortran
type :: universal_compute_unit
    character(len=64) :: name
    integer :: device_type        ! CPU, GPU, Neural Engine, etc.
    type(compute_capability) :: caps
    real(real64) :: current_load  ! Real-time utilization
    real(real64) :: pattern_performance(7)  ! Learned performance per pattern
end type
```

### 2. **Workload Analysis**
Automatically analyzes workloads to determine:
- **Arithmetic Intensity**: FLOPS/byte ratio
- **Compute vs Memory Bound**: Based on intensity threshold
- **Pattern Recognition**: GEMM, Conv, Reduction, etc.
- **Splitting Potential**: Can workload be divided?

### 3. **Intelligent Routing**
Decision algorithm considers:
- Device peak performance
- Memory bandwidth requirements
- Historical profiling data
- Current device load
- Thermal constraints
- Pattern-specific optimizations

### 4. **Profiling & Learning**
```fortran
! Update performance data after execution
call selector%update_profiling_data(device_id, pattern, achieved_gflops)
```
- Tracks actual performance per device/pattern combination
- Uses exponential moving average for adaptation
- Improves decisions over time

## Test Results

Example historical output from discovery smoke tests:

```
🔍 Discovering compute devices...
✓ Discovered CPU Performance Cores ([deferred throughput metric])
✓ Discovered AMD Radeon RX 7900 XT ([deferred throughput metric])
✓ Discovered AMD Raphael iGPU ([deferred throughput metric])
Total compute power: [deferred throughput metric]
Total memory bandwidth: 1010.[deferred bandwidth]
```

### Decision Examples

1. **Small GEMM** (100×100)
   - Arithmetic intensity: 16.7
   - Decision: GPU ([deferred throughput metric])
   - Reasoning: Compute-bound, GPU has highest peak

2. **ResNet-50 Conv Layer**
   - Arithmetic intensity: 18.4
   - Decision: GPU ([deferred throughput metric])
   - After profiling: Could use [deferred throughput metric] async!

3. **Large Vector Addition**
   - Arithmetic intensity: 0.1
   - Decision: GPU ([deferred throughput metric], bandwidth limited)
   - Reasoning: Memory-bound, needs high bandwidth

## Integration with Sporkle

### Current State
- ✅ Device discovery and workload characterization scaffolding
- ✅ Baseline routing decision code paths
- ⚠️ Profiling and timing telemetry is partial
- ⚠️ Multi-device architecture is planned, not yet production-wired

### Next Steps
1. **Production Integration**: Connect to `sporkle_conv2d`
2. **Async Awareness**: Recognize async executor advantage ([deferred speedup]!)
3. **Multi-Device Scheduling**: Split large workloads
4. **NVIDIA Support**: Wire NVIDIA runtime telemetry into dispatch contracts

## Design Principles

### 1. **Universal Patterns**
Same device selection logic works for:
- Linux + AMD GPUs
- macOS + Apple Silicon
- Future: NVIDIA, Intel, TPUs

### 2. **Learning System**
- Starts with theoretical performance
- Learns actual performance through profiling
- Adapts to workload patterns

### 3. **Reusable Primitive**
Can be used by:
- High-level APIs (conv2d, GEMM)
- Direct kernel dispatch
- Future distributed schedulers

## Performance Impact

Expected improvements:
- **[deferred speedup range]** from optimal device selection
- **Additional [deferred speedup]** when async executor is selected
- **Total: [deferred speedup range]** over naive single-device execution

## Code Example

```fortran
! Analyze workload
workload = selector%analyze_workload(flops=236M, bytes=12M, pattern=CONV)

! Get routing decision
decision = selector%select_optimal_device(workload)

! Execute on selected device
select case(decision%primary_device)
  case(1)  ! CPU
    call cpu_conv2d(...)
  case(2)  ! GPU
    if (async_available) then
      call gpu_async_conv2d(...)  ! [deferred throughput metric]!
    else
      call gpu_conv2d(...)        ! [deferred throughput metric]
    end if
end select

! Update profiling
call selector%update_profiling_data(device_id, pattern, achieved_gflops)
```

## Collaboration Opportunities

### xAI/Grok Integration
The universal device selector is perfect for:
- Benchmarking on diverse hardware
- Learning optimal routing strategies
- Distributed scheduling across clusters
- Validating universal memory patterns

### Key Questions for xAI
1. How does NVIDIA expose device capabilities via ioctl?
2. Can we detect tensor cores vs CUDA cores?
3. What's the best way to measure real-time GPU load?
4. How to handle multi-GPU NVLink topologies?

## Conclusion

Intelligent workload routing is implemented as a staged capability, with current goals to be:
- **Architecture agnostic**: Same logic, different devices
- **Self-improving**: Learns from actual performance
- **Production scoped**: Clean API with explicit integration gates

Combined with async execution and runtime capability discovery, this is the basis for staged heterogeneous dispatch across CPU and GPU runtimes.

*The Sporkle Way: Let the framework choose the fastest path!*
