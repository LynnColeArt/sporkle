! Automatic Device Selection for Convolution
! ==========================================
!
! This module enhances the juggling system with intelligent device selection
! based on workload characteristics, using the universal device selector framework.
!
! Key features:
!   - Automatic profiling of device performance
!   - Workload analysis (compute vs memory bound)
!   - Dynamic selection based on historical performance
!   - Thermal and load-aware scheduling

module sporkle_conv2d_auto_selector
  use kinds
  use iso_c_binding
  use sporkle_conv2d_juggling, only: conv2d_auto_juggling, init_juggling_system, &
                                      cleanup_juggling_system, get_device_info, &
                                      enable_async_gpu, disable_async_gpu, &
                                      juggling_device_capabilities => device_capabilities
  use sporkle_universal_device_selector
  use cpu_conv2d_adaptive
  use gpu_opengl_interface
  use gpu_async_executor
  implicit none
  
  private
  public :: conv2d_auto_select, init_auto_selector, cleanup_auto_selector
  public :: get_selector_stats, set_profiling_mode
  
  ! Global selector instance
  type(universal_device_selector), save :: selector
  logical, save :: selector_initialized = .false.
  
  ! Performance history for learning
  integer, parameter :: MAX_HISTORY = 1000
  type :: performance_record
    type(workload_characteristics) :: workload
    integer :: device_used
    real(sp) :: time_ms
    real(sp) :: gflops_achieved
  end type
  
  type(performance_record), save :: history(MAX_HISTORY)
  integer, save :: history_count = 0
  
contains

  ! Initialize the automatic selector
  subroutine init_auto_selector()
    type(juggling_device_capabilities) :: dev_caps
    integer :: i
    
    if (selector_initialized) return
    
    ! First initialize the juggling system
    call init_juggling_system()
    
    ! Get device info from juggling system
    dev_caps = get_device_info()
    
    ! Initialize selector with space for devices
    allocate(selector%devices(2))  ! CPU + GPU
    selector%num_devices = 0
    
    ! Add CPU if available
    if (dev_caps%cpu_available) then
      selector%num_devices = selector%num_devices + 1
      i = selector%num_devices
      
      selector%devices(i)%name = "AMD Ryzen CPU (AVX-512)"
      selector%devices(i)%device_type = UNI_DEVICE_CPU_PERFORMANCE
      selector%devices(i)%device_id = 1
      selector%devices(i)%available = .true.
      
      ! CPU capabilities
      selector%devices(i)%caps%supports_fp64 = .true.
      selector%devices(i)%caps%supports_fp32 = .true.
      selector%devices(i)%caps%supports_fp16 = .false.
      selector%devices(i)%caps%supports_matrix_ops = .false.
      selector%devices(i)%caps%supports_async = .false.
      selector%devices(i)%caps%vector_width = 16  ! AVX-512
      selector%devices(i)%caps%peak_gflops = dev_caps%cpu_gflops
      selector%devices(i)%caps%memory_bandwidth = 83.2  ! DDR5-5200 dual channel
      
      ! Set initial pattern performance based on what we know
      selector%devices(i)%pattern_performance(PATTERN_CONV) = dev_caps%cpu_gflops
      selector%devices(i)%pattern_performance(PATTERN_GEMM) = dev_caps%cpu_gflops
    end if
    
    ! Add GPU if available
    if (dev_caps%gpu_available) then
      selector%num_devices = selector%num_devices + 1
      i = selector%num_devices
      
      selector%devices(i)%name = trim(dev_caps%gpu_name)
      selector%devices(i)%device_type = UNI_DEVICE_GPU_DISCRETE
      selector%devices(i)%device_id = 2
      selector%devices(i)%available = .true.
      
      ! GPU capabilities
      selector%devices(i)%caps%supports_fp64 = .true.
      selector%devices(i)%caps%supports_fp32 = .true.
      selector%devices(i)%caps%supports_fp16 = .true.
      selector%devices(i)%caps%supports_matrix_ops = .true.
      selector%devices(i)%caps%supports_async = .true.
      selector%devices(i)%caps%warp_size = 32  ! AMD wavefront
      selector%devices(i)%caps%peak_gflops = max(1.0_sp, dev_caps%gpu_gflops)
      selector%devices(i)%caps%memory_bandwidth = 960.0  ! 7900 XT bandwidth
      
      ! Set initial pattern performance
      selector%devices(i)%pattern_performance(PATTERN_CONV) = selector%devices(i)%caps%peak_gflops
      selector%devices(i)%pattern_performance(PATTERN_GEMM) = selector%devices(i)%caps%peak_gflops
    end if
    
    ! Calculate total system capabilities
    selector%total_compute_power = 0.0
    selector%total_memory_bandwidth = 0.0
    do i = 1, selector%num_devices
      selector%total_compute_power = selector%total_compute_power + &
                                    selector%devices(i)%caps%peak_gflops
      selector%total_memory_bandwidth = selector%total_memory_bandwidth + &
                                       selector%devices(i)%caps%memory_bandwidth
    end do
    
    selector_initialized = .true.
    
    print *, ""
    print *, "🤖 Automatic Device Selector Initialized"
    print *, "========================================"
    print *, "Devices found:", selector%num_devices
    print '(A,F8.1,A)', "Total compute power: ", selector%total_compute_power, " GFLOPS"
    print *, "Profiling mode:", selector%profile_mode
    print *, ""
    
  end subroutine init_auto_selector
  
  ! Main automatic selection convolution
  function conv2d_auto_select(input, weights, output, &
                             N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    type(workload_characteristics) :: workload
    type(device_routing_decision) :: decision
    integer(i64) :: total_flops, memory_bytes
    real(sp) :: gflops_achieved
    integer :: device_idx
    
    ! Initialize if needed
    if (.not. selector_initialized) call init_auto_selector()
    
    ! Analyze workload
    total_flops = int(N, int64) * int(K, int64) * int(H_out, int64) * int(W_out, int64) * &
                  int(C, int64) * int(kernel_size, int64) * int(kernel_size, int64) * 2_int64
    
    memory_bytes = int(size(input) + size(weights) + size(output), int64) * 4_int64
    
    workload = selector%analyze_workload(total_flops, memory_bytes, PATTERN_CONV)
    workload%batch_size = N
    
    ! Get device recommendation
    decision = selector%select_optimal_device(workload)
    
    ! Override for small workloads (CPU is better due to kernel overhead)
    if (total_flops < 100e6_int64 .and. selector%num_devices > 1) then
      ! Force CPU for tiny workloads
      decision%primary_device = 1  ! CPU
      decision%reasoning = "CPU selected for small workload (avoids GPU overhead)"
    end if
    
    ! Print selection reasoning in profiling mode
    if (selector%profile_mode) then
      print '(A,A)', "🎯 ", trim(decision%reasoning)
      print '(A,F8.1,A,F6.1,A)', "   Workload: ", &
        real(total_flops)/1e9, " GFLOPS, AI=", workload%arithmetic_intensity, " FLOPS/byte"
    end if
    
    ! Execute on selected device
    device_idx = decision%primary_device
    
    if (device_idx == 1) then
      ! CPU selected
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    else if (device_idx == 2) then
      ! GPU selected - use async pipeline
      time_ms = execute_gpu_async_selection(input, weights, output, &
                                           N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    else
      ! Fallback to juggling system
      time_ms = conv2d_auto_juggling(input, weights, output, &
                                    N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    end if
    
    ! Calculate achieved performance
    gflops_achieved = real(total_flops) / (time_ms * 1e6)
    
    ! Update device performance history
    if (selector%profile_mode .and. device_idx > 0) then
      call update_device_performance(device_idx, workload, gflops_achieved)
    end if
    
    ! Record in history
    if (history_count < MAX_HISTORY) then
      history_count = history_count + 1
      history(history_count)%workload = workload
      history(history_count)%device_used = device_idx
      history(history_count)%time_ms = time_ms
      history(history_count)%gflops_achieved = gflops_achieved
    end if
    
  end function conv2d_auto_select
  
  ! Execute on GPU with async pipeline
  function execute_gpu_async_selection(input, weights, output, &
                                      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    ! For now, delegate to juggling system which has async
    ! In future, could manage async state here directly
    call enable_async_gpu()
    time_ms = conv2d_auto_juggling(input, weights, output, &
                                  N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    
  end function execute_gpu_async_selection
  
  ! Update device performance based on actual results
  subroutine update_device_performance(device_idx, workload, gflops)
    integer, intent(in) :: device_idx
    type(workload_characteristics), intent(in) :: workload
    real(sp), intent(in) :: gflops
    
    real(dp) :: alpha = 0.1  ! Learning rate
    integer :: pattern
    
    pattern = workload%pattern
    if (pattern < 1 .or. pattern > 7) return
    
    ! Update pattern performance with exponential moving average
    if (selector%devices(device_idx)%pattern_count(pattern) == 0) then
      ! First time seeing this pattern
      selector%devices(device_idx)%pattern_performance(pattern) = real(gflops, real64)
    else
      ! Blend with historical performance
      selector%devices(device_idx)%pattern_performance(pattern) = &
        (1.0 - alpha) * selector%devices(device_idx)%pattern_performance(pattern) + &
        alpha * real(gflops, real64)
    end if
    
    selector%devices(device_idx)%pattern_count(pattern) = &
      selector%devices(device_idx)%pattern_count(pattern) + 1
    
  end subroutine update_device_performance
  
  ! Get selector statistics
  subroutine get_selector_stats()
    integer :: i, j
    real(dp) :: avg_perf
    
    print *, ""
    print *, "📊 Automatic Device Selector Statistics"
    print *, "======================================"
    print *, "Total executions:", history_count
    print *, ""
    
    do i = 1, selector%num_devices
      print '(A,A)', "Device: ", trim(selector%devices(i)%name)
      
      do j = 1, 7
        if (selector%devices(i)%pattern_count(j) > 0) then
          avg_perf = selector%devices(i)%pattern_performance(j)
          print '(A,I0,A,F8.1,A,I0,A)', "  Pattern ", j, ": ", &
            avg_perf, " GFLOPS (", selector%devices(i)%pattern_count(j), " runs)"
        end if
      end do
      print *, ""
    end do
    
    ! Show recent history
    if (history_count > 0) then
      print *, "Recent selections (last 5):"
      do i = max(1, history_count-4), history_count
        print '(A,I0,A,A,A,F8.1,A)', "  #", i, ": ", &
          trim(selector%devices(history(i)%device_used)%name), &
          " achieved ", history(i)%gflops_achieved, " GFLOPS"
      end do
    end if
    
  end subroutine get_selector_stats
  
  ! Set profiling mode
  subroutine set_profiling_mode(enabled)
    logical, intent(in) :: enabled
    selector%profile_mode = enabled
  end subroutine set_profiling_mode
  
  ! Cleanup
  subroutine cleanup_auto_selector()
    if (selector_initialized) then
      call cleanup_juggling_system()
      ! Selector cleanup is automatic (allocatable arrays)
      selector_initialized = .false.
    end if
  end subroutine cleanup_auto_selector

end module sporkle_conv2d_auto_selector
