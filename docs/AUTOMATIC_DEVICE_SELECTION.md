> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Automatic Device Selection

## Overview

Sporkle now includes automatic device selection that chooses the compute device (CPU or Kronos-discovered GPU paths) based on workload characteristics and routing policy.
The intent is to reduce manual routing, while keeping selection behavior aligned with validated runtimes.

## How It Works

### 1. Workload Analysis
- Calculates total FLOPs and memory traffic
- Determines arithmetic intensity (FLOPs/byte)
- Classifies workload as compute-bound or memory-bound

### 2. Device Scoring
- Evaluates each device's capabilities against workload needs
- Considers historical performance data for specific patterns
- Accounts for current device load and thermal state

### 3. Intelligent Selection
- **Small workloads (<100 MFLOPS)**: Automatically selects CPU to avoid GPU kernel launch overhead
- **Large workloads**: Selects GPU with async pipeline for maximum throughput
- Learns from performance history to improve future selections

## Performance Results

### Example: Example Selection Trace
```
Tiny workload (1×3×32×32):
- Device: CPU
- Performance: [deferred throughput metric]
- Reasoning: Avoids GPU overhead

Large workload (4×128×56×56):
- Device: GPU (async)
- Performance: [deferred throughput metric]  
- Reasoning: Maximizes parallelism
```

## Usage

### Basic Usage
```fortran
use sporkle_conv2d_auto_selector

! Initialize the selector
call init_auto_selector()

! Run convolution with automatic device selection
time_ms = conv2d_auto_select(input, weights, output, &
                            N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)

! Get statistics
call get_selector_stats()

! Cleanup
call cleanup_auto_selector()
```

### Advanced Features
```fortran
! Enable/disable profiling output
call set_profiling_mode(.true.)  ! Verbose selection reasoning
call set_profiling_mode(.false.) ! Silent operation

! The selector maintains performance history
! Each device tracks performance per pattern (CONV, GEMM, etc.)
! Future selections improve based on past results
```

## Architecture

### Components
1. **Universal Device Selector**: Framework for device enumeration and scoring
2. **Workload Characterization**: Analyzes compute intensity and memory patterns
3. **Performance History**: Tracks actual vs expected performance
4. **Device Capabilities**: Detailed tracking of each device's features

### Device Types Supported
- CPU (Performance cores with AVX-512)
- GPU (Kronos-discovered AMD/NVIDIA dispatch)
  - SPIR-V pipeline integration
  - Async compute queues where available
  - Unified runtime capability model
- Apple Neural Engine path is planned in the Apple runtime module
- Future: matrix units, iGPU-specific routing, multi-device partitioning

### Selection Criteria
- Arithmetic intensity (compute vs memory bound)
- Workload size (avoids overhead for small tasks)
- Historical performance data
- Device availability and current load

## Benefits

1. **Policy-Aligned Routing**: Uses validated device capabilities and current policy
2. **Zero Configuration**: Works out of the box
3. **Adaptive**: Learns from measured telemetry where available
4. **Future-Proof**: Easy to add new device types

## Implementation Details

The selector integrates with the existing device juggling system:
- Maintains compatibility with manual device selection
- Uses async GPU executor for Kronos-native paths when active
- Returns explicit errors when explicit routing requirements cannot be satisfied

### Thresholds
- Small workload: <100 MFLOPS → CPU
- Medium workload: 100-1000 MFLOPS → Device-dependent
- Large workload: >1000 MFLOPS → GPU preferred

### Learning Rate
- Uses exponential moving average (α=0.1) for performance updates
- Balances historical data with recent observations
- Prevents outliers from skewing decisions

## Future Enhancements

1. **Multi-GPU Support**: Distribute work across multiple GPUs
2. **Pipeline Parallelism**: Use CPU for pre/post-processing while GPU computes
3. **Energy Awareness**: Consider power efficiency in selection
4. **Cloud Integration**: Select between local and remote devices
