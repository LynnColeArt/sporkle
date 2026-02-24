> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle/Sporkle Benchmarking Plan

## Objectives
1. Validate performance of Fortran GPU DSL
2. Compare implementations across backends
3. Establish baseline for future optimization
4. Demonstrate viability of Fortran for GPU compute

## Benchmark Suite

### 1. Micro-benchmarks

#### Memory Bandwidth
- **Test**: Copy N elements between buffers
- **Sizes**: 1KB, 1MB, 100MB, 1GB
- **Metrics**: GB/s throughput
- **Backends**: CPU, OpenGL, Fortran shaders

#### Compute Throughput  
- **Test**: Element-wise operations (add, multiply)
- **Sizes**: 1M, 10M, 100M elements
- **Metrics**: GFLOPS
- **Backends**: All available

### 2. BLAS Operations

#### SAXPY (Single-precision A*X + Y)
```fortran
!@kernel(local_size_x=256, in=2, out=1)
pure subroutine saxpy(i, a, x, y)
  real(real32), value :: a
  real(real32), intent(in) :: x
  real(real32), intent(inout) :: y
  y = a * x + y
end subroutine
```

#### SGEMM (Single-precision Matrix Multiply)
- **Sizes**: 256x256, 1024x1024, 4096x4096
- **Compare**: OpenBLAS, MKL (if available), our implementations

### 3. ML Operations

#### Convolution
- **Test**: 2D convolution with various kernel sizes
- **Input sizes**: 224x224, 512x512
- **Kernel sizes**: 3x3, 5x5, 7x7
- **Backends**: CPU im2col, OpenGL, Fortran shaders

#### Activation Functions
- **Test**: ReLU, Sigmoid, Tanh
- **Sizes**: 1M, 10M, 100M elements

### 4. Real-world Scenarios

#### Mini Neural Network
- **Test**: Forward pass of small CNN
- **Layers**: Conv → ReLU → Pool → FC
- **Compare**: PyTorch CPU vs our implementation

## Metrics to Collect

1. **Performance**
   - Execution time (ms)
   - Throughput (ops/sec)
   - Memory bandwidth (GB/s)
   - GPU utilization (%)

2. **Resource Usage**
   - Memory consumption
   - Power draw (if available)
   - Temperature

3. **Correctness**
   - Numerical accuracy vs reference
   - Error bounds

## Implementation Status

### Ready to Benchmark ✅
- [x] Memory copy
- [x] Element-wise operations  
- [x] Simple kernels (store constant)
- [x] CPU convolution

### Need Implementation 🚧
- [ ] SAXPY kernel in Fortran DSL
- [ ] SGEMM kernel in Fortran DSL
- [ ] Activation functions
- [ ] Pooling operations
- [ ] Batch operations

### Blocked ❌
- [ ] Direct PM4 benchmarks (shader binary issue)
- [ ] Multi-GPU scaling (not implemented)
- [ ] Distributed benchmarks (no mesh yet)

## Benchmark Harness Design

```fortran
module sporkle_benchmark
  type :: benchmark_result
    character(len=64) :: name
    character(len=32) :: backend
    integer :: size
    real :: time_ms
    real :: throughput
    real :: bandwidth_gb_s
    logical :: correct
  end type
  
  interface
    subroutine benchmark_runner(kernel, data, result)
      procedure(kernel_interface) :: kernel
      type(benchmark_data) :: data
      type(benchmark_result) :: result
    end subroutine
  end interface
end module
```

## Comparison Targets

1. **CPU Baseline**: Pure Fortran loops
2. **OpenBLAS**: Industry standard
3. **MKL**: Intel's optimized library (if available)
4. **cuBLAS**: NVIDIA reference (if available)
5. **ROCm**: AMD reference (if available)

## Expected Results

### Memory Bandwidth
- **CPU**: 50-[deferred bandwidth] (DDR5)
- **GPU**: 300-[deferred bandwidth] (GDDR6)
- **Efficiency**: 60-80% of theoretical

### Compute
- **CPU**: 100-[deferred throughput metric]
- **GPU**: 5-[deferred throughput metric]
- **Fortran overhead**: <10% vs native

### Convolution
- **Speedup**: [deferred speedup range] over CPU
- **vs cuDNN**: Within [deferred speedup] (acceptable)

## Benchmark Schedule

### Phase 1 (Immediate)
1. Implement SAXPY in Fortran DSL
2. Create benchmark harness
3. Run memory bandwidth tests
4. Run SAXPY comparison

### Phase 2 (This Week)
1. Implement SGEMM
2. Full BLAS comparison
3. Power efficiency analysis

### Phase 3 (Next Week)
1. ML operations
2. Full CNN benchmark
3. Performance report

## Success Criteria

1. **Fortran DSL overhead**: <10% vs hand-written GLSL
2. **vs CPU**: >[deferred speedup] speedup on parallel workloads
3. **vs vendor libraries**: Within [deferred speedup range]
4. **Ease of use**: Scientist-friendly API

## Benchmarking Commands

```bash
# Run all benchmarks
make -f Makefile.smart benchmark

# Run specific benchmark
./build/LINUX/benchmark_saxpy --size=1000000 --backend=all

# Generate report
./tools/benchmark_report.py results/*.json > report.md
```

## Publication Target

Results will demonstrate:
1. Fortran is viable for GPU programming
2. Direct hardware access eliminates dependencies
3. Performance competitive with C/CUDA
4. Lower barrier to entry for scientists

"Sparkle: Democratizing GPU Compute with Pure Fortran"