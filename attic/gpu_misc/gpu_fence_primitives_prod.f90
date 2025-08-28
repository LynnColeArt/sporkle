! GPU Fence Synchronization Primitives (Production Version)
! ========================================================
!
! Lightweight synchronization primitives for GPU operations
! QA-fixed version with configurable parameters and no debug output

module gpu_fence_primitives_prod
  use kinds
  use iso_c_binding
  implicit none
  
  private
  public :: gpu_fence, gpu_fence_create, gpu_fence_destroy
  public :: gpu_fence_wait, gpu_fence_is_signaled, gpu_fence_is_valid
  public :: gpu_fence_pool_init, gpu_fence_pool_cleanup
  public :: FENCE_READY, FENCE_TIMEOUT, FENCE_ERROR, FENCE_INFINITE_TIMEOUT
  public :: set_fence_pool_size, get_fence_stats
  
  ! Fence status constants
  enum, bind(C)
    enumerator :: FENCE_READY = 0
    enumerator :: FENCE_TIMEOUT = 1
    enumerator :: FENCE_ERROR = 2
  end enum
  
  ! Infinite timeout constant
  integer(i64), parameter :: FENCE_INFINITE_TIMEOUT = int(z'7FFFFFFFFFFFFFFF', i64)
  
  ! OpenGL sync constants
  integer(c_int), parameter :: GL_SYNC_GPU_COMMANDS_COMPLETE = int(z'9117', c_int)
  integer(c_int), parameter :: GL_SYNC_FLUSH_COMMANDS_BIT = int(z'00000001', c_int)
  integer(c_int), parameter :: GL_ALREADY_SIGNALED = int(z'911A', c_int)
  integer(c_int), parameter :: GL_TIMEOUT_EXPIRED = int(z'911B', c_int)
  integer(c_int), parameter :: GL_CONDITION_SATISFIED = int(z'911C', c_int)
  integer(c_int), parameter :: GL_WAIT_FAILED = int(z'911D', c_int)
  integer(c_int), parameter :: GL_SYNC_STATUS = int(z'9114', c_int)
  integer(c_int), parameter :: GL_SIGNALED = int(z'9119', c_int)
  
  ! Fence object
  type :: gpu_fence
    private
    type(c_ptr) :: gl_sync = c_null_ptr
    logical :: is_valid = .false.
  end type gpu_fence
  
  ! Fence pool for allocation-free operation
  type :: fence_pool_entry
    type(c_ptr) :: gl_sync = c_null_ptr
    logical :: in_use = .false.
  end type
  
  ! Configurable pool size
  integer, save :: fence_pool_size = 64
  type(fence_pool_entry), allocatable, save :: fence_pool(:)
  logical, save :: pool_initialized = .false.
  
  ! Statistics tracking
  integer(i64), save :: total_fences_created = 0
  integer(i64), save :: total_fences_destroyed = 0
  integer(i64), save :: pool_exhaustion_count = 0
  
  ! OpenGL function interfaces
  interface
    function glFenceSync(condition, flags) bind(C, name="glFenceSync")
      import :: c_ptr, c_int
      integer(c_int), value :: condition, flags
      type(c_ptr) :: glFenceSync
    end function
    
    function glClientWaitSync(sync, flags, timeout) bind(C, name="glClientWaitSync")
      import :: c_ptr, c_int, c_int64_t
      type(c_ptr), value :: sync
      integer(c_int), value :: flags
      integer(c_int64_t), value :: timeout
      integer(c_int) :: glClientWaitSync
    end function
    
    subroutine glGetSynciv(sync, pname, bufSize, length, values) bind(C, name="glGetSynciv")
      import :: c_ptr, c_int
      type(c_ptr), value :: sync
      integer(c_int), value :: pname, bufSize
      type(c_ptr), value :: length
      integer(c_int), intent(out) :: values(*)
    end subroutine
    
    subroutine glDeleteSync(sync) bind(C, name="glDeleteSync")
      import :: c_ptr
      type(c_ptr), value :: sync
    end subroutine
    
    function glGetError() bind(C, name="glGetError")
      import :: c_int
      integer(c_int) :: glGetError
    end function
  end interface
  
contains

  ! Set fence pool size (must be called before pool_init)
  subroutine set_fence_pool_size(size)
    integer, intent(in) :: size
    
    if (.not. pool_initialized) then
      fence_pool_size = max(1, size)
    end if
  end subroutine set_fence_pool_size
  
  ! Get fence statistics
  subroutine get_fence_stats(created, destroyed, exhaustions, pool_used)
    integer(i64), intent(out) :: created, destroyed, exhaustions
    integer, intent(out) :: pool_used
    integer :: i
    
    created = total_fences_created
    destroyed = total_fences_destroyed
    exhaustions = pool_exhaustion_count
    
    pool_used = 0
    if (allocated(fence_pool)) then
      do i = 1, fence_pool_size
        if (fence_pool(i)%in_use) pool_used = pool_used + 1
      end do
    end if
  end subroutine get_fence_stats
  
  ! Initialize fence pool
  subroutine gpu_fence_pool_init()
    integer :: i
    
    if (pool_initialized) return
    
    allocate(fence_pool(fence_pool_size))
    
    do i = 1, fence_pool_size
      fence_pool(i)%gl_sync = c_null_ptr
      fence_pool(i)%in_use = .false.
    end do
    
    pool_initialized = .true.
    
    ! Reset statistics
    total_fences_created = 0
    total_fences_destroyed = 0
    pool_exhaustion_count = 0
  end subroutine gpu_fence_pool_init
  
  ! Cleanup fence pool
  subroutine gpu_fence_pool_cleanup()
    integer :: i
    
    if (.not. pool_initialized) return
    
    ! Delete any remaining sync objects
    do i = 1, fence_pool_size
      if (c_associated(fence_pool(i)%gl_sync)) then
        call glDeleteSync(fence_pool(i)%gl_sync)
      end if
    end do
    
    deallocate(fence_pool)
    pool_initialized = .false.
  end subroutine gpu_fence_pool_cleanup
  
  ! Create a new fence
  function gpu_fence_create() result(fence)
    type(gpu_fence) :: fence
    integer :: i
    type(c_ptr) :: sync_obj
    
    fence%is_valid = .false.
    fence%gl_sync = c_null_ptr
    
    if (.not. pool_initialized) then
      call gpu_fence_pool_init()
    end if
    
    ! Find free slot in pool
    do i = 1, fence_pool_size
      if (.not. fence_pool(i)%in_use) then
        ! Create new sync object if needed
        if (.not. c_associated(fence_pool(i)%gl_sync)) then
          sync_obj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
          if (c_associated(sync_obj)) then
            fence_pool(i)%gl_sync = sync_obj
          else
            return
          end if
        else
          ! Reuse existing sync object
          sync_obj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
          if (c_associated(sync_obj)) then
            call glDeleteSync(fence_pool(i)%gl_sync)
            fence_pool(i)%gl_sync = sync_obj
          else
            return
          end if
        end if
        
        fence_pool(i)%in_use = .true.
        fence%gl_sync = fence_pool(i)%gl_sync
        fence%is_valid = .true.
        total_fences_created = total_fences_created + 1
        return
      end if
    end do
    
    ! Pool exhausted
    pool_exhaustion_count = pool_exhaustion_count + 1
    
  end function gpu_fence_create
  
  ! Destroy a fence
  subroutine gpu_fence_destroy(fence)
    type(gpu_fence), intent(inout) :: fence
    integer :: i
    
    if (.not. fence%is_valid .or. .not. c_associated(fence%gl_sync)) return
    
    ! Find fence in pool and mark as free
    do i = 1, fence_pool_size
      if (c_associated(fence_pool(i)%gl_sync, fence%gl_sync)) then
        fence_pool(i)%in_use = .false.
        exit
      end if
    end do
    
    fence%is_valid = .false.
    fence%gl_sync = c_null_ptr
    total_fences_destroyed = total_fences_destroyed + 1
    
  end subroutine gpu_fence_destroy
  
  ! Wait for fence with timeout
  function gpu_fence_wait(fence, timeout_ns) result(status)
    type(gpu_fence), intent(inout) :: fence
    integer(i64), intent(in) :: timeout_ns
    integer :: status
    
    integer(c_int) :: gl_result
    integer(c_int64_t) :: gl_timeout
    integer(c_int) :: flags
    integer(c_int) :: gl_error
    
    status = FENCE_ERROR
    
    if (.not. fence%is_valid .or. .not. c_associated(fence%gl_sync)) then
      return
    end if
    
    ! Convert timeout
    if (timeout_ns == FENCE_INFINITE_TIMEOUT) then
      gl_timeout = int(z'7FFFFFFFFFFFFFFF', c_int64_t)
    else
      gl_timeout = int(timeout_ns, c_int64_t)
    end if
    
    flags = GL_SYNC_FLUSH_COMMANDS_BIT
    
    gl_result = glClientWaitSync(fence%gl_sync, flags, gl_timeout)
    
    select case(gl_result)
    case(GL_ALREADY_SIGNALED, GL_CONDITION_SATISFIED)
      status = FENCE_READY
    case(GL_TIMEOUT_EXPIRED)
      status = FENCE_TIMEOUT
    case default
      status = FENCE_ERROR
      gl_error = glGetError()
    end select
    
  end function gpu_fence_wait
  
  ! Check if fence is signaled (non-blocking)
  function gpu_fence_is_signaled(fence) result(signaled)
    type(gpu_fence), intent(in) :: fence
    logical :: signaled
    
    integer(c_int) :: sync_status(1)
    
    signaled = .false.
    
    if (.not. fence%is_valid .or. .not. c_associated(fence%gl_sync)) then
      return
    end if
    
    call glGetSynciv(fence%gl_sync, GL_SYNC_STATUS, 1, c_null_ptr, sync_status)
    
    signaled = (sync_status(1) == GL_SIGNALED)
    
  end function gpu_fence_is_signaled
  
  ! Check if fence is valid
  function gpu_fence_is_valid(fence) result(valid)
    type(gpu_fence), intent(in) :: fence
    logical :: valid
    
    valid = fence%is_valid .and. c_associated(fence%gl_sync)
    
  end function gpu_fence_is_valid
  
end module gpu_fence_primitives_prod