! Production interface for convolution with intelligent device selection
! Uses Universal Device Selector for optimal performance
!
module sporkle_conv2d_v2
  use kinds
  use sporkle_universal_device_selector
  use gpu_async_executor
  use sporkle_conv2d_unified, only: sporkle_conv2d_unified
  implicit none
  
  private
  public :: conv2d, conv2d_init, conv2d_cleanup
  public :: conv2d_set_profiling, conv2d_show_stats
  
  ! Global device selector instance
  type(universal_device_selector), save :: global_selector
  logical, save :: selector_initialized = .false.
  
  ! Async executor state
  type(gpu_async_state), save :: async_state
  logical, save :: async_executor_enabled = .true.  ! ENABLED BY DEFAULT!
  logical, save :: async_executor_initialized = .false.
  
  ! Performance tracking
  logical :: profiling_enabled = .true.
  integer :: conv_count = 0
  real(dp) :: total_time = 0.0
  real(dp) :: total_gflops = 0.0
  
contains
  
  subroutine conv2d_init()
    character(len=100) :: env_value
    integer :: env_len, env_status
    
    ! Initialize the device selector
    if (.not. selector_initialized) then
      call global_selector%discover_devices()
      selector_initialized = .true.
      print *, "✅ Sporkle Conv2D v2 initialized with Universal Device Selector"
    end if
    
    ! Check environment variable to optionally disable async executor
    call get_environment_variable("SPORKLE_GPU_ASYNC", env_value, env_len, env_status)
    if (env_status == 0 .and. env_len > 0) then
      select case(trim(env_value))
      case("0", "off", "OFF", "false", "FALSE", "no", "NO")
        async_executor_enabled = .false.
        print *, "⚠️  GPU Async Executor disabled via SPORKLE_GPU_ASYNC environment variable"
      case default
        ! Keep default (enabled)
      end select
    end if
    
    if (async_executor_enabled) then
      print *, "⚡ GPU Async Executor enabled by default"
    end if
  end subroutine conv2d_init
  
  subroutine conv2d_cleanup()
    ! Clean up resources
    if (async_executor_initialized) then
      call gpu_async_executor_cleanup(async_state)
      async_executor_initialized = .false.
      print *, "🧹 GPU Async Executor cleaned up"
    end if
  end subroutine conv2d_cleanup
  
  subroutine conv2d(input, weights, output, &
                   N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, &
                   device_hint, use_async)
    use cpu_conv2d_reference, only: conv2d_cpu_with_warmup
    
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    character(len=*), intent(in), optional :: device_hint  ! "cpu", "gpu", "auto"
    logical, intent(in), optional :: use_async
    
    type(workload_characteristics) :: workload
    type(device_routing_decision) :: decision
    integer(i64) :: total_flops, total_bytes
    real(dp) :: elapsed_ms, gflops
    logical :: async_requested
    integer :: selected_device
    logical :: has_gpu_candidate
    
    ! Initialize if needed
    if (.not. selector_initialized) call conv2d_init()
    
    ! Calculate workload characteristics
    total_flops = int(N, int64) * int(K, int64) * int(H_out, int64) * int(W_out, int64) * &
                  int(C, int64) * int(kernel_size, int64) * int(kernel_size, int64) * 2_int64
    
    ! Input + weights + output memory traffic
    total_bytes = int(N * C * H * W * 4, int64) + &                    ! Input
                  int(K * C * kernel_size * kernel_size * 4, int64) + & ! Weights
                  int(N * K * H_out * W_out * 4, int64)                 ! Output
    
    ! Analyze workload
    workload = global_selector%analyze_workload(total_flops, total_bytes, PATTERN_CONV)
    
    ! Get device routing decision
    if (present(device_hint)) then
      select case(device_hint)
      case("cpu")
        selected_device = 1  ! Force CPU
      case("gpu")
        selected_device = find_first_gpu_device()
        if (selected_device == 0) then
          print *, "❌ No GPU device was discovered in selector inventory."
          error stop "sporkle_conv2d_v2: GPU hint was requested but no GPU backend is available"
        end if
      case default
        decision = global_selector%select_optimal_device(workload)
        selected_device = decision%primary_device
      end select
    else
      decision = global_selector%select_optimal_device(workload)
      selected_device = decision%primary_device
    end if
    
    ! Check async request
    async_requested = .false.
    if (present(use_async)) async_requested = use_async

    ! Execute on selected device
    if (selected_device < 1 .or. selected_device > global_selector%num_devices) then
      print '(A,I0)', "❌ sporkle_conv2d_v2 received invalid device selection: ", selected_device
      error stop "sporkle_conv2d_v2: invalid device selection from selector"
    end if

    has_gpu_candidate = is_gpu_selector_device(selected_device)

    if (selected_device == 1 .and. is_cpu_selector_device(selected_device)) then
      if (profiling_enabled) print '(A)', " 🖥️  Executing on CPU with universal memory optimization"
      elapsed_ms = conv2d_cpu_with_warmup(input, weights, output, &
                                         N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)

    else if (has_gpu_candidate) then
      if (async_requested) then
        print *, "❌ Async execution is not supported by sporkle_conv2d_v2 path."
        error stop "sporkle_conv2d_v2: async path is currently not supported"
      end if

      if (profiling_enabled) then
        print '(A)', " ⚠️  Device requested: " // trim(global_selector%devices(selected_device)%name)
        print '(A)', " 🚀 Dispatching through Kronos unified path."
      end if

      elapsed_ms = sporkle_conv2d_unified(input, weights, output, &
                                          N, C, H, W, K, kernel_size, stride, pad, &
                                          device_type="kronos")
    else
      print '(A,I0,A)', "❌ sporkle_conv2d_v2 selected unsupported device index ", selected_device, " from unified selector."
      error stop "sporkle_conv2d_v2: unsupported device class for this selector index"
    end if
    
    ! Calculate performance
    gflops = real(total_flops, real64) / (elapsed_ms * 1.0e6_real64)
    
    if (profiling_enabled) then
      print '(A,F8.2,A,F8.1,A)', " ✅ Completed in ", elapsed_ms, " ms, ", gflops, " GFLOPS"
    end if
    
    ! Update profiling data
    call global_selector%update_profiling_data(selected_device, PATTERN_CONV, gflops)
    
    ! Track statistics
    conv_count = conv_count + 1
    total_time = total_time + elapsed_ms
    total_gflops = total_gflops + gflops
    
  end subroutine conv2d
  
  subroutine conv2d_set_profiling(enabled)
    logical, intent(in) :: enabled
    profiling_enabled = enabled
  end subroutine conv2d_set_profiling
  
  subroutine conv2d_show_stats()
    real(dp) :: avg_time, avg_gflops
    integer :: i
    
    print *, ""
    print *, "📊 Conv2D Performance Statistics"
    print *, "================================"
    print '(A,I6)', " Total convolutions: ", conv_count
    
    if (conv_count > 0) then
      avg_time = total_time / real(conv_count, real64)
      avg_gflops = total_gflops / real(conv_count, real64)
      print '(A,F8.2,A)', " Average time: ", avg_time, " ms"
      print '(A,F8.1,A)', " Average measured throughput: ", avg_gflops, " GFLOPS"
    end if
    
    print *, ""
    print *, "🎯 Device Performance Profile:"
    do i = 1, global_selector%num_devices
      if (global_selector%devices(i)%pattern_count(PATTERN_CONV) > 0) then
        print '(A,A,A,F8.1,A,I4,A)', " ", &
              trim(global_selector%devices(i)%name), ": ", &
              global_selector%devices(i)%pattern_performance(PATTERN_CONV), &
              " GFLOPS (", &
              global_selector%devices(i)%pattern_count(PATTERN_CONV), &
              " runs)"
      end if
    end do
    
  end subroutine conv2d_show_stats

  function find_first_gpu_device() result(device_idx)
    integer :: device_idx
    integer :: i

    device_idx = 0
    do i = 1, global_selector%num_devices
      if (is_gpu_selector_device(i)) then
        device_idx = i
        return
      end if
    end do
  end function find_first_gpu_device

  logical function is_cpu_selector_device(device_idx)
    integer, intent(in) :: device_idx

    if (device_idx < 1 .or. device_idx > global_selector%num_devices) then
      is_cpu_selector_device = .false.
      return
    end if

    is_cpu_selector_device = (global_selector%devices(device_idx)%device_type == UNI_DEVICE_CPU_PERFORMANCE) .or. &
      (global_selector%devices(device_idx)%device_type == UNI_DEVICE_CPU_EFFICIENCY)
  end function is_cpu_selector_device

  logical function is_gpu_selector_device(device_idx)
    integer, intent(in) :: device_idx

    if (device_idx < 1 .or. device_idx > global_selector%num_devices) then
      is_gpu_selector_device = .false.
      return
    end if

    select case (global_selector%devices(device_idx)%device_type)
    case (UNI_DEVICE_GPU_DISCRETE, UNI_DEVICE_GPU_INTEGRATED, UNI_DEVICE_NEURAL_ENGINE, UNI_DEVICE_MATRIX_UNIT, &
          UNI_DEVICE_DSP)
      is_gpu_selector_device = .true.
    case default
      is_gpu_selector_device = .false.
    end select
  end function is_gpu_selector_device

end module sporkle_conv2d_v2
