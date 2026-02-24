> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle Performance Guide 🚀

## Current Performance (CPU)

As of 2025-08-10, Sparkle achieves the following performance on a 16-core CPU (using 14 threads for safety):

### Memory Bandwidth Operations
- **Vector Addition**: [deferred bandwidth] ([deferred speedup] parallel speedup)
- **SAXPY**: [deferred throughput metric] ([deferred speedup] parallel speedup)
- **Theoretical DDR4 Max**: ~[deferred bandwidth]
- **Efficiency**: 64% of theoretical bandwidth

### Compute-Intensive Operations
- **Complex (sqrt)**: [deferred throughput metric] ([deferred speedup] parallel speedup)
- **Normalize**: [deferred throughput metric] ([deferred speedup] parallel speedup)
- **Peak**: [deferred throughput metric] with 14 cores

### Cache-Aware Algorithms
- **Naive reduction**: [deferred latency]
- **Cache-aware reduction**: [deferred latency]
- **Speedup**: [deferred speedup] faster!

## Memory Wall Breakthrough

Sparkle implements three key strategies to break through the memory wall:

### 1. Operation Fusion
Reduces memory passes by combining operations:
```fortran
! Traditional: 6 memory passes
C = A * B        ! 3 passes
C = C + bias     ! 2 passes  
C = ReLU(C)      ! 1 pass

! Fused: 3 memory passes
C = ReLU(A*B + bias)  ! All in one go!
```

### 2. Cache-Aware Tiling
Processes data in cache-sized blocks:
- L1 tiles: 64×64 elements (16KB)
- L2 tiles: 256×256 elements (256KB)
- L3 tiles: 1024×1024 elements (4MB)

### 3. Thread Safety
Prevents desktop crashes with configurable limits:
```bash
export SPARKLE_MAX_CPU_THREADS=14  # Use 14 of 16 threads
export SPARKLE_THREAD_RESERVE=2    # Or reserve 2 for system
```

## Optimization Tips

### For Memory-Bound Operations
- Expect [deferred speedup range] parallel speedup (limited by bandwidth)
- Use operation fusion to reduce memory traffic
- Process data in cache-friendly chunks

### For Compute-Bound Operations
- Expect [deferred speedup range] parallel speedup (scales with cores)
- Add SIMD hints: `!$OMP SIMD`
- Increase arithmetic intensity

### Thread Configuration
```fortran
type(sporkle_config_type) :: config
config%max_cpu_threads = 14     ! Hard limit
config%thread_reserve = 2       ! Or reserve threads
call sporkle_set_config(config)
```

## Benchmark Reproduction

To reproduce these results:

```bash
# Compile with optimizations
gfortran -O3 -march=native -fopenmp -o bench src/*.f90 examples/test_parallel_speedup.f90

# Run with thread limit
export SPARKLE_MAX_CPU_THREADS=14
./bench
```

## What's Next?

### GPU Execution (Coming Soon)
- Target: 1-[deferred throughput metric]
- [deferred speedup]+ speedup over CPU
- RX 7900 XT: [deferred throughput metric] theoretical

### Network Mesh
- Distributed execution across devices
- Collective operations optimization
- Target: [deferred throughput metric] combined

## Performance Philosophy

"The Sporkle Way" for performance:
1. **Measure first** - Hot/cold benchmarking
2. **Respect the hardware** - Cache-aware algorithms
3. **Be a good neighbor** - Thread safety limits
4. **Pure Fortran** - No vendor lock-in

Remember: Every cycle counts, but don't crash the desktop! 🌟