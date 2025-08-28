module sporkle_fortran_shaders_v2
  ! Enhanced Fortran GPU shader integration with adaptive parameter passing
  use iso_c_binding
  use kinds
  use sporkle_shader_parser_v2
  use sporkle_fortran_params
  use gl_constants
  implicit none
  
  private
  public :: sporkle_compile_and_dispatch_v2
  public :: sporkle_set_param_method
  public :: sporkle_benchmark_params
  public :: shader_cache_entry_v2
  
  ! Shader cache to avoid recompilation
  type :: shader_cache_entry_v2
    character(len=256) :: kernel_name
    integer :: program
    integer :: param_method
    type(shader_kernel_v2) :: kernel_info
    logical :: is_valid = .false.
  end type
  
  integer :: MAX_CACHE_SIZE = 128
  type(shader_cache_entry_v2), allocatable, target, save :: shader_cache(:)
  integer, save :: cache_count = 0
  logical, save :: cache_initialized = .false.
  
  ! Global parameter strategy
  type(param_strategy), save :: global_strategy
  logical, save :: strategy_initialized = .false.
  
contains

  subroutine init_cache()
    if (.not. cache_initialized) then
      allocate(shader_cache(MAX_CACHE_SIZE))
      cache_initialized = .true.
    end if
    
    if (.not. strategy_initialized) then
      global_strategy = create_param_strategy()
      strategy_initialized = .true.
    end if
  end subroutine init_cache
  
  subroutine sporkle_set_param_method(method)
    integer, intent(in) :: method
    
    call init_cache()
    if (method >= PARAMS_UNIFORM .and. method <= PARAMS_INLINE) then
      global_strategy%preferred_method = method
    end if
  end subroutine sporkle_set_param_method
  
  subroutine sporkle_benchmark_params(kernel_file, kernel_name)
    character(len=*), intent(in) :: kernel_file, kernel_name
    type(shader_kernel_v2) :: test_kernel
    character(len=:), allocatable :: glsl_source
    
    call init_cache()
    
    ! Parse kernel
    test_kernel = parse_fortran_kernel_v2(kernel_file, kernel_name, PARAMS_BUFFER)
    
    ! Generate test GLSL
    glsl_source = generate_glsl_v2(test_kernel)
    
    ! Benchmark all methods - TODO: implement benchmark_param_methods
    ! call benchmark_param_methods(global_strategy, glsl_source)
    print *, "⚠️  benchmark_param_methods not yet implemented - skipping"
  end subroutine sporkle_benchmark_params
  
  subroutine sporkle_compile_and_dispatch_v2(kernel_file, kernel_name, global_size, &
                                            buffers, params, param_values, status)
    character(len=*), intent(in) :: kernel_file, kernel_name
    integer, intent(in) :: global_size
    type(c_ptr), intent(in) :: buffers(:)
    character(len=*), intent(in), optional :: params(:)      ! Parameter names
    integer, intent(in), optional :: param_values(:)         ! Parameter values
    integer, intent(out) :: status
    
    type(shader_kernel_v2) :: kernel
    type(shader_cache_entry_v2), pointer :: cache_entry
    character(len=:), allocatable :: glsl_source
    integer :: program, i
    integer :: param_buffer
    integer, target :: param_data(64)  ! Max 64 scalar params
    logical :: found
    
    status = 0
    call init_cache()
    
    ! Check cache first
    found = .false.
    do i = 1, cache_count
      if (shader_cache(i)%kernel_name == kernel_name .and. &
          shader_cache(i)%param_method == global_strategy%preferred_method) then
        cache_entry => shader_cache(i)
        found = .true.
        exit
      end if
    end do
    
    if (.not. found) then
      ! Parse kernel with preferred method
      kernel = parse_fortran_kernel_v2(kernel_file, kernel_name, &
                                      global_strategy%preferred_method)
      
      ! Generate GLSL based on method
      glsl_source = generate_glsl_v2(kernel)
      
      ! Compile shader
      program = compile_glsl_shader(glsl_source)
      if (program == 0) then
        print *, "Failed to compile shader: ", trim(kernel_name)
        status = -1
        return
      end if
      
      ! Add to cache
      if (cache_count < MAX_CACHE_SIZE) then
        cache_count = cache_count + 1
        shader_cache(cache_count)%kernel_name = kernel_name
        shader_cache(cache_count)%program = program
        shader_cache(cache_count)%param_method = global_strategy%preferred_method
        shader_cache(cache_count)%kernel_info = kernel
        shader_cache(cache_count)%is_valid = .true.
        cache_entry => shader_cache(cache_count)
      else
        ! Cache full, just use without caching
        print *, "Warning: Shader cache full"
        call dispatch_shader_with_params(program, kernel, global_size, buffers, &
                                       params, param_values, status)
        return
      end if
    else
      program = cache_entry%program
      kernel = cache_entry%kernel_info
    end if
    
    ! Dispatch with parameters
    call dispatch_shader_with_params(program, kernel, global_size, buffers, &
                                   params, param_values, status)
    
  end subroutine sporkle_compile_and_dispatch_v2
  
  subroutine dispatch_shader_with_params(program, kernel, global_size, buffers, &
                                       param_names, param_values, status)
    integer, intent(in) :: program
    type(shader_kernel_v2), intent(in) :: kernel
    integer, intent(in) :: global_size
    type(c_ptr), intent(in) :: buffers(:)
    character(len=*), intent(in), optional :: param_names(:)
    integer, intent(in), optional :: param_values(:)
    integer, intent(out) :: status
    
    integer :: i, loc, param_buffer
    integer, target :: param_data(64)
    
    status = 0
    
    ! Use program
    call glUseProgram(program)
    
    ! Bind buffers
    do i = 1, size(buffers)
      call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, i-1, transfer(buffers(i), 0))
    end do
    
    ! Handle parameters based on method
    select case(kernel%param_method)
    case(PARAMS_UNIFORM)
      ! Set uniforms
      if (present(param_names) .and. present(param_values)) then
        do i = 1, min(size(param_names), size(param_values))
          ! glGetUniformLocation not available in our interface, skip for now
          loc = -1
          if (loc >= 0) then
            call glUniform1i(loc, param_values(i))
          end if
        end do
      end if
      
    case(PARAMS_BUFFER)
      ! Create parameter buffer
      if (present(param_values) .and. size(param_values) > 0) then
        param_data(1:size(param_values)) = param_values
        
        call glGenBuffers(1, param_buffer)
        call glBindBuffer(GL_SHADER_STORAGE_BUFFER, param_buffer)
        call glBufferData(GL_SHADER_STORAGE_BUFFER, &
                         int(size(param_values) * 4, c_size_t), &
                         c_loc(param_data), int(z'88E8', c_int))
        call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 15, param_buffer)
      end if
      
    case(PARAMS_INLINE)
      ! Parameters were inlined at compile time
      ! Would need recompilation for different values
    end select
    
    ! Dispatch
    call glDispatchCompute(global_size, 1, 1)
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
    
    ! Cleanup param buffer if created
    if (kernel%param_method == PARAMS_BUFFER .and. &
        present(param_values) .and. size(param_values) > 0) then
      call glDeleteBuffers(1, param_buffer)
    end if
    
  end subroutine dispatch_shader_with_params
  
  function compile_glsl_shader(source) result(program)
    character(len=*), intent(in) :: source
    integer :: program
    integer :: shader, compile_status, link_status
    integer :: info_len
    
    program = 0
    
    ! Create shader
    shader = glCreateShader(GL_COMPUTE_SHADER)
    if (shader == 0) then
      print *, "Failed to create shader"
      return
    end if
    
    ! Set source
    block
      character(len=:,kind=c_char), allocatable, target :: c_source
      type(c_ptr), target :: source_ptr(1)
      integer(c_int), target :: source_len
      
      c_source = source // c_null_char
      source_ptr(1) = c_loc(c_source)
      source_len = len(source)
      
      call glShaderSource(shader, 1, c_loc(source_ptr), c_loc(source_len))
    end block
    
    ! Compile
    call glCompileShader(shader)
    call glGetShaderiv(shader, GL_COMPILE_STATUS, compile_status)
    
    if (compile_status == 0) then
      print *, "Shader compilation failed"
      call glDeleteShader(shader)
      return
    end if
    
    ! Create program
    program = glCreateProgram()
    call glAttachShader(program, shader)
    call glLinkProgram(program)
    
    call glGetProgramiv(program, GL_LINK_STATUS, link_status)
    if (link_status == 0) then
      print *, "Program linking failed"
      call glDeleteProgram(program)
      program = 0
    end if
    
    ! Clean up shader
    call glDeleteShader(shader)
    
  end function compile_glsl_shader
  
end module sporkle_fortran_shaders_v2