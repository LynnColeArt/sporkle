module sporkle_api_v2
  ! Sparkle API v2 - Unified interface with Kronos-backed runtime
  ! This implements Mini's vision of a clean, unified API
  
  use kinds
  use iso_c_binding
  use sporkle_types
  use sporkle_memory
  use cpu_device_module
  use amd_device_mod
  use sporkle_conv2d_unified
  implicit none
  private
  
  public :: sporkle_init, sporkle_cleanup
  public :: sporkle_create_device, sporkle_destroy_device
  public :: sporkle_allocate, sporkle_deallocate
  public :: sporkle_conv2d
  public :: sporkle_get_device_count, sporkle_get_device_name
  
  ! Global state
  logical, save :: g_initialized = .false.
  integer, save :: g_num_devices = 0
  type(cpu_device), allocatable, save :: g_cpu_devices(:)
  type(amd_device), allocatable, save :: g_gpu_devices(:)
  
contains

  subroutine sporkle_init()
    if (g_initialized) return
    
    print *, "🚀 Initializing Sparkle v2 (Kronos-backed runtime)"
    
    ! Count devices (Kronos discovery path is defined in sporkle_gpu_* modules)
    g_num_devices = 1  ! CPU baseline only; GPU integration is wired separately
    
    ! Allocate device arrays
    allocate(g_cpu_devices(1))
    if (g_num_devices > 1) then
      allocate(g_gpu_devices(g_num_devices - 1))
    end if
    
    ! Initialize CPU device
    g_cpu_devices(1) = cpu_device(0)
    
    ! Initialize GPU devices
    if (allocated(g_gpu_devices)) then
      block
        integer :: i
        do i = 1, size(g_gpu_devices)
          g_gpu_devices(i)%device_id = i - 1
          call g_gpu_devices(i)%initialize(enable_gpu=.true.)
        end do
      end block
    end if
    
    g_initialized = .true.
    print *, "✅ Sparkle initialized with", g_num_devices, "device(s)"
    
  end subroutine sporkle_init
  
  subroutine sporkle_cleanup()
    if (.not. g_initialized) return
    
    if (allocated(g_cpu_devices)) deallocate(g_cpu_devices)
    if (allocated(g_gpu_devices)) deallocate(g_gpu_devices)
    
    g_initialized = .false.
    print *, "✅ Sparkle cleaned up"
    
  end subroutine sporkle_cleanup
  
  function sporkle_create_device(device_id) result(device)
    integer, intent(in) :: device_id
    class(compute_device), allocatable :: device
    
    if (.not. g_initialized) then
      print *, "❌ Sparkle not initialized"
      return
    end if
    
    if (device_id == 0) then
      allocate(device, source=g_cpu_devices(1))
    else if (device_id > 0 .and. device_id < g_num_devices) then
      if (allocated(g_gpu_devices)) then
        allocate(device, source=g_gpu_devices(device_id))
      end if
    else
      print *, "❌ Invalid device ID:", device_id
    end if
    
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
    
    dev_id = 0  ! Default to CPU
    if (present(device_id)) dev_id = device_id
    
    if (dev_id == 0) then
      ! CPU allocation
      handle = create_memory(size_bytes)
    else
      ! GPU allocation
      if (allocated(g_gpu_devices) .and. dev_id <= size(g_gpu_devices)) then
        handle = create_memory(size_bytes, device=g_gpu_devices(dev_id))
      else
        print *, "❌ Invalid device ID for allocation:", dev_id
        handle%is_allocated = .false.
      end if
    end if
    
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
    
    if (present(device_id)) then
      if (device_id == 0) then
        device_type = "cpu"
      else
        device_type = "gpu"
      end if
    else
      device_type = "auto"
    end if
    
    time_ms = sporkle_conv2d_unified(input, weights, output, &
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
    
    if (device_id == 0) then
      name = "CPU"
    else if (device_id > 0 .and. device_id < g_num_devices) then
      name = "GPU (Kronos backend)"
    else
      name = "Unknown"
    end if
    
  end function sporkle_get_device_name

end module sporkle_api_v2
