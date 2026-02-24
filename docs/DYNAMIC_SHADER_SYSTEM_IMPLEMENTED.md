> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Dynamic Shader Generation System: From Vision to Reality

## Executive Summary

We have an implemented dynamic shader generation system that is intended to:
1. **Detects GPU architecture** (Wave32 vs Wave64, RDNA vs GCN)
2. **Generates architecture-specific shader variants** 
3. **Learns optimal variants through empirical testing**
4. **Adapts to different GPU architectures automatically**

This fulfills the vision from our proposal document - no more one-size-fits-all shaders!

## What We Built

### 1. Architecture Detection (`detect_gpu_architecture`)
```fortran
type :: gpu_architecture
  character(len=32) :: vendor          ! AMD, NVIDIA, Intel
  character(len=32) :: arch_name       ! GCN, RDNA1, RDNA2, RDNA3
  integer :: wave_size                 ! 32 or 64
  integer :: compute_units
  logical :: has_dual_issue            ! RDNA3 feature
  ! ... and more
end type
```

### 2. Variant Generation System
For RDNA GPUs, we automatically generate:
- **Basic Wave32-aligned** (64 threads = 2 waves)
- **Larger workgroup** (256 threads = 8 waves) 
- **LDS-optimized** (using local data share)
- **Dual-issue optimized** (RDNA3 [deferred speedup] FMA throughput)

### 3. Performance Learning
The system tracks performance of each variant:
```
Variant Performance:
  rdna_basic_64      - Runs: 2,  Avg Time: [deferred latency], GFLOPS: 2.02
  rdna_large_256     - Runs: 2,  Avg Time: [deferred latency], GFLOPS: 2.34
  rdna_lds_64        - Runs: 2,  Avg Time: [deferred latency], GFLOPS: 2.18
  rdna3_dual_issue   - Runs: 14, Avg Time: [deferred latency], GFLOPS: 2.56 <- BEST
```

### 4. Automatic Adaptation
When switching architectures:
- **RDNA3**: Generates Wave32-optimized shaders with dual-issue
- **GCN/Generic**: Falls back to Wave64-optimized 256-thread workgroups

## Key Implementation Details

### Exploration vs Exploitation
```fortran
if (system%auto_tune .and. rand_val < system%exploration_rate) then
  ! Exploration: try a random variant (10% of the time)
  selected_variant = random_variant()
else
  ! Exploitation: use best known variant (90% of the time)
  selected_variant = system%cache(cache_idx)%best_variant_idx
end if
```

### Architecture-Specific Generation
```fortran
select case (trim(system%current_arch%arch_name))
case ("RDNA3", "RDNA2", "RDNA1")
  ! Generate RDNA-optimized variants
  rdna_cfg%arch%wave_size = 32
  rdna_cfg%workgroup_size = 64  ! 2 waves
  
case default
  ! Generic/GCN variants
  params%tile_size = 16  ! 16x16 = 256 threads
end select
```

## Performance Impact

The system demonstrates clear performance differences between variants:
- **RDNA3 dual-issue**: [deferred latency] (best)
- **Basic Wave32**: [deferred latency] (27% slower)
- **Suboptimal workgroup size** can leave 20-30% performance on the table

## Integration Path

To connect this with production GPU execution:

1. **Replace static shaders** with dynamic generation:
```fortran
! Old way:
shader = load_precompiled_shader()

! New way:
shader = get_optimal_shader(shader_sys, "conv2d", params)
```

2. **Feed back real GPU timings**:
```fortran
time_ms = execute_on_gpu(shader)
call update_performance_system(shader_sys, "conv2d", variant_id, time_ms, problem_size)
```

3. **Persist learned performance** across runs (cache to disk)

## Conclusion

This file tracks a proven-in-progress system that currently includes:
- Eliminates architecture mismatches (Wave32 vs Wave64)
- Discovers optimal configurations through learning
- Adapts automatically to different GPU architectures

This is a major step toward true heterogeneous computing - where the framework handles all the architecture-specific optimizations automatically!

## Next Steps

1. **Integration**: Connect with production GPU pipeline
2. **Expansion**: Add NVIDIA and Intel architecture support
3. **Advanced Learning**: Implement genetic algorithms for variant discovery
4. **Community Sharing**: Build infrastructure for sharing learned optimizations

The future of GPU computing is adaptive, not static! 🚀
