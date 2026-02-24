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
                                      cleanup_juggling_system, enable_async_gpu
  use sporkle_universal_device_selector
  use cpu_conv2d_adaptive
  use gpu_async_executor
  use sporkle_conv2d_unified, only: sporkle_conv2d_unified
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
    integer :: i

    if (selector_initialized) return

    ! Initialize the lower-level scheduling probes
    call init_juggling_system()

    ! Discover all supported devices through the universal selector path.
    call selector%discover_devices()
    if (selector%num_devices == 0) then
      error stop "sporkle_conv2d_auto_selector: no devices discovered"
    end if

    selector%total_compute_power = 0.0
    selector%total_memory_bandwidth = 0.0
    do i = 1, selector%num_devices
      selector%devices(i)%device_id = i

      selector%total_compute_power = selector%total_compute_power + selector%devices(i)%caps%peak_gflops
      selector%total_memory_bandwidth = selector%total_memory_bandwidth + selector%devices(i)%caps%memory_bandwidth
    end do

    selector_initialized = .true.

    print *, ""
    print *, "🤖 Automatic Device Selector Initialized"
    print *, "========================================"
    print '(A,I0)', "Devices found: ", selector%num_devices
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
    integer :: cpu_idx

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
      cpu_idx = find_first_device_type(selector, UNI_DEVICE_CPU_PERFORMANCE)
      if (cpu_idx == 0) cpu_idx = find_first_device_type(selector, UNI_DEVICE_CPU_EFFICIENCY)
      if (cpu_idx > 0) then
        decision%primary_device = cpu_idx
        decision%reasoning = "CPU selected for small workload (avoids GPU overhead)"
      end if
    end if

    ! Print selection reasoning in profiling mode
    if (selector%profile_mode) then
      print '(A,A)', "🎯 ", trim(decision%reasoning)
      print '(A,F8.1,A,F6.1,A)', "   Workload: ", &
        real(total_flops)/1e9, " GFLOPS, AI=", workload%arithmetic_intensity, " FLOPS/byte"
    end if

    ! Execute on selected device.
    ! GPU/accelerator execution routes through unified Kronos-backed dispatch.
    device_idx = decision%primary_device
    if (device_idx < 1 .or. device_idx > selector%num_devices) then
      print *, "❌ Invalid selector result:", device_idx
      error stop "sporkle_conv2d_auto_selector: scheduler returned invalid device"
    end if
    if (.not. selector%devices(device_idx)%available) then
      print *, "❌ Selected device is unavailable: ", trim(selector%devices(device_idx)%name)
      error stop "sporkle_conv2d_auto_selector: selected device unavailable"
    end if

    select case (selector%devices(device_idx)%device_type)
    case (UNI_DEVICE_CPU_PERFORMANCE, UNI_DEVICE_CPU_EFFICIENCY)
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    case (UNI_DEVICE_GPU_DISCRETE, UNI_DEVICE_GPU_INTEGRATED, UNI_DEVICE_NEURAL_ENGINE, &
          UNI_DEVICE_MATRIX_UNIT, UNI_DEVICE_DSP)
      time_ms = execute_gpu_async_selection(input, weights, output, &
                                           N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    case default
      print *, "❌ Unsupported selected device class: ", trim(selector%devices(device_idx)%name)
      error stop "sporkle_conv2d_auto_selector: unsupported device class for this path"
    end select

    ! Calculate achieved performance
    if (time_ms > 0.0_sp) then
      gflops_achieved = real(total_flops) / (time_ms * 1e6)
    else
      gflops_achieved = 0.0_sp
    end if

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

    time_ms = sporkle_conv2d_unified(input, weights, output, &
                                     N, C, H, W, K, kernel_size, stride, pad, &
                                     device_type="kronos")

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
    if (device_idx < 1 .or. device_idx > selector%num_devices) return

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
        if (i > 0 .and. i <= history_count) then
          if (history(i)%device_used > 0 .and. history(i)%device_used <= selector%num_devices) then
            print '(A,I0,A,A,A,F8.1,A)', "  #", i, ": ", &
              trim(selector%devices(history(i)%device_used)%name), &
              " achieved ", history(i)%gflops_achieved, " GFLOPS"
          end if
        end if
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

  integer function find_first_device_type(this, target_type)
    class(universal_device_selector), intent(in) :: this
    integer, intent(in) :: target_type
    integer :: i

    find_first_device_type = 0
    do i = 1, this%num_devices
      if (this%devices(i)%available .and. this%devices(i)%device_type == target_type) then
        find_first_device_type = i
        return
      end if
    end do
  end function find_first_device_type

end module sporkle_conv2d_auto_selector
