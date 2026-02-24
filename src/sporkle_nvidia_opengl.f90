module sporkle_nvidia_opengl
  ! Compatibility layer for NVIDIA OpenGL-backed execution
  ! This module preserves the interface expected by historic sporkle_nvidia_* files
  ! and provides a minimal, deterministic implementation on top of the existing
  ! OpenGL reference runtime.

  use kinds
  use iso_c_binding
  implicit none

  private

  public :: nvidia_gl_init
  public :: nvidia_gl_shutdown
  public :: nvidia_gl_get_device_info
  public :: nvidia_gl_execute_conv2d
  public :: nvidia_gl_execute_conv2d_timed

  public :: GL_COPY_READ_BUFFER
  public :: GL_COPY_WRITE_BUFFER
  public :: GL_BUFFER_UPDATE_BARRIER_BIT
  public :: GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT
  public :: GL_DYNAMIC_STORAGE_BIT
  public :: GL_MAP_COHERENT_BIT
  public :: GL_MAP_FLUSH_EXPLICIT_BIT
  public :: GL_MAP_PERSISTENT_BIT
  public :: GL_MAP_READ_BIT
  public :: GL_MAP_WRITE_BIT
  public :: GL_QUERY_RESULT
  public :: GL_QUERY_RESULT_AVAILABLE
  public :: GL_TIME_ELAPSED
  public :: GL_READ_WRITE
  public :: GL_STATIC_DRAW
  public :: GL_STREAM_DRAW
  public :: GL_WRITE_ONLY

  public :: GL_SYNC_GPU_COMMANDS_COMPLETE
  public :: GL_SYNC_FLUSH_COMMANDS_BIT
  public :: GL_ALREADY_SIGNALED
  public :: GL_CONDITION_SATISFIED
  public :: GL_TIMEOUT_EXPIRED
  public :: GL_WAIT_FAILED

  public :: GL_DYNAMIC_COPY
  public :: GL_SHADER_STORAGE_BUFFER
  public :: GL_SHADER_STORAGE_BARRIER_BIT

  public :: glGetError
  public :: glGenBuffers
  public :: glDeleteBuffers
  public :: glBindBuffer
  public :: glBufferData
  public :: glBindBufferBase
  public :: glUseProgram
  public :: glGetUniformLocation
  public :: glUniform1i
  public :: glDispatchCompute
  public :: glMemoryBarrier
  public :: glFinish
  public :: glFlush
  public :: glMapBufferRange
  public :: glUnmapBuffer
  public :: glBeginQuery
  public :: glEndQuery
  public :: glGenQueries
  public :: glDeleteQueries
  public :: glGetQueryObjectiv
  public :: glGetQueryObjecti64v

  ! ---------------------------------------------------------------------------
  ! Constants shared with callers/tests
  ! ---------------------------------------------------------------------------
  integer(c_int), parameter :: GL_DYNAMIC_COPY = int(z'88EA', c_int)
  integer(c_int), parameter :: GL_SHADER_STORAGE_BUFFER = int(z'90D2', c_int)
  integer(c_int), parameter :: GL_SHADER_STORAGE_BARRIER_BIT = int(z'2000', c_int)
  integer(c_int), parameter :: GL_COPY_READ_BUFFER = int(z'8F36', c_int)
  integer(c_int), parameter :: GL_COPY_WRITE_BUFFER = int(z'8F37', c_int)
  integer(c_int), parameter :: GL_BUFFER_UPDATE_BARRIER_BIT = int(z'200', c_int)
  integer(c_int), parameter :: GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT = int(z'40000', c_int)
  integer(c_int), parameter :: GL_DYNAMIC_STORAGE_BIT = int(z'0100', c_int)
  integer(c_int), parameter :: GL_MAP_COHERENT_BIT = int(z'0080', c_int)
  integer(c_int), parameter :: GL_MAP_FLUSH_EXPLICIT_BIT = int(z'0010', c_int)
  integer(c_int), parameter :: GL_MAP_PERSISTENT_BIT = int(z'0040', c_int)
  integer(c_int), parameter :: GL_MAP_READ_BIT = int(z'0001', c_int)
  integer(c_int), parameter :: GL_MAP_WRITE_BIT = int(z'0002', c_int)
  integer(c_int), parameter :: GL_QUERY_RESULT = int(z'8866', c_int)
  integer(c_int), parameter :: GL_QUERY_RESULT_AVAILABLE = int(z'8867', c_int)
  integer(c_int), parameter :: GL_TIME_ELAPSED = int(z'88BF', c_int)
  integer(c_int), parameter :: GL_READ_WRITE = int(z'88BA', c_int)
  integer(c_int), parameter :: GL_STATIC_DRAW = int(z'88E4', c_int)
  integer(c_int), parameter :: GL_STREAM_DRAW = int(z'88E0', c_int)
  integer(c_int), parameter :: GL_WRITE_ONLY = int(z'88B9', c_int)

  integer(c_int), parameter :: GL_SYNC_GPU_COMMANDS_COMPLETE = int(z'9117', c_int)
  integer(c_int), parameter :: GL_SYNC_FLUSH_COMMANDS_BIT = int(z'00000001', c_int)
  integer(c_int), parameter :: GL_ALREADY_SIGNALED = int(z'911A', c_int)
  integer(c_int), parameter :: GL_TIMEOUT_EXPIRED = int(z'911B', c_int)
  integer(c_int), parameter :: GL_CONDITION_SATISFIED = int(z'911C', c_int)
  integer(c_int), parameter :: GL_WAIT_FAILED = int(z'911D', c_int)

  integer(c_int), public :: conv2d_program = 0
  logical, save :: initialized = .false.
  character(len=256), save :: cached_device_info = "Not initialized"

  interface
    ! Reference backend from source/gpu_opengl_reference.c
    function gpu_initialize_opengl() bind(C, name="gpu_initialize_opengl")
      import :: c_int
      integer(c_int) :: gpu_initialize_opengl
    end function

    subroutine gpu_cleanup_opengl() bind(C, name="gpu_cleanup_opengl")
    end subroutine

    function gpu_is_initialized() bind(C, name="gpu_is_initialized")
      import :: c_int
      integer(c_int) :: gpu_is_initialized
    end function

    function gpu_compile_conv2d_shader() bind(C, name="gpu_compile_conv2d_shader")
      import :: c_int
      integer(c_int) :: gpu_compile_conv2d_shader
    end function

    function gpu_get_compute_program() bind(C, name="gpu_get_compute_program")
      import :: c_int
      integer(c_int) :: gpu_get_compute_program
    end function

    function gpu_execute_conv2d_fortran(input, kernel, output, N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) &
        bind(C, name="gpu_execute_conv2d_fortran")
      import :: c_ptr, c_int, c_float
      type(c_ptr), value :: input
      type(c_ptr), value :: kernel
      type(c_ptr), value :: output
      integer(c_int), value :: N, C, H, W, K
      integer(c_int), value :: kernel_size, stride, pad, H_out, W_out
      real(c_float) :: gpu_execute_conv2d_fortran
    end function
  end interface

  interface
    ! GL APIs required by the NVIDIA path and tests
    function glGetError() bind(C, name="glGetError")
      import :: c_int
      integer(c_int) :: glGetError
    end function

    function glGetUniformLocation(program, name) bind(C, name="glGetUniformLocation")
      import :: c_int, c_ptr
      integer(c_int), value :: program
      type(c_ptr), value :: name
      integer(c_int) :: glGetUniformLocation
    end function

    function glMapBufferRange(target, offset, length, access) bind(C, name="glMapBufferRange")
      import :: c_int, c_intptr_t, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_intptr_t), value :: offset
      integer(c_size_t), value :: length
      integer(c_int), value :: access
      type(c_ptr) :: glMapBufferRange
    end function

    function glUnmapBuffer(target) bind(C, name="glUnmapBuffer")
      import :: c_int
      integer(c_int), value :: target
      integer(c_int) :: glUnmapBuffer
    end function

    subroutine glBindBuffer(target, buffer) bind(C, name="glBindBuffer")
      import :: c_int
      integer(c_int), value :: target, buffer
    end subroutine

    subroutine glBindBufferBase(target, index, buffer) bind(C, name="glBindBufferBase")
      import :: c_int
      integer(c_int), value :: target, index, buffer
    end subroutine

    subroutine glBufferData(target, size, data, usage) bind(C, name="glBufferData")
      import :: c_int, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
      integer(c_int), value :: usage
    end subroutine

    subroutine glGenBuffers(n, buffers) bind(C, name="glGenBuffers")
      import :: c_int, c_ptr
      integer(c_int), value :: n
      type(c_ptr), value :: buffers
    end subroutine

    subroutine glDeleteBuffers(n, buffers) bind(C, name="glDeleteBuffers")
      import :: c_int, c_ptr
      integer(c_int), value :: n
      type(c_ptr), value :: buffers
    end subroutine

    subroutine glUseProgram(program) bind(C, name="glUseProgram")
      import :: c_int
      integer(c_int), value :: program
    end subroutine

    subroutine glUniform1i(location, value) bind(C, name="glUniform1i")
      import :: c_int
      integer(c_int), value :: location, value
    end subroutine

    subroutine glDispatchCompute(num_x, num_y, num_z) bind(C, name="glDispatchCompute")
      import :: c_int
      integer(c_int), value :: num_x, num_y, num_z
    end subroutine

    subroutine glMemoryBarrier(barriers) bind(C, name="glMemoryBarrier")
      import :: c_int
      integer(c_int), value :: barriers
    end subroutine

    subroutine glFinish() bind(C, name="glFinish")
    end subroutine

    subroutine glFlush() bind(C, name="glFlush")
    end subroutine

    subroutine glBeginQuery(target, id) bind(C, name="glBeginQuery")
      import :: c_int
      integer(c_int), value :: target, id
    end subroutine

    subroutine glEndQuery(target) bind(C, name="glEndQuery")
      import :: c_int
      integer(c_int), value :: target
    end subroutine

    subroutine glGenQueries(n, ids) bind(C, name="glGenQueries")
      import :: c_int, c_ptr
      integer(c_int), value :: n
      type(c_ptr), value :: ids
    end subroutine

    subroutine glDeleteQueries(n, ids) bind(C, name="glDeleteQueries")
      import :: c_int, c_ptr
      integer(c_int), value :: n
      type(c_ptr), value :: ids
    end subroutine

    subroutine glGetQueryObjectiv(id, pname, params) bind(C, name="glGetQueryObjectiv")
      import :: c_int, c_ptr
      integer(c_int), value :: id
      integer(c_int), value :: pname
      type(c_ptr), value :: params
    end subroutine

    subroutine glGetQueryObjecti64v(id, pname, params) bind(C, name="glGetQueryObjecti64v")
      import :: c_int, c_int64_t, c_ptr
      integer(c_int), value :: id, pname
      type(c_ptr), value :: params
    end subroutine
  end interface

contains

  logical function nvidia_gl_init()
    nvidia_gl_init = .false.
    if (initialized) then
      nvidia_gl_init = .true.
      return
    end if

    if (gpu_initialize_opengl() == 0) then
      print *, "ERROR: nvidia_gl_init failed to initialize EGL/OpenGL context"
      cached_device_info = "Not initialized"
      return
    end if

    if (gpu_compile_conv2d_shader() == 0) then
      print *, "ERROR: nvidia_gl_init failed to compile baseline compute shader"
      call gpu_cleanup_opengl()
      cached_device_info = "Shader compile failure"
      return
    end if

    conv2d_program = gpu_get_compute_program()
    if (conv2d_program == 0) then
      print *, "ERROR: nvidia_gl_init could not retrieve compute program"
      call gpu_cleanup_opengl()
      cached_device_info = "Program setup failure"
      return
    end if

    cached_device_info = "NVIDIA/OpenGL compute backend ready"
    initialized = .true.
    nvidia_gl_init = .true.
  end function nvidia_gl_init

  subroutine nvidia_gl_shutdown()
    if (.not. initialized) then
      return
    end if

    call gpu_cleanup_opengl()
    conv2d_program = 0
    initialized = .false.
    cached_device_info = "Shutdown complete"
  end subroutine nvidia_gl_shutdown

  character(len=256) function nvidia_gl_get_device_info()
    if (.not. initialized) then
      nvidia_gl_get_device_info = "NVIDIA backend not initialized"
      return
    end if

    nvidia_gl_get_device_info = cached_device_info
  end function nvidia_gl_get_device_info

  logical function nvidia_gl_execute_conv2d(input, kernel, output, &
                                           batch, in_c, out_c, h, w, kh, kw)
    real(sp), intent(in), target :: input(*)
    real(sp), intent(in), target :: kernel(*)
    real(sp), intent(out), target :: output(*)
    integer, intent(in) :: batch, in_c, out_c, h, w, kh, kw
    real(c_float) :: kernel_ms
    integer(c_int) :: h_out, w_out
    integer(c_int) :: stride, pad

    nvidia_gl_execute_conv2d = .false.

    if (.not. nvidia_gl_init()) then
      return
    end if

    if (conv2d_program <= 0) then
      print *, "ERROR: nvidia_gl_execute_conv2d called without compiled compute program"
      return
    end if

    stride = 1
    pad = 0
    h_out = max(0, h - kh + 1)
    w_out = max(0, w - kw + 1)

    if (h_out <= 0 .or. w_out <= 0) then
      print *, "ERROR: nvidia_gl_execute_conv2d called with invalid convolution geometry"
      return
    end if

    kernel_ms = gpu_execute_conv2d_fortran(c_loc(input), c_loc(kernel), c_loc(output), &
                                          int(batch, c_int), int(in_c, c_int), int(h, c_int), int(w, c_int), &
                                          int(out_c, c_int), int(kh, c_int), int(stride, c_int), int(pad, c_int), &
                                          h_out, w_out)

    nvidia_gl_execute_conv2d = (kernel_ms >= 0.0_c_float)
  end function nvidia_gl_execute_conv2d

  logical function nvidia_gl_execute_conv2d_timed(input, kernel, output, &
                                                  batch, in_c, out_c, h, w, kh, kw, &
                                                  elapsed_ms)
    real(sp), intent(in), target :: input(*)
    real(sp), intent(in), target :: kernel(*)
    real(sp), intent(out), target :: output(*)
    integer, intent(in) :: batch, in_c, out_c, h, w, kh, kw
    real(dp), intent(out) :: elapsed_ms
    real(c_float) :: kernel_ms
    integer(c_int) :: h_out, w_out
    integer(c_int) :: stride, pad

    nvidia_gl_execute_conv2d_timed = .false.
    elapsed_ms = -1.0_dp

    if (.not. nvidia_gl_init()) then
      return
    end if

    if (conv2d_program <= 0) then
      print *, "ERROR: nvidia_gl_execute_conv2d_timed called without compiled compute program"
      return
    end if

    stride = 1
    pad = 0
    h_out = max(0, h - kh + 1)
    w_out = max(0, w - kw + 1)

    if (h_out <= 0 .or. w_out <= 0) then
      print *, "ERROR: nvidia_gl_execute_conv2d_timed called with invalid convolution geometry"
      return
    end if

    ! The reference backend returns a measured wall time in milliseconds.
    kernel_ms = gpu_execute_conv2d_fortran(c_loc(input), c_loc(kernel), c_loc(output), &
                                          int(batch, c_int), int(in_c, c_int), int(h, c_int), int(w, c_int), &
                                          int(out_c, c_int), int(kh, c_int), int(stride, c_int), int(pad, c_int), &
                                          h_out, w_out)

    nvidia_gl_execute_conv2d_timed = (kernel_ms >= 0.0_c_float)
    elapsed_ms = real(kernel_ms, dp)
  end function nvidia_gl_execute_conv2d_timed

end module sporkle_nvidia_opengl
