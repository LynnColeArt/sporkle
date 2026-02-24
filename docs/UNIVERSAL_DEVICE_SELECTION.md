> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Universal Device Selection: The Current Stability Frontier

## Executive Summary

The current goal is production-safe scheduling: keep runtime honest, route workloads consistently, and only claim gains that are measured after Kronos-native dispatch paths are stable. The next optimization frontier is **intelligent device selection** built from live topology and capability telemetry.

## Current State

### ✅ What We Have

1. **Multiple High-Performance Backends**
   - CPU: [deferred throughput metric] with AVX-512 SIMD
   - Vulkan: Modern GPU compute with SPIR-V shaders
     - Cross-platform GPU abstraction
     - Async compute queues for pipeline optimization
   - Metal/Neural Engine: Explicit capability-aware path when available
     - Runtime probing for vendor/accelerator availability
     - No synthetic timing or hidden fallback in production selection

2. **Abstract Device Interface**
   ```fortran
   type, abstract :: compute_device
     procedure(execute_interface), deferred :: execute
     procedure :: estimate_performance
   end type
   ```

3. **Existing Intelligence**
   - `intelligent_device_juggling.f90`: Profiles devices and learns optimal distribution
   - `sporkle_apple_orchestrator.f90`: Routes to CPU/GPU/ANE/AMX on Apple Silicon
   - Performance profiling and adaptive optimization

### ❌ What's Missing

1. **Unified Device Manager**: No single system that manages all backends
2. **Automatic Routing**: Currently requires manual device selection
3. **Multi-Device Execution**: Can't use CPU + GPU simultaneously
4. **Cross-Platform Intelligence**: Apple orchestrator logic not available on Linux

## The Vision: Universal Device Selector

### Architecture

```
┌─────────────────────────────────────────────────┐
│           Universal Device Selector              │
├─────────────────────────────────────────────────┤
│  Device Discovery & Profiling                   │
│  - Enumerate all compute devices                │
│  - Profile capabilities (GFLOPS, bandwidth)     │
│  - Test actual performance                      │
├─────────────────────────────────────────────────┤
│  Intelligent Routing Engine                     │
│  - Analyze workload characteristics             │
│  - Predict performance on each device           │
│  - Consider data locality                       │
│  - Route to optimal device(s)                   │
├─────────────────────────────────────────────────┤
│  Multi-Device Orchestration                     │
│  - Split large workloads                        │
│  - Pipeline through multiple devices            │
│  - Overlap computation and data transfer        │
├─────────────────────────────────────────────────┤
│  Learning & Adaptation                          │
│  - Track actual vs predicted performance        │
│  - Update routing decisions                     │
│  - Discover optimal configurations              │
└─────────────────────────────────────────────────┘
```

### Key Features

1. **Universal Device Abstraction**
   - Works with any compute device that implements the interface
   - CPU, GPU, NPU, TPU, custom accelerators
   - Local and remote devices (future)

2. **Workload Analysis**
   ```fortran
   type :: workload_characteristics
     integer(int64) :: flop_count
     integer(int64) :: memory_reads
     integer(int64) :: memory_writes
     real(real32) :: arithmetic_intensity
     logical :: is_memory_bound
     logical :: is_compute_bound
     logical :: has_data_dependencies
   end type
   ```

3. **Performance Prediction**
   - Based on device capabilities and workload characteristics
   - Learned from historical performance data
   - Considers current device load and availability

4. **Smart Routing Decisions**
   ```fortran
   ! Example routing logic
   if (workload%size < small_threshold) then
     ! Small workloads to CPU (lower latency)
     device = cpu_device
   else if (workload%arithmetic_intensity > 10.0) then
     ! Compute-intensive to GPU
     device = gpu_device
   else if (workload%is_convolution .and. has_neural_engine) then
     ! Convolutions to Neural Engine
     device = neural_engine
   else
     ! Split across multiple devices
     call multi_device_execute(workload)
   end if
   ```

## Implementation Plan

### Phase 1: Unified Device Manager
1. Create `sporkle_device_manager` module
2. Register all available compute devices
3. Implement device discovery for each platform
4. Add performance profiling infrastructure

### Phase 1.5: Kronos Dispatch Integration
1. **Capability Mapping**: Bind discovered vendor paths into a single selector model
   - Normalize AMD/NVIDIA/Apple discovery outputs
   - Preserve CPU, GPU, and Neural Engine traits as explicit capabilities
2. **Device Scoring for Kronos**:
   - Add measured/declared caps to routing heuristics
   - Consider dispatch support, memory topology, and load state
3. **Dispatch Selection Contracts**:
   - Route only to verified backends
   - Keep failures loud when a requested backend path is unavailable
4. **Multi-Device Support**:
   - Allow multi-device routing once dispatch telemetry reaches stable baselines

### Phase 2: Routing Intelligence
1. Port `intelligent_device_juggling` concepts
2. Integrate `apple_orchestrator` routing logic
3. Add workload analysis and characterization
4. Implement performance prediction model

### Phase 3: Multi-Device Execution
1. Workload splitting algorithms
2. Data movement optimization
3. Pipeline orchestration
4. Synchronization across devices

### Phase 4: Learning System
1. Performance tracking database
2. Online learning algorithms
3. Adaptive threshold tuning
4. Configuration optimization

## Expected Performance Impact

### Single Device Improvements
- **10-20% Better Device Utilization**: Route each workload to its optimal device
- **Reduced Latency**: Small workloads to CPU avoid GPU overhead
- **Better Throughput**: Large workloads to GPU with async pipeline

### Multi-Device Speedup
- **iGPU + dGPU**: Use both AMD GPUs simultaneously ([deferred speedup range])
- **CPU + GPU Pipeline**: Overlap preprocessing and compute ([deferred speedup])
- **Heterogeneous Execution**: Different layers to different devices

### Platform-Specific Gains
- **Linux**: CPU + iGPU + dGPU triple execution
- **macOS**: CPU + GPU + Neural Engine + AMX quad execution
- **Future**: Distributed execution across network

## Real-World Example

```fortran
! Current approach (manual selection)
if (use_gpu) then
  call gpu_conv2d(input, weights, output)
else
  call cpu_conv2d(input, weights, output)
end if

! With universal device selector
call sporkle_execute(conv2d_op, input, weights, output)
! Automatically routes to:
! - Neural Engine on M1 Mac ([deferred throughput metric])
! - GPU with async executor on Linux ([deferred throughput metric])
! - CPU with SIMD for small batches ([deferred throughput metric])
! - Split across CPU+GPU for optimal throughput
```

## Technical Challenges

1. **Data Movement**: Minimize transfers between devices
2. **Synchronization**: Coordinate multiple devices efficiently
3. **Load Balancing**: Adapt to dynamic workloads
4. **Portability**: Abstract platform differences

## Success Metrics

1. **Automatic Performance**: Match or exceed manual device selection
2. **Multi-Device Scaling**: >[deferred speedup] speedup using multiple devices
3. **Learning Effectiveness**: Performance improves over time
4. **Zero Configuration**: Works out-of-the-box on any platform

## Conclusion

Universal device selection represents the next major performance frontier for Sparkle. By intelligently utilizing all available compute resources and learning optimal configurations, we can achieve another [deferred speedup range] performance improvement beyond our already impressive gains.

This isn't just about raw performance - it's about making high-performance computing accessible. Users shouldn't need to know about GPU thread blocks or Neural Engine tiles. They should just call `sporkle_execute()` and get optimal performance automatically.

The foundation is already in place. Now we build the intelligence layer that makes Sparkle truly universal.
