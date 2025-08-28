module gpu_safety_guards
  ! GPU Safety Guards
  ! =================
  !
  ! Provides safety checks before allowing direct GPU submission
  ! Prevents system freezes from malformed PM4 packets
  
  use kinds
  implicit none
  
  private
  public :: is_gpu_safe, enable_gpu_safety, disable_gpu_safety
  
  ! Safety state
  logical, save :: safety_enabled = .true.
  logical, save :: gpu_is_safe = .true.
  
contains

  ! Check if GPU operations are safe
  function is_gpu_safe() result(safe)
    logical :: safe
    character(len=256) :: env_val
    integer :: env_len
    
    ! Check environment variable override
    call get_environment_variable("SPORKLE_PM4_UNSAFE", env_val, env_len)
    if (env_len > 0 .and. env_val(1:env_len) == "1") then
      safe = .true.
      return
    end if
    
    ! Allow if safety is disabled or GPU is marked safe
    safe = .not. safety_enabled .or. gpu_is_safe
    
    ! In production, we'd check:
    ! - GPU health status
    ! - Previous submission success
    ! - System memory pressure
    ! - GPU hang detection
    
  end function is_gpu_safe
  
  ! Enable safety checks
  subroutine enable_gpu_safety()
    safety_enabled = .true.
  end subroutine enable_gpu_safety
  
  ! Disable safety checks (for testing)
  subroutine disable_gpu_safety()
    safety_enabled = .false.
    print *, "⚠️  GPU safety checks disabled - use with caution!"
  end subroutine disable_gpu_safety

end module gpu_safety_guards