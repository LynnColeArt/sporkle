! Sporkle Conv2D V3 - Production Integration
! ==========================================
!
! This is the new production version that integrates:
! 1. Thread-safe GPU program cache
! 2. Dynamic shader generation
! 3. Binary persistence
! 4. Async execution (deferred)
! 5. Auto device selection (deferred for production recovery)
!
! This replaces sporkle_conv2d_juggling as the main interface.

module sporkle_conv2d_v3
  use kinds
  use sporkle_types
  use gpu_opengl_interface
  use gpu_dynamic_shader_cache
  use gpu_program_cache_threadsafe, only: init_program_cache_ts, &
                                             print_cache_stats_ts, &
                                             cleanup_program_cache_ts
  use gpu_async_executor, only: gpu_async_state, &
                                gpu_async_executor_init, gpu_async_executor_cleanup
  use sporkle_conv2d_auto_selector, only: init_auto_selector
  use cpu_conv2d_adaptive, only: conv2d_adaptive
  use sporkle_conv2d_unified, only: sporkle_conv2d_unified
  use timing_helpers
  use iso_c_binding, only: c_ptr, c_f_pointer, c_loc
  implicit none
  
  private
  public :: sporkle_conv2d_v3_execute
  public :: sporkle_conv2d_v3_init, sporkle_conv2d_v3_cleanup
  public :: sporkle_conv2d_v3_stats
  
  ! Global state
  type :: conv2d_v3_state
    type(dynamic_shader_cache) :: shader_cache
    type(gpu_async_state) :: async_exec
    ! type(auto_selector_state) :: device_selector  ! Not needed - selector is internal to module
    logical :: initialized = .false.
    logical :: use_dynamic_shaders = .true.
    logical :: use_async = .true.
    logical :: use_auto_select = .true.

    ! Statistics
    integer(i64) :: total_executions = 0
    integer(i64) :: gpu_executions = 0
    integer(i64) :: cpu_executions = 0
    real(dp) :: total_time_ms = 0.0
    real(dp) :: total_gflops = 0.0
  end type conv2d_v3_state
  
  type(conv2d_v3_state), save :: global_state
  
contains

  ! Initialize Conv2D V3 system
  subroutine sporkle_conv2d_v3_init(cache_dir, use_dynamic, use_async, use_auto)
    character(len=*), intent(in), optional :: cache_dir
    logical, intent(in), optional :: use_dynamic, use_async, use_auto
    
    character(len=256) :: actual_cache_dir
    
    if (global_state%initialized) then
      print *, "⚠️  Conv2D V3 already initialized"
      return
    end if
    
    print *, "🚀 Initializing Sporkle Conv2D V3 (Production)"
    print *, "============================================="
    
    ! Set options
    if (present(use_dynamic)) global_state%use_dynamic_shaders = use_dynamic
    if (present(use_async)) global_state%use_async = use_async
    if (present(use_auto)) global_state%use_auto_select = use_auto
    
    actual_cache_dir = "production_cache/"
    if (present(cache_dir)) actual_cache_dir = cache_dir
    
    ! Initialize GPU only when auto-selection requires recovery-policy routing.
    if (global_state%use_auto_select) then
      if (.not. gpu_init()) then
        print *, "❌ Failed to initialize GPU for auto-select policy"
        error stop "sporkle_conv2d_v3_init: auto-select policy requires GPU initialization"
      end if
    else
      print *, "⚠️  Auto-select disabled: skipping GPU init in CPU-recovery mode"
    end if
    
    ! Initialize dynamic shader cache (includes thread-safe cache)
    if (global_state%use_dynamic_shaders) then
      call init_dynamic_cache(global_state%shader_cache, &
                             cache_dir=actual_cache_dir, &
                             max_programs=200, &
                             enable_learning=.true.)
    else
      ! Fall back to basic thread-safe cache without dynamic generation
      call init_program_cache_ts(global_state%shader_cache%program_cache, &
                                max_programs=100, &
                                cache_directory=actual_cache_dir)
    end if
    
    ! Initialize async executor
    if (global_state%use_async) then
      ! Note: gpu_async_executor_init requires program and weight buffer
      ! We'll initialize it lazily when needed
      ! call gpu_async_executor_init(global_state%async_exec, program_id, weight_buffer)
    end if
    
    ! Initialize auto device selector
    if (global_state%use_auto_select) then
      call init_auto_selector()
    end if
    
    global_state%initialized = .true.
    
    print *, "✅ Conv2D V3 initialized with:"
    print '(A,L1)', "   Dynamic shaders: ", global_state%use_dynamic_shaders
    print '(A,L1)', "   Async execution: ", global_state%use_async
    print '(A,L1)', "   Auto device selection: ", global_state%use_auto_select
    print '(A,A)', "   Cache directory: ", trim(actual_cache_dir)
    print *, ""
    
  end subroutine sporkle_conv2d_v3_init
  
  ! Main execution function
  subroutine sporkle_conv2d_v3_execute(input, weights, bias, output, &
                                      stride_h, stride_w, pad_h, pad_w, &
                                      activation, group_count)
    real(sp), intent(in), target, contiguous :: input(:,:,:,:)    ! [N,H,W,C]
    real(sp), intent(in), target, contiguous :: weights(:,:,:,:)  ! [K,KH,KW,C]
    real(sp), intent(in), optional :: bias(:)  ! [K]
    real(sp), intent(out), target, contiguous :: output(:,:,:,:)  ! [N,OH,OW,K]
    integer, intent(in), optional :: stride_h, stride_w
    integer, intent(in), optional :: pad_h, pad_w
    character(len=*), intent(in), optional :: activation
    integer, intent(in), optional :: group_count
    
    ! Local variables
    integer :: N, H, W, C, K, KH, KW, OH, OW
    integer :: ii, jj, kk, ll  ! Loop indices for bias and activation
    integer :: actual_stride_h, actual_stride_w
    integer :: actual_pad_h, actual_pad_w
    logical :: use_gpu
    real(dp) :: start_time, end_time, elapsed_ms
    real(dp) :: gflops
    integer(i64) :: flops
    real(dp) :: cpu_time_ms
    real(sp) :: kronos_time_ms
    type(c_ptr) :: input_ptr, weights_ptr, output_ptr
    real(sp), pointer :: input_flat(:), weights_flat(:), output_flat(:)
    
    if (.not. global_state%initialized) then
      print *, "❌ Conv2D V3 not initialized! Call sporkle_conv2d_v3_init first."
      return
    end if
    
    ! Get dimensions
    N = size(input, 1)
    H = size(input, 2)
    W = size(input, 3)
    C = size(input, 4)
    K = size(weights, 1)
    KH = size(weights, 2)
    KW = size(weights, 3)
    OH = size(output, 2)
    OW = size(output, 3)
    
    ! Set defaults
    actual_stride_h = 1; if (present(stride_h)) actual_stride_h = stride_h
    actual_stride_w = 1; if (present(stride_w)) actual_stride_w = stride_w
    actual_pad_h = 0; if (present(pad_h)) actual_pad_h = pad_h
    actual_pad_w = 0; if (present(pad_w)) actual_pad_w = pad_w
    if (present(group_count) .and. group_count /= 1) then
      print *, "❌ sporkle_conv2d_v3_execute does not support grouped convolution in recovery mode."
      print '(A,I0)', "   Received group_count=", group_count
      error stop "sporkle_conv2d_v3_execute: grouped convolution unsupported in recovery mode"
    end if
    
    if (actual_stride_w /= actual_stride_h) then
      print *, "❌ sporkle_conv2d_v3_execute: stride_w must equal stride_h in recovery path."
      print '(A,I0,A,I0)', "   Got stride_h=", actual_stride_h, ", stride_w=", actual_stride_w
      error stop "sporkle_conv2d_v3_execute: asymmetric stride unsupported"
    end if
    if (actual_pad_w /= actual_pad_h) then
      print *, "❌ sporkle_conv2d_v3_execute: pad_w must equal pad_h in recovery path."
      print '(A,I0,A,I0)', "   Got pad_h=", actual_pad_h, ", pad_w=", actual_pad_w
      error stop "sporkle_conv2d_v3_execute: asymmetric padding unsupported"
    end if
    if (KH /= KW) then
      print *, "❌ sporkle_conv2d_v3_execute requires square kernels in this CPU fallback."
      print '(A,I0,A,I0)', "   Got KH=", KH, ", KW=", KW
      error stop "sporkle_conv2d_v3_execute: non-square kernels unsupported in recovery"
    end if

    ! Calculate FLOPs
    flops = int(N, int64) * int(OH, int64) * int(OW, int64) * int(K, int64) * &
            int(KH, int64) * int(KW, int64) * int(C, int64) * 2_int64
    
    ! Auto policy: if enabled, this path currently requires active Kronos/GPU backend.
    use_gpu = global_state%use_auto_select
    
    if (use_gpu) then
      input_ptr = c_loc(input)
      weights_ptr = c_loc(weights)
      output_ptr = c_loc(output)
      call c_f_pointer(input_ptr, input_flat, [size(input)])
      call c_f_pointer(weights_ptr, weights_flat, [size(weights)])
      call c_f_pointer(output_ptr, output_flat, [size(output)])

      print *, "🚀 Conv2D V3 dispatching through unified Kronos path."
      kronos_time_ms = sporkle_conv2d_unified(input_flat, weights_flat, output_flat, &
                                              N, C, H, W, K, KH, actual_stride_h, actual_pad_h, &
                                              device_type="kronos")
      if (kronos_time_ms <= 0.0_sp) then
        error stop "sporkle_conv2d_v3: unified Kronos path returned non-positive timing"
      end if
      elapsed_ms = real(kronos_time_ms, dp)

      !$omp atomic
      global_state%gpu_executions = global_state%gpu_executions + 1

    else
      call cpu_time(start_time)

      ! CPU recovery path
      print *, "🖥️  Conv2D V3 CPU path active (recovery mode)"
      input_ptr = c_loc(input)
      weights_ptr = c_loc(weights)
      output_ptr = c_loc(output)
      call c_f_pointer(input_ptr, input_flat, [size(input)])
      call c_f_pointer(weights_ptr, weights_flat, [size(weights)])
      call c_f_pointer(output_ptr, output_flat, [size(output)])

      cpu_time_ms = conv2d_adaptive(input_flat, weights_flat, output_flat, &
                                    N, C, H, W, K, KH, actual_stride_h, actual_pad_h, OH, OW)

      if (present(bias)) then
        do concurrent (ii = 1:N, jj = 1:OH, kk = 1:OW, ll = 1:K)
          output(ii, jj, kk, ll) = output(ii, jj, kk, ll) + bias(ll)
        end do
      end if
      if (present(activation)) then
        if (trim(activation) == "relu" .or. trim(activation) == "ReLU") then
          where (output < 0.0_sp) output = 0.0_sp
        end if
      end if

      cpu_time_ms = real(cpu_time_ms, real(dp))

      !$omp atomic
      global_state%cpu_executions = global_state%cpu_executions + 1

      call cpu_time(end_time)
      elapsed_ms = (end_time - start_time) * 1000.0
    end if

    if (elapsed_ms > 0.0_dp) then
      gflops = real(flops, dp) / (elapsed_ms * 1.0e6_dp)
    else
      gflops = 0.0_dp
    end if
    
    ! Update statistics
    !$omp atomic
    global_state%total_executions = global_state%total_executions + 1
    
    !$omp atomic
    global_state%total_time_ms = global_state%total_time_ms + elapsed_ms
    
    !$omp atomic
    global_state%total_gflops = global_state%total_gflops + gflops
    
    ! Update performance feedback
    ! Update device selector
    if (global_state%use_auto_select) then
      ! Auto selector doesn't expose update_performance
      ! Performance tracking is handled internally
    end if
    
  end subroutine sporkle_conv2d_v3_execute
  
  ! Get statistics
  subroutine sporkle_conv2d_v3_stats()
    real(dp) :: avg_time_ms, avg_gflops
    real(dp) :: gpu_percentage, cpu_percentage
    
    if (.not. global_state%initialized) then
      print *, "Conv2D V3 not initialized"
      return
    end if
    
    print *, ""
    print *, "📊 Sporkle Conv2D V3 Statistics"
    print *, "==============================="
    
    if (global_state%total_executions > 0) then
      avg_time_ms = global_state%total_time_ms / real(global_state%total_executions)
      avg_gflops = global_state%total_gflops / real(global_state%total_executions)
      gpu_percentage = real(global_state%gpu_executions) / real(global_state%total_executions) * 100.0
      cpu_percentage = real(global_state%cpu_executions) / real(global_state%total_executions) * 100.0
      
      print '(A,I0)', "Total executions: ", global_state%total_executions
      print '(A,I0,A,F5.1,A)', "GPU executions: ", global_state%gpu_executions, &
                               " (", gpu_percentage, "%)"
      print '(A,I0,A,F5.1,A)', "CPU executions: ", global_state%cpu_executions, &
                               " (", cpu_percentage, "%)"
      print '(A,F8.2,A)', "Average time: ", avg_time_ms, " ms"
      print '(A,F8.2,A)', "Average performance: ", avg_gflops, " GFLOPS"
      print '(A,F10.2,A)', "Total compute: ", global_state%total_gflops, " GFLOPS"
    else
      print *, "No executions yet"
    end if
    
    ! Show cache statistics
    if (global_state%use_dynamic_shaders) then
      call print_cache_stats_ts(global_state%shader_cache%program_cache)
    end if
    
    print *, ""
    
  end subroutine sporkle_conv2d_v3_stats
  
  ! Cleanup
  subroutine sporkle_conv2d_v3_cleanup()
    
    if (.not. global_state%initialized) return
    
    print *, "🧹 Cleaning up Conv2D V3..."
    
    ! Show final stats
    call sporkle_conv2d_v3_stats()
    
    ! Cleanup subsystems
    if (global_state%use_dynamic_shaders) then
      call cleanup_dynamic_cache(global_state%shader_cache)
    else
      call cleanup_program_cache_ts(global_state%shader_cache%program_cache)
    end if
    
    if (global_state%use_async) then
      call gpu_async_executor_cleanup(global_state%async_exec)
    end if
    
    call gpu_cleanup()
    
    global_state%initialized = .false.
    
  end subroutine sporkle_conv2d_v3_cleanup
  
end module sporkle_conv2d_v3
