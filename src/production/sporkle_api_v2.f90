module sporkle_api_v2
  ! Sparkle API v2 - Unified interface with Kronos-backed runtime
  ! This implements a unified API with explicit Kronos-backed non-CPU handling.
  
  use kinds
  use iso_c_binding
  use sporkle_types
  use sporkle_memory
  use cpu_device_module
  use sporkle_conv2d_unified, only: kronos_conv2d_unified
  use sporkle_discovery, only: scan_devices
  use sporkle_mesh_types, only: device_handle, mesh_topology, KIND_CPU, KIND_AMD, KIND_NVIDIA, KIND_APPLE, &
                                KIND_INTEL, KIND_FPGA, KIND_UNKNOWN
  implicit none
  private
  
  public :: sporkle_init, sporkle_cleanup
  public :: sporkle_create_device, sporkle_destroy_device
  public :: sporkle_allocate, sporkle_deallocate
  public :: sporkle_conv2d
  public :: sporkle_get_device_count, sporkle_get_device_name
  
  integer, parameter :: DEV_KIND_UNKNOWN = 0
  integer, parameter :: DEV_KIND_CPU = 1
  integer, parameter :: DEV_KIND_AMD = 2
  integer, parameter :: DEV_KIND_NVIDIA = 3
  integer, parameter :: DEV_KIND_APPLE = 4
  integer, parameter :: DEV_KIND_OTHER = 5

  type, extends(compute_device), private :: kronos_bridge_device
    logical :: is_kronos_bridge = .true.
  contains
    procedure :: allocate => kronos_bridge_allocate
    procedure :: deallocate => kronos_bridge_deallocate
    procedure :: memcpy => kronos_bridge_memcpy
    procedure :: execute => kronos_bridge_execute
    procedure :: synchronize => kronos_bridge_synchronize
    procedure :: get_info => kronos_bridge_get_info
  end type kronos_bridge_device
  
  ! Global state
  logical, save :: g_initialized = .false.
  integer, save :: g_num_devices = 0
  type(cpu_device), allocatable, save :: g_cpu_devices(:)
  type(kronos_bridge_device), allocatable, save :: g_kronos_devices(:)
  integer, allocatable, save :: g_device_slots(:) ! Per-discovery-device slot for backend storage
  integer, allocatable, save :: g_device_kinds(:) ! DEV_KIND_*
  character(len=256), allocatable, save :: g_device_names(:)
  
  contains

  subroutine sporkle_init()
    type(mesh_topology) :: mesh
    integer :: i
    integer :: slot_id
    integer :: bridge_count
    integer :: gmx
    character(len=64) :: kind_tag

    if (g_initialized) return

    print *, "🚀 Initializing Sparkle v2 (Kronos-backed runtime)"

    mesh = scan_devices()

    gmx = 0
    bridge_count = 0

    if (mesh%num_devices > 0) then
      do i = 1, mesh%num_devices
        slot_id = mesh%devices(i)%id + 1
        if (slot_id > gmx) gmx = slot_id

        if (allocated(mesh%devices(i)%caps%kind)) then
          kind_tag = trim(mesh%devices(i)%caps%kind)
        else
          kind_tag = KIND_UNKNOWN
        end if

        if (kind_tag == KIND_AMD .or. kind_tag == KIND_NVIDIA .or. kind_tag == KIND_APPLE) then
          bridge_count = bridge_count + 1
        end if
      end do
      g_num_devices = max(1, gmx)
    else
      g_num_devices = 1
    end if

    if (g_num_devices <= 0) g_num_devices = 1

    if (allocated(g_cpu_devices)) deallocate(g_cpu_devices)
    if (allocated(g_kronos_devices)) deallocate(g_kronos_devices)
    if (allocated(g_device_slots)) deallocate(g_device_slots)
    if (allocated(g_device_kinds)) deallocate(g_device_kinds)
    if (allocated(g_device_names)) deallocate(g_device_names)

    allocate(g_cpu_devices(1))
    allocate(g_device_slots(g_num_devices))
    allocate(g_device_kinds(g_num_devices))
    allocate(g_device_names(g_num_devices))

    if (bridge_count > 0) allocate(g_kronos_devices(bridge_count))

    g_device_slots = -1
    g_device_kinds = DEV_KIND_UNKNOWN
    g_device_names = "Unknown"

    ! Initialize CPU handle at discovery ID 0 by default
    g_device_kinds(1) = DEV_KIND_CPU
    g_device_names(1) = "CPU"
    g_device_slots(1) = 0
    g_cpu_devices(1) = cpu_device(0)

    bridge_count = 0
    do i = 1, mesh%num_devices
      slot_id = mesh%devices(i)%id + 1
      if (slot_id < 1 .or. slot_id > g_num_devices) cycle

      if (allocated(mesh%devices(i)%caps%kind)) then
        kind_tag = trim(mesh%devices(i)%caps%kind)
      else
        kind_tag = KIND_UNKNOWN
      end if

      if (kind_tag == KIND_CPU) cycle

      select case (kind_tag)
      case (KIND_AMD)
        bridge_count = bridge_count + 1
        g_device_kinds(slot_id) = DEV_KIND_AMD
        g_device_slots(slot_id) = bridge_count
        g_device_names(slot_id) = discover_name(mesh%devices(i))
        call init_kronos_bridge_device(g_kronos_devices(bridge_count), DEV_KIND_AMD, mesh%devices(i))
      case (KIND_NVIDIA)
        bridge_count = bridge_count + 1
        g_device_kinds(slot_id) = DEV_KIND_NVIDIA
        g_device_slots(slot_id) = bridge_count
        g_device_names(slot_id) = discover_name(mesh%devices(i))
        call init_kronos_bridge_device(g_kronos_devices(bridge_count), DEV_KIND_NVIDIA, mesh%devices(i))
      case (KIND_APPLE)
        bridge_count = bridge_count + 1
        g_device_kinds(slot_id) = DEV_KIND_APPLE
        g_device_slots(slot_id) = bridge_count
        g_device_names(slot_id) = discover_name(mesh%devices(i))
        call init_kronos_bridge_device(g_kronos_devices(bridge_count), DEV_KIND_APPLE, mesh%devices(i))
      case (KIND_INTEL, KIND_FPGA, KIND_UNKNOWN)
        g_device_kinds(slot_id) = DEV_KIND_OTHER
        g_device_slots(slot_id) = -1
        g_device_names(slot_id) = discover_name(mesh%devices(i))
        print *, "⚠️  Unsupported discovery kind treated as policy-disabled:", trim(kind_tag)
      case default
        g_device_kinds(slot_id) = DEV_KIND_OTHER
        g_device_slots(slot_id) = -1
        g_device_names(slot_id) = discover_name(mesh%devices(i))
        print *, "⚠️  Unsupported discovery kind will be treated as policy-disabled:", trim(kind_tag)
      end select
    end do

    if (allocated(mesh%devices)) deallocate(mesh%devices)
    if (allocated(mesh%links)) deallocate(mesh%links)

    g_initialized = .true.
    print *, "✅ Sparkle initialized with", g_num_devices, "device slot(s)"
    call explain_devices()
  end subroutine sporkle_init
  
  subroutine sporkle_cleanup()
    if (.not. g_initialized) return
    
    if (allocated(g_cpu_devices)) deallocate(g_cpu_devices)
    if (allocated(g_kronos_devices)) deallocate(g_kronos_devices)
    if (allocated(g_device_slots)) deallocate(g_device_slots)
    if (allocated(g_device_kinds)) deallocate(g_device_kinds)
    if (allocated(g_device_names)) deallocate(g_device_names)
    
    g_initialized = .false.
    print *, "✅ Sparkle cleaned up"
  end subroutine sporkle_cleanup
  
  function sporkle_create_device(device_id) result(device)
    integer, intent(in) :: device_id
    class(compute_device), allocatable :: device
    integer :: slot

    if (.not. g_initialized) then
      print *, "❌ Sparkle not initialized"
      error stop "sporkle_create_device called before initialization"
    end if
    if (device_id < 0 .or. device_id >= g_num_devices) then
      print *, "❌ Invalid device ID:", device_id
      error stop "sporkle_create_device: invalid device id"
    end if

    slot = device_id + 1
    select case (g_device_kinds(slot))
    case (DEV_KIND_CPU)
      allocate(device, source=g_cpu_devices(1))
    case (DEV_KIND_AMD)
      if (.not. allocated(g_kronos_devices) .or. g_device_slots(slot) <= 0 .or. g_device_slots(slot) > size(g_kronos_devices)) then
        print *, "❌ Kronos bridge slot missing for:", device_id
        error stop "sporkle_create_device: Kronos bridge slot mapping is invalid"
      end if
      allocate(device, source=g_kronos_devices(g_device_slots(slot)))
    case (DEV_KIND_NVIDIA, DEV_KIND_APPLE)
      if (.not. allocated(g_kronos_devices) .or. g_device_slots(slot) <= 0 .or. g_device_slots(slot) > size(g_kronos_devices)) then
        print *, "❌ Kronos bridge slot missing for:", device_id
        error stop "sporkle_create_device: Kronos bridge slot mapping is invalid"
      end if
      allocate(device, source=g_kronos_devices(g_device_slots(slot)))
    case (DEV_KIND_OTHER)
      print *, "❌ Unsupported device kind mapped as policy-disabled:", trim(g_device_names(slot))
      error stop "sporkle_create_device: unsupported discovery kind"
    case default
      print *, "❌ Device ID:", device_id, "is currently unsupported in the active runtime"
      error stop "sporkle_create_device: unsupported device class"
    end select
  end function sporkle_create_device
  
  subroutine sporkle_destroy_device(device)
    class(compute_device), allocatable, intent(inout) :: device
    if (allocated(device)) deallocate(device)
  end subroutine sporkle_destroy_device
  
  function sporkle_allocate(size_bytes, device_id) result(handle)
    integer(i64), intent(in) :: size_bytes
    integer, intent(in), optional :: device_id
    type(memory_handle) :: handle
    
    integer :: dev_id
    integer :: slot
    
    dev_id = 0  ! Default to CPU
    if (present(device_id)) dev_id = device_id
    
    if (.not. g_initialized) then
      print *, "❌ Sparkle not initialized"
      error stop "sporkle_allocate called before initialization"
    end if

    if (dev_id < 0 .or. dev_id >= g_num_devices) then
      print *, "❌ Invalid device ID for allocation:", dev_id
      error stop "sporkle_allocate: invalid device id"
    end if

    slot = dev_id + 1
    select case (g_device_kinds(slot))
    case (DEV_KIND_CPU)
      handle = create_memory(size_bytes)
    case (DEV_KIND_AMD)
      if (.not. allocated(g_kronos_devices) .or. g_device_slots(slot) <= 0 .or. g_device_slots(slot) > size(g_kronos_devices)) then
        print *, "❌ Kronos bridge allocation slot missing for:", dev_id
        error stop "sporkle_allocate: Kronos bridge slot mapping is invalid"
      end if
      handle = create_memory(size_bytes, device=g_kronos_devices(g_device_slots(slot)))
    case (DEV_KIND_NVIDIA, DEV_KIND_APPLE)
      if (.not. allocated(g_kronos_devices) .or. g_device_slots(slot) <= 0 .or. g_device_slots(slot) > size(g_kronos_devices)) then
        print *, "❌ Kronos bridge allocation slot missing for:", dev_id
        error stop "sporkle_allocate: Kronos bridge slot mapping is invalid"
      end if
      handle = create_memory(size_bytes, device=g_kronos_devices(g_device_slots(slot)))
    case (DEV_KIND_OTHER)
      print *, "❌ Unsupported device kind is excluded from runtime allocation:", trim(g_device_names(slot))
      error stop "sporkle_allocate: unsupported discovery kind"
    case default
      print *, "❌ Allocation requested on unsupported device:", dev_id
      error stop "sporkle_allocate: unsupported device class"
    end select
  end function sporkle_allocate
  
  subroutine sporkle_deallocate(handle)
    type(memory_handle), intent(inout) :: handle
    call destroy_memory(handle)
  end subroutine sporkle_deallocate
  
  function sporkle_conv2d(input, weights, output, &
                         N, C, H, W, K, kernel_size, stride, pad, &
                         device_id) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad
    integer, intent(in), optional :: device_id
    real(sp) :: time_ms
    
    character(len=16) :: device_type
    integer :: actual_device_id
    integer :: slot

    if (present(device_id)) then
      actual_device_id = device_id
    else
      actual_device_id = 0
    end if
    
    if (actual_device_id < 0 .or. actual_device_id >= g_num_devices) then
      print *, "❌ Invalid device ID for conv2d:", actual_device_id
      error stop "sporkle_conv2d: invalid device id"
    end if
    
    slot = actual_device_id + 1
    select case (g_device_kinds(slot))
    case (DEV_KIND_CPU)
      device_type = "cpu"
    case (DEV_KIND_AMD, DEV_KIND_NVIDIA, DEV_KIND_APPLE)
      device_type = "kronos"
    case default
      print *, "❌ conv2d requested on unsupported device:", actual_device_id
      error stop "sporkle_conv2d: unsupported device class"
    end select
    
    time_ms = kronos_conv2d_unified(input, weights, output, &
                                    N, C, H, W, K, kernel_size, stride, pad, &
                                    device_type=device_type)
    
  end function sporkle_conv2d
  
  function sporkle_get_device_count() result(count)
    integer :: count
    count = g_num_devices
  end function sporkle_get_device_count
  
  function sporkle_get_device_name(device_id) result(name)
    integer, intent(in) :: device_id
    character(len=256) :: name
    integer :: slot
    
    if (device_id < 0 .or. device_id >= g_num_devices) then
      name = "Unknown"
      return
    end if

    slot = device_id + 1
    if (slot < 1 .or. slot > size(g_device_names)) then
      name = "Unknown"
      return
    end if
    
    select case (g_device_kinds(slot))
    case (DEV_KIND_CPU)
      name = "CPU"
    case default
      name = trim(g_device_names(slot))
    end select
  end function sporkle_get_device_name

  function discover_name(handle) result(name)
    type(device_handle), intent(in) :: handle
    character(len=256) :: name

    if (allocated(handle%caps%pci_id)) then
      name = trim(handle%caps%pci_id)
    else if (allocated(handle%caps%driver_ver)) then
      name = trim(handle%caps%driver_ver)
    else if (allocated(handle%caps%kind)) then
      name = trim(handle%caps%kind)
    else
      name = "Unknown device"
    end if
  end function discover_name

  subroutine init_kronos_bridge_device(device, slot_kind, discovered)
    type(kronos_bridge_device), intent(inout) :: device
    integer, intent(in) :: slot_kind
    type(device_handle), intent(in) :: discovered

    device%device_id = discovered%id
    select case (slot_kind)
    case (DEV_KIND_AMD)
      device%device_type = DEVICE_GPU_AMD
    case (DEV_KIND_NVIDIA)
      device%device_type = DEVICE_GPU_NVIDIA
    case (DEV_KIND_APPLE)
      device%device_type = DEVICE_MOBILE
    case default
      device%device_type = DEVICE_UNKNOWN
    end select

    device%name = discover_name(discovered)
    device%is_available = .true.
    device%current_load = 0.0_sp

    device%capabilities%memory_bytes = max(0_i64, discovered%caps%vram_mb) * int(1024_i64, i64) * int(1024_i64, i64)
    device%capabilities%compute_units = discovered%caps%cores
    device%capabilities%clock_speed_ghz = 1.0_sp
    device%capabilities%memory_bandwidth_gbps = real(discovered%caps%mem_bw_gbs, sp)
    device%capabilities%supports_unified_memory = discovered%caps%unified_mem
    device%capabilities%supports_p2p = discovered%caps%p2p_direct
    device%capabilities%supports_float64 = .true.
    device%capabilities%supports_float16 = .true.

    if (allocated(discovered%caps%driver_ver)) then
      device%capabilities%instruction_set = trim(discovered%caps%driver_ver)
    else if (allocated(discovered%caps%kind)) then
      device%capabilities%instruction_set = trim(discovered%caps%kind)
    else
      device%capabilities%instruction_set = "kronos"
    end if

    call device%get_info()
  end subroutine init_kronos_bridge_device

  function kronos_bridge_allocate(self, size_bytes, pinned) result(buffer)
    class(kronos_bridge_device), intent(inout) :: self
    integer(i64), intent(in) :: size_bytes
    logical, intent(in), optional :: pinned
    type(sporkle_buffer) :: buffer
    logical :: is_pinned
    integer(c_int) :: status
    integer(c_size_t), parameter :: CACHE_LINE_SIZE = 64

    interface
      function posix_memalign(ptr, alignment, size) bind(c, name="posix_memalign")
        import :: c_ptr, c_size_t, c_int
        type(c_ptr), intent(out) :: ptr
        integer(c_size_t), value :: alignment, size
        integer(c_int) :: posix_memalign
      end function posix_memalign
    end interface

    is_pinned = .false.
    if (present(pinned)) is_pinned = pinned

    if (size_bytes <= 0_i64) then
      print *, "ERROR: Requested Kronos bridge allocation size must be positive:", size_bytes
      buffer%size_bytes = 0
      buffer%owning_device = self%device_id
      buffer%is_pinned = is_pinned
      return
    end if

    buffer%size_bytes = size_bytes
    buffer%owning_device = self%device_id
    buffer%is_pinned = is_pinned

    status = posix_memalign(buffer%data, CACHE_LINE_SIZE, int(size_bytes, c_size_t))
    if (status /= 0 .or. .not. c_associated(buffer%data)) then
      print *, "ERROR: Failed to allocate ", size_bytes, " bytes for ", trim(self%name)
      buffer%size_bytes = 0
      buffer%data = c_null_ptr
      buffer%owning_device = -1
    end if
  end function kronos_bridge_allocate

  subroutine kronos_bridge_deallocate(self, buffer)
    class(kronos_bridge_device), intent(inout) :: self
    type(sporkle_buffer), intent(inout) :: buffer

    interface
      subroutine free(ptr) bind(c, name="free")
        import :: c_ptr
        type(c_ptr), value :: ptr
      end subroutine free
    end interface

    if (c_associated(buffer%data)) then
      call free(buffer%data)
    end if

    buffer%data = c_null_ptr
    buffer%size_bytes = 0
    buffer%owning_device = -1
    buffer%is_pinned = .false.
  end subroutine kronos_bridge_deallocate

  function kronos_bridge_memcpy(self, dst, src, size_bytes) result(status)
    class(kronos_bridge_device), intent(inout) :: self
    type(sporkle_buffer), intent(inout) :: dst
    type(sporkle_buffer), intent(in) :: src
    integer(i64), intent(in) :: size_bytes
    integer(i32) :: status

    interface
      subroutine memcpy(dst, src, n) bind(c, name="memcpy")
        import :: c_ptr, c_size_t
        type(c_ptr), value :: dst, src
        integer(c_size_t), value :: n
      end subroutine memcpy
    end interface

    status = SPORKLE_ERROR

    if (.not. c_associated(dst%data) .or. .not. c_associated(src%data)) return
    if (size_bytes > dst%size_bytes .or. size_bytes > src%size_bytes) return

    call memcpy(dst%data, src%data, int(size_bytes, c_size_t))
    status = SPORKLE_SUCCESS
  end function kronos_bridge_memcpy

  function kronos_bridge_execute(self, kernel_name, args, grid_size, block_size) result(status)
    class(kronos_bridge_device), intent(inout) :: self
    character(len=*), intent(in) :: kernel_name
    type(c_ptr), intent(in) :: args(:)
    integer(i32), intent(in) :: grid_size(3)
    integer(i32), intent(in) :: block_size(3)
    integer(i32) :: status
    real(sp) :: elapsed_ms
    real(sp), pointer :: input(:), weights(:), output(:)
    integer, pointer :: params(:)
    integer, pointer :: p_N, p_C, p_H, p_W, p_K, p_kernel_size, p_stride, p_pad, p_h_out, p_w_out
    integer :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    integer(i64) :: input_count, weights_count, output_count

    status = SPORKLE_ERROR

    select case (trim(kernel_name))
    case ("conv2d", "convolution")
      if (size(args) == 4) then
        call c_f_pointer(args(4), params, [8])
        if (.not. associated(params)) then
          print *, "❌ conv2d args missing packed parameter block"
          return
        end if
        N = params(1)
        C = params(2)
        H = params(3)
        W = params(4)
        K = params(5)
        kernel_size = params(6)
        stride = params(7)
        pad = params(8)
      else if (size(args) >= 13) then
        call c_f_pointer(args(4), p_N)
        call c_f_pointer(args(5), p_C)
        call c_f_pointer(args(6), p_H)
        call c_f_pointer(args(7), p_W)
        call c_f_pointer(args(8), p_K)
        call c_f_pointer(args(9), p_kernel_size)
        call c_f_pointer(args(10), p_stride)
        call c_f_pointer(args(11), p_pad)
        call c_f_pointer(args(12), p_h_out)
        call c_f_pointer(args(13), p_w_out)
        if (.not. associated(p_N) .or. .not. associated(p_C) .or. .not. associated(p_H) .or. .not. associated(p_W) .or. &
            .not. associated(p_K) .or. .not. associated(p_kernel_size) .or. .not. associated(p_stride) .or. &
            .not. associated(p_pad) .or. .not. associated(p_h_out) .or. .not. associated(p_w_out)) then
          print *, "❌ conv2d args missing explicit scalar pointers"
          return
        end if

        N = p_N
        C = p_C
        H = p_H
        W = p_W
        K = p_K
        kernel_size = p_kernel_size
        stride = p_stride
        pad = p_pad
        H_out = p_h_out
        W_out = p_w_out
      else
        print *, "❌ conv2d execute expects either packed params (4 args) or explicit scalars (13 args)"
        return
      end if

      if (N <= 0 .or. C <= 0 .or. H <= 0 .or. W <= 0 .or. K <= 0 .or. kernel_size <= 0 .or. stride <= 0) then
        print *, "❌ invalid conv2d dimensions in Kronos bridge execute"
        return
      end if

      if (size(args) < 13) then
        H_out = (H + 2 * pad - kernel_size) / stride + 1
        W_out = (W + 2 * pad - kernel_size) / stride + 1
      end if

      if (H_out <= 0 .or. W_out <= 0) then
        print *, "❌ invalid conv2d output dimensions derived for kernel launch"
        return
      end if

      input_count = int(N, i64) * int(C, i64) * int(H, i64) * int(W, i64)
      weights_count = int(K, i64) * int(C, i64) * int(kernel_size, i64) * int(kernel_size, i64)
      output_count = int(N, i64) * int(K, i64) * int(H_out, i64) * int(W_out, i64)

      if (input_count <= 0 .or. weights_count <= 0 .or. output_count <= 0) then
        print *, "❌ computed conv2d tensor sizes must be positive"
        return
      end if

      call c_f_pointer(args(1), input, [int(input_count,kind(1))])
      call c_f_pointer(args(2), weights, [int(weights_count,kind(1))])
      call c_f_pointer(args(3), output, [int(output_count,kind(1))])
      if (.not. associated(input) .or. .not. associated(weights) .or. .not. associated(output)) then
        print *, "❌ Failed to materialize Kronos bridge argument pointers"
        return
      end if

      elapsed_ms = sporkle_conv2d(input, weights, output, &
                                  N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, device_type="kronos")
      if (elapsed_ms > 0.0_sp) then
        print '(A,F0.3,A)', "✅ Kronos bridge launch completed in ", elapsed_ms, " ms"
      else
        print *, "⚠️ Kronos bridge launch completed with non-positive timing; treating as unsupported"
        status = SPORKLE_ERROR
        return
      end if

      status = SPORKLE_SUCCESS

    case default
      print *, "❌ Kronos bridge execute does not support kernel:", trim(kernel_name), &
               " on device", trim(self%name)
      status = SPORKLE_ERROR
    end select
  end function kronos_bridge_execute

  function kronos_bridge_synchronize(self) result(status)
    class(kronos_bridge_device), intent(inout) :: self
    integer(i32) :: status

    status = SPORKLE_SUCCESS
    self%current_load = 0.0_sp
  end function kronos_bridge_synchronize

  subroutine kronos_bridge_get_info(self)
    class(kronos_bridge_device), intent(inout) :: self

    self%is_available = .true.
    self%current_load = 0.0_sp
  end subroutine kronos_bridge_get_info

  subroutine explain_devices()
    integer :: i
    if (g_num_devices <= 0) return

    print *, "Discovered devices:"
    do i = 1, g_num_devices
      select case (g_device_kinds(i))
      case (DEV_KIND_CPU)
        print *, "  [", i-1, "] CPU"
      case default
        print *, "  [", i-1, "] ", trim(g_device_names(i)), " (active runtime: ", &
            device_kind_name(g_device_kinds(i)), ")"
      end select
    end do
  end subroutine explain_devices

  function device_kind_name(kind) result(name)
    integer, intent(in) :: kind
    character(len=16) :: name

    select case (kind)
    case (DEV_KIND_CPU)
      name = "cpu"
    case (DEV_KIND_AMD)
      name = "amd"
    case (DEV_KIND_NVIDIA)
      name = "nvidia"
    case (DEV_KIND_APPLE)
      name = "apple"
    case (DEV_KIND_OTHER)
      name = "other"
    case default
      name = "unknown"
    end select
  end function device_kind_name

end module sporkle_api_v2
