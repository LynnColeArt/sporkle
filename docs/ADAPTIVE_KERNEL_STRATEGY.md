> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Adaptive Kernel Implementation Strategy

## Vision

Instead of choosing a single "best" implementation path for GPU kernels, Sparkle will implement multiple approaches and dynamically select the optimal one based on empirical performance measurements on the target system.

## Rationale

GPU compute ecosystems are fragmented and constantly evolving:
- Driver versions affect compiler optimizations
- Different GPU generations favor different approaches  
- Workload characteristics (size, shape) change optimal strategies
- New APIs and methods emerge regularly

By implementing multiple paths and measuring actual performance, we:
1. Always achieve the best possible performance on any given system
2. Create invaluable benchmarking data across implementation strategies
3. Future-proof against ecosystem changes
4. Avoid religious wars about "the right way"

## Implementation Strategies for AMDGPU

### Strategy 1: OpenGL Compute Shaders (GLSL)
**Approach**: Write kernels in GLSL, compile through OpenGL API
**Pros**: 
- High-level, maintainable code
- Leverages existing OpenGL infrastructure
- Cross-vendor intent (AMD/NVIDIA/Intel validation is staged in active backends)
- Well-documented, stable API

**Cons**:
- Additional abstraction layer
- Dependent on OpenGL driver quality
- May not expose all GPU features

**Implementation Path**:
1. Generate GLSL compute shader from convolution-as-GEMM kernel
2. Use existing `sporkle_gpu_opengl.f90` infrastructure
3. Compile shader, dispatch compute, measure performance

### Strategy 2: SPIR-V Intermediate Representation  
**Approach**: Generate SPIR-V bytecode, submit through Vulkan or OpenGL
**Pros**:
- More control than GLSL
- Portable across vendors
- Can optimize at IR level
- Modern approach

**Cons**:
- More complex to generate
- Still goes through driver compilation
- Requires SPIR-V toolchain

**Implementation Path**:
1. Generate SPIR-V from kernel representation
2. Submit through Vulkan compute or GL_ARB_gl_spirv
3. Measure performance vs GLSL

### Strategy 3: Direct Command Buffer Generation
**Approach**: Generate PM4 packets with inline shader binary
**Pros**:
- Maximum control
- No driver compilation variance
- Closest to metal
- Unique approach

**Cons**:
- Requires shader binary format knowledge
- More complex implementation
- AMD-specific

**Implementation Path**:
1. Pre-compile kernel to AMDGPU binary (offline)
2. Embed binary in PM4 command stream
3. Direct submission through our ioctl interface

## Adaptive Selection Algorithm

```fortran
module sporkle_adaptive_kernel
  implicit none
  
  type :: kernel_variant
    character(len=32) :: name
    type(sporkle_kernel) :: implementation
    real(dp) :: best_time
    integer :: measurement_count
    logical :: is_valid
  end type
  
  type :: adaptive_kernel
    type(kernel_variant) :: variants(MAX_VARIANTS)
    integer :: num_variants
    integer :: selected_variant
    real(dp) :: last_probe_time
  end type
  
contains
  
  function select_optimal_variant(kernel, workload_size) result(variant_idx)
    type(adaptive_kernel), intent(inout) :: kernel
    integer(int64), intent(in) :: workload_size
    integer :: variant_idx
    
    ! Re-probe periodically or on workload change
    if (should_reprobe(kernel, workload_size)) then
      call probe_all_variants(kernel, workload_size)
    end if
    
    variant_idx = kernel%selected_variant
  end function
  
  subroutine probe_all_variants(kernel, workload_size)
    type(adaptive_kernel), intent(inout) :: kernel
    integer(int64), intent(in) :: workload_size
    real(dp) :: times(kernel%num_variants)
    integer :: i
    
    ! Benchmark each variant
    do i = 1, kernel%num_variants
      if (kernel%variants(i)%is_valid) then
        times(i) = benchmark_variant(kernel%variants(i), workload_size)
      else
        times(i) = HUGE(1.0_dp)
      end if
    end do
    
    ! Select best
    kernel%selected_variant = minloc(times, 1)
    kernel%last_probe_time = get_time()
    
    ! Log results for analysis
    call log_probe_results(kernel, times, workload_size)
  end subroutine
  
end module
```

## Benchmarking Protocol

Each variant will be evaluated using:

1. **Warmup Phase**: 5-10 iterations to stabilize caches/clocks
2. **Measurement Phase**: 100 iterations for statistical significance  
3. **Metrics Collected**:
   - Minimum execution time (best case)
   - Mean and standard deviation
   - 95th percentile (worst case)
   - Power consumption (if available)

## Decision Factors

The selection algorithm considers:

1. **Raw Performance**: Kernel execution time
2. **Consistency**: Standard deviation of timings
3. **Workload Size**: Different strategies for different sizes
4. **GPU State**: Temperature, clock speeds
5. **System Load**: Other GPU users

## Reprobing Strategy

Variants are re-evaluated when:
- First run on a new system
- Workload size changes significantly (>[deferred speedup])
- Driver update detected
- Every N hours of runtime (configurable)
- Manual trigger for benchmarking

## Benefits

1. **Always Optimal**: Automatically uses the fastest path
2. **Scientific Data**: Creates comprehensive performance database
3. **Future Proof**: New strategies can be added anytime
4. **No Assumptions**: Lets reality determine the best approach
5. **Debugging Aid**: Can force specific variant for testing

## Example Usage

```fortran
! User code remains simple
type(sporkle_kernel) :: conv_kernel
type(sporkle_buffer) :: input, output

! Sparkle automatically selects best variant
call sporkle_execute(device, conv_kernel, input, output)

! Power user can examine variants
call sporkle_print_variant_stats(conv_kernel)
! Output:
! Convolution kernel variants (size=1048576):
!   GLSL:     [deferred latency] (selected) ✓
!   SPIR-V:   [deferred latency]
!   Direct:   [deferred latency] (error: driver too old)

! Force specific variant for testing
call sporkle_force_variant(conv_kernel, "SPIR-V")
```

## Implementation Priority

1. **Phase 1**: GLSL implementation (leverage existing OpenGL infrastructure)
2. **Phase 2**: Add adaptive framework with single variant
3. **Phase 3**: Add SPIR-V variant
4. **Phase 4**: Add direct command buffer variant
5. **Phase 5**: Comprehensive benchmarking and analysis

## Success Metrics

- All variants produce identical numerical results
- At least one benchmarkable variant is tracked for each tested system
- Performance variance between best/worst < [deferred speedup]
- Adaptation overhead < 1% of execution time
- Clear documentation of why each variant wins/loses

## Open Questions

1. How often should we reprobe in production?
2. Should we persist variant preferences across runs?
3. How do we handle variant-specific bugs gracefully?
4. Can we share performance data across users for better predictions?

## Conclusion

By implementing multiple kernel strategies and empirically selecting the best, Sparkle transcends the limitations of any single approach. This adaptive strategy embodies the framework's philosophy: pragmatic, performance-driven, and always seeking the optimal solution for the user's specific system.

*"The best code is the code that runs fastest on YOUR machine, not the one that looks prettiest in the textbook."* - The Sporkle Way
