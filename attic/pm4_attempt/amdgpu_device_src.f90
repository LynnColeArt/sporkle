module amdgpu_device_mod
  ! Connects AMDGPU direct implementation to Sporkle device interface
  use iso_c_binding
  use kinds
  use sporkle_types
  use sporkle_amdgpu_direct
  use sporkle_amdgpu_memory
  use sporkle_amdgpu_shaders
  use sporkle_amdgpu_shader_binary
  implicit none
  private
  
  public :: amdgpu_compute_device, create_amdgpu_device
  
  ! Extended compute device for AMDGPU direct access
  type, extends(compute_device) :: amdgpu_compute_device
    type(amdgpu_device) :: gpu_handle  ! From sporkle_amdgpu_direct
    integer :: context_handle = -1
    integer :: card_number = 1  ! Default to card1 (discrete GPU)
    logical :: is_initialized = .false.
    ! Track allocated buffers for cleanup
    type(amdgpu_buffer), allocatable :: gpu_buffers(:)
    integer :: num_buffers = 0
  contains
    procedure :: allocate => amdgpu_dev_allocate
    procedure :: deallocate => amdgpu_dev_deallocate
    procedure :: memcpy => amdgpu_dev_memcpy
    procedure :: execute => amdgpu_dev_execute
    procedure :: synchronize => amdgpu_dev_sync
    procedure :: get_info => amdgpu_dev_get_info
    procedure :: init => amdgpu_dev_init
    procedure :: cleanup => amdgpu_dev_cleanup
  end type amdgpu_compute_device
  
contains

  function create_amdgpu_device(card_number) result(device)
    integer, intent(in), optional :: card_number
    type(amdgpu_compute_device), allocatable :: device
    
    allocate(device)
    
    ! Set card number
    if (present(card_number)) then
      device%card_number = card_number
    else
      device%card_number = 1  ! Default to discrete GPU
    end if
    
    ! Initialize the device
    call device%init()
    
  end function create_amdgpu_device
  
  subroutine amdgpu_dev_init(self)
    class(amdgpu_compute_device), intent(inout) :: self
    character(len=256) :: device_path
    integer :: status
    
    ! Build device path
    write(device_path, '(A,I0)') "/dev/dri/card", self%card_number
    
    ! Open the device
    self%gpu_handle = amdgpu_open_device(trim(device_path))
    
    if (self%gpu_handle%is_open) then
      print *, "✅ Opened AMDGPU device card", self%card_number
      
      ! Create context (simplified - in real implementation would use proper ioctl)
      self%context_handle = 1
      self%is_initialized = .true.
      print *, "✅ Created AMDGPU context"
      
      ! Allocate buffer tracking array
      allocate(self%gpu_buffers(100))  ! Max 100 buffers
    else
      print *, "❌ Failed to open AMDGPU device"
    end if
    
    ! Get device info
    call self%get_info()
    
  end subroutine amdgpu_dev_init
  
  subroutine amdgpu_dev_cleanup(self)
    class(amdgpu_compute_device), intent(inout) :: self
    integer :: i
    
    if (self%is_initialized) then
      ! Free all allocated buffers
      do i = 1, self%num_buffers
        ! In real implementation, would properly free GPU memory
      end do
      
      ! Destroy context
      self%context_handle = -1
      
      ! Close device
      call amdgpu_close_device(self%gpu_handle)
      
      self%is_initialized = .false.
    end if
    
    if (allocated(self%gpu_buffers)) then
      deallocate(self%gpu_buffers)
    end if
    
  end subroutine amdgpu_dev_cleanup
  
  function amdgpu_dev_allocate(self, size_bytes, pinned) result(buffer)
    class(amdgpu_compute_device), intent(inout) :: self
    integer(i64), intent(in) :: size_bytes
    logical, intent(in), optional :: pinned
    type(sporkle_buffer) :: buffer
    type(amdgpu_buffer) :: gpu_buffer
    integer :: status
    
    if (.not. self%is_initialized) then
      print *, "❌ AMDGPU device not initialized"
      buffer%data = c_null_ptr
      return
    end if
    
    ! Allocate GPU buffer
    gpu_buffer = amdgpu_allocate_buffer(self%gpu_handle, size_bytes, 4)  ! 4 = AMDGPU_GEM_DOMAIN_VRAM
    
    if (gpu_buffer%handle /= 0) then
      ! Map to CPU for access
      status = amdgpu_map_buffer(self%gpu_handle, gpu_buffer)
      
      if (status == 0) then
        buffer%size_bytes = size_bytes
        buffer%owning_device = self%device_id
        buffer%is_pinned = .true.  ! GPU memory is effectively pinned
        buffer%data = gpu_buffer%cpu_ptr
        
        ! Track this buffer
        if (self%num_buffers < size(self%gpu_buffers)) then
          self%num_buffers = self%num_buffers + 1
          self%gpu_buffers(self%num_buffers) = gpu_buffer
        end if
        
        print *, "✅ Allocated AMDGPU buffer:", size_bytes, "bytes"
      else
        print *, "❌ Failed to map AMDGPU buffer"
        buffer%data = c_null_ptr
      end if
    else
      print *, "❌ Failed to allocate AMDGPU buffer"
      buffer%data = c_null_ptr
    end if
    
  end function amdgpu_dev_allocate
  
  subroutine amdgpu_dev_deallocate(self, buffer)
    class(amdgpu_compute_device), intent(inout) :: self
    type(sporkle_buffer), intent(inout) :: buffer
    
    ! TODO: Find and free the corresponding GPU buffer
    ! For now, just clear the pointer
    buffer%data = c_null_ptr
    buffer%size_bytes = 0
    
  end subroutine amdgpu_dev_deallocate
  
  function amdgpu_dev_memcpy(self, dst, src, size_bytes) result(status)
    class(amdgpu_compute_device), intent(inout) :: self
    type(sporkle_buffer), intent(inout) :: dst
    type(sporkle_buffer), intent(in) :: src
    integer(i64), intent(in) :: size_bytes
    integer(i32) :: status
    
    ! For now, do CPU memcpy since buffers are mapped
    block
      character, pointer :: src_bytes(:), dst_bytes(:)
      integer :: n
      
      if (.not. c_associated(src%data) .or. .not. c_associated(dst%data)) then
        status = -1
        return
      end if
      
      ! Fix: Convert int64 size_bytes to default integer for c_f_pointer shape
      n = int(size_bytes, kind(n))
      call c_f_pointer(src%data, src_bytes, [n])
      call c_f_pointer(dst%data, dst_bytes, [n])
      dst_bytes = src_bytes
      status = 0
    end block
    
  end function amdgpu_dev_memcpy
  
  function amdgpu_dev_execute(self, kernel_name, args, grid_size, block_size) result(status)
    class(amdgpu_compute_device), intent(inout) :: self
    character(len=*), intent(in) :: kernel_name
    type(c_ptr), intent(in) :: args(:)
    integer(i32), intent(in) :: grid_size(3)
    integer(i32), intent(in) :: block_size(3)
    integer(i32) :: status
    
    if (.not. self%is_initialized) then
      print *, "❌ AMDGPU device not initialized"
      status = -1
      return
    end if
    
    ! TODO: Implement shader execution via PM4 packets
    ! For now, we'll use the existing shader infrastructure
    
    print *, "🚀 AMDGPU Direct: Executing kernel", trim(kernel_name)
    print *, "   Grid:", grid_size
    print *, "   Block:", block_size
    
    ! This is where we'd submit PM4 packets for compute dispatch
    ! For now, return success
    status = 0
    
  end function amdgpu_dev_execute
  
  function amdgpu_dev_sync(self) result(status)
    class(amdgpu_compute_device), intent(inout) :: self
    integer(i32) :: status
    
    if (.not. self%is_initialized) then
      status = -1
      return
    end if
    
    ! TODO: Implement fence-based synchronization
    ! For now, return success
    status = 0
    
  end function amdgpu_dev_sync
  
  subroutine amdgpu_dev_get_info(self)
    class(amdgpu_compute_device), intent(inout) :: self
    
    if (self%card_number == 0) then
      self%name = "AMD Raphael iGPU (Direct)"
      self%device_id = 100  ! Unique ID for direct iGPU
    else
      self%name = "AMD RX 7900 XT (Direct)"
      self%device_id = 101  ! Unique ID for direct dGPU
    end if
    
    ! Fill capabilities
    self%capabilities%supports_unified_memory = .false.
    self%capabilities%supports_p2p = .true.  ! AMD supports GPU-to-GPU
    self%capabilities%supports_float64 = .true.
    self%capabilities%supports_float16 = .true.
    self%capabilities%supports_int8 = .true.
    
    ! Performance characteristics (approximate)
    if (self%card_number == 0) then
      ! iGPU
      self%capabilities%memory_bandwidth_gbps = 50.0_real32
    else
      ! dGPU (7900 XT)
      self%capabilities%memory_bandwidth_gbps = 960.0_real32
    end if
    
    self%is_available = self%is_initialized
    
  end subroutine amdgpu_dev_get_info

end module amdgpu_device_mod