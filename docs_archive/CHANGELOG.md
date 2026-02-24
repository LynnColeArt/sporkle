> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle Changelog

All notable changes to Sparkle will be documented in this file.

## [Unreleased] - 2025-08-10

### Added
- **Memory Wall Breakthrough**
  - Cache-aware algorithms achieving [deferred speedup] speedup on reductions
  - Fused kernel operations reducing memory traffic by [deferred speedup]
  - L1/L2/L3 cache-aware tiling for matrix operations
  - Pure Fortran implementation with no vendor dependencies

- **Thread Safety Configuration**
  - Configurable CPU thread limits to prevent desktop crashes
  - Environment variables: `SPARKLE_MAX_CPU_THREADS` and `SPARKLE_THREAD_RESERVE`
  - Default reserves 2 threads for system stability
  - Safe defaults prevent using all 16 threads on 16-core systems

- **OpenMP Parallelization**
  - Full parallel implementations of core kernels
  - SIMD vectorization hints for compiler optimization
  - Thread-safe execution with configurable limits
  - Performance gains: [deferred speedup range] speedup on 14 cores

### Performance
- **Single-threaded baseline**: 0.5-[deferred throughput metric]
- **Parallel performance**: Up to [deferred throughput metric], [deferred bandwidth] bandwidth
- **Cache-aware reduction**: [deferred speedup] faster than naive approach
- **Memory bandwidth**: 64% of theoretical DDR4 maximum

### Documentation
- Created "The Sporkle Way" philosophy document
- Updated style guide with personality and humor
- Added comprehensive benchmarking documentation
- Thread safety configuration guide

### Examples
- `test_benchmarks.f90` - Hot/cold benchmarking methodology
- `test_cache_aware.f90` - Memory wall breakthrough demonstration
- `test_parallel_safety.f90` - Thread safety configuration
- `test_parallel_speedup.f90` - Parallel performance analysis

## [0.1.0] - Previous Session

### Added
- Core architecture and API design
- Device abstraction layer (CPU, GPU detection)
- Memory management system
- Compute kernel abstraction
- Workload scheduler with cost models
- Device profiling and selection
- Vendor-neutral GPU execution framework (OpenGL/Vulkan)
- Mesh topology for distributed compute

### Infrastructure
- Pure Fortran implementation
- No external dependencies
- Hardware detection via kernel drivers
- Pythonic API design principles