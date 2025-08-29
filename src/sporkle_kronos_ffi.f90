module sporkle_kronos_ffi
  ! Fortran FFI bindings for Kronos zero-overhead Vulkan compute
  ! ============================================================
  ! Provides clean Fortran interface to Kronos's safe Rust API
  
  use iso_c_binding
  use kinds
  implicit none
  private
  
  ! Public API
  public :: kronos_context, kronos_buffer, kronos_pipeline, kronos_fence
  public :: kronos_init, kronos_cleanup, kronos_create_buffer, kronos_destroy_buffer
  public :: kronos_create_pipeline, kronos_dispatch, kronos_wait_fence
  public :: kronos_map_buffer, kronos_unmap_buffer
  
  ! Error codes
  integer(c_int), parameter, public :: KRONOS_SUCCESS = 0
  integer(c_int), parameter, public :: KRONOS_ERROR_INIT = -1
  integer(c_int), parameter, public :: KRONOS_ERROR_OOM = -2
  integer(c_int), parameter, public :: KRONOS_ERROR_COMPILE = -3
  integer(c_int), parameter, public :: KRONOS_ERROR_INVALID = -4
  
  ! Opaque handle types
  type :: kronos_context
    type(c_ptr) :: handle = c_null_ptr
  end type kronos_context
  
  type :: kronos_buffer
    type(c_ptr) :: handle = c_null_ptr
    integer(c_size_t) :: size = 0
  end type kronos_buffer
  
  type :: kronos_pipeline
    type(c_ptr) :: handle = c_null_ptr
  end type kronos_pipeline
  
  type :: kronos_fence
    type(c_ptr) :: handle = c_null_ptr
  end type kronos_fence
  
  ! C function interfaces
  interface
    ! Context management
    function kronos_create_context_c() bind(C, name="kronos_compute_create_context") result(ctx)
      import :: c_ptr
      type(c_ptr) :: ctx
    end function kronos_create_context_c
    
    subroutine kronos_destroy_context_c(ctx) bind(C, name="kronos_compute_destroy_context")
      import :: c_ptr
      type(c_ptr), value :: ctx
    end subroutine kronos_destroy_context_c
    
    ! Buffer management
    function kronos_create_buffer_c(ctx, size) bind(C, name="kronos_compute_create_buffer") result(buf)
      import :: c_ptr, c_size_t
      type(c_ptr), value :: ctx
      integer(c_size_t), value :: size
      type(c_ptr) :: buf
    end function kronos_create_buffer_c
    
    subroutine kronos_destroy_buffer_c(ctx, buf) bind(C, name="kronos_compute_destroy_buffer")
      import :: c_ptr
      type(c_ptr), value :: ctx, buf
    end subroutine kronos_destroy_buffer_c
    
    function kronos_map_buffer_c(ctx, buf) bind(C, name="kronos_compute_map_buffer") result(ptr)
      import :: c_ptr
      type(c_ptr), value :: ctx, buf
      type(c_ptr) :: ptr
    end function kronos_map_buffer_c
    
    subroutine kronos_unmap_buffer_c(ctx, buf) bind(C, name="kronos_compute_unmap_buffer")
      import :: c_ptr
      type(c_ptr), value :: ctx, buf
    end subroutine kronos_unmap_buffer_c
    
    ! Pipeline management
    function kronos_create_pipeline_c(ctx, spirv_data, spirv_size) &
        bind(C, name="kronos_compute_create_pipeline") result(pipe)
      import :: c_ptr, c_size_t
      type(c_ptr), value :: ctx, spirv_data
      integer(c_size_t), value :: spirv_size
      type(c_ptr) :: pipe
    end function kronos_create_pipeline_c
    
    subroutine kronos_destroy_pipeline_c(ctx, pipe) bind(C, name="kronos_destroy_pipeline")
      import :: c_ptr
      type(c_ptr), value :: ctx, pipe
    end subroutine kronos_destroy_pipeline_c
    
    ! Dispatch and synchronization
    function kronos_dispatch_c(ctx, pipe, buffers, num_buffers, &
                              global_x, global_y, global_z) &
        bind(C, name="kronos_compute_dispatch") result(fence)
      import :: c_ptr, c_int, c_size_t
      type(c_ptr), value :: ctx, pipe, buffers
      integer(c_int), value :: num_buffers
      integer(c_size_t), value :: global_x, global_y, global_z
      type(c_ptr) :: fence
    end function kronos_dispatch_c
    
    function kronos_wait_fence_c(ctx, fence, timeout_ns) &
        bind(C, name="kronos_compute_wait_fence") result(status)
      import :: c_ptr, c_int, c_int64_t
      type(c_ptr), value :: ctx, fence
      integer(c_int64_t), value :: timeout_ns
      integer(c_int) :: status
    end function kronos_wait_fence_c
    
    subroutine kronos_destroy_fence_c(ctx, fence) bind(C, name="kronos_compute_destroy_fence")
      import :: c_ptr
      type(c_ptr), value :: ctx, fence
    end subroutine kronos_destroy_fence_c
  end interface
  
contains
  
  function kronos_init() result(ctx)
    type(kronos_context) :: ctx
    
    ctx%handle = kronos_create_context_c()
    
  end function kronos_init
  
  subroutine kronos_cleanup(ctx)
    type(kronos_context), intent(inout) :: ctx
    
    if (c_associated(ctx%handle)) then
      call kronos_destroy_context_c(ctx%handle)
      ctx%handle = c_null_ptr
    end if
    
  end subroutine kronos_cleanup
  
  function kronos_create_buffer(ctx, size_bytes) result(buffer)
    type(kronos_context), intent(in) :: ctx
    integer(c_size_t), intent(in) :: size_bytes
    type(kronos_buffer) :: buffer
    
    buffer%handle = kronos_create_buffer_c(ctx%handle, size_bytes)
    buffer%size = size_bytes
    
  end function kronos_create_buffer
  
  subroutine kronos_destroy_buffer(ctx, buffer)
    type(kronos_context), intent(in) :: ctx
    type(kronos_buffer), intent(inout) :: buffer
    
    if (c_associated(buffer%handle)) then
      call kronos_destroy_buffer_c(ctx%handle, buffer%handle)
      buffer%handle = c_null_ptr
      buffer%size = 0_c_size_t
    end if
    
  end subroutine kronos_destroy_buffer
  
  function kronos_map_buffer(ctx, buffer, data_ptr) result(status)
    type(kronos_context), intent(in) :: ctx
    type(kronos_buffer), intent(in) :: buffer
    type(c_ptr), intent(out) :: data_ptr
    integer :: status
    
    data_ptr = kronos_map_buffer_c(ctx%handle, buffer%handle)
    if (c_associated(data_ptr)) then
      status = KRONOS_SUCCESS
    else
      status = KRONOS_ERROR_INVALID
    end if
    
  end function kronos_map_buffer
  
  subroutine kronos_unmap_buffer(ctx, buffer)
    type(kronos_context), intent(in) :: ctx
    type(kronos_buffer), intent(in) :: buffer
    
    call kronos_unmap_buffer_c(ctx%handle, buffer%handle)
    
  end subroutine kronos_unmap_buffer
  
  function kronos_create_pipeline(ctx, spirv_code, spirv_size) result(pipeline)
    type(kronos_context), intent(in) :: ctx
    integer(c_int8_t), intent(in), target :: spirv_code(*)
    integer(c_size_t), intent(in) :: spirv_size
    type(kronos_pipeline) :: pipeline
    
    pipeline%handle = kronos_create_pipeline_c(ctx%handle, &
                                               c_loc(spirv_code), &
                                               spirv_size)
    
  end function kronos_create_pipeline
  
  function kronos_dispatch(ctx, pipeline, buffers, global_size) result(fence)
    type(kronos_context), intent(in) :: ctx
    type(kronos_pipeline), intent(in) :: pipeline
    type(kronos_buffer), intent(in) :: buffers(:)
    integer(c_size_t), intent(in) :: global_size(3)
    type(kronos_fence) :: fence
    
    type(c_ptr), allocatable, target :: buffer_handles(:)
    integer :: i
    
    ! Extract buffer handles
    allocate(buffer_handles(size(buffers)))
    do i = 1, size(buffers)
      buffer_handles(i) = buffers(i)%handle
    end do
    
    fence%handle = kronos_dispatch_c(ctx%handle, &
                                    pipeline%handle, &
                                    c_loc(buffer_handles), &
                                    size(buffers, kind=c_int), &
                                    global_size(1), &
                                    global_size(2), &
                                    global_size(3))
    
    deallocate(buffer_handles)
    
  end function kronos_dispatch
  
  function kronos_wait_fence(ctx, fence, timeout_ms) result(status)
    type(kronos_context), intent(in) :: ctx
    type(kronos_fence), intent(in) :: fence
    integer, intent(in), optional :: timeout_ms
    integer :: status
    
    integer(c_int64_t) :: timeout_ns
    
    if (present(timeout_ms)) then
      timeout_ns = int(timeout_ms, c_int64_t) * 1000000_c_int64_t
    else
      timeout_ns = 5000000000_c_int64_t  ! 5 seconds default
    end if
    
    status = kronos_wait_fence_c(ctx%handle, fence%handle, timeout_ns)
    
  end function kronos_wait_fence
  
end module sporkle_kronos_ffi