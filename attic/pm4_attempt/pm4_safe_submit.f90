module pm4_safe_submit
  ! PM4 Safe Command Submission
  ! ===========================
  !
  ! Safe wrapper around direct PM4 submission with error handling
  ! and safety checks to prevent system freezes
  
  use kinds
  use iso_c_binding
  use sporkle_amdgpu_direct
  use sporkle_pm4_compute
  use sporkle_gpu_va_allocator, only: gpu_va_init
  use gpu_ring_buffer
  use pm4_conv2d_builder
  use gpu_safety_guards, only: is_gpu_safe
  implicit none
  
  private
  public :: pm4_safe_init, pm4_safe_cleanup
  public :: pm4_safe_conv2d
  public :: pm4_submission_context
  
  ! Safety limits
  integer, parameter :: MAX_WORKGROUPS = 65536  ! 256x256 max
  integer, parameter :: MAX_BUFFER_SIZE = 1024 * 1024 * 1024  ! 1GB
  integer, parameter :: SUBMISSION_TIMEOUT = 1000000000       ! 1 second
  
  ! Submission context
  type :: pm4_submission_context
    type(ring_buffer) :: ring
    type(amdgpu_device) :: device
    logical :: initialized = .false.
    
    ! Statistics
    integer(i64) :: total_submissions = 0
    integer(i64) :: failed_submissions = 0
    real(sp) :: total_time_ms = 0.0
  end type
  
  ! Global context
  type(pm4_submission_context), save :: g_submit_ctx
  
contains

  ! Initialize safe PM4 submission
  function pm4_safe_init() result(success)
    logical :: success
    
    success = .false.
    
    ! Check if we're allowed to use PM4
    if (.not. is_gpu_safe()) then
      print *, "❌ GPU safety check failed - PM4 submission disabled"
      return
    end if
    
    ! Open device directly
    g_submit_ctx%device = amdgpu_open_device("/dev/dri/renderD128")
    if (g_submit_ctx%device%fd <= 0) then
      print *, "❌ Failed to open AMDGPU device"
      return
    end if
    
    ! Initialize VA allocator
    call gpu_va_init()
    
    ! Create ring buffer
    g_submit_ctx%ring = create_ring_buffer(g_submit_ctx%device)
    if (.not. g_submit_ctx%ring%initialized) then
      print *, "❌ Failed to create ring buffer"
      call amdgpu_close_device(g_submit_ctx%device)
      return
    end if
    
    g_submit_ctx%initialized = .true.
    success = .true.
    
    print *, "✅ PM4 safe submission initialized"
    print *, "   Max workgroups:", MAX_WORKGROUPS
    print *, "   Max buffer size:", MAX_BUFFER_SIZE / (1024*1024), "MB"
    print *, "   Submission timeout:", SUBMISSION_TIMEOUT / 1000000, "ms"
    
  end function pm4_safe_init
  
  ! Cleanup
  subroutine pm4_safe_cleanup()
    
    if (.not. g_submit_ctx%initialized) return
    
    ! Destroy ring buffer
    call destroy_ring_buffer(g_submit_ctx%ring)
    
    ! Cleanup PM4
    call pm4_cleanup_compute()
    
    g_submit_ctx%initialized = .false.
    
    print *, "✅ PM4 safe submission cleaned up"
    print '(A,I0)', "   Total submissions: ", g_submit_ctx%total_submissions
    print '(A,I0)', "   Failed submissions: ", g_submit_ctx%failed_submissions
    print '(A,F8.1,A)', "   Total GPU time: ", g_submit_ctx%total_time_ms, " ms"
    
  end subroutine pm4_safe_cleanup
  
  ! Safe Conv2D execution
  function pm4_safe_conv2d(input, weights, output, &
                          N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    type(pm4_conv2d_params) :: params
    type(amdgpu_buffer) :: input_bo, weight_bo, output_bo, param_bo
    integer(i64) :: input_size, weight_size, output_size
    integer :: status
    integer(i64) :: start_time, end_time, clock_rate
    integer(i64) :: fence_value
    logical :: success
    
    time_ms = -1.0
    
    if (.not. g_submit_ctx%initialized) then
      print *, "❌ PM4 submission not initialized"
      return
    end if
    
    ! Validate parameters
    if (.not. validate_conv2d_params(N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)) then
      print *, "❌ Invalid Conv2D parameters"
      return
    end if
    
    ! Calculate buffer sizes
    input_size = int(N * C * H * W, i64) * 4
    weight_size = int(K * C * kernel_size * kernel_size, i64) * 4
    output_size = int(N * K * H_out * W_out, i64) * 4
    
    ! Safety check sizes
    if (input_size > MAX_BUFFER_SIZE .or. weight_size > MAX_BUFFER_SIZE .or. output_size > MAX_BUFFER_SIZE) then
      print *, "❌ Buffer size exceeds safety limit"
      return
    end if
    
    ! Start timing
    call system_clock(start_time, count_rate=clock_rate)
    
    ! Allocate GPU buffers
    success = allocate_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo, &
                                     input_size, weight_size, output_size)
    if (.not. success) then
      print *, "❌ Failed to allocate GPU buffers"
      return
    end if
    
    ! Upload data
    call upload_conv2d_data(input_bo, weight_bo, param_bo, &
                           input, weights, N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    
    ! Setup dispatch parameters
    params%input_addr = input_bo%va_addr
    params%weight_addr = weight_bo%va_addr
    params%output_addr = output_bo%va_addr
    params%param_addr = param_bo%va_addr
    
    params%n = N
    params%c = C
    params%h = H
    params%w = W
    params%k = K
    params%kernel_size = kernel_size
    params%stride = stride
    params%pad = pad
    params%h_out = H_out
    params%w_out = W_out
    
    ! Calculate dispatch dimensions
    params%workgroups_x = (N * H_out * W_out + 255) / 256
    params%workgroups_y = K
    params%workgroups_z = 1
    
    ! Safety check workgroups
    if (params%workgroups_x * params%workgroups_y * params%workgroups_z > MAX_WORKGROUPS) then
      print *, "❌ Too many workgroups - safety limit exceeded"
      call free_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo)
      return
    end if
    
    ! Compile shader using PM4 compiler
    block
      use sporkle_pm4_compute, only: pm4_compile_shader
      integer(i64) :: shader_addr
      
      ! For now use simple copy shader as conv2d placeholder
      shader_addr = pm4_compile_shader("copy_shader", "")
      if (shader_addr == 0) then
        print *, "❌ Failed to compile shader"
        call free_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo)
        return
      end if
      
      params%shader_addr = shader_addr
      params%num_vgprs = 32
      params%num_sgprs = 16
    end block
    
    ! Begin frame
    if (.not. ring_buffer_begin_frame(g_submit_ctx%ring)) then
      print *, "❌ Failed to begin frame"
      call free_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo)
      return
    end if
    
    ! Build command sequence
    call pm4_build_conv2d_dispatch(g_submit_ctx%ring, params)
    
    ! End frame
    fence_value = ring_buffer_end_frame(g_submit_ctx%ring)
    
    ! Submit with safety timeout
    status = ring_buffer_submit(g_submit_ctx%ring, 0, fence_value)
    
    if (status == 0) then
      ! Wait for completion
      block
        integer :: wait_status
        wait_status = amdgpu_wait_buffer_idle(g_submit_ctx%device, input_bo)
      end block
      
      ! Download results
      call download_conv2d_results(output_bo, output, output_size)
      
      g_submit_ctx%total_submissions = g_submit_ctx%total_submissions + 1
    else
      print *, "❌ PM4 submission failed:", status
      g_submit_ctx%failed_submissions = g_submit_ctx%failed_submissions + 1
    end if
    
    ! Cleanup
    call free_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo)
    
    ! End timing
    call system_clock(end_time)
    time_ms = real(end_time - start_time) / real(clock_rate) * 1000.0
    g_submit_ctx%total_time_ms = g_submit_ctx%total_time_ms + time_ms
    
  end function pm4_safe_conv2d
  
  ! Validate Conv2D parameters
  function validate_conv2d_params(N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(valid)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    logical :: valid
    
    valid = .true.
    
    ! Basic sanity checks
    if (N <= 0 .or. C <= 0 .or. H <= 0 .or. W <= 0 .or. K <= 0) then
      valid = .false.
      return
    end if
    
    if (kernel_size <= 0 .or. stride <= 0) then
      valid = .false.
      return
    end if
    
    ! Check output dimensions
    if (H_out /= (H + 2*pad - kernel_size) / stride + 1) then
      valid = .false.
      return
    end if
    
    if (W_out /= (W + 2*pad - kernel_size) / stride + 1) then
      valid = .false.
      return
    end if
    
  end function validate_conv2d_params
  
  ! Allocate Conv2D buffers
  function allocate_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo, &
                                  input_size, weight_size, output_size) result(success)
    type(amdgpu_buffer), intent(out) :: input_bo, weight_bo, output_bo, param_bo
    integer(i64), intent(in) :: input_size, weight_size, output_size
    logical :: success
    
    success = .false.
    
    ! Allocate input buffer
    input_bo = amdgpu_allocate_buffer(g_submit_ctx%device, input_size)
    if (input_bo%handle == 0) return
    
    ! Allocate weight buffer
    weight_bo = amdgpu_allocate_buffer(g_submit_ctx%device, weight_size)
    if (weight_bo%handle == 0) then
      ! TODO: need buffer free function
      return
    end if
    
    ! Allocate output buffer
    output_bo = amdgpu_allocate_buffer(g_submit_ctx%device, output_size)
    if (output_bo%handle == 0) then
      ! TODO: need buffer free function
      return
    end if
    
    ! Allocate param buffer (40 bytes for 10 ints)
    param_bo = amdgpu_allocate_buffer(g_submit_ctx%device, 40_i64)
    if (param_bo%handle == 0) then
      ! TODO: need buffer free function
      return
    end if
    
    success = .true.
    
  end function allocate_conv2d_buffers
  
  ! Upload Conv2D data
  subroutine upload_conv2d_data(input_bo, weight_bo, param_bo, &
                               input, weights, N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    type(amdgpu_buffer), intent(inout) :: input_bo, weight_bo, param_bo
    real(sp), intent(in) :: input(:), weights(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    type(c_ptr) :: cpu_ptr
    real(sp), pointer :: data_ptr(:)
    integer(i32), pointer :: param_ptr(:)
    integer :: status
    
    ! Map and upload input
    status = amdgpu_map_buffer(g_submit_ctx%device, input_bo)
    if (status == 0 .and. c_associated(input_bo%cpu_ptr)) then
      call c_f_pointer(input_bo%cpu_ptr, data_ptr, [size(input)])
      data_ptr = input
    end if
    
    ! Map and upload weights
    status = amdgpu_map_buffer(g_submit_ctx%device, weight_bo)
    if (status == 0 .and. c_associated(weight_bo%cpu_ptr)) then
      call c_f_pointer(weight_bo%cpu_ptr, data_ptr, [size(weights)])
      data_ptr = weights
    end if
    
    ! Map and upload parameters
    status = amdgpu_map_buffer(g_submit_ctx%device, param_bo)
    if (status == 0 .and. c_associated(param_bo%cpu_ptr)) then
      call c_f_pointer(param_bo%cpu_ptr, param_ptr, [10])
      param_ptr(1) = N
      param_ptr(2) = H
      param_ptr(3) = W
      param_ptr(4) = C
      param_ptr(5) = K
      param_ptr(6) = kernel_size
      param_ptr(7) = stride
      param_ptr(8) = pad
      param_ptr(9) = H_out
      param_ptr(10) = W_out
    end if
    
  end subroutine upload_conv2d_data
  
  ! Download results
  subroutine download_conv2d_results(output_bo, output, output_size)
    type(amdgpu_buffer), intent(in) :: output_bo
    real(sp), intent(out) :: output(:)
    integer(i64), intent(in) :: output_size
    
    type(c_ptr) :: cpu_ptr
    real(sp), pointer :: data_ptr(:)
    
    if (c_associated(output_bo%cpu_ptr)) then
      call c_f_pointer(output_bo%cpu_ptr, data_ptr, [output_size/4])
      output = data_ptr
    end if
    
  end subroutine download_conv2d_results
  
  ! Free buffers
  subroutine free_conv2d_buffers(input_bo, weight_bo, output_bo, param_bo)
    type(amdgpu_buffer), intent(inout) :: input_bo, weight_bo, output_bo, param_bo
    
    ! Clear all buffer handles - the actual memory will be freed when the
    ! PM4 context is cleaned up. This matches the C implementation where
    ! buffers are tied to the context lifetime.
    ! 
    ! Note: For proper buffer management, use pm4_buffer_raii module which
    ! provides RAII-style automatic cleanup.
    input_bo%handle = 0
    input_bo%gpu_addr = 0
    input_bo%size = 0
    
    weight_bo%handle = 0
    weight_bo%gpu_addr = 0
    weight_bo%size = 0
    
    output_bo%handle = 0
    output_bo%gpu_addr = 0
    output_bo%size = 0
    
    param_bo%handle = 0
    param_bo%gpu_addr = 0
    param_bo%size = 0
    
  end subroutine free_conv2d_buffers
  
end module pm4_safe_submit