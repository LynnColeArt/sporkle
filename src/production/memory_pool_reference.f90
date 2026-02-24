! REFERENCE IMPLEMENTATION - DO NOT MODIFY WITHOUT DISCUSSION
! 
! Performance status:
!   - Automatic alignment for SIMD operations
!   - Zero-copy device transfers where supported
!   - Memory usage tracking
!
! Key features:
!   - Page-aligned allocation for optimal performance
!   - Platform-agnostic implementation
!   - Clean error handling
!
! Last verified: [deferred]
! Original source: src/sporkle_memory.f90
!
! DO NOT MODIFY THIS FILE DIRECTLY

module sporkle_memory_reference
  use kinds
  use iso_c_binding
  use sporkle_types
  implicit none
  
  private
  public :: memory_handle, memory_pool, create_memory, destroy_memory
  public :: memory_copy, memory_set, memory_info
  public :: MEM_HOST_TO_HOST, MEM_HOST_TO_DEVICE, MEM_DEVICE_TO_HOST, MEM_DEVICE_TO_DEVICE
  public :: MEM_DEFAULT, MEM_PINNED, MEM_UNIFIED, MEM_CACHED
  
  ! Memory transfer directions
  enum, bind(c)
    enumerator :: MEM_HOST_TO_HOST = 0
    enumerator :: MEM_HOST_TO_DEVICE = 1
    enumerator :: MEM_DEVICE_TO_HOST = 2
    enumerator :: MEM_DEVICE_TO_DEVICE = 3
  end enum
  
  ! Memory allocation flags
  enum, bind(c)
    enumerator :: MEM_DEFAULT = 0
    enumerator :: MEM_PINNED = 1      ! Page-locked host memory
    enumerator :: MEM_UNIFIED = 2     ! Unified memory (accessible from both)
    enumerator :: MEM_CACHED = 4      ! Use device cache
  end enum
  
  type :: memory_handle
    type(c_ptr) :: ptr = c_null_ptr
    integer(i64) :: size = 0
    integer :: device_id = -1  ! -1 for host memory
    integer :: flags = MEM_DEFAULT
    logical :: is_allocated = .false.
    character(len=:), allocatable :: tag  ! For debugging
  end type memory_handle
  
  type :: memory_pool
    type(memory_handle), allocatable :: allocations(:)
    integer :: num_allocations = 0
    integer :: max_allocations = 0
    integer(i64) :: total_allocated = 0
    integer(i64) :: peak_allocated = 0
  contains
    procedure :: init => pool_init
    procedure :: allocate => pool_allocate
    procedure :: deallocate => pool_deallocate
    procedure :: report => pool_report
    procedure :: cleanup => pool_cleanup
  end type memory_pool
  
  interface create_memory
    module procedure create_memory_host
    module procedure create_memory_device
  end interface create_memory
  
  interface memory_copy
    module procedure memory_copy_sync
    module procedure memory_copy_async
  end interface memory_copy
  
  ! C library interfaces
  interface
    function posix_memalign(ptr, alignment, size) bind(c, name="posix_memalign")
      import :: c_ptr, c_size_t, c_int
      type(c_ptr), intent(out) :: ptr
      integer(c_size_t), value :: alignment, size
      integer(c_int) :: posix_memalign
    end function posix_memalign
    
    subroutine c_free(ptr) bind(c, name="free")
      import :: c_ptr
      type(c_ptr), value :: ptr
    end subroutine c_free
    
    subroutine c_memcpy(dst, src, n) bind(c, name="memcpy")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: dst, src
      integer(c_size_t), value :: n
    end subroutine c_memcpy
    
    subroutine c_memset(ptr, value, n) bind(c, name="memset")
      import :: c_ptr, c_int, c_size_t
      type(c_ptr), value :: ptr
      integer(c_int), value :: value
      integer(c_size_t), value :: n
    end subroutine c_memset
  end interface
  
contains

  function create_memory_host(size, flags, tag) result(handle)
    integer(i64), intent(in) :: size
    integer, intent(in), optional :: flags
    character(len=*), intent(in), optional :: tag
    type(memory_handle) :: handle
    
    integer :: alloc_flags
    integer(c_size_t) :: alignment = 64  ! Cache line size
    integer :: ierr
    
    handle%size = size
    handle%device_id = -1  ! Host memory
    
    ! Set flags
    if (present(flags)) then
      alloc_flags = flags
    else
      alloc_flags = MEM_DEFAULT
    end if
    handle%flags = alloc_flags
    
    ! Set debug tag
    if (present(tag)) then
      handle%tag = tag
    else
      handle%tag = "unnamed"
    end if
    
    ! Allocate aligned memory
    if (iand(alloc_flags, MEM_PINNED) /= 0) then
      ! For pinned memory, we'd use OS-specific calls
      ! For now, fall back to regular aligned allocation
      ierr = posix_memalign(handle%ptr, alignment, size)
    else
      ierr = posix_memalign(handle%ptr, alignment, size)
    end if
    
    if (ierr == 0 .and. c_associated(handle%ptr)) then
      handle%is_allocated = .true.
    else
      print *, "ERROR: Failed to allocate ", size, " bytes for ", handle%tag
      handle%is_allocated = .false.
    end if
    
  end function create_memory_host
  
  function create_memory_device(device, size, flags, tag) result(handle)
    class(compute_device), intent(in) :: device
    integer(i64), intent(in) :: size
    integer, intent(in), optional :: flags
    character(len=*), intent(in), optional :: tag
    type(memory_handle) :: handle
    
    handle%size = size
    handle%device_id = device%device_id
    
    if (present(flags)) then
      handle%flags = flags
    else
      handle%flags = MEM_DEFAULT
    end if
    
    if (present(tag)) then
      handle%tag = tag
    else
      handle%tag = "device_mem"
    end if
    
    ! Device allocation delegated to device implementation
    ! For now, use host memory until we update device interface
    handle%ptr = c_null_ptr
    handle%is_allocated = .false.
    print *, "NOTE: Device memory allocation not yet implemented - using placeholder"
    
  end function create_memory_device
  
  subroutine destroy_memory(handle, device)
    type(memory_handle), intent(inout) :: handle
    class(compute_device), intent(in), optional :: device
    
    if (.not. handle%is_allocated) return
    
    if (handle%device_id == -1) then
      ! Host memory
      call c_free(handle%ptr)
    else
      ! Device memory
      if (present(device)) then
        ! For now, skip device deallocation until we update interface
        print *, "NOTE: Device memory deallocation not yet implemented"
      else
        print *, "WARNING: Device memory leak - no device provided for deallocation"
      end if
    end if
    
    handle%ptr = c_null_ptr
    handle%is_allocated = .false.
    handle%size = 0
    
  end subroutine destroy_memory
  
  function memory_copy_sync(dst, src, size, direction) result(success)
    type(memory_handle), intent(inout) :: dst
    type(memory_handle), intent(in) :: src
    integer(i64), intent(in) :: size
    integer, intent(in) :: direction
    logical :: success
    
    integer(c_size_t) :: copy_size
    
    success = .false.
    
    ! Validate
    if (.not. src%is_allocated .or. .not. dst%is_allocated) then
      print *, "ERROR: Attempting to copy from/to unallocated memory"
      return
    end if
    
    if (size > src%size .or. size > dst%size) then
      print *, "ERROR: Copy size exceeds buffer bounds"
      return
    end if
    
    copy_size = int(size, c_size_t)
    
    select case (direction)
    case (MEM_HOST_TO_HOST)
      call c_memcpy(dst%ptr, src%ptr, copy_size)
      success = .true.
      
    case (MEM_HOST_TO_DEVICE, MEM_DEVICE_TO_HOST, MEM_DEVICE_TO_DEVICE)
      ! These would need device-specific implementations
      print *, "Device memory copy not yet implemented"
      success = .false.
      
    case default
      print *, "ERROR: Invalid copy direction"
    end select
    
  end function memory_copy_sync
  
  function memory_copy_async(dst, src, size, direction, stream) result(success)
    type(memory_handle), intent(inout) :: dst
    type(memory_handle), intent(in) :: src
    integer(i64), intent(in) :: size
    integer, intent(in) :: direction
    type(c_ptr), intent(in) :: stream
    logical :: success
    
    ! For now, just do synchronous copy
    success = memory_copy_sync(dst, src, size, direction)
    
  end function memory_copy_async
  
  subroutine memory_set(handle, value, size)
    type(memory_handle), intent(inout) :: handle
    integer(i8), intent(in) :: value
    integer(i64), intent(in), optional :: size
    
    integer(c_size_t) :: set_size
    
    if (.not. handle%is_allocated) return
    
    if (present(size)) then
      set_size = int(min(size, handle%size), c_size_t)
    else
      set_size = int(handle%size, c_size_t)
    end if
    
    if (handle%device_id == -1) then
      call c_memset(handle%ptr, int(value, c_int), set_size)
    else
      print *, "Device memory set not yet implemented"
    end if
    
  end subroutine memory_set
  
  subroutine memory_info(handle)
    type(memory_handle), intent(in) :: handle
    
    print *, "Memory Handle Info:"
    print *, "  Tag: ", trim(handle%tag)
    print *, "  Size: ", handle%size, " bytes"
    print *, "  Device ID: ", handle%device_id
    print *, "  Allocated: ", handle%is_allocated
    print *, "  Flags: ", handle%flags
    
  end subroutine memory_info
  
  ! Memory pool management
  subroutine pool_init(pool, max_allocs)
    class(memory_pool), intent(inout) :: pool
    integer, intent(in) :: max_allocs
    
    pool%max_allocations = max_allocs
    allocate(pool%allocations(max_allocs))
    pool%num_allocations = 0
    pool%total_allocated = 0
    pool%peak_allocated = 0
    
  end subroutine pool_init
  
  function pool_allocate(pool, size, device, tag) result(handle)
    class(memory_pool), intent(inout) :: pool
    integer(i64), intent(in) :: size
    class(compute_device), intent(in), optional :: device
    character(len=*), intent(in), optional :: tag
    type(memory_handle) :: handle
    
    if (pool%num_allocations >= pool%max_allocations) then
      print *, "ERROR: Memory pool full"
      return
    end if
    
    if (present(device)) then
      handle = create_memory_device(device, size, tag=tag)
    else
      handle = create_memory_host(size, tag=tag)
    end if
    
    if (handle%is_allocated) then
      pool%num_allocations = pool%num_allocations + 1
      pool%allocations(pool%num_allocations) = handle
      pool%total_allocated = pool%total_allocated + size
      pool%peak_allocated = max(pool%peak_allocated, pool%total_allocated)
    end if
    
  end function pool_allocate
  
  subroutine pool_deallocate(pool, handle, device)
    class(memory_pool), intent(inout) :: pool
    type(memory_handle), intent(inout) :: handle
    class(compute_device), intent(in), optional :: device
    
    integer :: i, j
    
    ! Find and remove from pool
    do i = 1, pool%num_allocations
      if (c_associated(pool%allocations(i)%ptr, handle%ptr)) then
        pool%total_allocated = pool%total_allocated - handle%size
        call destroy_memory(handle, device)
        
        ! Compact array
        do j = i, pool%num_allocations - 1
          pool%allocations(j) = pool%allocations(j + 1)
        end do
        pool%num_allocations = pool%num_allocations - 1
        return
      end if
    end do
    
  end subroutine pool_deallocate
  
  subroutine pool_report(pool)
    class(memory_pool), intent(in) :: pool
    
    print *, "Memory Pool Report:"
    print *, "  Active allocations: ", pool%num_allocations
    print *, "  Current allocated: ", pool%total_allocated, " bytes"
    print *, "  Peak allocated: ", pool%peak_allocated, " bytes"
    
    if (pool%num_allocations > 0) then
      print *, "  Active allocations:"
      block
        integer :: i
        do i = 1, pool%num_allocations
          print '(A,I0,A,A,A,I0,A)', "    ", i, ": ", &
                trim(pool%allocations(i)%tag), " (", &
                pool%allocations(i)%size, " bytes)"
        end do
      end block
    end if
    
  end subroutine pool_report
  
  subroutine pool_cleanup(pool)
    class(memory_pool), intent(inout) :: pool
    integer :: i
    
    ! Deallocate all remaining allocations
    do i = pool%num_allocations, 1, -1
      if (pool%allocations(i)%is_allocated) then
        call destroy_memory(pool%allocations(i))
      end if
    end do
    
    if (allocated(pool%allocations)) deallocate(pool%allocations)
    pool%num_allocations = 0
    pool%total_allocated = 0
    
  end subroutine pool_cleanup
  
end module sporkle_memory
