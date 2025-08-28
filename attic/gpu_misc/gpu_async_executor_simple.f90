module gpu_async_executor_simple
  use iso_c_binding
  use kinds
  implicit none
  
  private
  public :: gpu_async_state_simple, gpu_async_executor_init_simple
  
  ! Simplified state type to test
  type :: gpu_async_state_simple
    integer :: compute_program = 0
    integer :: weight_buffer = 0
    logical :: initialized = .false.
  end type gpu_async_state_simple
  
contains

  subroutine gpu_async_executor_init_simple(state, compute_program, weight_buffer)
    type(gpu_async_state_simple), intent(out) :: state
    integer, intent(in) :: compute_program
    integer, intent(in) :: weight_buffer
    
    ! Initialize state
    state%compute_program = compute_program
    state%weight_buffer = weight_buffer
    state%initialized = .true.
    
    print *, "✅ Simple GPU Async Executor initialized"
    
  end subroutine gpu_async_executor_init_simple

end module gpu_async_executor_simple