> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GPU Unique Features We're Not Exploiting

## Current State
We're getting 460 GFLOPS by optimizing compute shaders, but we're treating the GPU like a "fast CPU" rather than exploiting its unique architecture.

## Unique GPU Features We're Missing

### 1. **Texture Memory & Tensor Cores**
- GPUs have dedicated texture units with built-in filtering
- Tensor cores on newer GPUs (not on AMD yet, but coming)
- Could use texture memory for weight storage (spatial locality)

### 2. **Multiple Command Queues**
- Graphics queue + Compute queue + Transfer queue
- Could overlap rendering with compute
- DMA engines for async memory transfers

### 3. **GPU as Extended Memory**
- 24GB on the 7900 XT vs 32GB system RAM
- Could use GPU as a massive cache for datasets
- Persistent GPU-resident models

### 4. **Multi-GPU Heterogeneous**
- Integrated GPU (Raphael) sitting idle
- Could use for:
  - Preprocessing/postprocessing
  - Different precision work
  - Memory bandwidth tasks

### 5. **Hardware Video Encode/Decode**
- VCN units on AMD GPUs
- Could offload video preprocessing
- Free up compute for actual ML

### 6. **Display Pipeline Integration**
- Direct framebuffer access
- Zero-copy display of results
- Real-time visualization without CPU roundtrip

## Proposed Architecture

```
┌─────────────────────────────────────────────┐
│              CPU (Coordinator)              │
│  - Orchestration                           │
│  - Sequential logic                        │
└────────────┬──────────────┬────────────────┘
             │              │
    ┌────────▼────┐  ┌──────▼──────┐
    │  iGPU       │  │  dGPU       │
    │  (Raphael)  │  │  (7900 XT)  │
    │             │  │             │
    │ - Preproc   │  │ - Compute   │
    │ - Memory    │  │ - Training  │
    │ - Display   │  │ - Inference │
    └─────────────┘  └─────────────┘
           │                │
           └────────┬───────┘
                    │
            ┌───────▼────────┐
            │ Shared Memory  │
            │   (GPU P2P)    │
            └────────────────┘
```

## Specific Optimizations

### 1. **Persistent GPU Kernels**
Instead of launch → compute → return:
- Keep kernels running
- Feed work through queues
- Eliminate kernel launch overhead

### 2. **GPU-to-GPU Direct**
- Use PCIe P2P between iGPU and dGPU
- Skip CPU memory entirely
- Theoretical 32 GB/s between GPUs

### 3. **Async Everything**
```c
// Current (blocking)
upload_data();
compute();
download_result();

// Optimal (pipelined)
for (batch in batches) {
    async_upload(batch+2);
    async_compute(batch+1);
    async_download(batch);
}
```

### 4. **Memory Hierarchy Exploitation**
- L2 cache: 6MB on 7900 XT
- Infinity Cache: 96MB 
- Keep hot data in cache across kernels

## Performance Potential

Current: 460 GFLOPS (compute only)
With async: ~500 GFLOPS (hide transfer latency)
With dual GPU: ~600 GFLOPS (iGPU helps)
With persistence: ~650 GFLOPS (no kernel overhead)
With all optimizations: 700+ GFLOPS?

## Next Steps

1. **Implement async pipeline**
2. **Enable dual GPU execution**
3. **Exploit texture memory**
4. **Create persistent kernel framework**
5. **Benchmark holistic system performance**

The key insight: Stop thinking of GPU as "parallel CPU" and start exploiting its unique architectural features!