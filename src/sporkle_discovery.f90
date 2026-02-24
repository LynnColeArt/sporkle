module sporkle_discovery
  use sporkle_mesh_types
  use cpu_device_module
  use iso_c_binding
  use kinds
  implicit none
  private
  
  public :: scan_devices, profile_links, explain_devices
  
  ! Sparkle does NOT support proprietary SDKs by design
  
contains

  ! Scan all available compute devices
  function scan_devices() result(mesh)
    type(mesh_topology) :: mesh
    type(cpu_device) :: cpu
    type(device_handle) :: handle
    
    ! Always have at least CPU
    cpu = cpu_device(device_id=0)
    
    ! Convert CPU device to mesh handle
    handle%id = cpu%device_id
    handle%caps%kind = KIND_CPU
    handle%caps%cores = cpu%capabilities%compute_units
    handle%caps%unified_mem = .true.
    handle%caps%vram_mb = cpu%capabilities%memory_bytes / (1024 * 1024)
    handle%caps%peak_gflops = real(cpu%capabilities%compute_units, rk64) * &
                              real(cpu%capabilities%clock_speed_ghz, rk64) * &
                              8.0_rk64  ! Roughly estimated default
    handle%caps%sustained_gflops = handle%caps%peak_gflops * 0.7_rk64  ! Calibration placeholder
    handle%caps%mem_bw_gbs = 50.0_rk64  ! Typical DDR4 bandwidth
    handle%healthy = .true.
    handle%native = c_null_ptr  ! CPU doesn't need special handle
    
    ! Add instruction set info
    if (allocated(cpu%capabilities%instruction_set)) then
      handle%caps%driver_ver = cpu%capabilities%instruction_set
    else
      handle%caps%driver_ver = "unknown"
    end if
    
    call mesh%add_device(handle)
    
    ! Sparkle uses vendor-neutral discovery; vendor adapters are optional.
    
    ! Try to scan for AMD GPUs
    call try_amd_discovery(mesh)
    
    ! Try to scan for Intel GPUs
    call try_intel_discovery(mesh)
    
    mesh%profiled = .false.
    
  end function scan_devices
  
  ! Profile interconnect links between devices
  subroutine profile_links(mesh)
    type(mesh_topology), intent(inout) :: mesh
    type(link_metrics) :: link
    integer :: i, j
    integer(i64) :: clock_count, clock_rate
    
    ! For now, create basic host-memory links
    do i = 1, mesh%num_devices
      do j = 1, mesh%num_devices
        link%src_id = mesh%devices(i)%id
        link%dst_id = mesh%devices(j)%id
        
        if (i == j) then
          ! Self-link (no transfer needed)
          link%bw_gbs = 1000000.0_rk64  ! "Infinite"
          link%latency_us = 0.0_rk64
          link%direct = .true.
          link%hops = 0
        else
          ! Different devices - for now assume host staging
          link%bw_gbs = min(mesh%devices(i)%caps%mem_bw_gbs, &
                           mesh%devices(j)%caps%mem_bw_gbs) * 0.8_rk64  ! 80% efficiency
          link%latency_us = 10.0_rk64  ! Host memory latency
          link%direct = .false.
          link%hops = 2  ! src->host->dst
        end if
        
        link%reliability = 0.99_rk32  ! Assume 99% success rate
        call mesh%update_link(link)
      end do
    end do
    
    ! TODO: Actually profile with micro-benchmarks
    ! - Allocate test buffers
    ! - Time transfers of various sizes
    ! - Check for P2P capability
    call system_clock(clock_count, clock_rate)
    if (clock_rate > 0) then
      mesh%profile_timestamp = real(clock_count, rk64) / real(clock_rate, rk64)
    else
      mesh%profile_timestamp = 0.0_rk64
    end if
    mesh%profiled = .true.
    
  end subroutine profile_links
  
  ! Explain discovered devices (introspection)
  subroutine explain_devices(mesh)
    type(mesh_topology), intent(in) :: mesh
    integer :: i
    
    print *, "=== Sporkle Device Discovery ==="
    print *, "Found", mesh%num_devices, "compute device(s):"
    print *, ""
    
    do i = 1, mesh%num_devices
      associate(dev => mesh%devices(i))
        print '(A,I0,A)', "Device ", dev%id, ":"
        print '(A,A)', "  Type: ", dev%caps%kind
        print '(A,I0)', "  Cores/SMs: ", dev%caps%cores
        print '(A,I0,A)', "  Memory: ", dev%caps%vram_mb, " MB"
        print '(A,F0.1,A)', "  Estimated peak (unvalidated): ", dev%caps%peak_gflops, " GFLOPS"
        print '(A,F0.1,A)', "  Memory Bandwidth: ", dev%caps%mem_bw_gbs, " GB/s"
        print '(A,L1)', "  Unified Memory: ", dev%caps%unified_mem
        print '(A,L1)', "  P2P Capable: ", dev%caps%p2p_direct
        if (allocated(dev%caps%driver_ver)) then
          print '(A,A)', "  Driver/ISA: ", dev%caps%driver_ver
        end if
        print *, ""
      end associate
    end do
    
    if (mesh%profiled) then
      print *, "Interconnect profiling: COMPLETE"
    else
      print *, "Interconnect profiling: PENDING"
    end if
    print *, ""
    
  end subroutine explain_devices
  
  ! Try to discover NVIDIA devices through kernel driver
  
  ! Try to discover AMD devices through kernel driver
  subroutine try_amd_discovery(mesh)
    type(mesh_topology), intent(inout) :: mesh
    
    logical :: amd_gpu_found
    integer :: unit, iostat, gpu_count
    character(len=256) :: line
    character(len=64) :: vendor, device
    
    amd_gpu_found = .false.
    gpu_count = 0
    
    ! Check for AMD GPUs via sysfs (no external dependencies!)
    open(newunit=unit, file="/sys/class/drm/card0/device/vendor", &
         status="old", action="read", iostat=iostat)
    if (iostat == 0) then
      read(unit, '(A)', iostat=iostat) vendor
      close(unit)
      
      ! AMD vendor ID is 0x1002
      if (index(vendor, "0x1002") > 0 .or. index(vendor, "1002") > 0) then
        amd_gpu_found = .true.
        gpu_count = gpu_count + 1
      end if
    end if
    
    ! Check card1 too (for multi-GPU systems)
    open(newunit=unit, file="/sys/class/drm/card1/device/vendor", &
         status="old", action="read", iostat=iostat)
    if (iostat == 0) then
      read(unit, '(A)', iostat=iostat) vendor
      close(unit)
      
      if (index(vendor, "0x1002") > 0 .or. index(vendor, "1002") > 0) then
        amd_gpu_found = .true.
        gpu_count = gpu_count + 1
      end if
    end if
    
    if (amd_gpu_found) then
      print *, "AMD GPU(s) detected via kernel driver"
      
      ! Detect actual AMD GPU properties from sysfs
      block
        type(device_handle) :: handle
        integer :: i, card_num
        character(len=256) :: sysfs_path, mem_info
        integer(i64) :: vram_bytes
        
        card_num = 0
        do i = 0, 7  ! Check up to 8 cards
          write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", i, "/device/vendor"
          open(newunit=unit, file=trim(sysfs_path), status="old", action="read", iostat=iostat)
          if (iostat == 0) then
            read(unit, '(A)', iostat=iostat) vendor
            close(unit)
            
            if (index(vendor, "1002") > 0) then
              ! Found AMD GPU - read its properties
              handle%id = mesh%num_devices + card_num
              handle%caps%kind = KIND_AMD
              
              ! Read device ID for identification
              write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", i, "/device/device"
              open(newunit=unit, file=trim(sysfs_path), status="old", action="read", iostat=iostat)
              if (iostat == 0) then
                read(unit, '(A)', iostat=iostat) device
                close(unit)
                ! Map device IDs to known GPUs
                if (index(device, "744c") > 0) then
                  handle%caps%pci_id = "RX 7900 XT"
                else if (index(device, "73bf") > 0) then
                  handle%caps%pci_id = "RX 6900 XT"  
                else if (index(device, "164e") > 0) then
                  handle%caps%pci_id = "Raphael APU"
                else
                  handle%caps%pci_id = "AMD GPU"
                end if
              else
                handle%caps%pci_id = "AMD GPU"
              end if
              
              ! Read VRAM size from mem_info_vram_total
              write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", i, "/device/mem_info_vram_total"
              open(newunit=unit, file=trim(sysfs_path), status="old", action="read", iostat=iostat)
              if (iostat == 0) then
                read(unit, *, iostat=iostat) vram_bytes
                close(unit)
                if (iostat == 0) then
                  handle%caps%vram_mb = int(vram_bytes / (1024 * 1024), int32)
                else
                  handle%caps%vram_mb = 8192  ! Default 8GB if can't read
                end if
              else
                handle%caps%vram_mb = 8192
              end if
              
              ! TODO: Read actual core count, frequencies from sysfs
              ! For now, use conservative estimates
              handle%caps%cores = 60  ! Conservative estimate
              handle%caps%sm_count = 60
              handle%caps%mem_bw_gbs = 400.0_rk64  ! Conservative bandwidth
              handle%caps%peak_gflops = 20000.0_rk64  ! Placeholder for unvalidated topology probing
              handle%caps%sustained_gflops = 10000.0_rk64
              handle%caps%unified_mem = .false.
              handle%caps%p2p_direct = .false.
              handle%caps%driver_ver = "AMDGPU"
              handle%healthy = .true.
              handle%load = 0.0
              
              call mesh%add_device(handle)
              card_num = card_num + 1
              
              print '(A,I0,A,A,A,I0,A)', "  Card", i, ": ", &
                    trim(handle%caps%pci_id), " with ", &
                    handle%caps%vram_mb, " MB VRAM"
            end if
          end if
        end do
      end block
    else
      print *, "No AMD GPUs detected (checked kernel driver)"
    end if
    
  end subroutine try_amd_discovery
  
  ! Try to discover Intel GPUs (gracefully handles missing Level Zero)
  subroutine try_intel_discovery(mesh)
    type(mesh_topology), intent(inout) :: mesh
    
    interface
      function dlopen(filename, flag) bind(C, name="dlopen")
        import :: c_ptr, c_char, c_int
        character(c_char), intent(in) :: filename(*)
        integer(c_int), value :: flag
        type(c_ptr) :: dlopen
      end function dlopen
    end interface
    
    type(c_ptr) :: ze_lib
    integer, parameter :: RTLD_LAZY = 1
    
    ! Try to load Level Zero library
    ze_lib = dlopen("libze_loader.so"//c_null_char, RTLD_LAZY)
    
    if (c_associated(ze_lib)) then
      print *, "Intel GPU runtime detected, scanning for Intel GPUs..."
      print *, "  (Intel GPU discovery not yet implemented in this build)"
    else
      ! Level Zero not available
      print *, "No Intel GPU runtime found (this is normal if you don't have Intel GPUs)"
    end if
    
  end subroutine try_intel_discovery
  
end module sporkle_discovery
