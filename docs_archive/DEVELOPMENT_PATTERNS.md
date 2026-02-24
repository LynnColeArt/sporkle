> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle Development Patterns

## The Reference Pattern

To prevent the constant loss of optimized implementations, we use the **Reference Pattern**:

```
src/
  reference/      # Sacred, optimized implementations (DO NOT MODIFY)
  experimental/   # Playground for new ideas
  production/     # User-facing interfaces that link to implementations
```

### The Flow

1. **Start in experimental/** - Try new ideas, break things, experiment
2. **Benchmark everything** - Measure against reference implementations  
3. **Promote winners** - If it beats reference, it can become the new reference
4. **Production links to reference** - Users get the best implementation automatically

### Rules

#### Reference Rules
- **NO DIRECT MODIFICATIONS** - Changes require discussion and benchmarking
- **FULLY OPTIMIZED** - These are our best implementations
- **PERFORMANCE DOCUMENTED** - Must document achieved GFLOPS/metrics
- **WELL COMMENTED** - Explain the optimizations for future us

#### Experimental Rules
- **ANYTHING GOES** - Try wild optimizations
- **QUICK AND DIRTY OK** - Don't polish until it proves itself
- **BENCHMARK REQUIRED** - We need to know if it's better
- **FAILED EXPERIMENTS STAY** - Document what didn't work and why

#### Production Rules  
- **INTERFACES ONLY** - Just select which implementation to use
- **API STABILITY** - Changes must be backward compatible
- **REFERENCE BY DEFAULT** - Use the best we have
- **RUNTIME SWITCHABLE** - Allow users to select implementations

### Example: Adding a New Convolution

1. Create `src/experimental/conv2d_winograd.f90`
2. Implement and benchmark
3. If it beats `src/reference/conv2d_reference.f90`:
   - Clean up code
   - Add comprehensive tests
   - Document optimizations
   - Move to reference after review
4. Update `src/production/sporkle_conv2d.f90` to make it available

### Protection Against Regression

Each reference implementation must start with:

```fortran
! REFERENCE IMPLEMENTATION - DO NOT MODIFY WITHOUT DISCUSSION
! 
! Performance achieved:
!   - [deferred throughput metric] on AMD Ryzen 7900X (16 cores)
!   - [deferred throughput metric] on Intel Xeon E5-2680 (12 cores)
!
! Key optimizations:
!   - Cache-oblivious tiling
!   - Memory bandwidth optimization via fusion
!   - NUMA-aware memory allocation
!   - AVX-512 vectorization
!
! Last verified: 2024-12-20
! Original author: Lynn & Claude
!
! DO NOT MODIFY THIS FILE DIRECTLY
! Create experimental version if you want to try improvements
```

### Why This Works

1. **Clear Separation** - No confusion about what's production vs experiment
2. **Protected Performance** - Reference implementations can't be casually overwritten
3. **Innovation Friendly** - Experimental allows trying anything
4. **User Stability** - Production interface doesn't change even if implementation does

### Migration Plan

1. Move `sporkle_memory.f90` → `src/reference/memory_pool_reference.f90` ✓
2. Find the [deferred throughput metric] convolution → `src/reference/conv2d_reference.f90`
3. Move working GPU shader → `src/reference/conv2d_glsl_reference.glsl`
4. Create production interfaces in `src/production/`
5. Update all tests to use production interfaces

This pattern ensures we never again lose our hard-won optimizations to a "quick test implementation."