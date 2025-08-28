! GPU Unified Buffer Management
! ============================
!
! Zero-copy buffer abstraction for CPU/GPU shared memory
! Provides persistent mapped buffers with automatic synchronization

module gpu_unified_buffers
  use kinds
  use iso_c_binding
  use gpu_fence_primitives
  implicit none
  
  private
  public :: unified_buffer
  public :: create_unified_buffer, destroy_unified_buffer
  public :: get_buffer_pointer, buffer_is_valid
  public :: sync_buffer_to_gpu, sync_buffer_from_gpu
  public :: write_buffer, read_buffer
  public :: bind_buffer_to_shader
  public :: BUFFER_READ_ONLY, BUFFER_WRITE_ONLY, BUFFER_READ_WRITE
  public :: MEMORY_CPU_PREFERRED, MEMORY_GPU_PREFERRED, MEMORY_COHERENT, MEMORY_STREAMING
  
  ! Buffer access modes
  enum, bind(C)
    enumerator :: BUFFER_READ_ONLY = 1
    enumerator :: BUFFER_WRITE_ONLY = 2  
    enumerator :: BUFFER_READ_WRITE = 3
  end enum
  
  ! Memory hints
  enum, bind(C)
    enumerator :: MEMORY_CPU_PREFERRED = 1
    enumerator :: MEMORY_GPU_PREFERRED = 2
    enumerator :: MEMORY_COHERENT = 3
    enumerator :: MEMORY_STREAMING = 4
  end enum
  
  ! OpenGL constants
  integer(c_int), parameter :: GL_SHADER_STORAGE_BUFFER = int(z'90D2', c_int)
  integer(c_int), parameter :: GL_MAP_READ_BIT = int(z'0001', c_int)
  integer(c_int), parameter :: GL_MAP_WRITE_BIT = int(z'0002', c_int)
  integer(c_int), parameter :: GL_MAP_PERSISTENT_BIT = int(z'0040', c_int)
  integer(c_int), parameter :: GL_MAP_COHERENT_BIT = int(z'0080', c_int)
  integer(c_int), parameter :: GL_MAP_FLUSH_EXPLICIT_BIT = int(z'0010', c_int)
  integer(c_int), parameter :: GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT = int(z'4000', c_int)
  integer(c_int), parameter :: GL_DYNAMIC_STORAGE_BIT = int(z'0100', c_int)
  
  ! Unified buffer type
  type :: unified_buffer
    private
    integer :: gl_buffer = 0
    type(c_ptr) :: cpu_ptr = c_null_ptr
    integer(i64) :: size_bytes = 0
    integer :: access_mode = BUFFER_READ_WRITE
    integer :: memory_hint = MEMORY_COHERENT
    logical :: is_mapped = .false.
    logical :: is_coherent = .true.
    type(gpu_fence) :: sync_fence
  end type
  
  ! Generic interfaces for type safety
  interface write_buffer
    module procedure write_buffer_f32, write_buffer_f64, write_buffer_i32
  end interface
  
  interface read_buffer
    module procedure read_buffer_f32, read_buffer_f64, read_buffer_i32
  end interface
  
  ! OpenGL interfaces
  interface
    subroutine glGenBuffers(n, buffers) bind(C, name="glGenBuffers")
      import :: c_int
      integer(c_int), value :: n
      integer(c_int), intent(out) :: buffers(*)
    end subroutine
    
    subroutine glDeleteBuffers(n, buffers) bind(C, name="glDeleteBuffers")
      import :: c_int
      integer(c_int), value :: n
      integer(c_int), intent(in) :: buffers(*)
    end subroutine
    
    subroutine glBindBuffer(target, buffer) bind(C, name="glBindBuffer")
      import :: c_int
      integer(c_int), value :: target, buffer
    end subroutine
    
    subroutine glBufferStorage(target, size, data, flags) bind(C, name="glBufferStorage")
      import :: c_int, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
      integer(c_int), value :: flags
    end subroutine
    
    function glMapBufferRange(target, offset, length, access) bind(C, name="glMapBufferRange")
      import :: c_ptr, c_int, c_intptr_t, c_size_t
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
    
    subroutine glFlushMappedBufferRange(target, offset, length) bind(C, name="glFlushMappedBufferRange")
      import :: c_int, c_intptr_t, c_size_t
      integer(c_int), value :: target
      integer(c_intptr_t), value :: offset
      integer(c_size_t), value :: length
    end subroutine
    
    subroutine glMemoryBarrier(barriers) bind(C, name="glMemoryBarrier")
      import :: c_int
      integer(c_int), value :: barriers
    end subroutine
    
    subroutine glBindBufferBase(target, index, buffer) bind(C, name="glBindBufferBase")
      import :: c_int
      integer(c_int), value :: target, index, buffer
    end subroutine
    
    function glGetError() bind(C, name="glGetError")
      import :: c_int
      integer(c_int) :: glGetError
    end function
  end interface
  
contains

  ! Create a unified buffer with persistent mapping
  function create_unified_buffer(size, access_mode, memory_hint) result(buffer)
    integer(i64), intent(in) :: size
    integer, intent(in) :: access_mode
    integer, intent(in), optional :: memory_hint
    type(unified_buffer) :: buffer
    
    integer :: buffers(1)
    integer(c_int) :: storage_flags, map_flags
    integer(c_int) :: gl_error
    
    ! Initialize buffer
    buffer%size_bytes = size
    buffer%access_mode = access_mode
    if (present(memory_hint)) then
      buffer%memory_hint = memory_hint
    else
      buffer%memory_hint = MEMORY_COHERENT
    end if
    
    ! Generate buffer
    call glGenBuffers(1, buffers)
    buffer%gl_buffer = buffers(1)
    if (buffer%gl_buffer == 0) then
      print *, "Failed to generate buffer"
      return
    end if
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer%gl_buffer)
    
    ! Determine storage flags based on access mode and hint
    storage_flags = 0
    map_flags = GL_MAP_PERSISTENT_BIT
    
    select case(access_mode)
    case(BUFFER_READ_ONLY)
      storage_flags = ior(storage_flags, GL_MAP_READ_BIT)
      map_flags = ior(map_flags, GL_MAP_READ_BIT)
      
    case(BUFFER_WRITE_ONLY)
      storage_flags = ior(storage_flags, GL_MAP_WRITE_BIT)
      map_flags = ior(map_flags, GL_MAP_WRITE_BIT)
      
    case(BUFFER_READ_WRITE)
      storage_flags = ior(storage_flags, ior(GL_MAP_READ_BIT, GL_MAP_WRITE_BIT))
      map_flags = ior(map_flags, ior(GL_MAP_READ_BIT, GL_MAP_WRITE_BIT))
    end select
    
    ! Add coherent flag for simplicity (can optimize later)
    if (buffer%memory_hint == MEMORY_COHERENT) then
      storage_flags = ior(storage_flags, GL_MAP_COHERENT_BIT)
      map_flags = ior(map_flags, GL_MAP_COHERENT_BIT)
      buffer%is_coherent = .true.
    else
      storage_flags = ior(storage_flags, GL_MAP_FLUSH_EXPLICIT_BIT)
      map_flags = ior(map_flags, GL_MAP_FLUSH_EXPLICIT_BIT)
      buffer%is_coherent = .false.
    end if
    
    storage_flags = ior(storage_flags, GL_MAP_PERSISTENT_BIT)
    
    ! Create immutable storage
    print '(A,I0,A,Z8)', "Creating buffer: size=", size, ", flags=0x", storage_flags
    call glBufferStorage(GL_SHADER_STORAGE_BUFFER, &
                        int(size, c_size_t), &
                        c_null_ptr, &
                        storage_flags)
    
    gl_error = glGetError()
    if (gl_error /= 0) then
      print '(A,Z8)', "glBufferStorage error: 0x", gl_error
      buffer%gl_buffer = 0
      return
    end if
    
    ! Map the buffer persistently
    buffer%cpu_ptr = glMapBufferRange(GL_SHADER_STORAGE_BUFFER, &
                                     0_c_intptr_t, &
                                     int(size, c_size_t), &
                                     map_flags)
    
    if (c_associated(buffer%cpu_ptr)) then
      buffer%is_mapped = .true.
    else
      ! Mapping failed - cleanup
      gl_error = glGetError()
      print '(A,Z8)', "glMapBufferRange error: 0x", gl_error
      buffers(1) = buffer%gl_buffer
      call glDeleteBuffers(1, buffers)
      buffer%gl_buffer = 0
    end if
    
  end function create_unified_buffer
  
  ! Destroy unified buffer
  subroutine destroy_unified_buffer(buffer)
    type(unified_buffer), intent(inout) :: buffer
    integer :: buffers(1)
    integer :: wait_status
    
    if (buffer%gl_buffer == 0) return
    
    ! Wait for any pending operations
    if (gpu_fence_is_valid(buffer%sync_fence)) then
      wait_status = gpu_fence_wait(buffer%sync_fence, FENCE_INFINITE_TIMEOUT)
      call gpu_fence_destroy(buffer%sync_fence)
    end if
    
    ! Unmap if mapped
    if (buffer%is_mapped) then
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer%gl_buffer)
      if (glUnmapBuffer(GL_SHADER_STORAGE_BUFFER) == 0) then
        ! Unmapping can fail but we still need to cleanup
      end if
    end if
    
    ! Delete buffer
    buffers(1) = buffer%gl_buffer
    call glDeleteBuffers(1, buffers)
    
    ! Reset structure
    buffer%gl_buffer = 0
    buffer%cpu_ptr = c_null_ptr
    buffer%is_mapped = .false.
    
  end subroutine destroy_unified_buffer
  
  ! Get raw pointer for direct access
  function get_buffer_pointer(buffer) result(ptr)
    type(unified_buffer), intent(in) :: buffer
    type(c_ptr) :: ptr
    ptr = buffer%cpu_ptr
  end function get_buffer_pointer
  
  ! Check if buffer is valid
  function buffer_is_valid(buffer) result(valid)
    type(unified_buffer), intent(in) :: buffer
    logical :: valid
    valid = (buffer%gl_buffer /= 0) .and. buffer%is_mapped .and. c_associated(buffer%cpu_ptr)
  end function buffer_is_valid
  
  ! Sync buffer for GPU access
  subroutine sync_buffer_to_gpu(buffer, offset, length)
    type(unified_buffer), intent(inout) :: buffer
    integer(i64), intent(in), optional :: offset, length
    
    if (.not. buffer%is_coherent) then
      ! Need explicit flush for non-coherent
      if (present(offset) .and. present(length)) then
        call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer%gl_buffer)
        call glFlushMappedBufferRange(GL_SHADER_STORAGE_BUFFER, &
                                     int(offset, c_intptr_t), &
                                     int(length, c_size_t))
      else
        ! Flush entire buffer
        call glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer%gl_buffer)
        call glFlushMappedBufferRange(GL_SHADER_STORAGE_BUFFER, &
                                     0_c_intptr_t, &
                                     int(buffer%size_bytes, c_size_t))
      end if
    end if
    
    ! Memory barrier to ensure GPU sees writes
    call glMemoryBarrier(GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT)
    
    ! Create fence for synchronization
    if (gpu_fence_is_valid(buffer%sync_fence)) then
      call gpu_fence_destroy(buffer%sync_fence)
    end if
    buffer%sync_fence = gpu_fence_create()
    
  end subroutine sync_buffer_to_gpu
  
  ! Wait for GPU operations to complete
  subroutine sync_buffer_from_gpu(buffer)
    type(unified_buffer), intent(inout) :: buffer
    integer :: wait_status
    
    if (gpu_fence_is_valid(buffer%sync_fence)) then
      wait_status = gpu_fence_wait(buffer%sync_fence, FENCE_INFINITE_TIMEOUT)
      call gpu_fence_destroy(buffer%sync_fence)
    end if
    
  end subroutine sync_buffer_from_gpu
  
  ! Type-specific write operations
  subroutine write_buffer_f32(buffer, data, offset)
    type(unified_buffer), intent(inout) :: buffer
    real(sp), intent(in) :: data(:)
    integer(i64), intent(in), optional :: offset
    
    real(sp), pointer :: ptr(:)
    integer(i64) :: start_idx
    
    if (.not. buffer_is_valid(buffer)) return
    
    call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/4])
    
    if (present(offset)) then
      start_idx = offset/4 + 1
    else
      start_idx = 1
    end if
    
    ptr(start_idx:start_idx+size(data)-1) = data
    
    if (.not. buffer%is_coherent) then
      call sync_buffer_to_gpu(buffer, offset, int(size(data)*4, i64))
    end if
    
  end subroutine write_buffer_f32
  
  subroutine write_buffer_f64(buffer, data, offset)
    type(unified_buffer), intent(inout) :: buffer
    real(dp), intent(in) :: data(:)
    integer(i64), intent(in), optional :: offset
    
    real(dp), pointer :: ptr(:)
    integer(i64) :: start_idx
    
    if (.not. buffer_is_valid(buffer)) return
    
    call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/8])
    
    if (present(offset)) then
      start_idx = offset/8 + 1
    else
      start_idx = 1
    end if
    
    ptr(start_idx:start_idx+size(data)-1) = data
    
    if (.not. buffer%is_coherent) then
      call sync_buffer_to_gpu(buffer, offset, int(size(data)*8, i64))
    end if
    
  end subroutine write_buffer_f64
  
  subroutine write_buffer_i32(buffer, data, offset)
    type(unified_buffer), intent(inout) :: buffer
    integer(i32), intent(in) :: data(:)
    integer(i64), intent(in), optional :: offset
    
    integer(i32), pointer :: ptr(:)
    integer(i64) :: start_idx
    
    if (.not. buffer_is_valid(buffer)) return
    
    call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/4])
    
    if (present(offset)) then
      start_idx = offset/4 + 1
    else
      start_idx = 1
    end if
    
    ptr(start_idx:start_idx+size(data)-1) = data
    
    if (.not. buffer%is_coherent) then
      call sync_buffer_to_gpu(buffer, offset, int(size(data)*4, i64))
    end if
    
  end subroutine write_buffer_i32
  
  ! Type-specific read operations
  subroutine read_buffer_f32(buffer, data, offset)
    type(unified_buffer), intent(in) :: buffer
    real(sp), intent(out) :: data(:)
    integer(i64), intent(in), optional :: offset
    
    real(sp), pointer :: ptr(:)
    integer(i64) :: start_idx
    
    if (.not. buffer_is_valid(buffer)) return
    
    call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/4])
    
    if (present(offset)) then
      start_idx = offset/4 + 1
    else
      start_idx = 1
    end if
    
    data = ptr(start_idx:start_idx+size(data)-1)
    
  end subroutine read_buffer_f32
  
  subroutine read_buffer_f64(buffer, data, offset)
    type(unified_buffer), intent(in) :: buffer
    real(dp), intent(out) :: data(:)
    integer(i64), intent(in), optional :: offset
    
    real(dp), pointer :: ptr(:)
    integer(i64) :: start_idx
    
    if (.not. buffer_is_valid(buffer)) return
    
    call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/8])
    
    if (present(offset)) then
      start_idx = offset/8 + 1
    else
      start_idx = 1
    end if
    
    data = ptr(start_idx:start_idx+size(data)-1)
    
  end subroutine read_buffer_f64
  
  subroutine read_buffer_i32(buffer, data, offset)
    type(unified_buffer), intent(in) :: buffer
    integer(i32), intent(out) :: data(:)
    integer(i64), intent(in), optional :: offset
    
    integer(i32), pointer :: ptr(:)
    integer(i64) :: start_idx
    
    if (.not. buffer_is_valid(buffer)) return
    
    call c_f_pointer(buffer%cpu_ptr, ptr, [buffer%size_bytes/4])
    
    if (present(offset)) then
      start_idx = offset/4 + 1
    else
      start_idx = 1
    end if
    
    data = ptr(start_idx:start_idx+size(data)-1)
    
  end subroutine read_buffer_i32
  
  ! Bind buffer to shader slot
  subroutine bind_buffer_to_shader(buffer, binding_point)
    type(unified_buffer), intent(in) :: buffer
    integer, intent(in) :: binding_point
    
    if (buffer%gl_buffer /= 0) then
      call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, binding_point, buffer%gl_buffer)
    end if
    
  end subroutine bind_buffer_to_shader
  
end module gpu_unified_buffers