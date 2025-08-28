module sporkle_glsl_compute
  use iso_c_binding
  use sporkle_types
  use sporkle_glsl_generator
  ! use sporkle_amdgpu_direct  ! For buffer types
  use gl_constants
  implicit none
  
  private
  public :: glsl_kernel, compile_glsl_kernel, dispatch_conv_glsl, cleanup_glsl_kernel
  public :: init_opengl_compute, cleanup_opengl_compute
  
  ! GLSL kernel structure
  type :: glsl_kernel
    integer(c_int) :: shader_id
    integer(c_int) :: program_id
    type(convolution_config) :: config
    logical :: is_valid
  end type glsl_kernel
  
  ! Additional OpenGL function interfaces not in gl_constants
  interface
    function glGetUniformLocation(program, name) bind(C, name="glGetUniformLocation")
      import :: c_int, c_char
      integer(c_int), value :: program
      character(c_char), intent(in) :: name(*)
      integer(c_int) :: glGetUniformLocation
    end function
    
    subroutine glUniform1i(location, v0) bind(C, name="glUniform1i")
      import :: c_int
      integer(c_int), value :: location
      integer(c_int), value :: v0
    end subroutine
  end interface
  
contains

  function init_opengl_compute() result(status)
    integer :: status
    
    ! In a real implementation, we would:
    ! 1. Create an OpenGL context (via EGL or GLX)
    ! 2. Make it current
    ! 3. Initialize GL extensions
    
    ! For now, assume OpenGL context exists
    status = 0
  end function init_opengl_compute
  
  subroutine cleanup_opengl_compute()
    ! Clean up OpenGL context
  end subroutine cleanup_opengl_compute

  function compile_glsl_kernel(config) result(kernel)
    type(convolution_config), intent(in) :: config
    type(glsl_kernel) :: kernel
    character(len=:), allocatable :: shader_source
    character(len=1, kind=c_char), allocatable, target :: c_source(:)
    type(c_ptr) :: source_ptr
    integer(c_int) :: compile_status, link_status
    integer(c_int) :: log_length
    character(len=1024), target :: error_log
    integer :: i
    
    kernel%config = config
    kernel%is_valid = .false.
    
    ! Generate shader source
    shader_source = generate_conv_glsl_shader(config)
    
    ! Convert to C string
    allocate(c_source(len(shader_source) + 1))
    do i = 1, len(shader_source)
      c_source(i) = shader_source(i:i)
    end do
    c_source(len(shader_source) + 1) = c_null_char
    source_ptr = c_loc(c_source)
    
    ! Create and compile shader
    kernel%shader_id = glCreateShader(GL_COMPUTE_SHADER)
    if (kernel%shader_id == 0) then
      print *, "ERROR: Failed to create shader"
      return
    end if
    
    call glShaderSource(kernel%shader_id, 1, source_ptr, c_null_ptr)
    call glCompileShader(kernel%shader_id)
    
    ! Check compilation
    call glGetShaderiv(kernel%shader_id, GL_COMPILE_STATUS, compile_status)
    if (compile_status == 0) then
      call glGetShaderiv(kernel%shader_id, GL_INFO_LOG_LENGTH, log_length)
      if (log_length > 0) then
        call glGetShaderInfoLog(kernel%shader_id, min(log_length, 1024), c_null_ptr, c_loc(error_log))
        print *, "Shader compilation failed:"
        print *, error_log(1:log_length)
      end if
      call glDeleteShader(kernel%shader_id)
      return
    end if
    
    ! Create and link program
    kernel%program_id = glCreateProgram()
    if (kernel%program_id == 0) then
      print *, "ERROR: Failed to create program"
      call glDeleteShader(kernel%shader_id)
      return
    end if
    
    call glAttachShader(kernel%program_id, kernel%shader_id)
    call glLinkProgram(kernel%program_id)
    
    ! Check linking
    call glGetProgramiv(kernel%program_id, GL_LINK_STATUS, link_status)
    if (link_status == 0) then
      call glGetProgramiv(kernel%program_id, GL_INFO_LOG_LENGTH, log_length)
      if (log_length > 0) then
        call glGetProgramInfoLog(kernel%program_id, min(log_length, 1024), c_null_ptr, c_loc(error_log))
        print *, "Program linking failed:"
        print *, error_log(1:log_length)
      end if
      call glDeleteProgram(kernel%program_id)
      call glDeleteShader(kernel%shader_id)
      return
    end if
    
    kernel%is_valid = .true.
    
    ! Clean up
    deallocate(c_source)
    
  end function compile_glsl_kernel
  
  subroutine dispatch_conv_glsl(kernel, input_buffer, kernel_buffer, output_buffer, M, N, K)
    type(glsl_kernel), intent(in) :: kernel
    type(c_ptr), intent(in) :: input_buffer, kernel_buffer
    type(c_ptr), intent(inout) :: output_buffer
    integer, intent(in) :: M, N, K
    integer(c_int) :: loc_M, loc_N, loc_K
    integer(c_int) :: groups_x, groups_y, groups_z
    character(len=2, kind=c_char) :: c_M, c_N, c_K
    
    if (.not. kernel%is_valid) then
      print *, "ERROR: Invalid kernel"
      return
    end if
    
    ! Use program
    call glUseProgram(kernel%program_id)
    
    ! Bind buffers
    ! Note: In real implementation, we'd need GL buffer objects
    ! For now, assuming buffers have GL IDs
    ! Assuming buffers are GL buffer IDs passed as c_ptr
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, transfer(input_buffer, 0))
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, transfer(kernel_buffer, 0))
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, transfer(output_buffer, 0))
    
    ! Set uniforms
    c_M = "M" // c_null_char
    c_N = "N" // c_null_char
    c_K = "K" // c_null_char
    
    loc_M = glGetUniformLocation(kernel%program_id, c_M)
    loc_N = glGetUniformLocation(kernel%program_id, c_N)
    loc_K = glGetUniformLocation(kernel%program_id, c_K)
    
    if (loc_M >= 0) call glUniform1i(loc_M, M)
    if (loc_N >= 0) call glUniform1i(loc_N, N)
    if (loc_K >= 0) call glUniform1i(loc_K, K)
    
    ! Calculate dispatch dimensions
    groups_x = (N + 15) / 16  ! 16 = local_size_x
    groups_y = (M + 15) / 16  ! 16 = local_size_y
    groups_z = 1
    
    ! Dispatch compute
    call glDispatchCompute(groups_x, groups_y, groups_z)
    
    ! Ensure completion
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
    
  end subroutine dispatch_conv_glsl
  
  subroutine cleanup_glsl_kernel(kernel)
    type(glsl_kernel), intent(inout) :: kernel
    
    if (kernel%program_id /= 0) then
      call glDeleteProgram(kernel%program_id)
      kernel%program_id = 0
    end if
    
    if (kernel%shader_id /= 0) then
      call glDeleteShader(kernel%shader_id)
      kernel%shader_id = 0
    end if
    
    kernel%is_valid = .false.
  end subroutine cleanup_glsl_kernel

end module sporkle_glsl_compute