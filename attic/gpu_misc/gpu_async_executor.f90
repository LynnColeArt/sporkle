module gpu_async_executor
  use iso_c_binding
  use kinds
  implicit none
  
  private
  public :: gpu_async_state, gpu_async_executor_init, gpu_async_executor_cleanup
  public :: gpu_submit_work_async, gpu_wait_for_completion, gpu_is_work_complete
  public :: gpu_get_next_buffer_set, gpu_async_conv2d, MAX_IN_FLIGHT
  
  ! Maximum number of in-flight operations
  integer, parameter :: MAX_IN_FLIGHT = 3
  
  ! OpenGL constants needed for async execution
  integer(c_int), parameter :: GL_SHADER_STORAGE_BUFFER = int(z'90D2', c_int)
  integer(c_int), parameter :: GL_SHADER_STORAGE_BARRIER_BIT = int(z'2000', c_int)
  integer(c_int), parameter :: GL_DYNAMIC_DRAW = int(z'88E8', c_int)
  integer(c_int), parameter :: GL_DYNAMIC_COPY = int(z'88EA', c_int)
  
  ! OpenGL sync object type
  type(c_ptr), parameter :: GL_SYNC_NULL = c_null_ptr
  
  ! Sync constants (from GL spec)
  integer(c_int), parameter :: GL_SYNC_GPU_COMMANDS_COMPLETE = int(z'9117', c_int)
  integer(c_int), parameter :: GL_SYNC_FLUSH_COMMANDS_BIT = int(z'00000001', c_int)
  integer(c_int), parameter :: GL_ALREADY_SIGNALED = int(z'911A', c_int)
  integer(c_int), parameter :: GL_TIMEOUT_EXPIRED = int(z'911B', c_int)
  integer(c_int), parameter :: GL_CONDITION_SATISFIED = int(z'911C', c_int)
  integer(c_int), parameter :: GL_WAIT_FAILED = int(z'911D', c_int)
  
  ! Buffer state
  type :: buffer_set
    integer :: input_buffer = 0
    integer :: output_buffer = 0
    type(c_ptr) :: fence
    logical :: in_use = .false.
    integer(i64) :: submit_time = 0
    integer(i64) :: complete_time = 0
  end type buffer_set
  
  ! Async executor state
  type :: gpu_async_state
    ! Triple buffered sets
    type(buffer_set) :: buffer_sets(MAX_IN_FLIGHT)
    integer :: current_set = 1
    
    ! Shared resources
    integer :: weight_buffer = 0
    integer :: compute_program = 0
    
    ! Statistics
    integer(i64) :: total_gpu_time = 0
    integer(i64) :: total_idle_time = 0
    integer :: completed_operations = 0
    
    ! Configuration
    logical :: initialized = .false.
    integer :: max_workgroup_size = 256
  end type gpu_async_state
  
  ! C interfaces for OpenGL functions
  interface
    subroutine glGenBuffers(n, buffers) bind(C, name="glGenBuffers")
      import :: c_int
      integer(c_int), value :: n
      integer(c_int), intent(out) :: buffers
    end subroutine glGenBuffers
    
    subroutine glDeleteBuffers(n, buffers) bind(C, name="glDeleteBuffers")
      import :: c_int
      integer(c_int), value :: n
      integer(c_int), intent(in) :: buffers
    end subroutine glDeleteBuffers
    
    subroutine glBindBuffer(target, buffer) bind(C, name="glBindBuffer")
      import :: c_int
      integer(c_int), value :: target, buffer
    end subroutine glBindBuffer
    
    subroutine glBufferData(target, size, data, usage) bind(C, name="glBufferData")
      import :: c_int, c_size_t, c_ptr
      integer(c_int), value :: target, usage
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
    end subroutine glBufferData
    
    subroutine glBindBufferBase(target, index, buffer) bind(C, name="glBindBufferBase")
      import :: c_int
      integer(c_int), value :: target, index, buffer
    end subroutine glBindBufferBase
    
    subroutine glUseProgram(program) bind(C, name="glUseProgram")
      import :: c_int
      integer(c_int), value :: program
    end subroutine glUseProgram
    
    subroutine glDispatchCompute(num_groups_x, num_groups_y, num_groups_z) bind(C, name="glDispatchCompute")
      import :: c_int
      integer(c_int), value :: num_groups_x, num_groups_y, num_groups_z
    end subroutine glDispatchCompute
    
    function glFenceSync(condition, flags) bind(C, name="glFenceSync") result(sync)
      import :: c_ptr, c_int
      integer(c_int), value :: condition, flags
      type(c_ptr) :: sync
    end function glFenceSync
    
    function glClientWaitSync(sync, flags, timeout) bind(C, name="glClientWaitSync") result(status)
      import :: c_ptr, c_int, c_int64_t
      type(c_ptr), value :: sync
      integer(c_int), value :: flags
      integer(c_int64_t), value :: timeout
      integer(c_int) :: status
    end function glClientWaitSync
    
    subroutine glDeleteSync(sync) bind(C, name="glDeleteSync")
      import :: c_ptr
      type(c_ptr), value :: sync
    end subroutine glDeleteSync
    
    subroutine glMemoryBarrier_async(barriers) bind(C, name="glMemoryBarrier")
      import :: c_int
      integer(c_int), value :: barriers
    end subroutine glMemoryBarrier_async
    
    subroutine glGetBufferSubData(target, offset, size, data) bind(C, name="glGetBufferSubData")
      import :: c_int, c_intptr_t, c_size_t, c_ptr
      integer(c_int), value :: target
      integer(c_intptr_t), value :: offset
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
    end subroutine glGetBufferSubData
  end interface
  
contains

  subroutine gpu_async_executor_init(state, compute_program, weight_buffer)
    type(gpu_async_state), intent(out) :: state
    integer, intent(in) :: compute_program
    integer, intent(in) :: weight_buffer
    integer :: i
    
    ! Initialize state
    state%compute_program = compute_program
    state%weight_buffer = weight_buffer
    state%current_set = 1
    state%total_gpu_time = 0
    state%total_idle_time = 0
    state%completed_operations = 0
    
    ! Create buffer sets
    do i = 1, MAX_IN_FLIGHT
      ! Create input/output buffers for this set
      call glGenBuffers(1, state%buffer_sets(i)%input_buffer)
      call glGenBuffers(1, state%buffer_sets(i)%output_buffer)
      
      state%buffer_sets(i)%fence = GL_SYNC_NULL
      state%buffer_sets(i)%in_use = .false.
    end do
    
    state%initialized = .true.
    
    print *, "✅ GPU Async Executor initialized with", MAX_IN_FLIGHT, "buffer sets"
    
  end subroutine gpu_async_executor_init
  
  subroutine gpu_async_executor_cleanup(state)
    type(gpu_async_state), intent(inout) :: state
    integer :: i
    real(dp) :: avg_gpu_time, utilization
    
    if (.not. state%initialized) return
    
    ! Wait for all pending operations
    do i = 1, MAX_IN_FLIGHT
      if (state%buffer_sets(i)%in_use) then
        call gpu_wait_for_completion(state, i)
      end if
    end do
    
    ! Clean up buffers
    do i = 1, MAX_IN_FLIGHT
      if (state%buffer_sets(i)%input_buffer /= 0) then
        call glDeleteBuffers(1, state%buffer_sets(i)%input_buffer)
      end if
      if (state%buffer_sets(i)%output_buffer /= 0) then
        call glDeleteBuffers(1, state%buffer_sets(i)%output_buffer)
      end if
      if (c_associated(state%buffer_sets(i)%fence)) then
        call glDeleteSync(state%buffer_sets(i)%fence)
      end if
    end do
    
    ! Report statistics
    if (state%completed_operations > 0) then
      avg_gpu_time = real(state%total_gpu_time) / real(state%completed_operations)
      utilization = real(state%total_gpu_time) / &
                    real(state%total_gpu_time + state%total_idle_time) * 100.0
      
      print *, ""
      print *, "=== Async Executor Statistics ==="
      print *, "Completed kernels:", state%completed_operations
      print '(A,F8.2,A)', "Average GPU time per kernel: ", avg_gpu_time / 1.0e6, " ms"
      print '(A,F8.2,A)', "Total GPU compute time: ", &
        real(state%total_gpu_time) / 1.0e9, " seconds"
      print '(A,F8.2,A)', "Total idle time: ", &
        real(state%total_idle_time) / 1.0e9, " seconds"
      print '(A,F6.1,A)', "GPU utilization: ", utilization, "%"
    end if
    
    state%initialized = .false.
    
  end subroutine gpu_async_executor_cleanup
  
  function gpu_get_next_buffer_set(state) result(set_id)
    type(gpu_async_state), intent(inout) :: state
    integer :: set_id
    integer :: attempts
    
    ! Find next available buffer set
    attempts = 0
    do while (attempts < MAX_IN_FLIGHT)
      set_id = state%current_set
      
      ! If this set is available, use it
      if (.not. state%buffer_sets(set_id)%in_use) then
        state%current_set = mod(state%current_set, MAX_IN_FLIGHT) + 1
        return
      end if
      
      ! If it's in use but complete, collect it
      if (gpu_is_work_complete(state, set_id)) then
        call gpu_collect_completed_work(state, set_id)
        state%current_set = mod(state%current_set, MAX_IN_FLIGHT) + 1
        return
      end if
      
      ! Try next set
      state%current_set = mod(state%current_set, MAX_IN_FLIGHT) + 1
      attempts = attempts + 1
    end do
    
    ! All sets in use - wait for the oldest one
    set_id = state%current_set
    call gpu_wait_for_completion(state, set_id)
    state%current_set = mod(state%current_set, MAX_IN_FLIGHT) + 1
    
  end function gpu_get_next_buffer_set
  
  subroutine gpu_submit_work_async(state, set_id, input_data, output_data, &
                                  input_size, output_size, grid_x, grid_y, grid_z)
    type(gpu_async_state), intent(inout) :: state
    integer, intent(in) :: set_id
    real(sp), intent(in), target :: input_data(*)
    real(sp), intent(out), target :: output_data(*)
    integer(i64), intent(in) :: input_size, output_size
    integer, intent(in) :: grid_x, grid_y, grid_z
    
    integer(i64) :: start_time
    
    ! Upload input data
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%buffer_sets(set_id)%input_buffer)
    call glBufferData(GL_SHADER_STORAGE_BUFFER, input_size, c_loc(input_data), GL_DYNAMIC_DRAW)
    
    ! Allocate output buffer
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%buffer_sets(set_id)%output_buffer)
    call glBufferData(GL_SHADER_STORAGE_BUFFER, output_size, c_null_ptr, GL_DYNAMIC_COPY)
    
    ! Bind buffers to shader
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, state%buffer_sets(set_id)%input_buffer)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, state%weight_buffer)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, state%buffer_sets(set_id)%output_buffer)
    
    ! Use compute program
    call glUseProgram(state%compute_program)
    
    ! Record submission time
    call system_clock(start_time)
    state%buffer_sets(set_id)%submit_time = start_time
    
    ! Dispatch compute work
    call glDispatchCompute(grid_x, grid_y, grid_z)
    
    ! Insert memory barrier to ensure writes complete
    call glMemoryBarrier_async(GL_SHADER_STORAGE_BARRIER_BIT)
    
    ! Create fence to track completion
    state%buffer_sets(set_id)%fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
    state%buffer_sets(set_id)%in_use = .true.
    
  end subroutine gpu_submit_work_async
  
  function gpu_is_work_complete(state, set_id) result(complete)
    type(gpu_async_state), intent(in) :: state
    integer, intent(in) :: set_id
    logical :: complete
    integer :: wait_result
    
    complete = .false.
    
    if (.not. state%buffer_sets(set_id)%in_use) then
      complete = .true.
      return
    end if
    
    if (.not. c_associated(state%buffer_sets(set_id)%fence)) then
      return
    end if
    
    ! Check fence status without waiting
    wait_result = glClientWaitSync(state%buffer_sets(set_id)%fence, GL_SYNC_FLUSH_COMMANDS_BIT, 0_c_int64_t)
    
    complete = (wait_result == GL_ALREADY_SIGNALED .or. &
                wait_result == GL_CONDITION_SATISFIED)
    
  end function gpu_is_work_complete
  
  subroutine gpu_wait_for_completion(state, set_id)
    type(gpu_async_state), intent(inout) :: state
    integer, intent(in) :: set_id
    
    integer :: wait_result
    integer(c_int64_t), parameter :: timeout_ns = 1000000000_c_int64_t  ! 1 second
    
    if (.not. state%buffer_sets(set_id)%in_use) return
    if (.not. c_associated(state%buffer_sets(set_id)%fence)) return
    
    ! Wait for fence with timeout
    wait_result = glClientWaitSync(state%buffer_sets(set_id)%fence, GL_SYNC_FLUSH_COMMANDS_BIT, timeout_ns)
    
    if (wait_result == GL_WAIT_FAILED) then
      print *, "⚠️  GPU sync wait failed for set", set_id
    else if (wait_result == GL_TIMEOUT_EXPIRED) then
      print *, "⚠️  GPU sync timeout for set", set_id
    end if
    
    ! Collect the completed work
    call gpu_collect_completed_work(state, set_id)
    
  end subroutine gpu_wait_for_completion
  
  subroutine gpu_collect_completed_work(state, set_id)
    type(gpu_async_state), intent(inout) :: state
    integer, intent(in) :: set_id
    
    integer(i64) :: complete_time, gpu_time
    
    if (.not. state%buffer_sets(set_id)%in_use) return
    
    ! Record completion time
    call system_clock(complete_time)
    state%buffer_sets(set_id)%complete_time = complete_time
    
    ! Update statistics
    gpu_time = state%buffer_sets(set_id)%complete_time - state%buffer_sets(set_id)%submit_time
    state%total_gpu_time = state%total_gpu_time + gpu_time
    state%completed_operations = state%completed_operations + 1
    
    ! Clean up fence
    if (c_associated(state%buffer_sets(set_id)%fence)) then
      call glDeleteSync(state%buffer_sets(set_id)%fence)
      state%buffer_sets(set_id)%fence = GL_SYNC_NULL
    end if
    
    state%buffer_sets(set_id)%in_use = .false.
    
  end subroutine gpu_collect_completed_work
  
  ! High-level async conv2d function
  subroutine gpu_async_conv2d(state, input, weights, output, &
                              N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    type(gpu_async_state), intent(inout) :: state
    real(sp), intent(in), target :: input(*)
    real(sp), intent(in), target :: weights(*)
    real(sp), intent(out), target :: output(*)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    integer :: set_id
    integer :: grid_x, grid_y, grid_z
    integer(i64) :: input_size, output_size
    
    ! Calculate sizes
    input_size = int(N * C * H * W, int64) * 4  ! sizeof(float)
    output_size = int(N * K * H_out * W_out, int64) * 4
    
    ! Calculate grid dimensions
    grid_x = (W_out + 15) / 16
    grid_y = (H_out + 15) / 16
    grid_z = N * K
    
    ! Get next available buffer set
    set_id = gpu_get_next_buffer_set(state)
    
    ! Submit work asynchronously
    call gpu_submit_work_async(state, set_id, input, output, &
                              input_size, output_size, grid_x, grid_y, grid_z)
    
    ! Optionally wait for completion (for now, to maintain compatibility)
    ! In real async usage, caller would check completion later
    call gpu_wait_for_completion(state, set_id)
    
    ! Download results
    call glBindBuffer(GL_SHADER_STORAGE_BUFFER, state%buffer_sets(set_id)%output_buffer)
    call glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0_c_intptr_t, output_size, c_loc(output))
    
  end subroutine gpu_async_conv2d

end module gpu_async_executor