module sporkle_kronos_conv2d
  ! Kronos backend for Conv2D operations
  ! ====================================
  ! Integrates Kronos zero-overhead Vulkan compute
  
  use kinds
  use iso_c_binding
  ! No need for sporkle_types - kronos types come from sporkle_kronos_ffi
  use sporkle_error_handling, only: sporkle_error => sporkle_warning, &
                                     SPORKLE_SUCCESS, SPORKLE_FAILURE => SPORKLE_ERR_INVALID
  use sporkle_kronos_ffi
  use spirv_shaders
  implicit none
  private
  
  public :: kronos_conv2d_execute
  
  ! Cached pipeline for conv2d
  type(kronos_pipeline), save :: conv2d_pipeline
  logical, save :: pipeline_initialized = .false.
  
  ! Push constant structure matching GLSL
  type, bind(C) :: conv2d_params
    integer(c_int32_t) :: C          ! Input channels
    integer(c_int32_t) :: H          ! Input height
    integer(c_int32_t) :: W          ! Input width
    integer(c_int32_t) :: K          ! Output channels
    integer(c_int32_t) :: kernel_size
    integer(c_int32_t) :: stride
    integer(c_int32_t) :: pad
    integer(c_int32_t) :: H_out      ! Output height
    integer(c_int32_t) :: W_out      ! Output width
  end type conv2d_params
  
contains
  
  function kronos_conv2d_execute(ctx, input_buf, weight_buf, output_buf, &
                                N, C, H, W, K, kernel_size, stride, pad) result(status)
    type(kronos_context), intent(in) :: ctx
    type(kronos_buffer), intent(in) :: input_buf, weight_buf, output_buf
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad
    integer :: status
    
    type(conv2d_params) :: params
    type(kronos_buffer) :: buffers(3)
    type(kronos_fence) :: fence
    integer :: H_out, W_out
    integer(c_size_t) :: global_size(3)
    type(c_ptr) :: spirv_ptr
    integer(c_size_t) :: spirv_size
    integer(c_int8_t), pointer :: spirv_data(:)
    
    status = SPORKLE_FAILURE
    
    ! Calculate output dimensions
    H_out = (H + 2*pad - kernel_size) / stride + 1
    W_out = (W + 2*pad - kernel_size) / stride + 1
    
    ! Initialize pipeline if needed
    if (.not. pipeline_initialized) then
      spirv_ptr = get_conv2d_spirv(spirv_size)
      call c_f_pointer(spirv_ptr, spirv_data, [spirv_size])
      conv2d_pipeline = kronos_create_pipeline(ctx, spirv_data, spirv_size)
      
      if (.not. c_associated(conv2d_pipeline%handle)) then
        call sporkle_error("Failed to create conv2d pipeline")
        return
      end if
      pipeline_initialized = .true.
    end if
    
    ! Set up parameters
    params%C = C
    params%H = H
    params%W = W
    params%K = K
    params%kernel_size = kernel_size
    params%stride = stride
    params%pad = pad
    params%H_out = H_out
    params%W_out = W_out
    
    ! Set up buffers
    buffers(1) = input_buf
    buffers(2) = weight_buf
    buffers(3) = output_buf
    
    ! Calculate dispatch size
    ! X: Total output pixels (will be divided among threads)
    ! Y: Output channels
    ! Z: Batch dimension
    global_size(1) = (H_out * W_out + 255) / 256 * 256  ! Round up to multiple of 256
    global_size(2) = K
    global_size(3) = N
    
    ! TODO: Set push constants before dispatch
    ! For now, we'll skip this since our mock doesn't support it
    
    ! Dispatch kernel
    fence = kronos_dispatch(ctx, conv2d_pipeline, buffers, global_size)
    
    if (.not. c_associated(fence%handle)) then
      call sporkle_error("Failed to dispatch conv2d kernel")
      return
    end if
    
    ! Wait for completion
    status = kronos_wait_fence(ctx, fence, 5000)  ! 5 second timeout
    
    if (status == KRONOS_SUCCESS) then
      status = SPORKLE_SUCCESS
    else
      call sporkle_error("Conv2d kernel timeout or error")
      status = SPORKLE_FAILURE
    end if
    
    ! Fence is automatically destroyed when it goes out of scope
    
  end function kronos_conv2d_execute
  
end module sporkle_kronos_conv2d