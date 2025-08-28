module gpu_dynamic_shader_cache
  ! Stub implementation for build compatibility
  use kinds
  implicit none
  
  private
  public :: gpu_get_cached_program
  
contains

  function gpu_get_cached_program(kernel_type, params) result(program_id)
    character(len=*), intent(in) :: kernel_type
    integer, intent(in) :: params(:)
    integer :: program_id
    
    ! Stub - always return 0 (no program)
    program_id = 0
  end function gpu_get_cached_program

end module gpu_dynamic_shader_cache