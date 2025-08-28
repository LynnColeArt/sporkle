module sporkle_amdgpu_direct
  ! Direct AMDGPU kernel driver interface
  ! The Sporkle Way: Talk directly to the kernel!
  
  use kinds
  use iso_c_binding
  implicit none
  private
  
  ! Define unsigned types as aliases
  integer, parameter :: c_uint32_t = c_int32_t
  integer, parameter :: c_uint64_t = c_int64_t
  
  ! System constants
  integer(c_int), parameter :: O_RDWR = 2
  integer(c_int), parameter :: PROT_READ = 1
  integer(c_int), parameter :: PROT_WRITE = 2
  integer(c_int), parameter :: MAP_SHARED = 1
  
  public :: amdgpu_device, amdgpu_buffer, amdgpu_command_buffer
  public :: amdgpu_open_device, amdgpu_close_device
  public :: amdgpu_allocate_buffer
  public :: amdgpu_map_buffer
  public :: amdgpu_submit_command_buffer
  public :: amdgpu_wait_buffer_idle
  public :: amdgpu_write_compute_shader
  public :: amdgpu_create_context
  public :: amdgpu_destroy_context
  public :: amdgpu_create_bo_list
  public :: amdgpu_destroy_bo_list
  public :: amdgpu_map_va
  public :: amdgpu_unmap_va
  
  ! ioctl command codes for AMDGPU
  ! From include/uapi/drm/amdgpu_drm.h
  integer(c_int), parameter :: DRM_AMDGPU_GEM_CREATE = 0
  integer(c_int), parameter :: DRM_AMDGPU_GEM_MMAP = 1
  integer(c_int), parameter :: DRM_AMDGPU_CTX = 2
  integer(c_int), parameter :: DRM_AMDGPU_BO_LIST = 3
  integer(c_int), parameter :: DRM_AMDGPU_CS = 4
  integer(c_int), parameter :: DRM_AMDGPU_INFO = 5
  integer(c_int), parameter :: DRM_AMDGPU_GEM_WAIT_IDLE = 7
  integer(c_int), parameter :: DRM_AMDGPU_GEM_VA = 8
  
  ! DRM ioctl encoding
  integer(c_int), parameter :: DRM_IOCTL_BASE = int(z'64', c_int)
  integer(c_int), parameter :: DRM_COMMAND_BASE = int(z'40', c_int)
  
  ! Memory domains
  integer(c_int), parameter :: AMDGPU_GEM_DOMAIN_CPU = 1
  integer(c_int), parameter :: AMDGPU_GEM_DOMAIN_GTT = 2
  integer(c_int), parameter :: AMDGPU_GEM_DOMAIN_VRAM = 4
  
  ! Query info types
  integer(c_int), parameter :: AMDGPU_INFO_ACCEL_WORKING = int(z'00', c_int)
  integer(c_int), parameter :: AMDGPU_INFO_FW_VERSION = int(z'0e', c_int)
  integer(c_int), parameter :: AMDGPU_INFO_DEV_INFO = int(z'16', c_int)
  integer(c_int), parameter :: AMDGPU_INFO_MEMORY = int(z'19', c_int)
  
  ! Chunk types for command submission
  integer(c_int), parameter :: AMDGPU_CHUNK_ID_IB = int(z'01', c_int)
  integer(c_int), parameter :: AMDGPU_CHUNK_ID_FENCE = int(z'02', c_int)
  integer(c_int), parameter :: AMDGPU_CHUNK_ID_DEPENDENCIES = int(z'03', c_int)
  
  ! HW IP types
  integer(c_int), parameter :: AMDGPU_HW_IP_GFX = 0
  integer(c_int), parameter :: AMDGPU_HW_IP_COMPUTE = 1
  integer(c_int), parameter :: AMDGPU_HW_IP_DMA = 2
  
  ! Context operations
  integer(c_int), parameter :: AMDGPU_CTX_OP_ALLOC_CTX = 1
  integer(c_int), parameter :: AMDGPU_CTX_OP_FREE_CTX = 2
  
  ! BO list operations
  integer(c_int), parameter :: AMDGPU_BO_LIST_OP_CREATE = 0
  integer(c_int), parameter :: AMDGPU_BO_LIST_OP_DESTROY = 1
  
  ! VA operations
  integer(c_int), parameter :: AMDGPU_VA_OP_MAP = 1
  integer(c_int), parameter :: AMDGPU_VA_OP_UNMAP = 2
  
  ! VA flags
  integer(c_int), parameter :: AMDGPU_VM_PAGE_READABLE = 1
  integer(c_int), parameter :: AMDGPU_VM_PAGE_WRITEABLE = 2
  integer(c_int), parameter :: AMDGPU_VM_PAGE_EXECUTABLE = 4
  
  ! Device info structure (simplified)
  type, bind(C) :: drm_amdgpu_info_device
    integer(c_int32_t) :: device_id
    integer(c_int32_t) :: chip_rev
    integer(c_int32_t) :: external_rev
    integer(c_int32_t) :: pci_rev
    integer(c_int32_t) :: family
    integer(c_int32_t) :: num_shader_engines
    integer(c_int32_t) :: num_shader_arrays_per_engine
    integer(c_int32_t) :: gpu_counter_freq
    integer(c_int64_t) :: max_engine_clock
    integer(c_int64_t) :: max_memory_clock
    integer(c_int32_t) :: cu_active_number
    integer(c_int32_t) :: cu_ao_mask
    integer(c_int32_t) :: cu_bitmap(4)
    ! ... more fields ...
  end type drm_amdgpu_info_device
  
  ! GEM create structure
  type, bind(C) :: drm_amdgpu_gem_create_in
    integer(c_int64_t) :: bo_size
    integer(c_int64_t) :: alignment
    integer(c_int64_t) :: domains
    integer(c_int64_t) :: domain_flags
  end type drm_amdgpu_gem_create_in
  
  type, bind(C) :: drm_amdgpu_gem_create_out
    integer(c_int32_t) :: handle
    integer(c_int32_t) :: pad
  end type drm_amdgpu_gem_create_out
  
  ! Command submission structures
  type, bind(C) :: drm_amdgpu_cs_chunk
    integer(c_int32_t) :: chunk_id
    integer(c_int32_t) :: length_dw
    integer(c_int64_t) :: chunk_data
  end type drm_amdgpu_cs_chunk
  
  type, bind(C) :: drm_amdgpu_cs_in
    integer(c_int32_t) :: ctx_id
    integer(c_int32_t) :: bo_list_handle
    integer(c_int32_t) :: num_chunks
    integer(c_int32_t) :: pad
    integer(c_int64_t) :: chunks
  end type drm_amdgpu_cs_in
  
  type, bind(C) :: drm_amdgpu_cs_out
    integer(c_int64_t) :: handle
  end type drm_amdgpu_cs_out
  
  type, bind(C) :: drm_amdgpu_gem_wait_idle_in
    integer(c_int32_t) :: handle
    integer(c_int32_t) :: flags
    integer(c_int64_t) :: timeout
  end type drm_amdgpu_gem_wait_idle_in
  
  type, bind(C) :: drm_amdgpu_gem_wait_idle_out
    integer(c_int32_t) :: status
    integer(c_int32_t) :: first_signaled
  end type drm_amdgpu_gem_wait_idle_out
  
  ! IB (Indirect Buffer) chunk data structure
  type, bind(C) :: drm_amdgpu_cs_chunk_ib
    integer(c_int32_t) :: pad
    integer(c_int32_t) :: flags
    integer(c_int64_t) :: va_start
    integer(c_int32_t) :: ib_bytes
    integer(c_int32_t) :: ip_type
    integer(c_int32_t) :: ip_instance
    integer(c_int32_t) :: ring
  end type drm_amdgpu_cs_chunk_ib
  
  ! Our wrapper types
  type :: amdgpu_device
    integer :: fd = -1
    logical :: is_open = .false.
    character(len=256) :: device_path = ""
    type(drm_amdgpu_info_device) :: info
  end type amdgpu_device
  
  type :: amdgpu_buffer
    integer(c_int32_t) :: handle = 0
    integer(c_int64_t) :: size = 0
    integer(c_int64_t) :: gpu_addr = 0
    integer(c_int64_t) :: va_addr = 0  ! GPU virtual address from GEM_VA
    type(c_ptr) :: cpu_ptr = c_null_ptr
    logical :: is_mapped = .false.
    logical :: is_va_mapped = .false.
  end type amdgpu_buffer
  
  type :: amdgpu_command_buffer
    integer(c_int32_t) :: ib_handle = 0
    integer(c_int64_t) :: ib_size = 0
    type(c_ptr) :: ib_cpu_ptr = c_null_ptr
    integer :: num_chunks = 0
    integer(c_int32_t) :: ctx_id = 0
    integer(c_int32_t) :: bo_list_handle = 0
    type(amdgpu_buffer) :: ib_buffer
  end type amdgpu_command_buffer
  
  ! C interfaces
  interface
    function open_device(path, flags) bind(C, name="open")
      import :: c_char, c_int
      character(kind=c_char), dimension(*) :: path
      integer(c_int), value :: flags
      integer(c_int) :: open_device
    end function open_device
    
    function get_errno() bind(C, name="__errno_location")
      import :: c_ptr
      type(c_ptr) :: get_errno
    end function get_errno
    
    function close(fd) bind(C, name="close")
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: close
    end function close
    
    function ioctl(fd, request, argp) bind(C, name="ioctl")
      import :: c_int, c_long, c_ptr
      integer(c_int), value :: fd
      integer(c_long), value :: request
      type(c_ptr), value :: argp
      integer(c_int) :: ioctl
    end function ioctl
    
    function mmap(addr, length, prot, flags, fd, offset) bind(C, name="mmap")
      import :: c_ptr, c_size_t, c_int, c_long
      type(c_ptr), value :: addr
      integer(c_size_t), value :: length
      integer(c_int), value :: prot
      integer(c_int), value :: flags
      integer(c_int), value :: fd
      integer(c_long), value :: offset
      type(c_ptr) :: mmap
    end function mmap
    
    function munmap(addr, length) bind(C, name="munmap")
      import :: c_ptr, c_size_t, c_int
      type(c_ptr), value :: addr
      integer(c_size_t), value :: length
      integer(c_int) :: munmap
    end function munmap
  end interface
  
contains

  ! Open AMDGPU device
  function amdgpu_open_device(device_path) result(device)
    character(len=*), intent(in), optional :: device_path
    type(amdgpu_device) :: device
    character(len=256) :: path
    integer :: fd, status
    
    ! Default to card0 if not specified
    if (present(device_path)) then
      path = device_path
    else
      path = "/dev/dri/card0"
    end if
    
    ! Open device
    fd = open_device(trim(path) // c_null_char, O_RDWR)
    if (fd < 0) then
      print *, "❌ Failed to open AMDGPU device: ", trim(path)
      return
    end if
    
    device%fd = fd
    device%device_path = path
    device%is_open = .true.
    
    ! Query device info
    status = query_device_info(device)
    if (status /= 0) then
      print *, "⚠️ Failed to query device info"
    else
      print *, "✅ Opened AMDGPU device: ", trim(path)
      print '(A,Z8)', "   Device ID: 0x", device%info%device_id
      print '(A,I0)', "   Compute Units: ", device%info%cu_active_number
      print '(A,I0,A)', "   Max Engine Clock: ", device%info%max_engine_clock, " MHz"
      print '(A,I0,A)', "   Max Memory Clock: ", device%info%max_memory_clock, " MHz"
    end if
    
  end function amdgpu_open_device
  
  ! Query device information
  function query_device_info(device) result(status)
    type(amdgpu_device), intent(inout) :: device
    integer :: status
    
    type, bind(C) :: drm_amdgpu_info
      integer(c_int64_t) :: return_pointer
      integer(c_int32_t) :: return_size
      integer(c_int32_t) :: query
    end type drm_amdgpu_info
    
    type(drm_amdgpu_info), target :: info_req
    type(drm_amdgpu_info_device), target :: dev_info
    integer(c_long) :: request
    
    ! Setup info request
    info_req%return_pointer = int(loc(dev_info), c_int64_t)
    info_req%return_size = int(sizeof(dev_info), c_int32_t)
    info_req%query = AMDGPU_INFO_DEV_INFO
    
    ! Build ioctl request
    ! DRM_IOR(DRM_COMMAND_BASE + DRM_AMDGPU_INFO, ...)
    ! _IOR('d', 0x45, struct drm_amdgpu_info)
    request = int(z'40206445', c_long)  ! Pre-calculated ioctl number
    
    ! Make ioctl call
    status = ioctl(device%fd, request, c_loc(info_req))
    
    if (status == 0) then
      device%info = dev_info
    end if
    
  end function query_device_info
  
  ! Allocate GPU buffer
  function amdgpu_allocate_buffer(device, size, domain) result(buffer)
    type(amdgpu_device), intent(in) :: device
    integer(c_int64_t), intent(in) :: size
    integer, intent(in), optional :: domain
    type(amdgpu_buffer) :: buffer
    
    ! The union is 32 bytes total (size of the larger member)
    type, bind(C) :: drm_amdgpu_gem_create
      integer(c_int64_t) :: data(4)  ! 32 bytes total
    end type drm_amdgpu_gem_create
    
    type(drm_amdgpu_gem_create), target :: gem_create
    integer(c_long) :: request
    integer :: status, mem_domain
    
    ! Initialize the structure to zero
    gem_create%data = 0
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      return
    end if
    
    ! Default to GTT (system memory accessible by GPU)
    mem_domain = AMDGPU_GEM_DOMAIN_GTT
    if (present(domain)) mem_domain = domain
    
    ! Setup gem create request - fill in as drm_amdgpu_gem_create_in
    gem_create%data(1) = size               ! bo_size
    gem_create%data(2) = 4096               ! alignment
    gem_create%data(3) = mem_domain         ! domains
    gem_create%data(4) = 0                  ! domain_flags
    
    ! Build ioctl request
    ! DRM_IOWR(DRM_COMMAND_BASE + DRM_AMDGPU_GEM_CREATE, ...)
    ! _IOWR('d', 0x40, ...)
    request = int(z'C0206440', c_long)  ! Pre-calculated ioctl number
    
    ! Make ioctl call
    status = ioctl(device%fd, request, c_loc(gem_create))
    
    if (status == 0) then
      ! Extract handle from first 32 bits of the union
      buffer%handle = int(iand(gem_create%data(1), int(z'FFFFFFFF', c_int64_t)), c_int32_t)
      buffer%size = size
      ! For AMDGPU, we'll get the GPU address when we map the buffer
      buffer%gpu_addr = 0
      print '(A,I0,A)', "✅ Allocated ", size, " bytes on GPU"
      print '(A,I0)', "   Handle: ", buffer%handle
      print '(A,Z8)', "   Handle (hex): 0x", buffer%handle
    else
      print *, "❌ Failed to allocate GPU buffer"
      print '(A,I0)', "   Status: ", status
    end if
    
  end function amdgpu_allocate_buffer
  
  ! Map buffer for CPU access
  function amdgpu_map_buffer(device, buffer) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_buffer), intent(inout) :: buffer
    integer :: status
    
    ! Union for mmap - using integer(8) to ensure 8-byte size
    type, bind(C) :: drm_amdgpu_gem_mmap
      integer(c_int64_t) :: data  ! 8 bytes total
    end type drm_amdgpu_gem_mmap
    
    type(drm_amdgpu_gem_mmap), target :: mmap_req
    integer(c_long) :: request
    integer(c_int) :: prot, flags
    integer(c_int), pointer :: errno
    type(c_ptr) :: errno_ptr
    
    if (buffer%is_mapped) then
      status = 0
      return
    end if
    
    ! Setup mmap request - handle is in the first 4 bytes
    ! Using transfer to pack the handle into the union
    mmap_req%data = 0  ! Clear all 8 bytes
    ! Mask to ensure only lower 32 bits are used (avoid sign extension)
    mmap_req%data = iand(int(buffer%handle, c_int64_t), int(z'FFFFFFFF', c_int64_t))
    
    print '(A,I0)', "   Debug: buffer handle = ", buffer%handle
    print '(A,Z16)', "   Debug: mmap_req data = 0x", mmap_req%data
    
    ! Get mmap offset
    ! DRM_IOWR(DRM_COMMAND_BASE + DRM_AMDGPU_GEM_MMAP, ...)
    ! _IOWR('d', 0x41, union drm_amdgpu_gem_mmap)
    request = int(z'C0086441', c_long)  ! Pre-calculated ioctl number
    status = ioctl(device%fd, request, c_loc(mmap_req))
    
    if (status /= 0) then
      errno_ptr = get_errno()
      call c_f_pointer(errno_ptr, errno)
      print '(A,I0)', "❌ Failed to get mmap offset, status: ", status
      print '(A,I0)', "   errno: ", errno
      print '(A,Z16)', "   Request was: 0x", request
      print '(A,I0)', "   Handle: ", buffer%handle
      return
    end if
    
    print '(A,Z16)', "✅ Got mmap offset: 0x", mmap_req%data
    
    ! Map the buffer
    prot = ior(PROT_READ, PROT_WRITE)
    flags = MAP_SHARED
    
    buffer%cpu_ptr = mmap(c_null_ptr, buffer%size, prot, flags, &
                         device%fd, int(mmap_req%data, c_long))
    
    if (c_associated(buffer%cpu_ptr)) then
      buffer%is_mapped = .true.
      ! Store the GPU virtual address (offset in this case)
      buffer%gpu_addr = mmap_req%data
      print *, "✅ Mapped GPU buffer to CPU"
      print '(A,Z16)', "   GPU virtual address: 0x", buffer%gpu_addr
      status = 0
    else
      print *, "❌ Failed to map GPU buffer"
      status = -1
    end if
    
  end function amdgpu_map_buffer
  
  ! Close device
  subroutine amdgpu_close_device(device)
    type(amdgpu_device), intent(inout) :: device
    integer :: status
    
    if (device%is_open) then
      status = close(device%fd)
      device%is_open = .false.
      device%fd = -1
      print *, "✅ Closed AMDGPU device"
    end if
    
  end subroutine amdgpu_close_device
  
  ! Submit command buffer
  function amdgpu_submit_command_buffer(device, cmd_buf) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_command_buffer), intent(inout) :: cmd_buf
    integer :: status
    
    ! Union for CS ioctl - 24 bytes total
    type, bind(C) :: drm_amdgpu_cs
      integer(c_int64_t) :: data(3)  ! 24 bytes total
    end type drm_amdgpu_cs
    
    type(drm_amdgpu_cs), target :: cs_req
    type(drm_amdgpu_cs_chunk), target :: chunk
    type(drm_amdgpu_cs_chunk_ib), target :: ib_info
    integer(c_int64_t), target :: chunk_array(1)  ! Array of pointers for double indirection!
    integer(c_long) :: request
    integer(c_int), pointer :: errno
    type(c_ptr) :: errno_ptr
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      status = -1
      return
    end if
    
    ! Setup IB info structure
    ib_info%pad = 0
    ib_info%flags = 0
    ! Use VA address if mapped, otherwise fall back to gpu_addr
    if (cmd_buf%ib_buffer%is_va_mapped) then
      ib_info%va_start = cmd_buf%ib_buffer%va_addr
    else
      ib_info%va_start = cmd_buf%ib_buffer%gpu_addr
    end if
    ib_info%ib_bytes = int(cmd_buf%ib_size, c_int32_t)  ! Size in bytes
    ib_info%ip_type = AMDGPU_HW_IP_COMPUTE  ! Use compute ring, not GFX!
    ib_info%ip_instance = 0
    ib_info%ring = 0  ! Ring 0
    
    ! Setup chunk
    chunk%chunk_id = AMDGPU_CHUNK_ID_IB
    chunk%length_dw = int(sizeof(ib_info) / 4, c_int32_t)  ! Size of IB info in dwords
    chunk%chunk_data = int(loc(ib_info), c_int64_t)  ! Pointer to IB info
    
    ! CRITICAL: Set up double indirection!
    chunk_array(1) = int(loc(chunk), c_int64_t)  ! Array element points to chunk
    
    ! Debug prints
    print '(A,I0)', "   Debug: chunk_id = ", chunk%chunk_id
    print '(A,I0)', "   Debug: length_dw = ", chunk%length_dw
    print '(A,Z16)', "   Debug: chunk_data ptr = 0x", chunk%chunk_data
    print '(A,Z16)', "   Debug: IB va_start = 0x", ib_info%va_start
    print '(A,I0)', "   Debug: IB bytes = ", ib_info%ib_bytes
    
    ! Setup CS request
    cs_req%data = 0
    ! Fill as drm_amdgpu_cs_in
    cs_req%data(1) = ior(int(cmd_buf%ctx_id, c_int64_t), &
                        ishft(int(cmd_buf%bo_list_handle, c_int64_t), 32))  ! ctx_id | bo_list_handle<<32
    cs_req%data(2) = ior(int(1, c_int64_t), &
                        ishft(int(0, c_int64_t), 32))  ! num_chunks | pad<<32
    cs_req%data(3) = int(loc(chunk_array), c_int64_t)  ! Points to array of chunk pointers!
    
    ! Build ioctl request
    request = int(z'C0186444', c_long)  ! DRM_IOWR(DRM_AMDGPU_CS, ...)
    
    ! Submit command buffer
    status = ioctl(device%fd, request, c_loc(cs_req))
    
    if (status == 0) then
      ! Extract handle from output
      cmd_buf%ib_handle = int(cs_req%data(1), c_int32_t)
      print *, "✅ Submitted command buffer"
    else
      ! Get errno for debugging
      errno_ptr = get_errno()
      call c_f_pointer(errno_ptr, errno)
      print '(A,I0)', "❌ Failed to submit command buffer, status: ", status
      print '(A,I0)', "   errno: ", errno
      ! Common errors:
      ! 22 (EINVAL) - Invalid argument
      ! 2 (ENOENT) - No such file or directory (missing context)
      ! 13 (EACCES) - Permission denied
    end if
    
  end function amdgpu_submit_command_buffer
  
  ! Wait for buffer to be idle
  function amdgpu_wait_buffer_idle(device, buffer, timeout_ns) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_buffer), intent(in) :: buffer
    integer(c_int64_t), intent(in), optional :: timeout_ns
    integer :: status
    
    ! Union for wait idle - 16 bytes total
    type, bind(C) :: drm_amdgpu_gem_wait_idle
      integer(c_int64_t) :: data(2)  ! 16 bytes total
    end type drm_amdgpu_gem_wait_idle
    
    type(drm_amdgpu_gem_wait_idle), target :: wait_req
    integer(c_long) :: request
    integer(c_int64_t) :: timeout
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      status = -1
      return
    end if
    
    ! Default timeout: 1 second
    timeout = 1000000000_c_int64_t
    if (present(timeout_ns)) timeout = timeout_ns
    
    ! Setup wait request
    wait_req%data = 0
    ! Fill as drm_amdgpu_gem_wait_idle_in
    wait_req%data(1) = ior(int(buffer%handle, c_int64_t), &
                          ishft(int(0, c_int64_t), 32))  ! handle | flags<<32
    wait_req%data(2) = timeout
    
    ! Build ioctl request
    request = int(z'C0106447', c_long)  ! DRM_IOWR(DRM_AMDGPU_GEM_WAIT_IDLE, ...)
    
    status = ioctl(device%fd, request, c_loc(wait_req))
    
    if (status == 0) then
      print *, "✅ Buffer is idle"
    else
      print *, "❌ Failed to wait for buffer idle"
    end if
    
  end function amdgpu_wait_buffer_idle
  
  ! Write simple compute shader to command buffer
  subroutine amdgpu_write_compute_shader(cmd_buf, shader_data, shader_size)
    type(amdgpu_command_buffer), intent(inout) :: cmd_buf
    integer(c_int32_t), intent(in) :: shader_data(*)
    integer(c_int64_t), intent(in) :: shader_size
    
    integer(c_int32_t), pointer :: ib_data(:)
    integer :: i, num_dwords
    
    if (.not. c_associated(cmd_buf%ib_cpu_ptr)) then
      print *, "❌ Command buffer not mapped"
      return
    end if
    
    ! Map command buffer as array of dwords
    num_dwords = int(shader_size / 4)
    call c_f_pointer(cmd_buf%ib_cpu_ptr, ib_data, [num_dwords])
    
    ! Copy shader data
    do i = 1, num_dwords
      ib_data(i) = shader_data(i)
    end do
    
    cmd_buf%ib_size = shader_size
    
    print '(A,I0,A)', "✅ Wrote ", shader_size, " bytes to command buffer"
    
  end subroutine amdgpu_write_compute_shader
  
  ! Create GPU context
  function amdgpu_create_context(device) result(ctx_id)
    type(amdgpu_device), intent(in) :: device
    integer(c_int32_t) :: ctx_id
    
    ! Context ioctl union - varies by operation
    type, bind(C) :: drm_amdgpu_ctx
      integer(c_int64_t) :: data(2)  ! 16 bytes total
    end type drm_amdgpu_ctx
    
    type(drm_amdgpu_ctx), target :: ctx_req
    integer(c_long) :: request
    integer :: status
    
    ctx_id = -1
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      return
    end if
    
    ! Setup context allocation request
    ctx_req%data = 0
    ! Fill as drm_amdgpu_ctx_in for ALLOC_CTX
    ! data(1) contains: op (lower 32) | flags (upper 32)
    ctx_req%data(1) = ior(int(AMDGPU_CTX_OP_ALLOC_CTX, c_int64_t), &
                         ishft(int(0, c_int64_t), 32))  ! op | flags<<32
    
    ! Build ioctl request
    ! DRM_IOWR(DRM_COMMAND_BASE + DRM_AMDGPU_CTX, ...)
    request = int(z'C0106442', c_long)  ! Pre-calculated ioctl number
    
    status = ioctl(device%fd, request, c_loc(ctx_req))
    
    if (status == 0) then
      ! Extract ctx_id from output (lower 32 bits of data(1))
      ctx_id = int(iand(ctx_req%data(1), int(z'FFFFFFFF', c_int64_t)), c_int32_t)
      print '(A,I0)', "✅ Created context with ID: ", ctx_id
    else
      print *, "❌ Failed to create context"
    end if
    
  end function amdgpu_create_context
  
  ! Destroy GPU context
  subroutine amdgpu_destroy_context(device, ctx_id)
    type(amdgpu_device), intent(in) :: device
    integer(c_int32_t), intent(in) :: ctx_id
    
    type, bind(C) :: drm_amdgpu_ctx
      integer(c_int64_t) :: data(2)  ! 16 bytes total
    end type drm_amdgpu_ctx
    
    type(drm_amdgpu_ctx), target :: ctx_req
    integer(c_long) :: request
    integer :: status
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      return
    end if
    
    ! Setup context free request
    ctx_req%data = 0
    ! Fill as drm_amdgpu_ctx_in for FREE_CTX
    ctx_req%data(1) = ior(int(AMDGPU_CTX_OP_FREE_CTX, c_int64_t), &
                         ishft(int(ctx_id, c_int64_t), 32))  ! op | ctx_id<<32
    ctx_req%data(2) = 0  ! flags
    
    ! Build ioctl request
    request = int(z'C0106442', c_long)
    
    status = ioctl(device%fd, request, c_loc(ctx_req))
    
    if (status == 0) then
      print '(A,I0)', "✅ Destroyed context: ", ctx_id
    else
      print *, "❌ Failed to destroy context"
    end if
    
  end subroutine amdgpu_destroy_context
  
  ! Create BO list
  function amdgpu_create_bo_list(device, handles, num_buffers) result(bo_list_handle)
    type(amdgpu_device), intent(in) :: device
    integer(c_int32_t), intent(in) :: handles(:)
    integer, intent(in) :: num_buffers
    integer(c_int32_t) :: bo_list_handle
    
    ! BO list entry structure
    type, bind(C) :: drm_amdgpu_bo_list_entry
      integer(c_int32_t) :: bo_handle
      integer(c_int32_t) :: bo_priority
    end type drm_amdgpu_bo_list_entry
    
    ! BO list ioctl union - 24 bytes total
    type, bind(C) :: drm_amdgpu_bo_list
      integer(c_int64_t) :: data(3)  ! 24 bytes total
    end type drm_amdgpu_bo_list
    
    type(drm_amdgpu_bo_list), target :: bo_list
    type(drm_amdgpu_bo_list_entry), allocatable, target :: entries(:)
    integer(c_long) :: request
    integer :: status, i
    
    bo_list_handle = 0
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      return
    end if
    
    if (num_buffers <= 0) then
      print *, "❌ Invalid number of buffers"
      return
    end if
    
    ! Allocate and fill BO list entries
    allocate(entries(num_buffers))
    do i = 1, num_buffers
      entries(i)%bo_handle = handles(i)
      entries(i)%bo_priority = 0
    end do
    
    ! Setup BO list creation request
    bo_list%data = 0
    ! Fill as drm_amdgpu_bo_list_in
    bo_list%data(1) = ior(int(AMDGPU_BO_LIST_OP_CREATE, c_int64_t), &
                         ishft(int(0, c_int64_t), 32))  ! operation | list_handle<<32
    bo_list%data(2) = ior(int(num_buffers, c_int64_t), &
                         ishft(int(sizeof(entries(1)), c_int64_t), 32))  ! bo_number | bo_info_size<<32
    bo_list%data(3) = int(loc(entries), c_int64_t)  ! bo_info_ptr
    
    ! Build ioctl request
    ! DRM_IOWR(DRM_COMMAND_BASE + DRM_AMDGPU_BO_LIST, ...)
    request = int(z'C0186443', c_long)  ! Pre-calculated ioctl number
    
    status = ioctl(device%fd, request, c_loc(bo_list))
    
    if (status == 0) then
      ! Extract list_handle from output
      bo_list_handle = int(iand(bo_list%data(1), int(z'FFFFFFFF', c_int64_t)), c_int32_t)
      print '(A,I0)', "✅ Created BO list with handle: ", bo_list_handle
    else
      print *, "❌ Failed to create BO list"
    end if
    
    deallocate(entries)
    
  end function amdgpu_create_bo_list
  
  ! Destroy BO list
  subroutine amdgpu_destroy_bo_list(device, bo_list_handle)
    type(amdgpu_device), intent(in) :: device
    integer(c_int32_t), intent(in) :: bo_list_handle
    
    type, bind(C) :: drm_amdgpu_bo_list
      integer(c_int64_t) :: data(3)  ! 24 bytes total
    end type drm_amdgpu_bo_list
    
    type(drm_amdgpu_bo_list), target :: bo_list
    integer(c_long) :: request
    integer :: status
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      return
    end if
    
    ! Setup BO list destroy request
    bo_list%data = 0
    ! Fill as drm_amdgpu_bo_list_in
    bo_list%data(1) = ior(int(AMDGPU_BO_LIST_OP_DESTROY, c_int64_t), &
                         ishft(int(bo_list_handle, c_int64_t), 32))  ! operation | list_handle<<32
    bo_list%data(2) = 0  ! bo_number | bo_info_size<<32
    bo_list%data(3) = 0  ! bo_info_ptr
    
    ! Build ioctl request
    request = int(z'C0186443', c_long)
    
    status = ioctl(device%fd, request, c_loc(bo_list))
    
    if (status == 0) then
      print '(A,I0)', "✅ Destroyed BO list: ", bo_list_handle
    else
      print *, "❌ Failed to destroy BO list"
    end if
    
  end subroutine amdgpu_destroy_bo_list
  
  ! Map buffer to GPU virtual address space
  function amdgpu_map_va(device, buffer, va_address) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_buffer), intent(inout) :: buffer
    integer(c_int64_t), intent(in) :: va_address
    integer :: status
    
    ! GEM VA structure - 40 bytes total
    type, bind(C) :: drm_amdgpu_gem_va
      integer(c_int32_t) :: handle
      integer(c_int32_t) :: pad
      integer(c_int32_t) :: operation
      integer(c_int32_t) :: flags
      integer(c_int64_t) :: va_address
      integer(c_int64_t) :: offset_in_bo
      integer(c_int64_t) :: map_size
    end type drm_amdgpu_gem_va
    
    type(drm_amdgpu_gem_va), target :: va_req
    integer(c_long) :: request
    
    status = -1
    
    if (.not. device%is_open) then
      print *, "❌ Device not open"
      return
    end if
    
    if (buffer%handle == 0) then
      print *, "❌ Invalid buffer handle"
      return
    end if
    
    ! Setup VA mapping request
    va_req%handle = buffer%handle
    va_req%pad = 0
    va_req%operation = AMDGPU_VA_OP_MAP
    va_req%flags = ior(ior(AMDGPU_VM_PAGE_READABLE, AMDGPU_VM_PAGE_WRITEABLE), &
                      AMDGPU_VM_PAGE_EXECUTABLE)
    va_req%va_address = va_address
    va_req%offset_in_bo = 0
    va_req%map_size = buffer%size
    
    ! Build ioctl request - use IOW not IOWR
    request = int(z'40286448', c_long)  ! DRM_IOW(DRM_AMDGPU_GEM_VA, ...)
    
    status = ioctl(device%fd, request, c_loc(va_req))
    
    if (status == 0) then
      buffer%va_addr = va_address
      buffer%is_va_mapped = .true.
      print '(A,Z16)', "✅ Mapped buffer to GPU VA: 0x", va_address
    else
      block
        integer(c_int), pointer :: errno
        type(c_ptr) :: errno_ptr
        
        errno_ptr = get_errno()
        call c_f_pointer(errno_ptr, errno)
        print '(A,I0)', "❌ Failed to map buffer to GPU VA, errno: ", errno
        ! Common errors:
        ! 16 (EBUSY) - Address already in use
        ! 22 (EINVAL) - Invalid argument
        ! 12 (ENOMEM) - Out of memory
      end block
    end if
    
  end function amdgpu_map_va
  
  ! Unmap buffer from GPU virtual address space
  subroutine amdgpu_unmap_va(device, buffer)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_buffer), intent(inout) :: buffer
    
    type, bind(C) :: drm_amdgpu_gem_va
      integer(c_int32_t) :: handle
      integer(c_int32_t) :: pad
      integer(c_int32_t) :: operation
      integer(c_int32_t) :: flags
      integer(c_int64_t) :: va_address
      integer(c_int64_t) :: offset_in_bo
      integer(c_int64_t) :: map_size
    end type drm_amdgpu_gem_va
    
    type(drm_amdgpu_gem_va), target :: va_req
    integer(c_long) :: request
    integer :: status
    
    if (.not. device%is_open .or. .not. buffer%is_va_mapped) then
      return
    end if
    
    ! Setup VA unmapping request
    va_req%handle = buffer%handle
    va_req%pad = 0
    va_req%operation = AMDGPU_VA_OP_UNMAP
    va_req%flags = 0
    va_req%va_address = buffer%va_addr
    va_req%offset_in_bo = 0
    va_req%map_size = buffer%size
    
    ! Build ioctl request
    request = int(z'40286448', c_long)
    
    status = ioctl(device%fd, request, c_loc(va_req))
    
    if (status == 0) then
      buffer%va_addr = 0
      buffer%is_va_mapped = .false.
      print '(A)', "✅ Unmapped buffer from GPU VA"
    else
      print *, "❌ Failed to unmap buffer from GPU VA"
    end if
    
  end subroutine amdgpu_unmap_va
  
end module sporkle_amdgpu_direct