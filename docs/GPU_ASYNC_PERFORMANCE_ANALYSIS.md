> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GPU Async Executor Performance Analysis

## Executive Summary

The async executor reports [deferred throughput metric] ([deferred latency] for 20 batches) versus [deferred throughput metric] ([deferred latency]) for synchronous execution. This [deferred speedup] speedup appears to be physically impossible given the AMD RX 7900 XTX's theoretical peak of ~[deferred throughput metric]. This analysis identifies multiple measurement and methodology issues that explain these anomalous results.

## Key Findings

### 1. **Fundamental Measurement Inconsistency**

The async executor is measuring **wall-clock time** for the entire pipeline, while the synchronous executor measures **GPU kernel execution time** multiplied by iterations:

- **Synchronous**: Uses GPU timestamp queries (`glQueryCounter`) to measure actual kernel execution time
- **Async**: Uses CPU `system_clock` to measure wall-clock time including all overhead

This is comparing apples to oranges.

### 2. **The [deferred latency] GPU Kernel Time is Misleading**

Looking at the synchronous C implementation:
```c
// Multiple iterations for accurate timing (like original test)
int bench_iters = 20;

glQueryCounter(query_ids[0], GL_TIMESTAMP);

// Execute multiple times
for (int i = 0; i < bench_iters; i++) {
    glDispatchCompute(num_groups, 1, 1);
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
}
glFinish();

glQueryCounter(query_ids[1], GL_TIMESTAMP);

// Calculate average time per iteration in milliseconds
double time_ms = (double)(time_end - time_start) / 1.0e6 / bench_iters;
```

The synchronous test runs 20 GPU kernel iterations **within the GPU timing**, then divides by 20. So [deferred latency] is the average time for one kernel execution. The total GPU time for 20 kernels is actually ~[deferred latency].

### 3. **Pipeline Overlapping Explains the "Speedup"**

The async executor achieves apparent speedup through:

1. **Triple Buffering**: Three sets of buffers allow CPU and GPU to work in parallel
2. **Async Submission**: GPU kernels are submitted without waiting for completion
3. **Pipeline Filling**: Multiple kernels execute concurrently on the GPU

However, the measured [deferred latency] wall-clock time for 20 batches ([deferred latency] per batch) is **physically impossible** if each kernel takes [deferred latency].

### 4. **The Real Issue: Incorrect GFLOPS Calculation**

The async executor calculates GFLOPS based on total wall-clock time:
```fortran
async_gflops = real(flop_count * NUM_BATCHES, real64) / &
               (real(async_total_time) / clock_rate * 1.0e9)
```

But this assumes all 20 batches completed their computations within [deferred latency], which would require:
- 20 batches × [deferred latency]/batch = [deferred latency] of GPU compute
- Compressed into [deferred latency] wall-clock time
- Implying [deferred speedup] parallelism on a single GPU

This is impossible. The GPU cannot execute 5.4 convolution kernels simultaneously.

### 5. **What's Really Happening**

The async executor is likely:

1. **Submitting** all 20 kernels to the GPU command queue in [deferred latency]
2. **Not waiting** for actual GPU execution to complete
3. **Measuring submission time**, not execution time
4. **Incorrectly calculating GFLOPS** based on submission time

The GPU is still executing kernels long after the measured period ends.

## Verification Tests Needed

### Test 1: Add Proper Synchronization
```fortran
! After all submissions, before measuring end time:
call glFinish()  ! Force all GPU work to complete
call system_clock(end_time)
```

### Test 2: Measure Actual GPU Time
Use GPU timestamp queries in the async executor to measure actual kernel execution time, not wall-clock time.

### Test 3: Track Buffer Readback
Ensure output data is actually read back before declaring completion. The current async test may not be reading results.

### Test 4: Single Batch Comparison
Run both sync and async with just 1 batch to eliminate pipeline effects.

## Expected Real Performance

Based on the analysis:

1. **GPU Kernel Time**: ~[deferred latency] per batch (as measured)
2. **20 Batches**: ~[deferred latency] minimum GPU execution time
3. **Theoretical Best Case**: With perfect overlapping of CPU/GPU work:
   - First kernel: [deferred latency]
   - Remaining 19 kernels overlapped: ~[deferred latency] total
   - **Best possible**: ~[deferred latency] wall-clock time

4. **Expected GFLOPS**: 
   - At [deferred latency] for 20 batches: ~[deferred throughput metric]
   - This is reasonable for AMD RX 7900 XTX

## Synchronous Performance Issues

The synchronous test shows [deferred latency] wall-clock for 20 batches ([deferred latency] per batch) versus [deferred latency] GPU kernel time. This [deferred speedup] overhead suggests:

1. **Driver overhead**: OpenGL command submission overhead
2. **Synchronization overhead**: `glFinish()` after each kernel
3. **Memory transfer overhead**: Not measured in GPU time
4. **CPU-GPU round-trip latency**: ~[deferred latency] per operation

This overhead is why async execution provides real benefits - not [deferred speedup], but potentially [deferred speedup range].

## Conclusions

1. **The [deferred throughput metric] claim is incorrect** - based on flawed measurement
2. **Real speedup is likely [deferred speedup range]**, not [deferred speedup]
3. **Async execution provides real benefits** by hiding CPU-GPU latency
4. **Both tests need consistent measurement** - either GPU time or wall-clock time
5. **Physical limits must be respected** - can't exceed GPU's theoretical peak

## Recommendations

1. **Fix measurement methodology**:
   - Use GPU timestamps for both sync and async
   - Or use wall-clock time with proper synchronization for both
   - Never mix measurement types

2. **Add verification**:
   - Verify output data is actually computed
   - Add checksums to ensure correctness
   - Use `glFinish()` before stopping timing

3. **Report honest metrics**:
   - GPU utilization percentage
   - Actual kernel execution time
   - Pipeline efficiency
   - Real-world speedup

4. **Test incrementally**:
   - Start with single batch
   - Measure each component separately
   - Build up to full pipeline

The async executor is a valuable optimization, but claims must be grounded in physical reality.