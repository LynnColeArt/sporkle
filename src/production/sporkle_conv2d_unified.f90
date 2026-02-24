module sporkle_conv2d_unified
  ! Unified Conv2D implementation - selects CPU or Kronos runtime intent.
  ! Production intent: unsupported or unimplemented GPU/Kronos launch requests fail hard.

  use kinds
  use iso_c_binding, only: c_ptr, c_sizeof, c_loc, c_float, c_null_ptr, c_associated
  use sporkle_conv2d, only: conv2d_cpu
  use gpu_vulkan_interface, only: gpu_allocate_buffer_vulkan, gpu_copy_from_buffer_vulkan, gpu_copy_to_buffer_vulkan, &
                                   gpu_init_vulkan, &
                                   gpu_free_buffer_vulkan, vk_create_conv2d_shader, vk_dispatch_conv2d
  implicit none
  private
  
  public :: kronos_conv2d_unified

  logical, save :: vulkan_conv2d_initialized = .false.
  logical, save :: vulkan_conv2d_unavailable = .false.
  type(c_ptr), save :: vulkan_conv2d_shader = c_null_ptr
  
contains

  function kronos_conv2d_unified(input, weights, output, &
                                 N, C, H, W, K, kernel_size, stride, pad, &
                                 device_type) result(time_ms)
    real(sp), intent(in), target :: input(:), weights(:)
    real(sp), intent(out), target :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad
    character(len=*), intent(in), optional :: device_type
    real(sp) :: time_ms
    
    character(len=16) :: device_choice
    integer :: H_out, W_out
    integer(i64) :: workload_flops
    
    ! Calculate output dimensions
    H_out = (H + 2*pad - kernel_size) / stride + 1
    W_out = (W + 2*pad - kernel_size) / stride + 1
    workload_flops = int(N, int64) * int(C, int64) * int(H_out, int64) * int(W_out, int64) * &
      int(K, int64) * int(kernel_size, int64) * int(kernel_size, int64) * 2_int64
    
    ! Determine device
    if (present(device_type)) then
      device_choice = device_type
    else
      device_choice = "auto"
    end if
    
    select case(trim(device_choice))
    case("cpu")
      time_ms = execute_cpu_conv2d()
    case("gpu", "kronos", "amd", "nvidia", "apple", "apple_neural", "neural", "neural_engine")
      time_ms = execute_gpu_conv2d()
    case("auto")
      if (workload_flops > 5000000_int64) then
        time_ms = execute_gpu_conv2d()
      else
        time_ms = execute_cpu_conv2d()
      end if
    case default
      print *, "❌ Unknown device type: ", trim(device_choice)
      print *, "   Supported: cpu, kronos/gpu, amd, nvidia, apple, auto"
      print *, "   Unknown backends are treated as hard-fail to prevent silent fallback."
      error stop "sporkle_conv2d_unified received unsupported device type."
    end select
    
  contains
  
    function execute_cpu_conv2d() result(time_ms)
      real(sp) :: time_ms
      real(dp) :: start_t, end_t

      call cpu_time(start_t)
      
      print *, "🔧 Executing Conv2D on CPU..."
      call conv2d_cpu(input, weights, output, &
                      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
      
      call cpu_time(end_t)
      time_ms = real((end_t - start_t) * 1000.0_dp, sp)

      if (time_ms > 0.0_sp) then
        print '(A,F8.2,A)', "✅ CPU Conv2D completed in ", time_ms, " ms"
      end if
      
    end function execute_cpu_conv2d

    function execute_gpu_conv2d() result(time_ms)
      real(sp) :: time_ms
      integer(i64) :: input_bytes
      integer(i64) :: weights_bytes
      integer(i64) :: output_bytes
      type(c_ptr) :: input_buffer
      type(c_ptr) :: weights_buffer
      type(c_ptr) :: output_buffer
      real(c_float) :: dispatch_ms
      logical :: copy_ok

      if (vulkan_conv2d_unavailable) then
        print *, "❌ Kronos GPU path disabled by prior Vulkan staging failure."
        error stop "sporkle_conv2d_unified: GPU dispatch backend unavailable"
      end if

      call init_kronos_vulkan_conv2d_backend()

      input_bytes = int(size(input), i64) * int(c_sizeof(input(1)), i64)
      weights_bytes = int(size(weights), i64) * int(c_sizeof(weights(1)), i64)
      output_bytes = int(size(output), i64) * int(c_sizeof(output(1)), i64)

      if (input_bytes <= 0 .or. weights_bytes <= 0 .or. output_bytes <= 0) then
        print *, "❌ Invalid tensor size for Vulkan staging buffers."
        print '(A,I0,A,I0)', "   Input bytes: ", input_bytes, ", Weights bytes: ", weights_bytes
        print '(A,I0,A,I0)', "   Output bytes: ", output_bytes
        error stop "sporkle_conv2d_unified: invalid GPU staging byte size"
      end if

      input_buffer = gpu_allocate_buffer_vulkan(input_bytes, .false.)
      weights_buffer = gpu_allocate_buffer_vulkan(weights_bytes, .false.)
      output_buffer = gpu_allocate_buffer_vulkan(output_bytes, .false.)
      if (.not. c_associated(input_buffer) .or. .not. c_associated(weights_buffer) .or. .not. c_associated(output_buffer)) then
        print *, "❌ Vulkan staging allocation failed."
        print *, "   input_buffer: ", c_associated(input_buffer)
        print *, "   weight_buffer: ", c_associated(weights_buffer)
        print *, "   output_buffer: ", c_associated(output_buffer)
        call release_staging_buffers(input_buffer, weights_buffer, output_buffer)
        call mark_vulkan_conv2d_unavailable("staging-allocation-failed")
        error stop "sporkle_conv2d_unified: GPU staging allocation failed"
      end if

      copy_ok = gpu_copy_to_buffer_vulkan(input_buffer, c_loc(input), input_bytes)
      if (.not. copy_ok) then
        print *, "❌ Failed to copy input staging buffer from host memory."
        call release_staging_buffers(input_buffer, weights_buffer, output_buffer)
        error stop "sporkle_conv2d_unified: GPU input staging copy failed"
      end if

      copy_ok = gpu_copy_to_buffer_vulkan(weights_buffer, c_loc(weights), weights_bytes)
      if (.not. copy_ok) then
        print *, "❌ Failed to copy weight staging buffer from host memory."
        call release_staging_buffers(input_buffer, weights_buffer, output_buffer)
        error stop "sporkle_conv2d_unified: GPU weights staging copy failed"
      end if

      dispatch_ms = vk_dispatch_conv2d(vulkan_conv2d_shader, input_buffer, weights_buffer, output_buffer, &
                                      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)

      if (dispatch_ms <= 0.0) then
        print *, "❌ Vulkan conv2d dispatch failed or returned non-positive runtime."
        print '(A,F0.4)', "   Dispatch return:", dispatch_ms
        call release_staging_buffers(input_buffer, weights_buffer, output_buffer)
        error stop "sporkle_conv2d_unified: GPU dispatch returned failure code"
      end if

      copy_ok = gpu_copy_from_buffer_vulkan(output_buffer, c_loc(output), output_bytes)
      if (.not. copy_ok) then
        print *, "❌ Failed to copy output staging buffer back to host memory."
        call release_staging_buffers(input_buffer, weights_buffer, output_buffer)
        error stop "sporkle_conv2d_unified: GPU output staging copy failed"
      end if

      time_ms = real(dispatch_ms, sp)

      call release_staging_buffers(input_buffer, weights_buffer, output_buffer)

      print '(A,F8.3,A)', "✅ Vulkan conv2d dispatch completed in ", time_ms, " ms"

      if (time_ms <= 0.0_sp) then
        error stop "sporkle_conv2d_unified: GPU dispatch returned non-positive execution time"
      end if

    end function execute_gpu_conv2d

    subroutine init_kronos_vulkan_conv2d_backend()
      if (vulkan_conv2d_initialized) return
      if (.not. gpu_init_vulkan()) then
        call mark_vulkan_conv2d_unavailable("vk-init-failed")
        error stop "sporkle_conv2d_unified: GPU backend init failed"
      end if

      if (c_associated(vulkan_conv2d_shader)) return
      vulkan_conv2d_shader = vk_create_conv2d_shader()
      if (.not. c_associated(vulkan_conv2d_shader)) then
        call mark_vulkan_conv2d_unavailable("conv2d-shader-failed")
        error stop "sporkle_conv2d_unified: Vulkan conv2d shader creation failed"
      end if

      vulkan_conv2d_initialized = .true.
      print *, "✅ Vulkan conv2d runtime backend is active."
    end subroutine init_kronos_vulkan_conv2d_backend

    subroutine release_staging_buffers(input_buffer, weights_buffer, output_buffer)
      type(c_ptr), intent(inout) :: input_buffer
      type(c_ptr), intent(inout) :: weights_buffer
      type(c_ptr), intent(inout) :: output_buffer
      if (c_associated(input_buffer)) then
        call gpu_free_buffer_vulkan(input_buffer)
        input_buffer = c_null_ptr
      end if
      if (c_associated(weights_buffer)) then
        call gpu_free_buffer_vulkan(weights_buffer)
        weights_buffer = c_null_ptr
      end if
      if (c_associated(output_buffer)) then
        call gpu_free_buffer_vulkan(output_buffer)
        output_buffer = c_null_ptr
      end if
    end subroutine release_staging_buffers

    subroutine mark_vulkan_conv2d_unavailable(reason)
      character(len=*), intent(in), optional :: reason
      vulkan_conv2d_unavailable = .true.
      if (present(reason)) then
        print '(A,A)', "⚠️  Marking Vulkan conv2d backend unavailable: ", trim(reason)
      end if
    end subroutine mark_vulkan_conv2d_unavailable
    
  end function kronos_conv2d_unified

end module sporkle_conv2d_unified
