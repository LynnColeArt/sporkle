module pm4_fence_binding
  ! Fortran bindings for PM4 fence operations
  ! Connects to the C fence implementation in submit.c
  
  use iso_c_binding
  use kinds
  implicit none
  private
  
  public :: pm4_fence_t
  public :: pm4_fence_wait, pm4_fence_check
  public :: FENCE_TIMEOUT_INFINITE
  
  ! Fence timeout constants
  integer(i64), parameter :: FENCE_TIMEOUT_INFINITE = -1_i64
  integer(i64), parameter :: FENCE_TIMEOUT_1MS = 1000000_i64
  integer(i64), parameter :: FENCE_TIMEOUT_1S = 1000000000_i64
  
  ! Mirror of C struct sp_fence
  type, bind(c) :: pm4_fence_t
    integer(c_int32_t) :: ctx_id
    integer(c_int32_t) :: ip_type
    integer(c_int32_t) :: ring
    integer(c_int64_t) :: fence
  end type pm4_fence_t
  
  interface
    ! int sp_fence_wait(sp_pm4_ctx* ctx, sp_fence* fence, uint64_t timeout_ns)
    function sp_fence_wait_c(ctx, fence, timeout_ns) &
             bind(c, name="sp_fence_wait") result(status)
      import :: c_ptr, c_int, c_int64_t, pm4_fence_t
      type(c_ptr), value :: ctx
      type(pm4_fence_t), intent(in) :: fence
      integer(c_int64_t), value :: timeout_ns
      integer(c_int) :: status
    end function sp_fence_wait_c
    
    ! int sp_fence_check(sp_pm4_ctx* ctx, sp_fence* fence)
    function sp_fence_check_c(ctx, fence) &
             bind(c, name="sp_fence_check") result(status)
      import :: c_ptr, c_int, pm4_fence_t
      type(c_ptr), value :: ctx
      type(pm4_fence_t), intent(in) :: fence
      integer(c_int) :: status
    end function sp_fence_check_c
  end interface
  
contains

  function pm4_fence_wait(ctx_ptr, fence, timeout_ns) result(status)
    type(c_ptr), intent(in) :: ctx_ptr
    type(pm4_fence_t), intent(in) :: fence
    integer(i64), intent(in) :: timeout_ns
    integer :: status
    
    status = sp_fence_wait_c(ctx_ptr, fence, timeout_ns)
    
    if (status == -62) then  ! ETIME
      print *, "⏱️ Fence wait timed out"
    else if (status < 0) then
      print '(A,I0)', "❌ Fence wait failed with error: ", status
    end if
    
  end function pm4_fence_wait
  
  function pm4_fence_check(ctx_ptr, fence) result(is_signaled)
    type(c_ptr), intent(in) :: ctx_ptr
    type(pm4_fence_t), intent(in) :: fence
    logical :: is_signaled
    
    integer :: status
    
    status = sp_fence_check_c(ctx_ptr, fence)
    is_signaled = (status == 0)
    
  end function pm4_fence_check

end module pm4_fence_binding