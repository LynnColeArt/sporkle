module intelligent_device_juggling_pm4
  ! PM4-Enhanced Intelligent Device Juggling
  ! =======================================
  ! Extends the intelligent device juggling system with PM4 device discovery
  ! for AMD GPUs, while maintaining compatibility with existing interfaces.
  
  use kinds
  use pm4_device_discovery
  use intelligent_device_juggling
  implicit none
  private
  
  public :: discover_and_profile_devices_pm4
  public :: create_gpu_profile_from_pm4
  
contains

  ! Enhanced device discovery that includes PM4 devices
  subroutine discover_and_profile_devices_pm4(strategy)
    type(juggling_strategy), intent(inout) :: strategy
    type(pm4_device), allocatable :: pm4_devices(:)
    integer :: i
    
    print *, "🔍 Layer 1: Device Discovery & Profiling (PM4-Enhanced)"
    print *, "======================================================"
    
    ! Profile CPU device (unchanged)
    call profile_cpu_device_default(strategy%cpu_profile)
    
    ! Discover PM4 devices
    pm4_devices = discover_pm4_devices()
    
    if (size(pm4_devices) > 0) then
      print *, "📊 Found", size(pm4_devices), "AMD GPU(s) via PM4:"
      
      ! Use the most powerful GPU (highest GFLOPS)
      call select_best_pm4_device(pm4_devices, strategy%gpu_profile)
      
      ! Display all discovered devices
      do i = 1, size(pm4_devices)
        print '(A,I0,A,A)', "   [", i, "] ", trim(pm4_devices(i)%device_name)
        print '(A,F0.1,A,I0,A)', "       ", pm4_devices(i)%theoretical_gflops/1000.0, &
                                 " TFLOPS, ", pm4_devices(i)%compute_units, " CUs"
      end do
    else
      print *, "⚠️  No AMD GPUs found via PM4, falling back to stub GPU"
      call profile_gpu_device_stub(strategy%gpu_profile)
    end if
    
    ! Initialize learning parameters
    strategy%total_runs = 0
    strategy%learning_mode = .true.
    strategy%best_combined_gflops = 0.0
    
    print *, ""
    print *, "📊 Device Discovery Complete:"
    print '(A,A,A,F0.1,A)', "   CPU: ", trim(strategy%cpu_profile%device_name), &
                             " (", strategy%cpu_profile%peak_gflops, " GFLOPS theoretical)"
    print '(A,A,A,F0.1,A)', "   GPU: ", trim(strategy%gpu_profile%device_name), &
                             " (", strategy%gpu_profile%peak_gflops, " GFLOPS theoretical)"
  end subroutine discover_and_profile_devices_pm4
  
  ! Select the best PM4 device based on theoretical performance
  subroutine select_best_pm4_device(pm4_devices, gpu_profile)
    type(pm4_device), intent(in) :: pm4_devices(:)
    type(device_profile), intent(out) :: gpu_profile
    integer :: best_idx, i
    real(sp) :: best_gflops
    
    ! Find device with highest theoretical GFLOPS
    best_idx = 1
    best_gflops = pm4_devices(1)%theoretical_gflops
    
    do i = 2, size(pm4_devices)
      if (pm4_devices(i)%theoretical_gflops > best_gflops) then
        best_idx = i
        best_gflops = pm4_devices(i)%theoretical_gflops
      end if
    end do
    
    ! Create profile from PM4 device
    call create_gpu_profile_from_pm4(pm4_devices(best_idx), gpu_profile)
  end subroutine select_best_pm4_device
  
  ! Create a device profile from PM4 device info
  subroutine create_gpu_profile_from_pm4(pm4_dev, profile)
    type(pm4_device), intent(in) :: pm4_dev
    type(device_profile), intent(out) :: profile
    
    profile%device_name = trim(pm4_dev%device_name)
    profile%device_type = "GPU"
    profile%cores = pm4_dev%compute_units
    profile%memory_bandwidth_gb = pm4_dev%memory_bandwidth_gb
    profile%available = .true.
    
    ! Use theoretical GFLOPS
    profile%peak_gflops = pm4_dev%theoretical_gflops
    
    ! Estimate conv2d performance based on device
    if (pm4_dev%device_id == int(z'744c', i32)) then
      ! RX 7900 XT - measured performance
      profile%conv2d_gflops = 451.0  ! From our PM4 implementation
    else if (pm4_dev%device_id == int(z'164e', i32)) then
      ! Raphael iGPU - estimate lower efficiency
      profile%conv2d_gflops = pm4_dev%theoretical_gflops * 0.002  ! 0.2% efficiency
    else
      ! Unknown device - conservative estimate
      profile%conv2d_gflops = pm4_dev%theoretical_gflops * 0.006  ! 0.6% efficiency
    end if
    
    profile%efficiency_ratio = profile%conv2d_gflops / profile%peak_gflops
    profile%optimal_tile_size = 64
    profile%optimal_batch_size = 1
  end subroutine create_gpu_profile_from_pm4
  
  ! Default CPU profile (same as original)
  subroutine profile_cpu_device_default(profile)
    type(device_profile), intent(out) :: profile
    
    profile%device_name = "AMD Ryzen 7900X"
    profile%device_type = "CPU"
    profile%cores = 16  ! Physical cores
    profile%cache_size_mb = 64.0  ! L3 cache
    profile%memory_bandwidth_gb = 100.0  ! DDR5-5200
    profile%available = .true.
    
    ! Conservative CPU GFLOPS estimate
    profile%peak_gflops = 600.0
    profile%conv2d_gflops = 196.7  ! Our measured AVX-512 performance
    profile%efficiency_ratio = profile%conv2d_gflops / profile%peak_gflops
    
    profile%optimal_tile_size = 64
    profile%optimal_batch_size = 1
  end subroutine profile_cpu_device_default
  
  ! Stub GPU profile when no PM4 devices found
  subroutine profile_gpu_device_stub(profile)
    type(device_profile), intent(out) :: profile
    
    profile%device_name = "No GPU (PM4)"
    profile%device_type = "None"
    profile%available = .false.
    profile%cores = 0
    profile%memory_bandwidth_gb = 0.0
    profile%peak_gflops = 0.0
    profile%conv2d_gflops = 0.0
    profile%efficiency_ratio = 0.0
  end subroutine profile_gpu_device_stub

end module intelligent_device_juggling_pm4