module kronos_device
  ! Kronos GPU device implementation
  ! ================================
  ! Zero-overhead Vulkan compute via Kronos
  
  use kinds
  use iso_c_binding
  use sporkle_types, only: sporkle_buffer, compute_device, DEVICE_GPU_AMD, &
                           device_capabilities
  use sporkle_error_handling, only: sporkle_error => sporkle_warning, &
                                     sporkle_info => sporkle_warning, &
                                     ERR_SUCCESS => SPORKLE_SUCCESS, &
                                     ERR_FAILURE => SPORKLE_ERR_INVALID
  use sporkle_kronos_ffi
  implicit none
  private
  
  ! Public API
  public :: create_kronos_device
  
  ! Interface for C function we need directly
  interface
    subroutine kronos_destroy_buffer_c(ctx, buf) bind(C, name="kronos_compute_destroy_buffer")
      import :: c_ptr
      type(c_ptr), value :: ctx
      type(c_ptr), value :: buf
    end subroutine kronos_destroy_buffer_c
  end interface
  
  ! Kronos device type
  type, extends(compute_device) :: kronos_device_t
    type(kronos_context) :: ctx
    logical :: initialized = .false.
  contains
    procedure :: allocate => kronos_allocate
    procedure :: deallocate => kronos_deallocate
    procedure :: memcpy => kronos_memcpy
    procedure :: execute => kronos_execute
    procedure :: synchronize => kronos_synchronize
    procedure :: get_info => kronos_get_info
    procedure :: cleanup => kronos_device_cleanup
  end type kronos_device_t
  
  ! Buffer tracking
  type :: buffer_entry
    type(sporkle_buffer) :: sporkle_buf
    type(kronos_buffer) :: kronos_buf
  end type buffer_entry
  
  ! Simple buffer registry (in production, use hash table)
  integer, parameter :: MAX_BUFFERS = 1000
  type(buffer_entry), save :: buffer_registry(MAX_BUFFERS)
  integer, save :: num_buffers = 0
  
contains
  
  function create_kronos_device() result(device)
    class(compute_device), allocatable :: device
    type(kronos_device_t), allocatable :: kronos_dev
    
    allocate(kronos_dev)
    
    ! Initialize Kronos context
    kronos_dev%ctx = kronos_init()
    
    if (c_associated(kronos_dev%ctx%handle)) then
      kronos_dev%initialized = .true.
      call sporkle_info("Kronos device initialized successfully")
    else
      kronos_dev%initialized = .false.
      call sporkle_error("Failed to initialize Kronos context")
    end if
    
    ! Set device info
    call kronos_dev%get_info()
    
    device = kronos_dev
    
  end function create_kronos_device
  
  subroutine kronos_get_info(self)
    class(kronos_device_t), intent(inout) :: self
    
    ! Set device information
    self%name = "Kronos GPU (Vulkan Compute)"
    self%device_type = DEVICE_GPU_AMD
    self%is_available = self%initialized
    
  end subroutine kronos_get_info
  
  function kronos_allocate(self, size_bytes, pinned) result(buffer)
    class(kronos_device_t), intent(inout) :: self
    integer(i64), intent(in) :: size_bytes
    logical, intent(in), optional :: pinned
    type(sporkle_buffer) :: buffer
    
    type(kronos_buffer) :: kbuf
    integer :: i
    
    if (.not. self%initialized) then
      buffer%data = c_null_ptr
      buffer%size_bytes = 0
      return
    end if
    
    ! Create Kronos buffer
    kbuf = kronos_create_buffer(self%ctx, int(size_bytes, c_size_t))
    
    if (c_associated(kbuf%handle)) then
      buffer%data = kbuf%handle  ! Store handle for now
      buffer%size_bytes = size_bytes
      buffer%owning_device = 0  ! TODO: proper device ID
      
      ! Register buffer
      if (num_buffers < MAX_BUFFERS) then
        num_buffers = num_buffers + 1
        buffer_registry(num_buffers)%sporkle_buf = buffer
        buffer_registry(num_buffers)%kronos_buf = kbuf
      end if
    else
      buffer%data = c_null_ptr
      buffer%size_bytes = 0
      call sporkle_error("Failed to allocate Kronos buffer")
    end if
    
  end function kronos_allocate
  
  subroutine kronos_deallocate(self, buffer)
    class(kronos_device_t), intent(inout) :: self
    type(sporkle_buffer), intent(inout) :: buffer
    
    integer :: i
    
    if (.not. self%initialized) return
    if (.not. c_associated(buffer%data)) return
    
    ! Find and remove from registry
    do i = 1, num_buffers
      if (c_associated(buffer_registry(i)%sporkle_buf%data, buffer%data)) then
        call kronos_destroy_buffer_c(self%ctx%handle, &
                                     buffer_registry(i)%kronos_buf%handle)
        
        ! Remove from registry (swap with last)
        if (i < num_buffers) then
          buffer_registry(i) = buffer_registry(num_buffers)
        end if
        num_buffers = num_buffers - 1
        exit
      end if
    end do
    
    buffer%data = c_null_ptr
    buffer%size_bytes = 0
    
  end subroutine kronos_deallocate
  
  function kronos_memcpy(self, dst, src, size_bytes) result(status)
    class(kronos_device_t), intent(inout) :: self
    type(sporkle_buffer), intent(inout) :: dst
    type(sporkle_buffer), intent(in) :: src
    integer(i64), intent(in) :: size_bytes
    integer :: status
    
    type(c_ptr) :: src_ptr, dst_ptr
    type(kronos_buffer) :: src_kbuf, dst_kbuf
    integer :: i
    logical :: found_src, found_dst
    integer(c_int8_t), pointer :: src_data(:), dst_data(:)
    
    status = ERR_FAILURE
    
    if (.not. self%initialized) return
    if (size_bytes <= 0) return
    
    found_src = .false.
    found_dst = .false.
    
    ! Find buffers in registry
    do i = 1, num_buffers
      if (c_associated(buffer_registry(i)%sporkle_buf%data, src%data)) then
        src_kbuf = buffer_registry(i)%kronos_buf
        found_src = .true.
      end if
      if (c_associated(buffer_registry(i)%sporkle_buf%data, dst%data)) then
        dst_kbuf = buffer_registry(i)%kronos_buf
        found_dst = .true.
      end if
      if (found_src .and. found_dst) exit
    end do
    
    if (.not. (found_src .and. found_dst)) then
      call sporkle_error("Buffer not found in registry")
      return
    end if
    
    ! Map buffers
    status = kronos_map_buffer(self%ctx, src_kbuf, src_ptr)
    if (status /= KRONOS_SUCCESS) return
    
    status = kronos_map_buffer(self%ctx, dst_kbuf, dst_ptr)
    if (status /= KRONOS_SUCCESS) then
      call kronos_unmap_buffer(self%ctx, src_kbuf)
      return
    end if
    
    ! Copy data
    call c_f_pointer(src_ptr, src_data, [size_bytes])
    call c_f_pointer(dst_ptr, dst_data, [size_bytes])
    dst_data(1:size_bytes) = src_data(1:size_bytes)
    
    ! Unmap buffers
    call kronos_unmap_buffer(self%ctx, src_kbuf)
    call kronos_unmap_buffer(self%ctx, dst_kbuf)
    
    status = ERR_SUCCESS
    
  end function kronos_memcpy
  
  function kronos_execute(self, kernel_name, args, grid_size, block_size) result(status)
    class(kronos_device_t), intent(inout) :: self
    character(len=*), intent(in) :: kernel_name
    type(c_ptr), intent(in) :: args(:)
    integer(i32), intent(in) :: grid_size(3), block_size(3)
    integer :: status
    
    status = ERR_FAILURE
    
    if (.not. self%initialized) return
    
    ! TODO: Implement kernel dispatch
    ! For now, we need to:
    ! 1. Look up pre-compiled SPIR-V for kernel_name
    ! 2. Create pipeline if not cached
    ! 3. Gather buffer handles from args
    ! 4. Dispatch with proper work sizes
    
    call sporkle_warning("Kronos kernel execution not yet implemented")
    
  end function kronos_execute
  
  function kronos_synchronize(self) result(status)
    class(kronos_device_t), intent(inout) :: self
    integer :: status
    
    ! Kronos uses explicit fence synchronization
    ! Nothing to do here for device-wide sync
    status = ERR_SUCCESS
    
  end function kronos_synchronize
  
  subroutine kronos_device_cleanup(self)
    class(kronos_device_t), intent(inout) :: self
    
    integer :: i
    
    if (.not. self%initialized) return
    
    ! Clean up any remaining buffers
    do i = 1, num_buffers
      call kronos_destroy_buffer_c(self%ctx%handle, &
                                   buffer_registry(i)%kronos_buf%handle)
    end do
    num_buffers = 0
    
    ! Destroy context
    call kronos_cleanup(self%ctx)
    self%initialized = .false.
    
  end subroutine kronos_device_cleanup
  
end module kronos_device