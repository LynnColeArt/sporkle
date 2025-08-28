module pm4_buffer_raii
  ! RAII-style buffer management for PM4
  ! ====================================
  ! Automatic cleanup using Fortran finalizers
  
  use kinds
  use iso_c_binding
  use pm4_submit
  implicit none
  private
  
  ! Public interface
  public :: gpu_buffer
  
  ! RAII buffer type with automatic cleanup
  type :: gpu_buffer
    type(c_ptr) :: ctx_ptr = c_null_ptr
    type(c_ptr) :: bo_ptr = c_null_ptr
    type(sp_bo), pointer :: bo => null()
    logical :: owns_resource = .false.
  contains
    procedure :: init => gpu_buffer_init
    procedure :: get_va => gpu_buffer_get_va
    procedure :: get_cpu_ptr => gpu_buffer_get_cpu_ptr
    procedure :: get_size => gpu_buffer_get_size
    procedure :: get_handle => gpu_buffer_get_handle
    procedure :: is_valid => gpu_buffer_is_valid
    procedure :: release => gpu_buffer_release
    final :: gpu_buffer_destructor
  end type gpu_buffer
  
contains

  ! Initialize buffer
  subroutine gpu_buffer_init(this, ctx_ptr, size, flags)
    class(gpu_buffer), intent(inout) :: this
    type(c_ptr), intent(in) :: ctx_ptr
    integer(i64), intent(in) :: size
    integer, intent(in) :: flags
    
    ! Clean up any existing resource
    call this%release()
    
    ! Allocate new buffer
    this%ctx_ptr = ctx_ptr
    this%bo_ptr = sp_buffer_alloc(ctx_ptr, size, flags)
    
    if (c_associated(this%bo_ptr)) then
      call c_f_pointer(this%bo_ptr, this%bo)
      this%owns_resource = .true.
    else
      this%owns_resource = .false.
    end if
  end subroutine
  
  ! Get GPU virtual address
  function gpu_buffer_get_va(this) result(va)
    class(gpu_buffer), intent(in) :: this
    integer(i64) :: va
    
    if (associated(this%bo)) then
      va = this%bo%gpu_va
    else
      va = 0
    end if
  end function
  
  ! Get CPU pointer (if mapped)
  function gpu_buffer_get_cpu_ptr(this) result(ptr)
    class(gpu_buffer), intent(in) :: this
    type(c_ptr) :: ptr
    
    if (associated(this%bo)) then
      ptr = this%bo%cpu_ptr
    else
      ptr = c_null_ptr
    end if
  end function
  
  ! Get buffer size
  function gpu_buffer_get_size(this) result(size)
    class(gpu_buffer), intent(in) :: this
    integer(i64) :: size
    
    if (associated(this%bo)) then
      size = int(this%bo%size, i64)
    else
      size = 0
    end if
  end function
  
  ! Get GEM handle
  function gpu_buffer_get_handle(this) result(handle)
    class(gpu_buffer), intent(in) :: this
    integer :: handle
    
    if (associated(this%bo)) then
      handle = int(this%bo%handle)
    else
      handle = 0
    end if
  end function
  
  ! Check if buffer is valid
  function gpu_buffer_is_valid(this) result(valid)
    class(gpu_buffer), intent(in) :: this
    logical :: valid
    
    valid = this%owns_resource .and. c_associated(this%bo_ptr)
  end function
  
  ! Explicit release
  subroutine gpu_buffer_release(this)
    class(gpu_buffer), intent(inout) :: this
    
    if (this%owns_resource .and. c_associated(this%bo_ptr)) then
      call sp_buffer_free(this%ctx_ptr, this%bo_ptr)
    end if
    
    this%ctx_ptr = c_null_ptr
    this%bo_ptr = c_null_ptr
    this%bo => null()
    this%owns_resource = .false.
  end subroutine
  
  ! Automatic cleanup on destruction
  subroutine gpu_buffer_destructor(this)
    type(gpu_buffer), intent(inout) :: this
    call this%release()
  end subroutine

end module pm4_buffer_raii