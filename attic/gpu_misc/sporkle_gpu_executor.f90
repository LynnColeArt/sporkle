module sporkle_gpu_executor
  ! GPU execution module using OpenGL compute shaders
  ! This module takes parsed kernels and executes them on the GPU
  use kinds
  use iso_c_binding
  use gl_constants
  use sporkle_shader_parser_v2
  use sporkle_fortran_params
  implicit none
  private
  
  public :: gpu_executor, initialize_executor, execute_kernel, cleanup_executor
  public :: create_buffer, update_buffer, read_buffer, delete_buffer
  
  type :: gpu_buffer
    integer(c_int) :: id = 0
    integer(c_size_t) :: size = 0
    integer :: binding = -1
  end type gpu_buffer
  
  type :: gpu_executor
    integer(c_int) :: program = 0
    integer(c_int) :: shader = 0
    type(gpu_buffer), allocatable :: buffers(:)
    integer(c_int), allocatable :: buffer_sizes(:)
    integer(c_int) :: param_buffer = 0
    integer :: num_buffers = 0
    logical :: initialized = .false.
  end type gpu_executor
  
contains

  function compile_shader(source) result(shader)
    character(len=*), intent(in) :: source
    integer(c_int) :: shader
    integer(c_int) :: compile_status, info_len
    character(len=1024) :: info_log
    character(len=:,kind=c_char), allocatable, target :: c_source
    type(c_ptr) :: source_ptr
    integer(c_int) :: source_len
    
    ! Create compute shader
    shader = glCreateShader(GL_COMPUTE_SHADER)
    
    ! Prepare source for OpenGL
    c_source = source // c_null_char
    source_ptr = c_loc(c_source)
    source_len = len(source)
    
    ! Set shader source and compile
    block
      type(c_ptr), target :: source_ptr_array(1)
      integer(c_int), target :: source_len_array(1)
      source_ptr_array(1) = source_ptr
      source_len_array(1) = source_len
      call glShaderSource(shader, 1, c_loc(source_ptr_array), c_loc(source_len_array))
    end block
    call glCompileShader(shader)
    
    ! Check compilation
    call glGetShaderiv(shader, GL_COMPILE_STATUS, compile_status)
    if (compile_status == 0) then
      call glGetShaderiv(shader, GL_INFO_LOG_LENGTH, info_len)
      if (info_len > 0) then
        block
          integer(c_int), target :: actual_len
          character(len=1024), target :: temp_log
          temp_log = info_log
          call glGetShaderInfoLog(shader, min(info_len, 1024), c_loc(actual_len), c_loc(temp_log))
          print *, "Shader compilation failed:"
          print *, trim(temp_log(1:actual_len))
        end block
      end if
      call glDeleteShader(shader)
      shader = 0
    end if
  end function compile_shader
  
  function create_program(shader) result(program)
    integer(c_int), intent(in) :: shader
    integer(c_int) :: program
    integer(c_int) :: link_status, info_len
    character(len=1024) :: info_log
    
    program = glCreateProgram()
    call glAttachShader(program, shader)
    call glLinkProgram(program)
    
    ! Check linking
    call glGetProgramiv(program, GL_LINK_STATUS, link_status)
    if (link_status == 0) then
      call glGetProgramiv(program, GL_INFO_LOG_LENGTH, info_len)
      if (info_len > 0) then
        block
          integer(c_int), target :: actual_len
          character(len=1024), target :: temp_log
          temp_log = info_log
          call glGetProgramInfoLog(program, min(info_len, 1024), c_loc(actual_len), c_loc(temp_log))
          print *, "Program linking failed:"
          print *, trim(temp_log(1:actual_len))
        end block
      end if
      call glDeleteProgram(program)
      program = 0
    end if
    
    ! Clean up shader after linking
    if (shader /= 0) call glDeleteShader(shader)
  end function create_program
  
  subroutine initialize_executor(exec, kernel)
    type(gpu_executor), intent(inout) :: exec
    type(shader_kernel_v2), intent(in) :: kernel
    character(len=:), allocatable :: glsl_source
    integer(c_int) :: shader
    integer :: i, buffer_count
    
    ! Generate GLSL from kernel
    glsl_source = generate_glsl_v2(kernel)
    
    ! Compile and link
    shader = compile_shader(glsl_source)
    if (shader == 0) then
      print *, "Failed to compile shader for kernel: ", trim(kernel%name)
      return
    end if
    
    exec%program = create_program(shader)
    if (exec%program == 0) then
      print *, "Failed to create program for kernel: ", trim(kernel%name)
      return
    end if
    
    ! Count buffers needed (arrays only, not scalars)
    buffer_count = 0
    if (allocated(kernel%args)) then
      do i = 1, size(kernel%args)
        if (.not. kernel%args(i)%is_scalar) then
          buffer_count = buffer_count + 1
        end if
      end do
    end if
    
    ! Allocate buffer tracking
    exec%num_buffers = buffer_count
    if (buffer_count > 0) then
      allocate(exec%buffers(buffer_count))
    end if
    
    ! Create parameter buffer if using BUFFER method
    if (kernel%param_method == PARAMS_BUFFER .and. allocated(kernel%params)) then
      call glGenBuffers(1, exec%param_buffer)
    end if
    
    exec%initialized = .true.
  end subroutine initialize_executor
  
  function create_buffer(exec, size_bytes, binding) result(buffer_id)
    type(gpu_executor), intent(inout) :: exec
    integer(c_size_t), intent(in) :: size_bytes
    integer, intent(in) :: binding
    integer(c_int) :: buffer_id
    integer :: idx
    
    call glGenBuffers(1, buffer_id)
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer_id)
    call glBufferData(GL_SHADER_STORAGE_BUFFER, size_bytes, c_null_ptr, GL_DYNAMIC_DRAW)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, binding, buffer_id)
    
    ! Track buffer
    do idx = 1, exec%num_buffers
      if (exec%buffers(idx)%id == 0) then
        exec%buffers(idx)%id = buffer_id
        exec%buffers(idx)%size = size_bytes
        exec%buffers(idx)%binding = binding
        exit
      end if
    end do
  end function create_buffer
  
  subroutine update_buffer(buffer_id, data, size_bytes)
    integer(c_int), intent(in) :: buffer_id
    type(c_ptr), intent(in) :: data
    integer(c_size_t), intent(in) :: size_bytes
    
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer_id)
    call glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0_c_size_t, size_bytes, data)
  end subroutine update_buffer
  
  subroutine read_buffer(buffer_id, data, size_bytes)
    integer(c_int), intent(in) :: buffer_id
    type(c_ptr), intent(in) :: data
    integer(c_size_t), intent(in) :: size_bytes
    
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer_id)
    call glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0_c_size_t, size_bytes, data)
  end subroutine read_buffer
  
  subroutine delete_buffer(buffer_id)
    integer(c_int), intent(inout) :: buffer_id
    
    if (buffer_id /= 0) then
      call glDeleteBuffers(1, buffer_id)
      buffer_id = 0
    end if
  end subroutine delete_buffer
  
  subroutine execute_kernel(exec, kernel, work_size, params)
    type(gpu_executor), intent(inout) :: exec
    type(shader_kernel_v2), intent(in) :: kernel
    integer, intent(in) :: work_size
    real(sp), dimension(:), intent(in), optional :: params
    
    integer :: i, param_size
    integer(c_int) :: loc
    
    if (.not. exec%initialized) then
      call initialize_executor(exec, kernel)
      if (.not. exec%initialized) return
    end if
    
    ! Use program
    call glUseProgram(exec%program)
    
    ! Set parameters based on method
    if (present(params) .and. allocated(kernel%params)) then
      select case (kernel%param_method)
      case (PARAMS_UNIFORM)
        ! Set each scalar as a uniform
        do i = 1, size(kernel%params)
          loc = glGetUniformLocation(exec%program, &
                                     trim(kernel%params(i)%name) // c_null_char)
          if (loc >= 0) then
            call glUniform1f(loc, params(i))
          end if
        end do
        
      case (PARAMS_BUFFER)
        ! Update parameter buffer
        if (exec%param_buffer /= 0 .and. present(params)) then
          param_size = size(params) * 4  ! sizeof(float)
          call glBindBuffer(GL_SHADER_STORAGE_BUFFER, exec%param_buffer)
          ! Create a target copy of params
          block
            integer :: n_params
            real(sp), allocatable, target :: temp_params(:)
            n_params = size(params)
            allocate(temp_params(n_params))
            temp_params = params
            call glBufferData(GL_SHADER_STORAGE_BUFFER, int(param_size, c_size_t), &
                              c_loc(temp_params), GL_DYNAMIC_DRAW)
          end block
          call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, PARAM_BUFFER_BINDING, &
                                exec%param_buffer)
        end if
      end select
    end if
    
    ! Dispatch compute work
    call glDispatchCompute(work_size / kernel%local_size_x + 1, 1, 1)
    
    ! Ensure completion
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
    call glFinish()
  end subroutine execute_kernel
  
  subroutine cleanup_executor(exec)
    type(gpu_executor), intent(inout) :: exec
    integer :: i
    
    if (exec%program /= 0) then
      call glDeleteProgram(exec%program)
      exec%program = 0
    end if
    
    if (allocated(exec%buffers)) then
      do i = 1, size(exec%buffers)
        if (exec%buffers(i)%id /= 0) then
          call delete_buffer(exec%buffers(i)%id)
        end if
      end do
      deallocate(exec%buffers)
    end if
    
    if (exec%param_buffer /= 0) then
      call delete_buffer(exec%param_buffer)
    end if
    
    exec%initialized = .false.
  end subroutine cleanup_executor

end module sporkle_gpu_executor