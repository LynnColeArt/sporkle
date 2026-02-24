> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Fortran Shader MVP Implementation Plan

Based on Mini's excellent feedback, here's our concrete plan for Fortran-native GPU shaders.

## Phase 1: MVP Features

### Kernel Grammar (v0)
```fortran
!@kernel(local_size_x=64, local_size_y=1, in=1, out=1)
pure elemental subroutine store_deadbeef(i, out)
  use iso_fortran_env
  integer(int32), value :: i
  integer(int32), intent(out) :: out
  out = int(z'DEADBEEF', int32)
end subroutine
```

### Supported Types
- `integer(int32|int64)`
- `real(real32|real64)` 
- `logical(c_bool)`
- Arrays as device buffers only

### Allowed Operations
- Elementwise math
- Simple indexing
- No allocations/IO
- No recursion

## Implementation Components

### 1. Parser/Translator
Simple Python or Fortran parser that:
- Validates kernel annotations
- Checks allowed subset
- Emits GLSL ES 3.10 compute shader
- Generates reflection metadata (JSON)

### 2. Runtime API
```fortran
call sporkle_compile_and_dispatch( &
  kernel = "store_deadbeef", &
  global_size = N, &
  args = (/ output_buffer /), &
  device = SPORKLE_AUTO &
)
```

### 3. Backend Flow
1. Detect device (already have this)
2. Generate GLSL from Fortran kernel
3. Compile via our existing OpenGL infrastructure
4. Bind buffers using reflection data
5. Dispatch with proper barriers
6. Fence and wait

### 4. Caching
- Key: `(kernel_hash, device_id, driver_version, local_size)`
- Store compiled program objects
- Zero-compile on subsequent runs

## Test Plan

1. **Fill literal** - Exercises basic path
2. **SAXPY** - Scalar + two buffers
3. **Reduce sum** - Tests barriers & workgroups
4. **Shape zoo** - Edge cases (primes, misaligned, huge)
5. **Precision modes** - strict/balanced/fast

## Integration Details

### GBM/EGL Binding
Create EGLDisplay from chosen render node FD to prevent GPU hopping.

### Error Handling
Capture and surface shader compile/link logs verbatim.

### APU Coherency
Keep output in GTT during tests, wait on fence, then read.

## Example: Generated GLSL

From Fortran:
```fortran
!@kernel(local_size_x=256, in=2, out=1)
pure subroutine saxpy(i, a, x, y)
  integer(int32), value :: i
  real(real32), value :: a
  real(real32), intent(in) :: x
  real(real32), intent(inout) :: y
  y = a * x + y
end subroutine
```

To GLSL:
```glsl
#version 310 es
layout(local_size_x = 256) in;
layout(std430, binding = 0) readonly buffer X { float x[]; };
layout(std430, binding = 1) buffer Y { float y[]; };
uniform float a;

void main() {
  uint i = gl_GlobalInvocationID.x;
  if (i >= y.length()) return;
  y[i] = a * x[i] + y[i];
}
```

## Next Steps

1. Implement minimal parser for `store_deadbeef`
2. Wire into existing GLSL compute infrastructure
3. Add SAXPY as second test case
4. Build out test suite

This gives us a "Fortran shaders" pathway for early milestones while preserving future flexibility.
