> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# The 99% Idle GPU Problem

## The Breakthrough Insight

We've been optimizing the 0.56ms of GPU compute time, but missing that the GPU sits idle for 99% of the execution:

```
Timeline:
[CPU prep: 10ms] → [Upload: 2ms] → [GPU: 0.56ms] → [Download: 2ms] → [CPU post: 10ms]
                 GPU IDLE         GPU IDLE      ^^^^       GPU IDLE        GPU IDLE
                                               ACTIVE
```

**GPU Utilization: 0.56 / 24.56 = 2.3%**

## The Solution: Continuous Compute Pipeline

Transform from:
- **Current**: Synchronous function calls
- **Target**: Continuous compute engine

```
CPU:  [Prep 1][Prep 2][Prep 3][Prep 4][Process 1][Process 2]...
GPU:          [Comp 1][Comp 2][Comp 3][Comp 4]...
iGPU:                 [Pre 3][Pre 4][Pre 5]...
PCIe: [Up 1]  [Up 2]  [Up 3]  [Dn 1]  [Dn 2]...
```

## Required Changes

1. **Async Everything** - No blocking operations
2. **Triple Buffering** - Input/Output/Working sets
3. **Persistent Kernels** - Eliminate launch overhead
4. **Dual GPU Pipeline** - iGPU + dGPU collaboration
5. **CPU-GPU Overlap** - Both always busy

## Performance Potential

- Current: 460 GFLOPS at 2.3% utilization
- Target: 2000+ GFLOPS at 90% utilization
- Method: Not faster compute, but never idle

**The GPU is a river, not a bucket. Keep it flowing!**