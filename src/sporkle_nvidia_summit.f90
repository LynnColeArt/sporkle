module sporkle_nvidia_summit
  ! Summit implementation: Device-local buffers with staging ring
  ! This is the REAL way to do GPU compute on dGPUs!
  
  use kinds
  use iso_c_binding
  use sporkle_nvidia_opengl
  implicit none
  
  private
  public :: summit_init, summit_shutdown
  public :: summit_conv2d_async
  
  ! Ring configuration
  integer, parameter :: RING_DEPTH = 4
  
  ! Staging and device buffer set
  type :: buffer_ring_slot
    ! Staging buffers (host-visible, non-coherent)
    integer(c_int) :: staging_input
    integer(c_int) :: staging_kernel
    type(c_ptr) :: staging_input_ptr
    type(c_ptr) :: staging_kernel_ptr
    
    ! Device buffers (VRAM-resident)
    integer(c_int) :: device_input
    integer(c_int) :: device_kernel
    integer(c_int) :: device_output
    
    ! Sync objects
    type(c_ptr) :: fence
    integer(c_int) :: query_id
    logical :: in_flight
  end type
  
  ! Global state
  type(buffer_ring_slot) :: ring(RING_DEPTH)
  integer :: current_slot = 1
  logical :: initialized = .false.
  integer(c_int) :: summit_program = 0
  
  ! OpenGL constants we need
  integer(c_int), parameter :: GL_CLIENT_STORAGE_BIT = int(z'0200', c_int)
  
  ! Interfaces
  interface
    subroutine glBufferStorage(target, size, data, flags) bind(C, name='glBufferStorage')
      import :: c_int, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
      integer(c_int), value :: flags
    end subroutine
    
    subroutine glFlushMappedBufferRange(target, offset, length) &
        bind(C, name='glFlushMappedBufferRange')
      import :: c_int, c_intptr_t, c_size_t
      integer(c_int), value :: target
      integer(c_intptr_t), value :: offset
      integer(c_size_t), value :: length
    end subroutine
    
    subroutine glCopyBufferSubData(readTarget, writeTarget, readOffset, &
                                  writeOffset, size) bind(C, name='glCopyBufferSubData')
      import :: c_int, c_intptr_t, c_size_t
      integer(c_int), value :: readTarget, writeTarget
      integer(c_intptr_t), value :: readOffset, writeOffset
      integer(c_size_t), value :: size
    end subroutine
    
    function glFenceSync(condition, flags) bind(C, name='glFenceSync')
      import :: c_int, c_ptr
      integer(c_int), value :: condition, flags
      type(c_ptr) :: glFenceSync
    end function
    
    function glClientWaitSync(sync, flags, timeout) bind(C, name='glClientWaitSync')
      import :: c_int, c_ptr, c_int64_t
      type(c_ptr), value :: sync
      integer(c_int), value :: flags
      integer(c_int64_t), value :: timeout
      integer(c_int) :: glClientWaitSync
    end function
    
    subroutine glDeleteSync(sync) bind(C, name='glDeleteSync')
      import :: c_ptr
      type(c_ptr), value :: sync
    end subroutine
  end interface
  
contains

  function summit_init() result(success)
    logical :: success
    integer :: i
    integer(c_size_t) :: buffer_size
    integer(c_int) :: staging_flags, device_flags
    integer(c_int), target :: ids(5)
    integer(c_int), target :: query_temp
    
    success = .false.
    
    if (.not. nvidia_gl_init()) then
      print *, "ERROR: Failed to initialize OpenGL"
      return
    end if
    
    print *, "=== Summit GPU Pipeline Initialization ==="
    print *, "Device-local VRAM buffers + staging ring"
    print *, "This is how dGPUs are meant to be used!"
    print *, ""
    
    ! Compile Summit kernel
    if (.not. compile_summit_kernel()) then
      print *, "ERROR: Failed to compile Summit kernel"
      return
    end if
    
    ! Buffer size (adjust as needed)
    buffer_size = 256 * 1024 * 1024  ! 256 MB max
    
    ! Staging flags: persistent, non-coherent, explicit flush
    staging_flags = ior(GL_MAP_WRITE_BIT, &
                   ior(GL_MAP_PERSISTENT_BIT, &
                   ior(GL_MAP_FLUSH_EXPLICIT_BIT, &
                       GL_CLIENT_STORAGE_BIT)))
    
    ! Device flags: just dynamic storage
    device_flags = GL_DYNAMIC_STORAGE_BIT
    
    ! Initialize each ring slot
    do i = 1, RING_DEPTH
      ! Generate buffer IDs
      call glGenBuffers(5, c_loc(ids))
      ring(i)%staging_input = ids(1)
      ring(i)%staging_kernel = ids(2)
      ring(i)%device_input = ids(3)
      ring(i)%device_kernel = ids(4)
      ring(i)%device_output = ids(5)
      
      ! Create staging buffers (host-visible)
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(i)%staging_input)
      call glBufferStorage(GL_SHADER_STORAGE_BUFFER, buffer_size, &
                          c_null_ptr, staging_flags)
      ring(i)%staging_input_ptr = glMapBufferRange(GL_SHADER_STORAGE_BUFFER, &
                                                  0_c_size_t, buffer_size, &
                                                  staging_flags)
      
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(i)%staging_kernel)
      call glBufferStorage(GL_SHADER_STORAGE_BUFFER, buffer_size, &
                          c_null_ptr, staging_flags)
      ring(i)%staging_kernel_ptr = glMapBufferRange(GL_SHADER_STORAGE_BUFFER, &
                                                   0_c_size_t, buffer_size, &
                                                   staging_flags)
      
      ! Create device buffers (VRAM-resident)
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(i)%device_input)
      call glBufferStorage(GL_SHADER_STORAGE_BUFFER, buffer_size, &
                          c_null_ptr, device_flags)
      
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(i)%device_kernel)
      call glBufferStorage(GL_SHADER_STORAGE_BUFFER, buffer_size, &
                          c_null_ptr, device_flags)
      
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(i)%device_output)
      call glBufferStorage(GL_SHADER_STORAGE_BUFFER, buffer_size, &
                          c_null_ptr, device_flags)
      
      ! Generate query for GPU timing
      call glGenQueries(1, c_loc(query_temp))
      ring(i)%query_id = query_temp
      
      ring(i)%in_flight = .false.
      print '(A,I0,A)', "  Ring slot ", i, " ready"
    end do
    
    initialized = .true.
    success = .true.
    
    print *, ""
    print *, "🏔️ Summit pipeline ready!"
    print *, "  - Device-local VRAM buffers"
    print *, "  - Non-coherent staging with explicit flush"
    print *, "  - 4-deep async ring"
    print *, "  - GPU timer queries"
    print *, ""
    
  end function summit_init
  
  function compile_summit_kernel() result(success)
    logical :: success
    ! TODO: Load and compile summit_kernel.glsl
    ! For now, use the existing conv2d_program
    summit_program = conv2d_program
    success = .true.
  end function compile_summit_kernel
  
  function summit_conv2d_async(input, kernel, output, &
                              batch, in_c, out_c, h, w, kh, kw, &
                              gpu_time_ns) result(success)
    real(sp), intent(in) :: input(*), kernel(*)
    real(sp), intent(out) :: output(*)
    integer, intent(in) :: batch, in_c, out_c, h, w, kh, kw
    integer(c_int64_t), intent(out) :: gpu_time_ns
    logical :: success
    
    integer :: slot, prev_slot
    integer(c_size_t) :: input_size, kernel_size
    integer(c_int) :: groups_x, groups_y, groups_z
    integer(c_int), target :: query_available
    integer(c_int64_t), target :: gpu_time_local
    type(c_ptr) :: fence
    real(sp), pointer :: staging_input(:), staging_kernel(:)
    
    success = .false.
    gpu_time_ns = 0
    
    if (.not. initialized) return
    
    ! Find next available slot (poll, don't block)
    slot = current_slot
    current_slot = mod(current_slot, RING_DEPTH) + 1
    
    ! Check if previous slot has GPU timing ready
    prev_slot = mod(slot + RING_DEPTH - 2, RING_DEPTH) + 1
    if (ring(prev_slot)%in_flight) then
      call glGetQueryObjectiv(ring(prev_slot)%query_id, &
                             GL_QUERY_RESULT_AVAILABLE, c_loc(query_available))
      if (query_available /= 0) then
        call glGetQueryObjecti64v(ring(prev_slot)%query_id, &
                                 GL_QUERY_RESULT, c_loc(gpu_time_local))
        gpu_time_ns = gpu_time_local
        ring(prev_slot)%in_flight = .false.
      end if
    end if
    
    ! Calculate sizes
    input_size = batch * in_c * h * w * 4
    kernel_size = out_c * in_c * kh * kw * 4
    
    ! Write to staging buffers
    call c_f_pointer(ring(slot)%staging_input_ptr, staging_input, &
                    [batch * in_c * h * w])
    call c_f_pointer(ring(slot)%staging_kernel_ptr, staging_kernel, &
                    [out_c * in_c * kh * kw])
    
    staging_input(1:batch*in_c*h*w) = input(1:batch*in_c*h*w)
    staging_kernel(1:out_c*in_c*kh*kw) = kernel(1:out_c*in_c*kh*kw)
    
    ! Flush staging buffers (critical for non-coherent!)
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(slot)%staging_input)
    call glFlushMappedBufferRange(GL_SHADER_STORAGE_BUFFER, 0_c_intptr_t, input_size)
    
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, ring(slot)%staging_kernel)
    call glFlushMappedBufferRange(GL_SHADER_STORAGE_BUFFER, 0_c_intptr_t, kernel_size)
    
    ! Copy staging → device (async DMA)
    call glCopyBufferSubData(GL_SHADER_STORAGE_BUFFER, GL_SHADER_STORAGE_BUFFER, &
                            0_c_intptr_t, 0_c_intptr_t, input_size)
    
    ! Bind device buffers
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, ring(slot)%device_input)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, ring(slot)%device_kernel)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, ring(slot)%device_output)
    
    ! Use Summit kernel
    call glUseProgram(summit_program)
    
    ! Calculate dispatch (32x32 tiles, 4 output channels per workgroup)
    groups_x = (w + 31) / 32
    groups_y = (h + 31) / 32
    groups_z = (out_c + 3) / 4
    
    ! Start GPU timer
    call glBeginQuery(GL_TIME_ELAPSED, ring(slot)%query_id)
    
    ! Dispatch!
    call glDispatchCompute(groups_x, groups_y, groups_z)
    
    ! End GPU timer
    call glEndQuery(GL_TIME_ELAPSED)
    
    ! Insert fence (non-blocking)
    fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
    ring(slot)%fence = fence
    ring(slot)%in_flight = .true.
    
    success = .true.
    
  end function summit_conv2d_async
  
  subroutine summit_shutdown()
    ! TODO: Clean up
    initialized = .false.
  end subroutine summit_shutdown

end module sporkle_nvidia_summit
