module sporkle_fortran_shaders
  use iso_c_binding
  use sporkle_types
  use sporkle_shader_parser
  use gl_constants
  implicit none
  private
  
  public :: sporkle_compile_and_dispatch
  public :: glsl_context, glsl_init, glsl_cleanup
  
  ! GLSL context type
  type :: glsl_context
    type(c_ptr) :: egl_display = c_null_ptr
    type(c_ptr) :: egl_context = c_null_ptr
    logical :: initialized = .false.
  end type
  
  ! EGL constants
  integer(c_int32_t), parameter :: EGL_DEFAULT_DISPLAY = 0
  integer(c_int32_t), parameter :: EGL_NO_CONTEXT = 0
  integer(c_int32_t), parameter :: EGL_NO_SURFACE = 0
  integer(c_int32_t), parameter :: EGL_OPENGL_ES_API = int(z'30A0', c_int32_t)
  integer(c_int32_t), parameter :: EGL_CONTEXT_CLIENT_VERSION = int(z'3098', c_int32_t)
  integer(c_int32_t), parameter :: EGL_PBUFFER_BIT = int(z'0001', c_int32_t)
  integer(c_int32_t), parameter :: EGL_SURFACE_TYPE = int(z'3033', c_int32_t)
  integer(c_int32_t), parameter :: EGL_RENDERABLE_TYPE = int(z'3040', c_int32_t)
  integer(c_int32_t), parameter :: EGL_OPENGL_ES3_BIT = int(z'0040', c_int32_t)
  integer(c_int32_t), parameter :: EGL_NONE = int(z'3038', c_int32_t)
  integer(c_int32_t), parameter :: EGL_TRUE = 1
  
  ! EGL functions
  interface
    function eglGetDisplay(display_id) bind(C, name="eglGetDisplay")
      import :: c_ptr, c_int
      integer(c_int), value :: display_id
      type(c_ptr) :: eglGetDisplay
    end function
    
    function eglInitialize(dpy, major, minor) bind(C, name="eglInitialize")
      import :: c_ptr, c_int
      type(c_ptr), value :: dpy
      type(c_ptr), value :: major, minor
      integer(c_int) :: eglInitialize
    end function
    
    function eglBindAPI(api) bind(C, name="eglBindAPI")
      import :: c_int
      integer(c_int), value :: api
      integer(c_int) :: eglBindAPI
    end function
    
    function eglChooseConfig(dpy, attrib_list, configs, config_size, num_config) &
        bind(C, name="eglChooseConfig")
      import :: c_ptr, c_int
      type(c_ptr), value :: dpy
      type(c_ptr), value :: attrib_list, configs, num_config
      integer(c_int), value :: config_size
      integer(c_int) :: eglChooseConfig
    end function
    
    function eglCreateContext(dpy, config, share_context, attrib_list) &
        bind(C, name="eglCreateContext")
      import :: c_ptr
      type(c_ptr), value :: dpy, config, share_context, attrib_list
      type(c_ptr) :: eglCreateContext
    end function
    
    function eglMakeCurrent(dpy, draw, read, ctx) bind(C, name="eglMakeCurrent")
      import :: c_ptr, c_int
      type(c_ptr), value :: dpy, draw, read, ctx
      integer(c_int) :: eglMakeCurrent
    end function
    
    subroutine eglDestroyContext(dpy, ctx) bind(C, name="eglDestroyContext")
      import :: c_ptr
      type(c_ptr), value :: dpy, ctx
    end subroutine
    
    subroutine eglTerminate(dpy) bind(C, name="eglTerminate")
      import :: c_ptr
      type(c_ptr), value :: dpy
    end subroutine
  end interface
  
  ! Simple shader cache entry
  type :: cached_shader
    character(len=256) :: kernel_name = ""
    integer :: device_id = 0
    integer :: program = 0
    logical :: valid = .false.
  end type
  
  ! Static cache for now
  type(cached_shader), save :: shader_cache(32)
  integer, save :: cache_count = 0

contains

  function glsl_init(ctx) result(status)
    type(glsl_context), intent(out) :: ctx
    integer :: status
    integer(c_int) :: result
    integer(c_int32_t), target :: config_attribs(9) = [ &
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, &
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, &
      EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE ]
    integer(c_int32_t), target :: context_attribs(3) = [ &
      EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE ]
    type(c_ptr), target :: configs(1)
    integer(c_int), target :: num_configs
    
    status = 0
    
    ! Get EGL display
    ctx%egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY)
    if (.not. c_associated(ctx%egl_display)) then
      print *, "Failed to get EGL display"
      status = -1
      return
    end if
    
    ! Initialize EGL
    result = eglInitialize(ctx%egl_display, c_null_ptr, c_null_ptr)
    if (result /= EGL_TRUE) then
      print *, "Failed to initialize EGL"
      status = -1
      return
    end if
    
    ! Bind OpenGL ES API
    result = eglBindAPI(EGL_OPENGL_ES_API)
    if (result /= EGL_TRUE) then
      print *, "Failed to bind OpenGL ES API"
      status = -1
      return
    end if
    
    ! Choose config
    result = eglChooseConfig(ctx%egl_display, c_loc(config_attribs), &
                           c_loc(configs), 1, c_loc(num_configs))
    if (result /= EGL_TRUE .or. num_configs == 0) then
      print *, "Failed to choose EGL config"
      status = -1
      return
    end if
    
    ! Create context
    ctx%egl_context = eglCreateContext(ctx%egl_display, configs(1), &
                                     c_null_ptr, c_loc(context_attribs))
    if (.not. c_associated(ctx%egl_context)) then
      print *, "Failed to create EGL context"
      status = -1
      return
    end if
    
    ! Make current
    result = eglMakeCurrent(ctx%egl_display, c_null_ptr, c_null_ptr, ctx%egl_context)
    if (result /= EGL_TRUE) then
      print *, "Failed to make EGL context current"
      status = -1
      return
    end if
    
    ctx%initialized = .true.
  end function glsl_init

  subroutine glsl_cleanup(ctx)
    type(glsl_context), intent(inout) :: ctx
    
    if (ctx%initialized) then
      if (c_associated(ctx%egl_context)) then
        call eglDestroyContext(ctx%egl_display, ctx%egl_context)
      end if
      if (c_associated(ctx%egl_display)) then
        call eglTerminate(ctx%egl_display)
      end if
      ctx%initialized = .false.
    end if
  end subroutine glsl_cleanup

  function glsl_compile_compute_shader(source) result(program)
    character(len=*), intent(in) :: source
    integer :: program
    integer :: shader, compile_status, link_status
    character(len=1024), target :: info_log
    type(c_ptr) :: source_ptr
    character(len=:,kind=c_char), allocatable, target :: c_source
    
    ! Convert Fortran string to C string
    c_source = trim(source) // c_null_char
    source_ptr = c_loc(c_source)
    
    ! Create shader
    shader = glCreateShader(GL_COMPUTE_SHADER)
    if (shader == 0) then
      print *, "Failed to create shader"
      program = 0
      return
    end if
    
    ! Set source
    call glShaderSource(shader, 1, source_ptr, c_null_ptr)
    
    ! Compile
    call glCompileShader(shader)
    call glGetShaderiv(shader, GL_COMPILE_STATUS, compile_status)
    
    if (compile_status /= GL_TRUE) then
      call glGetShaderInfoLog(shader, 1024, c_null_ptr, c_loc(info_log))
      print *, "Shader compilation failed:"
      print *, trim(info_log)
      call glDeleteShader(shader)
      program = 0
      return
    end if
    
    ! Create program
    program = glCreateProgram()
    if (program == 0) then
      print *, "Failed to create program"
      call glDeleteShader(shader)
      return
    end if
    
    ! Attach and link
    call glAttachShader(program, shader)
    call glLinkProgram(program)
    call glGetProgramiv(program, GL_LINK_STATUS, link_status)
    
    if (link_status /= GL_TRUE) then
      call glGetProgramInfoLog(program, 1024, c_null_ptr, c_loc(info_log))
      print *, "Program linking failed:"
      print *, trim(info_log)
      call glDeleteProgram(program)
      call glDeleteShader(shader)
      program = 0
      return
    end if
    
    ! Clean up shader (program keeps reference)
    call glDeleteShader(shader)
    
  end function glsl_compile_compute_shader

  subroutine sporkle_compile_and_dispatch(kernel_file, kernel_name, global_size, buffers, status)
    character(len=*), intent(in) :: kernel_file
    character(len=*), intent(in) :: kernel_name
    integer, intent(in) :: global_size
    type(c_ptr), intent(in) :: buffers(:)
    integer, intent(out) :: status
    
    type(shader_kernel) :: kernel
    character(len=:), allocatable :: glsl_source
    type(glsl_context) :: ctx
    integer :: program, i, j
    logical :: found_cached
    
    status = 0
    
    ! Check cache first
    found_cached = .false.
    do i = 1, cache_count
      if (shader_cache(i)%kernel_name == kernel_name .and. shader_cache(i)%valid) then
        program = shader_cache(i)%program
        found_cached = .true.
        exit
      end if
    end do
    
    if (.not. found_cached) then
      ! Parse Fortran kernel
      kernel = parse_fortran_kernel(kernel_file, kernel_name)
      
      ! Generate GLSL
      glsl_source = generate_glsl(kernel)
      
      ! print *, "Generated GLSL for kernel '", trim(kernel_name), "':"
      ! print *, trim(glsl_source)
      
      ! Don't create a new context - assume the caller has one
      ctx%initialized = .true.
      
      ! Compile shader
      program = glsl_compile_compute_shader(glsl_source)
      if (program == 0) then
        print *, "Failed to compile GLSL shader"
        status = -1
        call glsl_cleanup(ctx)
        return
      end if
      
      ! Add to cache
      if (cache_count < size(shader_cache)) then
        cache_count = cache_count + 1
        shader_cache(cache_count)%kernel_name = kernel_name
        shader_cache(cache_count)%program = program
        shader_cache(cache_count)%valid = .true.
      end if
    else
      ! For cached shader, ensure we have a context
      ctx%initialized = .true.  ! Assume existing context
    end if
    
    ! Bind buffers and dispatch
    ! print *, "Using program ID:", program
    call glUseProgram(program)
    
    ! Bind buffers to their correct slots
    ! For now, assume buffers array matches the binding slots
    j = 1
    do i = 1, size(kernel%args)
      if (kernel%args(i)%binding_slot >= 0) then
        if (j <= size(buffers)) then
          block
            integer :: buffer_id
            buffer_id = transfer(buffers(j), 0_c_int32_t)
            ! print *, "Binding buffer ID", buffer_id, "to slot", kernel%args(i)%binding_slot
            call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, kernel%args(i)%binding_slot, buffer_id)
          end block
          j = j + 1
        end if
      end if
    end do
    
    ! Dispatch with proper work group calculation
    block
      integer :: num_groups
      num_groups = (global_size + kernel%local_size_x - 1) / kernel%local_size_x
      ! print *, "Dispatching", num_groups, "work groups of size", kernel%local_size_x
      call glDispatchCompute(num_groups, 1, 1)
    end block
    
    ! Memory barrier
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
    call glFinish()
    
    ! Check for GL errors
    block
      interface
        function glGetError() bind(C, name="glGetError")
          import :: c_int
          integer(c_int) :: glGetError
        end function
      end interface
      integer(c_int) :: gl_error
      gl_error = glGetError()
      if (gl_error /= 0) then
        write(*, '(A,Z8.8)') "GL Error after dispatch: 0x", gl_error
      else
        ! print *, "No GL errors after dispatch"
      end if
    end block
    
    ! Don't cleanup context - let the caller manage it
    
  end subroutine sporkle_compile_and_dispatch

end module sporkle_fortran_shaders