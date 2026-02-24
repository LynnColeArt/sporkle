> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Adaptive Parameter Passing - Implementation Status

## What We've Built

A historical framework for adaptive parameter passing in Fortran GPU kernels that:

1. **Parses Fortran kernels** to identify scalar vs array parameters
2. **Generates GLSL** for three different parameter passing methods
3. **Benchmarks** each method to select the optimal approach
4. **Uses proper GL interfaces** with well-documented functions

## Key Improvements Made Today

### 1. Added Missing GL Functions
```fortran
! Now properly defined in gl_constants.f90:
- glGetUniformLocation
- glUniform1i, glUniform1f, glUniform2i, glUniform3i, glUniform4i
- glUniform1iv, glUniform4iv  
- glBufferSubData
```

### 2. Replaced Hardcoded Values
- Binding slot 15 → `PARAM_BUFFER_BINDING` constant
- Can be easily changed without searching through code
- Properly exported and used across modules

### 3. Added Comprehensive Documentation
Each benchmarking method has comments describing intent:
- Pros and cons of each approach
- When each method is intended to be used
- What the code does (or is planned to do once GPU execution is connected)

### 4. Created Working Test Program
`test_adaptive_benchmark.f90` demonstrates:
- Creating a parameter strategy
- Running benchmarks
- Selecting optimal method
- Generating GLSL for the selected method

## Current Architecture

```
┌─────────────────────────┐
│   Fortran Kernel Code   │
└───────────┬─────────────┘
            │ parse
┌───────────▼─────────────┐
│ sporkle_shader_parser_v2│
│  - Identifies scalars   │
│  - Generates GLSL       │
└───────────┬─────────────┘
            │ 
┌───────────▼─────────────┐
│ sporkle_fortran_params  │
│  - Benchmarks methods   │
│  - Selects optimal      │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│   Optimal GLSL Output   │
│  (UNIFORM/BUFFER/INLINE)│
└─────────────────────────┘
```

## What Still Needs Work

1. **GPU Execution**: Currently mocked - needs real shader compilation
2. **INLINE Method**: Placeholder substitution not implemented
3. **GPU Timing**: Using CPU time instead of GPU timer queries
4. **Integration**: Connect to sporkle_fortran_shaders_v2 for full pipeline

## Example Output

When you run the benchmark:
```
BUFFER Method:
  Setup time:       [deferred latency]
  Dispatch time:    [deferred latency]
  Total time:       [deferred latency]

Recommended method: BUFFER
```

The staged harness currently reports BUFFER as the selected method for this test case.

## Next Steps

1. Connect real shader compilation (remove mocks)
2. Implement GPU timer queries for accurate benchmarking
3. Add parameter substitution for INLINE method
4. Test with real convolution kernels
