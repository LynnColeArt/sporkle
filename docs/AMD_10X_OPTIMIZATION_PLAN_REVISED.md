> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# AMD [deferred speedup] Performance Optimization Plan (REVISED with Mini's Feedback)

## Current Performance: [deferred throughput metric] (13.4% of theoretical)
## Target Performance: [deferred throughput metric] (75% efficiency via direct conv)

## Mini's Critical Corrections Applied

### 1. **Wave32 for RDNA3 (NOT Wave64)**
```glsl
// RDNA prefers wave32 for occupancy
#ifdef RDNA
  #define WAVE_SIZE 32
#else
  #define WAVE_SIZE 64  // GCN/CDNA
#endif
```

### 2. **256-Thread Workgroups (NOT 1024)**
```glsl
layout(local_size_x = 32, local_size_y = 8) in;  // 256 threads
// Or: layout(local_size_x = 16, local_size_y = 16) in;
```
- Allows ≥2 workgroups per CU
- Keeps register pressure ≤64
- Matches universal pattern (4 SIMD groups)

### 3. **We're NOT Bandwidth Limited!**
With proper tiling:
- **32×32 LDS tiles** + **Ko=64 blocking**
- **Arithmetic intensity**: ~150 FLOP/byte
- **RDNA3 balance**: ~64 FLOP/byte
- **Result**: COMPUTE BOUND with direct convolution!

### 4. **Optimal Configuration for Auto-tuner**
```c
typedef struct {
    int wave_size;        // 32 for RDNA, 64 for GCN
    int threads_x, threads_y;  // 32×8 or 16×16 = 256
    int tile_size;        // 32×32 input tile
    int ko_tile;          // 64 output channels per pass
    int outputs_per_thread_x, outputs_per_thread_y;  // 4×4 or 4×2
    int unroll_factor;    // 12-16 inner MAC unroll
    int lds_pad;          // 1-2 to avoid bank conflicts
} amd_conv_config_t;
```

### 5. **LDS Bank Conflict Avoidance**
```glsl
// BAD: Perfect power of 2
shared float tile[32][32];  // Bank conflicts!

// GOOD: Padded
shared float tile[32][33];  // Or [34][33] for extra safety
```

### 6. **Memory Layout Strategy**
- **Global**: NHWC with vec4 loads/stores
- **LDS**: Blocked/tiled with padding
- **Staging**: 4-8 ring buffers, persistently mapped
- **Device**: Separate device-local SSBOs for compute

## Revised Performance Roadmap

### Phase 1: Fix Fundamentals (3,630 → [deferred throughput metric])
1. Switch to 256-thread workgroups
2. Use wave32 on RDNA3
3. Fix GPU timing measurement
4. Vec4 memory access

### Phase 2: LDS Tiling (8,000 → [deferred throughput metric])
```glsl
shared float input_tile[34][33];   // 32×32 + padding
shared float weight_tile[64][9];   // Ko=64, 3×3 kernel

// 4×4 outputs per thread
float acc[4][4];
```

### Phase 3: Full Optimization (16,000 → [deferred throughput metric])
- Ko-blocking (process 64 output channels at once)
- [deferred speedup range] inner loop unroll
- Non-coherent buffer management
- Optimal register allocation (≤64)

### Phase 4: Algorithm Innovation (20,000 → [deferred throughput metric])
- Winograd F(2,3) for 3×3 kernels
- FFT for larger kernels
- But only AFTER direct conv hits 75% efficiency!

## Key Architecture Insights

### Register/LDS Budget
```
256 threads × 64 registers = 16,384 registers/WG
→ Allows 2-3 workgroups per CU
→ Good occupancy!

32×33×4 bytes (input) + 64×9×4 bytes (weights) = ~6.5 KB LDS
→ Fits comfortably in 64 KB LDS/CU
→ Room for double buffering
```

### Arithmetic Intensity Calculation
For 32×32 output tile, C=256, Ko=64:
- **Input tile**: 34×34×256×4 = 1.15 MB (read once)
- **Weights**: 64×256×9×4 = 0.56 MB (read once)
- **Output**: 32×32×64×4 = 0.26 MB (write once)
- **Total**: ~2.0 MB moved

- **FLOPs**: 32×32×64×256×9×2 = 302 MFLOPs
- **Intensity**: 302/2.0 = **151 FLOP/byte**
- **Required**: 64 FLOP/byte → **We're compute bound!**

## Auto-tunable Parameters

| Parameter | RDNA3 Default | Range | Notes |
|-----------|--------------|-------|-------|
| wave_size | 32 | 32,64 | 32 for RDNA, 64 for GCN |
| workgroup | 32×8 | 128-512 | 256 optimal |
| tile_size | 32×32 | 16-64 | Match cache line |
| ko_tile | 64 | 32,64,128 | Balance LDS usage |
| outputs/thread | 4×4 | 2×2 to 8×8 | Register pressure |
| unroll | 12 | 8-16 | Compiler dependent |
| lds_pad | 1 | 0-2 | Avoid bank conflicts |

## Corrected Implementation

```glsl
#version 450

// Tunable parameters
#define TILE_M 32
#define TILE_N 32
#define TILE_K 64
#define PAD 1

layout(local_size_x = 32, local_size_y = 8) in;

// Padded LDS to avoid bank conflicts
shared float input_tile[TILE_M + 2][TILE_N + 2 + PAD];
shared float weight_cache[TILE_K][9];

void main() {
    // Each thread: 4×4 outputs
    vec4 acc[4][4];
    
    // Ko-blocking: process 64 output channels
    for (int ko = 0; ko < K; ko += TILE_K) {
        // Cooperative load with vec4
        // ...
        
        barrier();
        
        // Compute with proper unrolling
        #pragma unroll 12
        for (int k = 0; k < 3; k++) {
            // ...
        }
        
        barrier();
    }
}
```

## The Truth About Performance

- **Current**: [deferred throughput metric] (with CPU timing overhead)
- **Real GPU**: Probably already [deferred throughput metric]
- **Optimized Direct**: [deferred throughput metric] (75% efficiency)
- **With Winograd**: 25,000-[deferred throughput metric]

We don't need to exceed theoretical peak - we need to properly utilize what we have!

## Action Items

1. ✅ Apply wave32 default for RDNA
2. ✅ Use 256-thread workgroups
3. ✅ Implement LDS padding
4. ⏳ Create auto-tuner with parameter sweep
5. ⏳ Measure with GPU timers
6. ⏳ Validate arithmetic intensity