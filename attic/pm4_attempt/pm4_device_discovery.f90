module pm4_device_discovery
  ! PM4 Device Discovery Module
  ! ===========================
  ! Enumerate and profile AMD GPUs using PM4
  
  use kinds
  use iso_c_binding
  use pm4_submit
  implicit none
  private
  
  public :: pm4_device, discover_pm4_devices, get_pm4_device_count
  public :: init_pm4_device, cleanup_pm4_device
  
  ! Maximum number of render nodes to check
  integer, parameter :: MAX_RENDER_NODES = 8
  
  ! PM4 device information
  type :: pm4_device
    logical :: available = .false.
    character(len=64) :: device_path = ""
    character(len=64) :: device_name = ""
    integer :: device_id = 0
    integer :: family = 0
    integer :: compute_units = 0
    integer :: shader_engines = 0
    real(sp) :: max_engine_clock_ghz = 0.0
    real(sp) :: max_memory_clock_ghz = 0.0
    integer :: vram_type = 0
    integer :: memory_bus_width = 0
    real(sp) :: vram_size_gb = 0.0
    real(sp) :: gtt_size_gb = 0.0
    
    ! Performance estimates
    real(sp) :: theoretical_gflops = 0.0
    real(sp) :: memory_bandwidth_gb = 0.0
    
    ! PM4 context (only allocated when device is opened)
    type(c_ptr) :: ctx_ptr = c_null_ptr
  end type pm4_device
  
  ! Module storage for discovered devices
  type(pm4_device), save :: discovered_devices(MAX_RENDER_NODES)
  integer, save :: num_devices = 0
  logical, save :: discovery_done = .false.
  
  ! AMD GPU family IDs (from amdgpu_drm.h)
  integer, parameter :: AMDGPU_FAMILY_SI = 110    ! Southern Islands (GCN 1.0)
  integer, parameter :: AMDGPU_FAMILY_CI = 120    ! Sea Islands (GCN 2.0)
  integer, parameter :: AMDGPU_FAMILY_KV = 125    ! Kaveri (GCN 2.0)
  integer, parameter :: AMDGPU_FAMILY_VI = 130    ! Volcanic Islands (GCN 3.0)
  integer, parameter :: AMDGPU_FAMILY_CZ = 135    ! Carrizo (GCN 3.0)
  integer, parameter :: AMDGPU_FAMILY_AI = 141    ! Vega (GCN 5.0)
  integer, parameter :: AMDGPU_FAMILY_RV = 142    ! Raven (GCN 5.0)
  integer, parameter :: AMDGPU_FAMILY_NV = 143    ! Navi 1x (RDNA 1)
  integer, parameter :: AMDGPU_FAMILY_VGH = 144   ! Van Gogh (RDNA 2)
  integer, parameter :: AMDGPU_FAMILY_GC_10_3_6 = 149  ! Navi 2x (RDNA 2)
  integer, parameter :: AMDGPU_FAMILY_YC = 146    ! Yellow Carp (RDNA 2)
  integer, parameter :: AMDGPU_FAMILY_GC_10_3_7 = 151  ! Navi 2x (RDNA 2)
  integer, parameter :: AMDGPU_FAMILY_GC_11_0_0 = 145  ! Navi 3x (RDNA 3)
  integer, parameter :: AMDGPU_FAMILY_GC_11_0_1 = 148  ! Navi 3x (RDNA 3)
  
contains

  ! Get architecture-specific GPU configuration
  subroutine get_gpu_arch_config(family, device_id, shaders_per_cu, ops_per_cycle)
    integer, intent(in) :: family
    integer, intent(in) :: device_id
    integer, intent(out) :: shaders_per_cu
    real(sp), intent(out) :: ops_per_cycle
    
    ! Default to GCN values
    shaders_per_cu = 64
    ops_per_cycle = 2.0
    
    ! Check for RDNA architectures
    if (family == AMDGPU_FAMILY_NV) then
      ! RDNA 1: Wavefront size of 32, but still 64 ALUs per CU
      shaders_per_cu = 64
      ops_per_cycle = 2.0
    else if (family == AMDGPU_FAMILY_VGH .or. family == AMDGPU_FAMILY_YC .or. &
             family == AMDGPU_FAMILY_GC_10_3_6 .or. family == AMDGPU_FAMILY_GC_10_3_7) then
      ! RDNA 2: Same as RDNA 1
      shaders_per_cu = 64
      ops_per_cycle = 2.0
    else if (family == AMDGPU_FAMILY_GC_11_0_0 .or. family == AMDGPU_FAMILY_GC_11_0_1) then
      ! RDNA 3: Dual-issue compute units with 128 stream processors
      shaders_per_cu = 128  ! Doubled from RDNA 2
      ops_per_cycle = 2.0
    else if (family >= AMDGPU_FAMILY_AI) then
      ! Vega and newer GCN: 64 shaders per CU
      shaders_per_cu = 64
      ops_per_cycle = 2.0
    else
      ! Older GCN architectures
      shaders_per_cu = 64
      ops_per_cycle = 2.0
    end if
    
    ! Debug output
    print '(A,I0,A,Z4,A,I0,A,F3.1)', &
      "  Architecture detection: family=", family, " device=0x", device_id, &
      " -> ", shaders_per_cu, " shaders/CU, ", ops_per_cycle, " ops/cycle"
    
  end subroutine get_gpu_arch_config

  ! Discover all available PM4 devices
  function discover_pm4_devices() result(devices)
    type(pm4_device), allocatable :: devices(:)
    type(c_ptr) :: ctx_ptr
    type(sp_device_info) :: dev_info
    character(len=32) :: device_path
    integer :: i, status
    integer :: shaders_per_cu
    real(sp) :: ops_per_cycle
    real(sp) :: effective_mem_rate_gbps
    
    if (.not. discovery_done) then
      num_devices = 0
      
      ! Try each render node
      do i = 0, MAX_RENDER_NODES-1
        write(device_path, '(A,I0)') "/dev/dri/renderD", 128+i
        
        ! Try to open device
        ctx_ptr = sp_pm4_init(trim(device_path))
        if (.not. c_associated(ctx_ptr)) cycle
        
        ! Get device info
        status = sp_pm4_get_device_info(ctx_ptr, dev_info)
        if (status == 0) then
          num_devices = num_devices + 1
          
          ! Store device info
          discovered_devices(num_devices)%available = .true.
          discovered_devices(num_devices)%device_path = trim(device_path)
          discovered_devices(num_devices)%device_id = dev_info%device_id
          discovered_devices(num_devices)%family = dev_info%family
          discovered_devices(num_devices)%compute_units = dev_info%num_compute_units
          discovered_devices(num_devices)%shader_engines = dev_info%num_shader_engines
          discovered_devices(num_devices)%max_engine_clock_ghz = real(dev_info%max_engine_clock) / 1.0e6_sp
          discovered_devices(num_devices)%max_memory_clock_ghz = real(dev_info%max_memory_clock) / 1.0e6_sp
          
          ! Debug: print raw values
          print '(A,A)', "  Device: ", trim(discovered_devices(num_devices)%device_name)
          print '(A,I0,A,I0,A)', "    Raw clocks: engine=", dev_info%max_engine_clock, &
                               " KHz, memory controller=", dev_info%max_memory_clock, " KHz"
          print '(A,I0,A,I0,A,F4.1,A)', "    CUs: ", dev_info%num_compute_units, &
                               ", Bus: ", dev_info%vram_bit_width, " bits, Effective: ", &
                               effective_mem_rate_gbps, " Gbps"
          discovered_devices(num_devices)%vram_type = dev_info%vram_type
          discovered_devices(num_devices)%memory_bus_width = dev_info%vram_bit_width
          discovered_devices(num_devices)%vram_size_gb = real(dev_info%vram_size) / 1024.0_sp**3
          discovered_devices(num_devices)%gtt_size_gb = real(dev_info%gtt_size) / 1024.0_sp**3
          
          ! Convert C string to Fortran
          call c_string_to_fortran(dev_info%name, discovered_devices(num_devices)%device_name)
          
          ! Fix SKU detection for 7900 XT vs XTX (both use device ID 0x744C)
          if (dev_info%device_id == int(z'744C')) then
            if (dev_info%num_compute_units >= 96 .or. dev_info%vram_bit_width >= 384) then
              discovered_devices(num_devices)%device_name = "AMD Radeon RX 7900 XTX"
            else if (dev_info%num_compute_units >= 84 .or. dev_info%vram_bit_width >= 320) then
              discovered_devices(num_devices)%device_name = "AMD Radeon RX 7900 XT"
            end if
          end if
          
          ! Calculate theoretical performance using architecture-aware values
          call get_gpu_arch_config(discovered_devices(num_devices)%family, &
                                  discovered_devices(num_devices)%device_id, &
                                  shaders_per_cu, ops_per_cycle)
          
          ! CUs * shaders/CU * ops/cycle * clock (GHz) = GFLOPS
          discovered_devices(num_devices)%theoretical_gflops = &
            real(discovered_devices(num_devices)%compute_units) * real(shaders_per_cu) * &
            ops_per_cycle * discovered_devices(num_devices)%max_engine_clock_ghz
            
          ! Memory bandwidth calculation
          ! For GDDR6: effective rate = controller clock * 2
          ! Then: bandwidth = (bus_width_bits / 8) * effective_rate_Gbps
          ! Convert controller clock from KHz to GHz, then to effective Gbps
          effective_mem_rate_gbps = real(dev_info%max_memory_clock) / 1.0e6_sp * 2.0_sp  ! KHz to GHz, then *2 for DDR
          
          ! For 7900 series, we know they use 20 Gbps GDDR6, so use that if it looks wrong
          if (dev_info%device_id == int(z'744C')) then
            ! 7900 XT/XTX use 20 Gbps GDDR6
            effective_mem_rate_gbps = 20.0_sp
          end if
          
          discovered_devices(num_devices)%memory_bandwidth_gb = &
            real(discovered_devices(num_devices)%memory_bus_width) / 8.0_sp * effective_mem_rate_gbps
        end if
        
        ! Cleanup temporary context
        call sp_pm4_cleanup(ctx_ptr)
      end do
      
      discovery_done = .true.
    end if
    
    ! Return discovered devices
    if (num_devices > 0) then
      allocate(devices(num_devices), stat=status)
      if (status /= 0) then
        print *, "ERROR: Failed to allocate device array"
        allocate(devices(0), stat=status)  ! Fallback allocation
        return
      end if
      devices = discovered_devices(1:num_devices)
    else
      allocate(devices(0), stat=status)  ! Empty device list
    end if
  end function discover_pm4_devices
  
  ! Get number of discovered devices
  function get_pm4_device_count() result(count)
    integer :: count
    type(pm4_device), allocatable :: devices(:)
    
    if (.not. discovery_done) then
      devices = discover_pm4_devices()
    end if
    count = num_devices
  end function get_pm4_device_count
  
  ! Initialize a PM4 device (open context)
  function init_pm4_device(device_index) result(success)
    integer, intent(in) :: device_index
    logical :: success
    
    success = .false.
    if (device_index < 1 .or. device_index > num_devices) return
    
    ! Check if already initialized
    if (c_associated(discovered_devices(device_index)%ctx_ptr)) then
      success = .true.
      return
    end if
    
    ! Open device
    discovered_devices(device_index)%ctx_ptr = &
      sp_pm4_init(trim(discovered_devices(device_index)%device_path))
      
    success = c_associated(discovered_devices(device_index)%ctx_ptr)
  end function init_pm4_device
  
  ! Cleanup a PM4 device (close context)
  subroutine cleanup_pm4_device(device_index)
    integer, intent(in) :: device_index
    
    if (device_index < 1 .or. device_index > num_devices) return
    
    if (c_associated(discovered_devices(device_index)%ctx_ptr)) then
      call sp_pm4_cleanup(discovered_devices(device_index)%ctx_ptr)
      discovered_devices(device_index)%ctx_ptr = c_null_ptr
    end if
  end subroutine cleanup_pm4_device
  
  ! Helper: Convert C string to Fortran
  subroutine c_string_to_fortran(c_str, f_str)
    character(kind=c_char), intent(in) :: c_str(*)
    character(len=*), intent(out) :: f_str
    integer :: i
    
    f_str = ' '
    do i = 1, len(f_str)
      if (c_str(i) == c_null_char) exit
      f_str(i:i) = c_str(i)
    end do
  end subroutine c_string_to_fortran

end module pm4_device_discovery