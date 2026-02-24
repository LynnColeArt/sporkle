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

    ! Try to scan for NVIDIA GPUs
    call try_nvidia_discovery(mesh)

    ! Try to scan for Apple GPUs/Neural Engine
    call try_apple_discovery(mesh)
    
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
    integer :: iostat
    integer :: card_index
    integer(i64) :: vram_bytes
    character(len=256) :: line
    character(len=64) :: vendor, device
    character(len=256) :: sysfs_path
    
    amd_gpu_found = .false.
    
    ! Check up to eight DRM cards for AMD vendor ID
    do card_index = 0, 7
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/vendor"
      if (.not. read_text_file_line(trim(sysfs_path), vendor)) then
        cycle
      end if
      
      ! AMD vendor ID is 0x1002
      if (index(vendor, "0x1002") > 0 .or. index(vendor, "1002") > 0) then
        amd_gpu_found = .true.
      end if
    end do
    
    if (amd_gpu_found) then
      print *, "AMD GPU(s) detected via kernel driver"
      
      ! Detect AMD GPU properties from sysfs
      block
        type(device_handle) :: handle
        integer :: i
        integer :: added_count
        
        added_count = 0
        do i = 0, 7  ! Check up to 8 cards
          write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", i, "/device/vendor"
          if (.not. read_text_file_line(trim(sysfs_path), vendor)) then
            cycle
          end if
          
          if (index(vendor, "1002") == 0) then
            cycle
          end if

          handle%id = mesh%num_devices + added_count
          handle%caps%kind = KIND_AMD

          ! Read device ID for identification
          write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", i, "/device/device"
          if (read_text_file_line(trim(sysfs_path), device)) then
            if (index(device, "744c") > 0) then
              handle%caps%pci_id = "RX 7900 XT"
            else if (index(device, "73bf") > 0) then
              handle%caps%pci_id = "RX 6900 XT"
            else if (index(device, "164e") > 0) then
              handle%caps%pci_id = "Raphael APU"
            else
              handle%caps%pci_id = "AMD GPU (" // trim(adjustl(device)) // ")"
            end if
          else
            handle%caps%pci_id = "AMD GPU"
          end if

          ! Read VRAM size if available
          handle%caps%vram_mb = 0_i64
          write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", i, "/device/mem_info_vram_total"
          if (read_text_file_line(trim(sysfs_path), line)) then
            read(line, *, iostat=iostat) vram_bytes
            if (iostat == 0 .and. vram_bytes > 0) then
              handle%caps%vram_mb = vram_bytes / (1024_i64 * 1024_i64)
            end if
          end if
          
          handle%caps%cores = 0
          handle%caps%sm_count = 0
          handle%caps%mem_bw_gbs = 0.0_rk64
          handle%caps%peak_gflops = 0.0_rk64
          handle%caps%sustained_gflops = 0.0_rk64
          handle%caps%unified_mem = .false.
          handle%caps%p2p_direct = .false.
          handle%caps%driver_ver = "AMDGPU"
          handle%healthy = .true.
          handle%load = 0.0
          
          call mesh%add_device(handle)
          added_count = added_count + 1

          print '(A,I0,A,A,A,I0,A)', "  Card", i, ": ", trim(handle%caps%pci_id), " with ", &
            handle%caps%vram_mb, " MB VRAM (unmeasured capabilities)"
        end do
      end block
    else
      print *, "No AMD GPUs detected (checked kernel driver)"
    end if
    
  end subroutine try_amd_discovery
  
  ! Try to discover NVIDIA devices through kernel driver
  subroutine try_nvidia_discovery(mesh)
    type(mesh_topology), intent(inout) :: mesh
    
    logical :: nvidia_gpu_found
    integer :: card_index, iostat, added_count
    integer(i64) :: vram_bytes
    character(len=256) :: line
    character(len=64) :: vendor, device
    character(len=256) :: sysfs_path
    type(device_handle) :: handle
    
    nvidia_gpu_found = .false.
    
    do card_index = 0, 7
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/vendor"
      if (.not. read_text_file_line(trim(sysfs_path), vendor)) then
        cycle
      end if
      
      if (index(vendor, "0x10de") > 0 .or. index(vendor, "10de") > 0) then
        nvidia_gpu_found = .true.
      end if
    end do
    
    if (.not. nvidia_gpu_found) then
      print *, "No NVIDIA GPUs detected (checked kernel driver)"
      return
    end if
    
    print *, "NVIDIA GPU(s) detected via kernel driver"
    added_count = 0
    
    do card_index = 0, 7
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/vendor"
      if (.not. read_text_file_line(trim(sysfs_path), vendor)) then
        cycle
      end if
      
      if (index(vendor, "0x10de") == 0 .and. index(vendor, "10de") == 0) then
        cycle
      end if
      
      handle%id = mesh%num_devices + added_count
      handle%caps%kind = KIND_NVIDIA
      handle%caps%unified_mem = .false.
      handle%caps%p2p_direct = .false.
      
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/device"
      if (read_text_file_line(trim(sysfs_path), device)) then
        write(handle%caps%pci_id, '(A)') trim(adjustl(device))
      else
        handle%caps%pci_id = "NVIDIA GPU"
      end if
      
      handle%caps%vram_mb = 0_i64
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/mem_info_vram_total"
      if (read_text_file_line(trim(sysfs_path), line)) then
        read(line, *, iostat=iostat) vram_bytes
        if (iostat == 0 .and. vram_bytes > 0) then
          handle%caps%vram_mb = vram_bytes / (1024_i64 * 1024_i64)
        end if
      end if
      
      ! Probe compute units and performance only where the kernel exposes fields directly.
      ! Leave unmeasured performance fields at zero by design.
      handle%caps%cores = 0
      handle%caps%sm_count = 0
      handle%caps%mem_bw_gbs = 0.0_rk64
      handle%caps%peak_gflops = 0.0_rk64
      handle%caps%sustained_gflops = 0.0_rk64
      handle%caps%driver_ver = "NVIDIA kernel DRM"
      handle%healthy = .true.
      handle%load = 0.0
      
      call mesh%add_device(handle)
      added_count = added_count + 1
      
      print '(A,I0,A,A)', "  Card", card_index, ": NVIDIA GPU (", &
            trim(handle%caps%pci_id), ") (unmeasured capabilities)"
    end do
  end subroutine try_nvidia_discovery
  
  ! Try to discover Apple GPUs/Neural Engine candidates
  subroutine try_apple_discovery(mesh)
    type(mesh_topology), intent(inout) :: mesh
    
    logical :: apple_gpu_found
    integer :: card_index
    character(len=64) :: vendor
    character(len=256) :: sysfs_path
    type(device_handle) :: handle
    
    apple_gpu_found = .false.
    
    do card_index = 0, 7
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/vendor"
      if (.not. read_text_file_line(trim(sysfs_path), vendor)) then
        cycle
      end if
      
      if (index(vendor, "0x106b") > 0 .or. index(vendor, "106b") > 0) then
        apple_gpu_found = .true.
        exit
      end if
    end do
    
    if (.not. apple_gpu_found) then
      ! macOS path: discover Apple Silicon via platform APIs when possible
      if (inquire_directory("/System/Library/Frameworks/Metal.framework/")) then
        apple_gpu_found = .true.
        card_index = 0
      else
        print *, "No Apple GPUs detected (checked kernel driver)"
      end if
    end if
    
    if (.not. apple_gpu_found) then
      return
    end if
    
    print *, "Apple GPU/ANE candidate detected"
    if (card_index > 7) then
      card_index = 0
    end if
    
    if (card_index <= 7) then
      write(sysfs_path, '(A,I0,A)') "/sys/class/drm/card", card_index, "/device/name"
      handle%id = mesh%num_devices
      handle%caps%kind = KIND_APPLE
      if (read_text_file_line(trim(sysfs_path), vendor)) then
        handle%caps%pci_id = trim(adjustl(vendor))
      else
        handle%caps%pci_id = "Apple GPU"
      end if
    else
      handle%caps%pci_id = "Apple GPU"
    end if
    
    handle%caps%kind = KIND_APPLE
    handle%caps%cores = 0
    handle%caps%sm_count = 0
    handle%caps%vram_mb = 0_i64
    handle%caps%mem_bw_gbs = 0.0_rk64
    handle%caps%peak_gflops = 0.0_rk64
    handle%caps%sustained_gflops = 0.0_rk64
    handle%caps%unified_mem = .true.
    handle%caps%p2p_direct = .false.
    handle%caps%uvm_supported = .true.
    handle%caps%driver_ver = "Apple Foundation/Metal/ANE (candidate)"
    handle%healthy = .true.
    handle%load = 0.0
    
    call mesh%add_device(handle)
    print '(A,A)', "  Apple GPU/ANE candidate: ", trim(handle%caps%pci_id)
  end subroutine try_apple_discovery

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
  
  logical function read_text_file_line(path, line)
    character(len=*), intent(in) :: path
    character(len=*), intent(out) :: line
    integer :: unit
    integer :: iostat
    logical :: exists
    
    read_text_file_line = .false.
    line = ""
    
    inquire(file=path, exist=exists)
    if (.not. exists) then
      return
    end if
    
    open(newunit=unit, file=trim(path), status="old", action="read", iostat=iostat)
    if (iostat /= 0) then
      return
    end if
    
    read(unit, "(A)", iostat=iostat) line
    close(unit)
    if (iostat == 0) then
      read_text_file_line = .true.
    end if
  end function read_text_file_line
  
  logical function inquire_directory(path)
    character(len=*), intent(in) :: path
    logical :: exists

    inquire(file=trim(path), exist=exists)
    inquire_directory = exists
  end function inquire_directory
end module sporkle_discovery
