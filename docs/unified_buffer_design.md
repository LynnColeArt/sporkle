> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Unified Buffer Abstraction Design

## Overview
A unified buffer abstraction that provides zero-copy data sharing between CPU and GPU, with automatic synchronization and optimal memory access patterns.

## Design Goals

1. **Zero-Copy Operations**: Eliminate all memory transfers
2. **Type Safety**: Strong typing in Fortran interface
3. **Automatic Sync**: Integrate with fence primitives
4. **Performance**: Optimal access patterns for each platform
5. **Ease of Use**: Simple API hiding complexity

## Architecture

### Core Types

```fortran
module gpu_unified_buffers
  use kinds
  use iso_c_binding
  use gpu_fence_primitives
  
  ! Buffer access modes
  enum, bind(C)
    enumerator :: BUFFER_READ_ONLY = 1
    enumerator :: BUFFER_WRITE_ONLY = 2
    enumerator :: BUFFER_READ_WRITE = 3
  end enum
  
  ! Memory hints
  enum, bind(C)
    enumerator :: MEMORY_CPU_PREFERRED = 1
    enumerator :: MEMORY_GPU_PREFERRED = 2
    enumerator :: MEMORY_COHERENT = 3
    enumerator :: MEMORY_STREAMING = 4
  end enum
  
  ! Unified buffer type
  type :: unified_buffer
    private
    integer :: gl_buffer = 0
    type(c_ptr) :: cpu_ptr = c_null_ptr
    integer(i64) :: size_bytes = 0
    integer :: access_mode = BUFFER_READ_WRITE
    integer :: memory_hint = MEMORY_COHERENT
    logical :: is_mapped = .false.
    logical :: is_coherent = .true.
    type(gpu_fence) :: sync_fence
  end type
end module
```

### Buffer Lifecycle

```
1. Create
   ├─> Allocate GL buffer with glBufferStorage
   ├─> Set appropriate flags based on hints
   └─> Map persistently with glMapBufferRange

2. Access
   ├─> CPU Write
   │   ├─> Direct write through pointer
   │   ├─> Memory barrier if needed
   │   └─> Fence for GPU sync
   │
   └─> GPU Access
       ├─> Bind buffer to shader
       ├─> Execute compute
       └─> Fence signals completion

3. Destroy
   ├─> Wait for pending operations
   ├─> Unmap buffer
   └─> Delete GL resources
```

## API Design

### Basic Operations

```fortran
! Create a unified buffer
function create_unified_buffer(size, access_mode, memory_hint) result(buffer)
  integer(i64), intent(in) :: size
  integer, intent(in) :: access_mode
  integer, intent(in), optional :: memory_hint
  type(unified_buffer) :: buffer
end function

! Get CPU pointer for direct access
function get_cpu_pointer(buffer, element_size) result(ptr)
  type(unified_buffer), intent(in) :: buffer
  integer, intent(in) :: element_size
  type(c_ptr) :: ptr
end function

! Synchronization
subroutine sync_to_gpu(buffer)
  type(unified_buffer), intent(inout) :: buffer
end subroutine

subroutine sync_from_gpu(buffer)
  type(unified_buffer), intent(inout) :: buffer
end subroutine

! Cleanup
subroutine destroy_unified_buffer(buffer)
  type(unified_buffer), intent(inout) :: buffer
end subroutine
```

### Type-Safe Wrappers

```fortran
! Generic interface for different types
interface write_buffer
  module procedure write_buffer_f32, write_buffer_f64, write_buffer_i32
end interface

interface read_buffer
  module procedure read_buffer_f32, read_buffer_f64, read_buffer_i32
end interface

! Example implementation
subroutine write_buffer_f32(buffer, data, offset)
  type(unified_buffer), intent(inout) :: buffer
  real(sp), intent(in) :: data(:)
  integer(i64), intent(in), optional :: offset
  
  real(sp), pointer :: ptr(:)
  call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/4])
  
  if (present(offset)) then
    ptr(offset+1:offset+size(data)) = data
  else
    ptr(1:size(data)) = data
  end if
  
  if (.not. buffer%is_coherent) then
    call flush_buffer_range(buffer, offset, size(data)*4)
  end if
end subroutine
```

## Memory Access Patterns

### Write-Only Buffers (GPU Input)
- Use write-combined memory
- No CPU cache pollution
- Streaming writes optimal
- Example: Input data, weights

### Read-Only Buffers (GPU Output)
- Cacheable memory
- Prefetch friendly
- Good for result gathering
- Example: Convolution output

### Read-Write Buffers (Shared)
- Coherent mapping
- Automatic visibility
- Higher overhead but simpler
- Example: Accumulation buffers

## Integration with Conv2D

### Current Implementation
```fortran
! Allocate temporary buffers
allocate(gpu_input(size))
allocate(gpu_output(size))

! Copy data
gpu_input = cpu_input
call glBufferData(..., gpu_input)

! Execute
call gpu_compute()

! Copy back
call glGetBufferSubData(..., gpu_output)
cpu_output = gpu_output
```

### Zero-Copy Implementation
```fortran
! Create unified buffers once
input_buffer = create_unified_buffer(size, BUFFER_WRITE_ONLY)
output_buffer = create_unified_buffer(size, BUFFER_READ_ONLY)

! Direct write - no copy!
call write_buffer(input_buffer, cpu_input)

! Execute
call bind_buffer_to_shader(input_buffer, 0)
call bind_buffer_to_shader(output_buffer, 1)
call gpu_compute()

! Direct read - no copy!
call read_buffer(output_buffer, cpu_output)
```

## Synchronization Strategy

### Automatic Fencing
```fortran
! Buffer tracks its own fence
type :: unified_buffer
  type(gpu_fence) :: write_fence  ! CPU write completion
  type(gpu_fence) :: read_fence   ! GPU operation completion
end type

! Automatic sync on access
subroutine write_buffer_safe(buffer, data)
  ! Wait for previous GPU ops
  if (gpu_fence_is_valid(buffer%read_fence)) then
    call gpu_fence_wait(buffer%read_fence, timeout_ns)
  end if
  
  ! Write data
  call write_buffer_internal(buffer, data)
  
  ! Signal write completion
  buffer%write_fence = gpu_fence_create()
end subroutine
```

## Performance Optimizations

### 1. Buffer Pooling
- Pre-allocate common sizes
- Reuse across frames
- Avoid allocation overhead

### 2. Alignment
- Align to cache lines (64 bytes)
- Align to page boundaries (4KB)
- GPU optimal alignments

### 3. Batching
- Group small writes
- Minimize sync points
- Coalesce operations

### 4. Platform-Specific
- AMD: Write-combined for uploads
- Intel: Coherent everywhere
- NVIDIA: Explicit flushes

## Error Handling

```fortran
! Buffer creation can fail
if (.not. buffer_is_valid(buffer)) then
  ! Fallback to traditional copy
  call use_copy_fallback()
end if

! Map can fail
if (.not. c_associated(buffer%cpu_ptr)) then
  ! Handle out of address space
  call handle_map_failure()
end if
```

## Migration Path

### Phase 1: Drop-in Replacement
- Keep existing API
- Use unified buffers internally
- Measure performance

### Phase 2: Direct Access API
- Expose pointer access
- Remove intermediate copies
- Update algorithms

### Phase 3: Full Integration
- Redesign around zero-copy
- Streaming operations
- Async pipeline

## Expected Benefits

1. **Memory Usage**: 50% reduction (no duplicates)
2. **Bandwidth**: Save 15 GB/s (no transfers)
3. **Latency**: Remove 1-4ms per operation
4. **Simplicity**: Direct pointer access
5. **Scalability**: Foundation for PM4 direct

## Success Metrics

- Zero memory copies in hot path
- <0.1ms buffer management overhead
- 30% overall performance improvement
- Seamless integration with existing code
- Platform-agnostic interface