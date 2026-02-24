> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Reference Implementations

This file tracks our reference implementations - the optimized, tested, sacred versions that we compare everything else against.

## Critical Rule
**NEVER MODIFY REFERENCE IMPLEMENTATIONS WITHOUT EXPLICIT DISCUSSION**

## New Structure (As of 2024-12-20)
We now use the Reference Pattern to prevent loss of optimizations:
- `src/reference/` - Sacred, optimized implementations
- `src/experimental/` - Playground for new ideas  
- `src/production/` - User-facing interfaces

See DEVELOPMENT_PATTERNS.md for details.

## Current References

### 1. CPU Convolution
- **Status**: ⚠️ DEGRADED - Current best is only [deferred throughput metric] with OpenMP
- **Expected Performance**: ~90% of theoretical peak on Ryzen 7900X
- **Current Performance**: [deferred throughput metric] (test_conv_cpu_vs_gpu.f90)
- **Location**: `examples/test_conv_cpu_vs_gpu.f90` (but this is NOT the reference)
- **Missing Features**: 
  - Proper im2col transformation
  - GEMM-based approach
  - Cache blocking
  - Vectorization

### 2. GPU Convolution (Simple)
- **Status**: ✅ ESTABLISHED
- **Performance**: [deferred throughput metric] on RX 7900 XTX
- **Location**: `examples/test_conv_cpu_vs_gpu.c` (the GLSL shader)
- **Key Features**:
  - Direct convolution with boundary checks
  - Parameter buffer at binding 15
  - Local size 64

### 3. Memory Management
- **Status**: ✅ ESTABLISHED  
- **Location**: `src/sporkle_memory.f90`
- **Key Features**:
  - Automatic alignment
  - Usage tracking
  - Clear allocation/deallocation patterns

### 4. Parser V2
- **Status**: ✅ ESTABLISHED
- **Location**: `src/sporkle_shader_parser_v2.f90`
- **Key Features**:
  - Multi-line signature support
  - Comma-separated variable parsing
  - Parameter extraction for GPU buffers

## Missing References We Need

1. **Matrix Multiplication** - Where is our optimized GEMM?
2. **Im2col Transform** - Do we have a reference?
3. **Tensor Operations** - Need reference implementations
4. **Device Detection** - Current best approach?

## How to Add a Reference

1. Implementation must be fully optimized and tested
2. Performance must be documented with benchmark results
3. Code must be clean and well-commented
4. Add entry to this file with location and performance data
5. Mark source file with comment: `! REFERENCE IMPLEMENTATION - DO NOT MODIFY WITHOUT DISCUSSION`

## Regression Tracking

When performance regresses:
1. Check against reference implementation
2. Document what changed
3. Either fix or explicitly accept the regression with justification