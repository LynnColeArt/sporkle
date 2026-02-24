> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Fence API Design Document

## Overview
Replace heavyweight glFinish() with lightweight fence synchronization primitives for 2x performance improvement.

## Background

### Current Problem
- `glFinish()` blocks CPU until ALL GPU work completes
- Forces full pipeline flush
- No granularity - can't wait for specific operations
- Causes CPU spinning at 100% usage
- Adds 20-50µs latency per sync

### Fence Solution
- Lightweight synchronization objects
- Wait for specific operations only
- Non-blocking status queries
- Minimal CPU usage while waiting
- <1µs overhead per sync

## Platform Fence Mechanisms

### OpenGL (GL_ARB_sync)
```c
// Create fence after GPU commands
GLsync fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);

// Wait with timeout (nanoseconds)
GLenum result = glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, timeout_ns);

// Query without blocking
GLint status;
glGetSynciv(fence, GL_SYNC_STATUS, 1, NULL, &status);

// Cleanup
glDeleteSync(fence);
```

### Vulkan (for comparison)
```c
// More explicit but similar concept
VkFence fence;
vkCreateFence(device, &createInfo, NULL, &fence);
vkQueueSubmit(queue, 1, &submitInfo, fence);
vkWaitForFences(device, 1, &fence, VK_TRUE, timeout);
```

### AMD Native (future)
- Could use PM4 WAIT_REG_MEM packets
- Direct fence addresses in GPU memory
- No driver involvement

## Proposed Fortran API

```fortran
module gpu_fence_api
  use iso_c_binding
  implicit none
  
  ! Opaque fence handle
  type :: gpu_fence
    private
    type(c_ptr) :: handle = c_null_ptr
    logical :: is_valid = .false.
    integer(i64) :: fence_value = 0
  end type
  
  ! Fence wait results
  enum, bind(c)
    enumerator :: FENCE_READY = 0
    enumerator :: FENCE_TIMEOUT = 1
    enumerator :: FENCE_ERROR = 2
  end enum
  
  interface
    ! Create fence after current GPU commands
    function gpu_fence_create() result(fence)
      type(gpu_fence) :: fence
    end function
    
    ! Wait for fence with timeout
    function gpu_fence_wait(fence, timeout_ns) result(status)
      type(gpu_fence), intent(inout) :: fence
      integer(i64), intent(in) :: timeout_ns
      integer :: status  ! FENCE_READY, FENCE_TIMEOUT, or FENCE_ERROR
    end function
    
    ! Check fence status without blocking
    function gpu_fence_is_signaled(fence) result(signaled)
      type(gpu_fence), intent(in) :: fence
      logical :: signaled
    end function
    
    ! Clean up fence resources
    subroutine gpu_fence_destroy(fence)
      type(gpu_fence), intent(inout) :: fence
    end subroutine
  end interface
end module
```

## Integration Points

### 1. Juggler Pattern
```fortran
! Current (slow)
call glFinish()  ! Wait for everything

! New (fast)
call gpu_fence_wait(buffer%fence, timeout_ns=1000000)  ! Wait 1ms max
```

### 2. Async Executor
```fortran
! Track multiple operations
type :: async_operation
  type(gpu_fence) :: fence
  integer :: operation_id
  logical :: is_complete
end type
```

### 3. Performance Measurement
```fortran
! Precise GPU timing
call start_gpu_operation()
fence = gpu_fence_create()
! ... later ...
call gpu_fence_wait(fence, INFINITE)
gpu_time = get_gpu_timestamp()
```

## Fence Lifecycle

```
1. GPU Command Submission
   └─> 2. Create Fence
       └─> 3. Commands Execute on GPU
           └─> 4. Fence Signals
               └─> 5. CPU Wakes
                   └─> 6. Destroy Fence
```

## Timeout Strategy

1. **Immediate (0ns)**: Just check status
2. **Short (1ms)**: Normal operations  
3. **Medium (100ms)**: Heavy workloads
4. **Long (1s)**: Debug/recovery
5. **Infinite**: Never timeout (dangerous)

## Error Handling

```fortran
select case(gpu_fence_wait(fence, timeout_ns))
  case(FENCE_READY)
    ! Continue processing
  case(FENCE_TIMEOUT)
    ! Skip this buffer, try next
    call log_timeout_warning()
  case(FENCE_ERROR)
    ! GPU might be hung
    call initiate_gpu_recovery()
end select
```

## Platform Fallbacks

```fortran
! Runtime detection
if (gl_has_ARB_sync()) then
  ! Use fence path
  impl_ptr => fence_implementation_gl
else
  ! Fallback to glFinish
  impl_ptr => fence_implementation_legacy
  call log_performance_warning()
end if
```

## Performance Expectations

### Current (glFinish)
- CPU wait: 20-50µs
- CPU usage: 100% (spinning)
- Granularity: All or nothing
- Scalability: Poor

### Target (Fences)  
- CPU wait: <1µs
- CPU usage: ~0% (sleeping)
- Granularity: Per-operation
- Scalability: Excellent

## Implementation Priority

1. **Phase 1**: Basic fence create/wait/destroy
2. **Phase 2**: Fence pooling (avoid alloc)
3. **Phase 3**: Multi-fence wait
4. **Phase 4**: GPU timestamp correlation
5. **Phase 5**: PM4 native fences

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Platform doesn't support GL_ARB_sync | Fallback to glFinish |
| Fence never signals | Timeout + recovery |
| Fence object leaks | Pool with fixed size |
| Driver bugs | Vendor-specific workarounds |

## Success Criteria

- ✅ 2x reduction in sync overhead
- ✅ <1µs fence operations
- ✅ Zero CPU spinning
- ✅ Works on 90% of GPUs
- ✅ Graceful fallbacks

## Next Steps

1. Implement basic fence primitives
2. Create fence pool
3. Update juggler
4. Benchmark improvements
5. Add to async executor