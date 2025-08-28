module gpu_async_executor_fixed
  use iso_c_binding,  only: c_int, c_uint, c_ptr, c_null_ptr, c_intptr_t, c_size_t, c_int64_t, c_loc
  use kinds
  implicit none
  
  private
  public :: gpu_async_state, gpu_async_init, gpu_async_cleanup
  public :: gpu_submit_conv2d, gpu_poll_complete, gpu_gather_output
  public :: gpu_conv2d_sync, gpu_async_policy
  
  ! OpenGL constants
  integer(c_int), parameter :: GL_SHADER_STORAGE_BUFFER = int(z'90D2', c_int)
  integer(c_int), parameter :: GL_SHADER_STORAGE_BARRIER_BIT = int(z'2000', c_int)
  integer(c_int), parameter :: GL_DYNAMIC_DRAW = int(z'88E8', c_int)
  integer(c_int), parameter :: GL_DYNAMIC_COPY = int(z'88EA', c_int)
  
  ! Sync constants
  integer(c_int), parameter :: GL_SYNC_GPU_COMMANDS_COMPLETE = int(z'9117', c_int)
  integer(c_int), parameter :: GL_SYNC_FLUSH_COMMANDS_BIT = int(z'00000001', c_int)
  integer(c_int), parameter :: GL_ALREADY_SIGNALED = int(z'911A', c_int)
  integer(c_int), parameter :: GL_TIMEOUT_EXPIRED = int(z'911B', c_int)
  integer(c_int), parameter :: GL_CONDITION_SATISFIED = int(z'911C', c_int)
  integer(c_int), parameter :: GL_WAIT_FAILED = int(z'911D', c_int)

  ! === Types: make GL handles explicit; add timing fields ===
  type :: buffer_set
    integer(c_uint) :: input_buffer  = 0_c_uint
    integer(c_uint) :: output_buffer = 0_c_uint
    type(c_ptr)     :: fence         = c_null_ptr
    logical         :: in_use        = .false.
    integer(i64)  :: submit_ticks  = 0_int64
    integer(i64)  :: complete_ticks= 0_int64
  end type

  type :: gpu_async_policy
    integer(c_int)  :: max_in_flight = 3_c_int
    logical         :: collect_stats = .true.
  end type

  type :: gpu_async_state
    type(buffer_set), allocatable :: sets(:)
    integer(c_uint)               :: compute_program = 0_c_uint
    integer(c_uint)               :: weight_buffer = 0_c_uint
    type(gpu_async_policy)        :: policy
    integer(i64)                :: clock_rate = 0_int64  ! system_clock ticks per second
    ! optional running totals…
    integer(i64)                :: total_gpu_ticks = 0_int64
    integer(i64)                :: total_wait_ticks = 0_int64
    integer                       :: completed_operations = 0
    logical                       :: initialized = .false.
    ! Buffer capacities (allocated once)
    integer(c_size_t)             :: input_capacity = 0_c_size_t
    integer(c_size_t)             :: output_capacity = 0_c_size_t
  end type
  
  ! C interfaces
  interface
    subroutine glGenBuffers(n, buffers) bind(C, name="glGenBuffers")
      import :: c_int, c_uint
      integer(c_int), value :: n
      integer(c_uint), intent(out) :: buffers
    end subroutine
    
    subroutine glDeleteBuffers(n, buffers) bind(C, name="glDeleteBuffers")
      import :: c_int, c_uint
      integer(c_int), value :: n
      integer(c_uint), intent(in) :: buffers
    end subroutine
    
    subroutine glBindBuffer(target, buffer) bind(C, name="glBindBuffer")
      import :: c_int, c_uint
      integer(c_int), value :: target
      integer(c_uint), value :: buffer
    end subroutine
    
    subroutine glBufferData(target, size, data, usage) bind(C, name="glBufferData")
      import :: c_int, c_size_t, c_ptr
      integer(c_int), value :: target, usage
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
    end subroutine
    
    subroutine glBufferSubData(target, offset, size, data) bind(C, name="glBufferSubData")
      import :: c_int, c_intptr_t, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_intptr_t), value :: offset
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
    end subroutine
    
    subroutine glBindBufferBase(target, index, buffer) bind(C, name="glBindBufferBase")
      import :: c_int, c_uint
      integer(c_int), value :: target, index
      integer(c_uint), value :: buffer
    end subroutine
    
    subroutine glUseProgram(program) bind(C, name="glUseProgram")
      import :: c_uint
      integer(c_uint), value :: program
    end subroutine
    
    subroutine glDispatchCompute(num_groups_x, num_groups_y, num_groups_z) bind(C, name="glDispatchCompute")
      import :: c_int
      integer(c_int), value :: num_groups_x, num_groups_y, num_groups_z
    end subroutine
    
    function glFenceSync(condition, flags) bind(C, name="glFenceSync") result(sync)
      import :: c_ptr, c_int
      integer(c_int), value :: condition, flags
      type(c_ptr) :: sync
    end function
    
    function glClientWaitSync(sync, flags, timeout) bind(C, name="glClientWaitSync") result(status)
      import :: c_ptr, c_int, c_, i64_t
      type(c_ptr), value :: sync
      integer(c_int), value :: flags
      integer(c_int64_t), value :: timeout
      integer(c_int) :: status
    end function
    
    subroutine glDeleteSync(sync) bind(C, name="glDeleteSync")
      import :: c_ptr
      type(c_ptr), value :: sync
    end subroutine
    
    subroutine glMemoryBarrier(barriers) bind(C, name="glMemoryBarrier")
      import :: c_int
      integer(c_int), value :: barriers
    end subroutine
    
    subroutine glGetBufferSubData(target, offset, size, data) bind(C, name="glGetBufferSubData")
      import :: c_int, c_intptr_t, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_intptr_t), value :: offset
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
    end subroutine
  end interface

contains

  ! === Timing helpers ===
  pure function ticks_now() result(t)
    integer(i64) :: t
    call system_clock(count=t)
  end function

  pure function ticks_to_ns(ticks, rate) result(ns)
    integer(i64), intent(in) :: ticks, rate
    integer(i64) :: ns
    if (rate <= 0_int64) then
       ns = 0_int64
    else
       ! ns = ticks * 1e9 / rate  (all int64)
       ns = (ticks * 1000000000_int64) / rate
    end if
  end function

  ! === Initialize ===
  subroutine gpu_async_init(state, program, weight_buffer, max_sets)
    type(gpu_async_state), intent(out) :: state
    integer(c_uint),       intent(in)  :: program
    integer(c_uint),       intent(in)  :: weight_buffer
    integer(c_int),        intent(in), optional :: max_sets
    integer :: rate, i
    integer(c_size_t), parameter :: MAX_BUFFER_SIZE = 256_c_size_t * 1024 * 1024  ! 256MB

    call system_clock(count_rate=rate)
    state%clock_rate = int(rate, int64)
    state%compute_program = program
    state%weight_buffer = weight_buffer
    state%policy%max_in_flight = merge(max_sets, 3_c_int, present(max_sets))
    
    ! Allocate buffer sets
    allocate(state%sets(state%policy%max_in_flight))
    
    ! Set buffer capacities
    state%input_capacity = MAX_BUFFER_SIZE
    state%output_capacity = MAX_BUFFER_SIZE
    
    ! Create SSBOs once with maximum capacity
    do i = 1, state%policy%max_in_flight
      call glGenBuffers(1, state%sets(i)%input_buffer)
      call glGenBuffers(1, state%sets(i)%output_buffer)
      
      ! Allocate buffers with max capacity
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%sets(i)%input_buffer)
      call glBufferData(GL_SHADER_STORAGE_BUFFER, state%input_capacity, c_null_ptr, GL_DYNAMIC_DRAW)
      
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%sets(i)%output_buffer)
      call glBufferData(GL_SHADER_STORAGE_BUFFER, state%output_capacity, c_null_ptr, GL_DYNAMIC_COPY)
      
      state%sets(i)%fence = c_null_ptr
      state%sets(i)%in_use = .false.
    end do
    
    state%initialized = .true.
    print '(A,I0,A)', "✅ GPU Async Executor (fixed) initialized with ", state%policy%max_in_flight, " buffer sets"
  end subroutine

  ! === Oldest-first / already-signaled selection ===
  integer function select_reusable_set(state) result(idx)
    type(gpu_async_state), intent(in) :: state
    integer :: i
    integer :: oldest_i
    logical :: any_in_use
    integer(i64) :: oldest_ticks

    idx = 0
    any_in_use   = .false.
    oldest_ticks = huge(oldest_ticks)
    oldest_i     = 0

    ! 1) Prefer any signaled fence
    do i = 1, size(state%sets)
      if (state%sets(i)%in_use) then
        any_in_use = .true.
        if (gpu_is_work_complete(state%sets(i)%fence)) then
          idx = i
          return
        end if
      end if
    end do

    ! 2) If none are signaled, take oldest in-flight
    if (any_in_use) then
      do i = 1, size(state%sets)
        if (state%sets(i)%in_use) then
          if (state%sets(i)%submit_ticks < oldest_ticks) then
            oldest_ticks = state%sets(i)%submit_ticks
            oldest_i     = i
          end if
        end if
      end do
      idx = oldest_i
      return
    end if

    ! 3) If none in use, take first free
    do i = 1, size(state%sets)
      if (.not. state%sets(i)%in_use) then
        idx = i
        return
      end if
    end do
  end function

  logical function gpu_is_work_complete(fence) result(complete)
    type(c_ptr), intent(in) :: fence
    integer(c_int) :: wait_result
    
    complete = .false.
    if (.not. c_associated(fence)) return
    
    ! Check without waiting
    wait_result = glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, 0_c_int64_t)
    complete = (wait_result == GL_ALREADY_SIGNALED .or. &
                wait_result == GL_CONDITION_SATISFIED)
  end function

  subroutine gpu_wait_for_completion(fence)
    type(c_ptr), intent(in) :: fence
    integer(c_int) :: wait_result
    integer(c_int64_t), parameter :: timeout_ns = 1000000000_c_int64_t  ! 1 second
    
    if (.not. c_associated(fence)) return
    
    wait_result = glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, timeout_ns)
    
    if (wait_result == GL_WAIT_FAILED) then
      print *, "⚠️  GPU sync wait failed"
    else if (wait_result == GL_TIMEOUT_EXPIRED) then
      print *, "⚠️  GPU sync timeout"
    end if
  end subroutine

  ! === Truly async API ===
  
  ! Submit work; returns set_id you can poll later.
  integer(c_int) function gpu_submit_conv2d(state, input_data, output_data, &
                                           input_bytes, output_bytes, &
                                           grid_x, grid_y, grid_z) result(set_id)
    type(gpu_async_state), intent(inout) :: state
    real(sp), intent(in), target :: input_data(*)
    real(sp), intent(out), target :: output_data(*)  ! For address only
    integer(c_size_t), intent(in) :: input_bytes, output_bytes
    integer(c_int), intent(in) :: grid_x, grid_y, grid_z
    integer :: i
    integer(i64) :: now

    i = select_reusable_set(state)
    if (i <= 0) then
      ! Should not happen; fallback
      i = 1
    end if

    ! If the chosen set is still in use, block minimally to reclaim it.
    if (state%sets(i)%in_use) then
      call gpu_wait_for_completion(state%sets(i)%fence)
      state%sets(i)%complete_ticks = ticks_now()
      if (c_associated(state%sets(i)%fence)) then
        call glDeleteSync(state%sets(i)%fence)
        state%sets(i)%fence = c_null_ptr
      end if
      state%sets(i)%in_use = .false.
    end if

    ! Reuse buffers: glBufferSubData instead of glBufferData
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%sets(i)%input_buffer)
    call glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0_c_intptr_t, input_bytes, c_loc(input_data))

    ! No need to reallocate output buffer - it's pre-allocated

    ! Bind SSBOs to expected binding points
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0_c_int, state%sets(i)%input_buffer)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1_c_int, state%weight_buffer)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2_c_int, state%sets(i)%output_buffer)
    
    ! Bind program and dispatch
    call glUseProgram(state%compute_program)
    call glDispatchCompute(grid_x, grid_y, grid_z)
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

    ! Fence
    state%sets(i)%fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0_c_int)
    state%sets(i)%in_use = .true.

    now = ticks_now()
    state%sets(i)%submit_ticks = now

    set_id = int(i, c_int)
  end function

  logical function gpu_poll_complete(state, set_id) result(done)
    type(gpu_async_state), intent(inout) :: state
    integer(c_int),        intent(in)    :: set_id
    integer :: i
    
    i = set_id
    if (i < 1 .or. i > size(state%sets)) then
      done = .false.
      return
    end if
    
    done = gpu_is_work_complete(state%sets(i)%fence)
    if (done .and. state%sets(i)%complete_ticks == 0) then
      state%sets(i)%complete_ticks = ticks_now()
    end if
  end function

  subroutine gpu_gather_output(state, set_id, output_data, output_bytes)
    type(gpu_async_state), intent(inout) :: state
    integer(c_int),        intent(in)    :: set_id
    real(sp), intent(out), target    :: output_data(*)
    integer(c_size_t),     intent(in)    :: output_bytes
    integer :: i
    integer(i64) :: dt

    i = set_id
    if (i < 1 .or. i > size(state%sets)) return

    ! If not finished, block briefly to complete
    if (.not. gpu_poll_complete(state, set_id)) then
      call gpu_wait_for_completion(state%sets(i)%fence)
      state%sets(i)%complete_ticks = ticks_now()
    end if

    ! Read back result
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%sets(i)%output_buffer)
    call glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0_c_intptr_t, output_bytes, c_loc(output_data))

    ! Stats
    if (state%policy%collect_stats .and. state%sets(i)%submit_ticks > 0) then
      dt = state%sets(i)%complete_ticks - state%sets(i)%submit_ticks
      state%total_gpu_ticks = state%total_gpu_ticks + max(0_int64, dt)
      state%completed_operations = state%completed_operations + 1
    end if

    ! Cleanup this in-flight slot
    if (c_associated(state%sets(i)%fence)) then
      call glDeleteSync(state%sets(i)%fence)
      state%sets(i)%fence = c_null_ptr
    end if
    state%sets(i)%in_use = .false.
    state%sets(i)%submit_ticks = 0
    state%sets(i)%complete_ticks = 0
  end subroutine

  ! === Sync wrapper for compatibility ===
  subroutine gpu_conv2d_sync(state, input_data, output_data, &
                            input_bytes, output_bytes, &
                            grid_x, grid_y, grid_z)
    type(gpu_async_state), intent(inout) :: state
    real(sp), intent(in), target :: input_data(*)
    real(sp), intent(out), target :: output_data(*)
    integer(c_size_t), intent(in) :: input_bytes, output_bytes
    integer(c_int), intent(in) :: grid_x, grid_y, grid_z
    integer(c_int) :: id
    
    id = gpu_submit_conv2d(state, input_data, output_data, &
                          input_bytes, output_bytes, grid_x, grid_y, grid_z)
    call gpu_gather_output(state, id, output_data, output_bytes)
  end subroutine

  ! === Cleanup ===
  subroutine gpu_async_cleanup(state)
    type(gpu_async_state), intent(inout) :: state
    integer :: i
    real :: avg_gpu_ms, total_gpu_s
    
    if (.not. state%initialized) return
    
    ! Wait for all pending operations
    do i = 1, size(state%sets)
      if (state%sets(i)%in_use) then
        call gpu_wait_for_completion(state%sets(i)%fence)
        if (c_associated(state%sets(i)%fence)) then
          call glDeleteSync(state%sets(i)%fence)
        end if
      end if
    end do
    
    ! Clean up buffers
    do i = 1, size(state%sets)
      if (state%sets(i)%input_buffer /= 0) then
        call glDeleteBuffers(1, state%sets(i)%input_buffer)
      end if
      if (state%sets(i)%output_buffer /= 0) then
        call glDeleteBuffers(1, state%sets(i)%output_buffer)
      end if
    end do
    
    ! Report statistics
    if (state%completed_operations > 0 .and. state%policy%collect_stats) then
      avg_gpu_ms = real(ticks_to_ns(state%total_gpu_ticks / state%completed_operations, &
                                    state%clock_rate)) / 1.0e6
      total_gpu_s = real(ticks_to_ns(state%total_gpu_ticks, state%clock_rate)) / 1.0e9
      
      print *, ""
      print *, "=== Async Executor Statistics (Fixed) ==="
      print *, "Completed operations:", state%completed_operations
      print '(A,F8.2,A)', "Average GPU time per op: ", avg_gpu_ms, " ms"
      print '(A,F8.2,A)', "Total GPU compute time: ", total_gpu_s, " seconds"
    end if
    
    deallocate(state%sets)
    state%initialized = .false.
  end subroutine

end module gpu_async_executor_fixed