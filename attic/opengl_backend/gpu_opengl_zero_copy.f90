! GPU OpenGL Zero-Copy Conv2D Implementation
! ==========================================
!
! Zero-copy convolution using unified buffers
! Eliminates all memory transfers between CPU and GPU

module gpu_opengl_zero_copy
  use kinds
  use iso_c_binding
  use gpu_unified_buffers
  use gpu_fence_primitives
  implicit none
  
  private
  public :: gpu_init_zero_copy, gpu_cleanup_zero_copy
  public :: gpu_execute_conv2d_zero_copy
  public :: gpu_conv2d_state
  
  ! OpenGL constants
  integer(c_int), parameter :: GL_SHADER_STORAGE_BUFFER = int(z'90D2', c_int)
  integer(c_int), parameter :: GL_SHADER_STORAGE_BARRIER_BIT = int(z'2000', c_int)
  
  ! Parameter structure for shader
  type, bind(C) :: conv2d_params
    integer(c_int) :: N, H, W, C, K
    integer(c_int) :: kernel_size, stride, pad
    integer(c_int) :: H_out, W_out
  end type
  
  ! Conv2D state with persistent buffers
  type :: gpu_conv2d_state
    type(unified_buffer) :: input_buffer
    type(unified_buffer) :: weight_buffer
    type(unified_buffer) :: output_buffer
    type(unified_buffer) :: param_buffer
    integer :: compute_program = 0
    logical :: initialized = .false.
    integer :: last_n = 0, last_c = 0, last_h = 0, last_w = 0
    integer :: last_k = 0, last_kernel_size = 0
    integer(i64) :: weight_hash = 0
  end type
  
  ! Global state (can be made instance-based later)
  type(gpu_conv2d_state), save :: global_state
  
  ! OpenGL interfaces
  interface
    function gpu_initialize_opengl() bind(C, name="gpu_initialize_opengl")
      import :: c_int
      integer(c_int) :: gpu_initialize_opengl
    end function
    
    subroutine gpu_cleanup_opengl() bind(C, name="gpu_cleanup_opengl")
    end subroutine
    
    function gpu_compile_conv2d_shader() bind(C, name="gpu_compile_conv2d_shader")
      import :: c_int
      integer(c_int) :: gpu_compile_conv2d_shader
    end function
    
    function gpu_get_compute_program() bind(C, name="gpu_get_compute_program")
      import :: c_int
      integer(c_int) :: gpu_get_compute_program
    end function
    
    subroutine glUseProgram(program) bind(C, name="glUseProgram")
      import :: c_int
      integer(c_int), value :: program
    end subroutine
    
    subroutine glDispatchCompute(x, y, z) bind(C, name="glDispatchCompute")
      import :: c_int
      integer(c_int), value :: x, y, z
    end subroutine
    
    subroutine glMemoryBarrier(barriers) bind(C, name="glMemoryBarrier")
      import :: c_int
      integer(c_int), value :: barriers
    end subroutine
    
    subroutine glUniform1i(location, value) bind(C, name="glUniform1i")
      import :: c_int
      integer(c_int), value :: location, value
    end subroutine
    
    function glGetUniformLocation(program, name) bind(C, name="glGetUniformLocation")
      import :: c_int, c_char
      integer(c_int), value :: program
      character(kind=c_char), intent(in) :: name(*)
      integer(c_int) :: glGetUniformLocation
    end function
  end interface
  
contains

  ! Initialize zero-copy GPU system
  logical function gpu_init_zero_copy()
    gpu_init_zero_copy = .false.
    
    ! Initialize OpenGL
    if (gpu_initialize_opengl() == 0) then
      print *, "Failed to initialize GPU OpenGL context"
      return
    end if
    
    ! Compile shaders
    if (gpu_compile_conv2d_shader() == 0) then
      print *, "Failed to compile GPU shaders"
      call gpu_cleanup_opengl()
      return
    end if
    
    ! Get compute program
    global_state%compute_program = gpu_get_compute_program()
    
    ! Initialize fence pool
    call gpu_fence_pool_init()
    
    global_state%initialized = .true.
    gpu_init_zero_copy = .true.
    
    print *, "✅ GPU Zero-Copy system initialized"
    
  end function gpu_init_zero_copy
  
  ! Cleanup
  subroutine gpu_cleanup_zero_copy()
    if (global_state%initialized) then
      ! Destroy buffers if allocated
      if (buffer_is_valid(global_state%input_buffer)) then
        call destroy_unified_buffer(global_state%input_buffer)
      end if
      if (buffer_is_valid(global_state%weight_buffer)) then
        call destroy_unified_buffer(global_state%weight_buffer)
      end if
      if (buffer_is_valid(global_state%output_buffer)) then
        call destroy_unified_buffer(global_state%output_buffer)
      end if
      if (buffer_is_valid(global_state%param_buffer)) then
        call destroy_unified_buffer(global_state%param_buffer)
      end if
      
      ! Cleanup fence pool
      call gpu_fence_pool_cleanup()
      
      ! Cleanup OpenGL
      call gpu_cleanup_opengl()
      
      global_state%initialized = .false.
    end if
  end subroutine gpu_cleanup_zero_copy
  
  ! Execute Conv2D with zero-copy
  function gpu_execute_conv2d_zero_copy(input, weights, output, &
                                       N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    integer(i64) :: input_size, weight_size, output_size
    integer(i64) :: start_time, end_time, clock_rate
    integer :: workgroups_x, workgroups_y, workgroups_z
    logical :: need_realloc
    integer(i64) :: new_weight_hash
    type(gpu_fence) :: compute_fence
    integer :: wait_status
    
    if (.not. global_state%initialized) then
      print *, "GPU not initialized!"
      time_ms = -1.0
      return
    end if
    
    
    ! Calculate buffer sizes
    input_size = int(N * C * H * W, int64) * 4
    weight_size = int(K * C * kernel_size * kernel_size, int64) * 4
    output_size = int(N * K * H_out * W_out, int64) * 4
    
    ! Check if we need to reallocate buffers
    need_realloc = .false.
    if (N /= global_state%last_n .or. C /= global_state%last_c .or. &
        H /= global_state%last_h .or. W /= global_state%last_w .or. &
        K /= global_state%last_k .or. kernel_size /= global_state%last_kernel_size) then
      need_realloc = .true.
    end if
    
    ! Reallocate if needed
    if (need_realloc .or. .not. buffer_is_valid(global_state%input_buffer)) then
      ! Destroy old buffers
      if (buffer_is_valid(global_state%input_buffer)) then
        call destroy_unified_buffer(global_state%input_buffer)
      end if
      if (buffer_is_valid(global_state%weight_buffer)) then
        call destroy_unified_buffer(global_state%weight_buffer)
      end if
      if (buffer_is_valid(global_state%output_buffer)) then
        call destroy_unified_buffer(global_state%output_buffer)
      end if
      if (buffer_is_valid(global_state%param_buffer)) then
        call destroy_unified_buffer(global_state%param_buffer)
      end if
      
      ! Create new buffers
      global_state%input_buffer = create_unified_buffer(input_size, BUFFER_WRITE_ONLY, MEMORY_COHERENT)
      global_state%weight_buffer = create_unified_buffer(weight_size, BUFFER_WRITE_ONLY, MEMORY_COHERENT)
      global_state%output_buffer = create_unified_buffer(output_size, BUFFER_READ_WRITE, MEMORY_COHERENT)
      global_state%param_buffer = create_unified_buffer(int(10 * 4, i64), BUFFER_WRITE_ONLY, MEMORY_COHERENT)  ! 10 integers
      
      if (.not. buffer_is_valid(global_state%input_buffer) .or. &
          .not. buffer_is_valid(global_state%weight_buffer) .or. &
          .not. buffer_is_valid(global_state%output_buffer) .or. &
          .not. buffer_is_valid(global_state%param_buffer)) then
        print *, "Failed to create unified buffers!"
        print *, "Input buffer valid: ", buffer_is_valid(global_state%input_buffer)
        print *, "Weight buffer valid: ", buffer_is_valid(global_state%weight_buffer)
        print *, "Output buffer valid: ", buffer_is_valid(global_state%output_buffer)
        time_ms = -1.0
        return
      end if
      
      ! Update dimensions
      global_state%last_n = N
      global_state%last_c = C
      global_state%last_h = H
      global_state%last_w = W
      global_state%last_k = K
      global_state%last_kernel_size = kernel_size
    end if
    
    ! Start timing
    call system_clock(start_time, count_rate=clock_rate)
    
    ! Write input data (zero-copy!)
    call write_buffer(global_state%input_buffer, input)
    
    ! Check if weights changed
    new_weight_hash = compute_weight_hash(weights)
    if (new_weight_hash /= global_state%weight_hash) then
      call write_buffer(global_state%weight_buffer, weights)
      global_state%weight_hash = new_weight_hash
    end if
    
    ! Write parameters
    block
      type(conv2d_params) :: params
      params%N = N
      params%H = H
      params%W = W
      params%C = C
      params%K = K
      params%kernel_size = kernel_size
      params%stride = stride
      params%pad = pad
      params%H_out = H_out
      params%W_out = W_out
      
      call write_buffer_params(global_state%param_buffer, params)
    end block
    
    ! Bind buffers to shader
    call bind_buffer_to_shader(global_state%input_buffer, 0)
    call bind_buffer_to_shader(global_state%weight_buffer, 1)
    call bind_buffer_to_shader(global_state%output_buffer, 2)
    call bind_buffer_to_shader(global_state%param_buffer, 3)
    
    ! Use compute shader
    call glUseProgram(global_state%compute_program)
    
    ! Calculate workgroups
    workgroups_x = (N * H_out * W_out + 255) / 256
    workgroups_y = K
    workgroups_z = 1
    
    ! Sync input/weight/param writes to GPU
    call sync_buffer_to_gpu(global_state%input_buffer)
    call sync_buffer_to_gpu(global_state%weight_buffer)
    call sync_buffer_to_gpu(global_state%param_buffer)
    
    ! Dispatch compute
    call glDispatchCompute(workgroups_x, workgroups_y, workgroups_z)
    
    ! Memory barrier
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
    
    ! Create fence for completion
    compute_fence = gpu_fence_create()
    
    ! Wait for computation
    wait_status = gpu_fence_wait(compute_fence, 100000000_i64)  ! 100ms timeout
    
    if (wait_status == FENCE_READY) then
      ! Sync output from GPU
      call sync_buffer_from_gpu(global_state%output_buffer)
      
      ! Read results (zero-copy!)
      call read_buffer(global_state%output_buffer, output)
    else
      print *, "⚠️ GPU computation timed out!"
    end if
    
    ! Cleanup fence
    call gpu_fence_destroy(compute_fence)
    
    ! End timing
    call system_clock(end_time)
    time_ms = real(end_time - start_time, real32) / real(clock_rate, real32) * 1000.0
    
    
  end function gpu_execute_conv2d_zero_copy
  
  ! Set shader uniforms
  subroutine set_conv2d_uniforms(N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    character(len=20, kind=c_char) :: uniform_name
    integer :: loc
    
    ! Set dimensions
    uniform_name = "N" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, N)
    
    uniform_name = "C" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, C)
    
    uniform_name = "H" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, H)
    
    uniform_name = "W" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, W)
    
    uniform_name = "K" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, K)
    
    uniform_name = "kernel_size" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, kernel_size)
    
    uniform_name = "stride" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, stride)
    
    uniform_name = "pad" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, pad)
    
    uniform_name = "H_out" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, H_out)
    
    uniform_name = "W_out" // c_null_char
    loc = glGetUniformLocation(global_state%compute_program, uniform_name)
    if (loc >= 0) call glUniform1i(loc, W_out)
    
  end subroutine set_conv2d_uniforms
  
  ! Simple weight hash function
  function compute_weight_hash(weights) result(hash)
    real(sp), intent(in) :: weights(:)
    integer(i64) :: hash
    integer :: i
    
    hash = 0
    if (size(weights) > 0) then
      hash = transfer(weights(1), 0_int64)
      if (size(weights) > 1) then
        hash = hash + transfer(weights(size(weights)), 0_int64)
      end if
      do i = 100, size(weights), 100
        hash = hash + transfer(weights(i), 0_int64)
      end do
    end if
  end function compute_weight_hash
  
  ! Write parameters to buffer
  subroutine write_buffer_params(buffer, params)
    type(unified_buffer), intent(inout) :: buffer
    type(conv2d_params), intent(in) :: params
    
    type(conv2d_params), pointer :: ptr
    type(c_ptr) :: cpu_ptr
    
    if (.not. buffer_is_valid(buffer)) return
    
    cpu_ptr = get_buffer_pointer(buffer)
    call c_f_pointer(cpu_ptr, ptr)
    ptr = params
    
  end subroutine write_buffer_params
  
end module gpu_opengl_zero_copy