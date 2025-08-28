module sporkle_gpu_metal
  ! Metal backend for macOS GPU compute
  ! The Sporkle Way: Use what you've got!
  
  use kinds
  use iso_c_binding
  use sporkle_types
  use sporkle_error_handling, only: sporkle_error_sub => sporkle_error
  implicit none
  private
  
  public :: metal_context, metal_buffer, metal_kernel
  public :: create_metal_context, create_metal_buffer
  public :: compile_metal_kernel, dispatch_metal_kernel
  public :: metal_memcpy, destroy_metal_context
  public :: check_metal_available
  
  ! Metal context handle
  type :: metal_context
    type(c_ptr) :: device = c_null_ptr
    type(c_ptr) :: queue = c_null_ptr
    logical :: initialized = .false.
    character(len=256) :: device_name = "Unknown"
  end type metal_context
  
  ! Metal buffer handle
  type :: metal_buffer
    type(c_ptr) :: buffer = c_null_ptr
    integer(i64) :: size_bytes = 0
    logical :: allocated = .false.
  end type metal_buffer
  
  ! Metal kernel handle
  type :: metal_kernel
    type(c_ptr) :: function = c_null_ptr
    type(c_ptr) :: pipeline = c_null_ptr
    character(len=:), allocatable :: name
    logical :: compiled = .false.
    integer :: threads_per_group = 256
  end type metal_kernel
  
  ! C interfaces to Metal wrapper functions
  interface
    ! Check if Metal is available
    function c_metal_available() bind(C, name="metal_available")
      import :: c_int
      integer(c_int) :: c_metal_available
    end function
    
    ! Create Metal device and command queue
    function c_metal_create_context() bind(C, name="metal_create_context")
      import :: c_ptr
      type(c_ptr) :: c_metal_create_context
    end function
    
    ! Get device name
    subroutine c_metal_get_device_name(context, name, len) &
        bind(C, name="metal_get_device_name")
      import :: c_ptr, c_char, c_int
      type(c_ptr), value :: context
      character(c_char), intent(out) :: name(*)
      integer(c_int), value :: len
    end subroutine
    
    ! Create buffer
    function c_metal_create_buffer(context, size) &
        bind(C, name="metal_create_buffer")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: context
      integer(c_size_t), value :: size
      type(c_ptr) :: c_metal_create_buffer
    end function
    
    ! Copy to buffer
    subroutine c_metal_copy_to_buffer(buffer, data, size) &
        bind(C, name="metal_copy_to_buffer")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: buffer
      type(c_ptr), value :: data
      integer(c_size_t), value :: size
    end subroutine
    
    ! Copy from buffer
    subroutine c_metal_copy_from_buffer(buffer, data, size) &
        bind(C, name="metal_copy_from_buffer")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: buffer
      type(c_ptr), value :: data
      integer(c_size_t), value :: size
    end subroutine
    
    ! Compile kernel
    function c_metal_compile_kernel(context, source, name) &
        bind(C, name="metal_compile_kernel")
      import :: c_ptr, c_char
      type(c_ptr), value :: context
      character(c_char), intent(in) :: source(*)
      character(c_char), intent(in) :: name(*)
      type(c_ptr) :: c_metal_compile_kernel
    end function
    
    ! Dispatch kernel
    subroutine c_metal_dispatch_kernel(context, kernel, &
        buffers, num_buffers, global_size, local_size) &
        bind(C, name="metal_dispatch_kernel")
      import :: c_ptr, c_int, c_size_t
      type(c_ptr), value :: context
      type(c_ptr), value :: kernel
      type(c_ptr), intent(in) :: buffers(*)
      integer(c_int), value :: num_buffers
      integer(c_size_t), intent(in) :: global_size(3)
      integer(c_size_t), intent(in) :: local_size(3)
    end subroutine
    
    ! Wait for completion
    subroutine c_metal_wait_idle(context) bind(C, name="metal_wait_idle")
      import :: c_ptr
      type(c_ptr), value :: context
    end subroutine
    
    ! Cleanup
    subroutine c_metal_destroy_buffer(buffer) bind(C, name="metal_destroy_buffer")
      import :: c_ptr
      type(c_ptr), value :: buffer
    end subroutine
    
    subroutine c_metal_destroy_kernel(kernel) bind(C, name="metal_destroy_kernel")
      import :: c_ptr
      type(c_ptr), value :: kernel
    end subroutine
    
    subroutine c_metal_destroy_context(context) bind(C, name="metal_destroy_context")
      import :: c_ptr
      type(c_ptr), value :: context
    end subroutine
  end interface
  
contains

  ! Check if Metal is available
  function check_metal_available() result(available)
    logical :: available
    integer(c_int) :: result
    
    result = c_metal_available()
    available = (result /= 0)
    
  end function check_metal_available
  
  ! Create Metal context
  function create_metal_context() result(ctx)
    type(metal_context) :: ctx
    character(kind=c_char, len=256) :: c_name
    integer :: i
    
    ! Check availability first
    if (.not. check_metal_available()) then
      call sporkle_error_sub("Metal is not available on this system", .false.)
      return
    end if
    
    ! Create context through C wrapper
    ctx%device = c_metal_create_context()
    
    if (c_associated(ctx%device)) then
      ctx%initialized = .true.
      ctx%queue = ctx%device  ! Queue is bundled with device in our wrapper
      
      ! Get device name
      call c_metal_get_device_name(ctx%device, c_name, 256)
      
      ! Convert C string to Fortran string
      do i = 1, 256
        if (c_name(i:i) == c_null_char) exit
        ctx%device_name(i:i) = c_name(i:i)
      end do
      
      print *, "🎮 Metal Device Initialized:"
      print '(A,A)', "   Name: ", trim(ctx%device_name)
      print *, "   API: Metal 3.0"
      print *, "   Unified Memory: Yes"
    else
      call sporkle_error_sub("Failed to create Metal context", .false.)
    end if
    
  end function create_metal_context
  
  ! Create Metal buffer
  function create_metal_buffer(ctx, size_bytes) result(buffer)
    type(metal_context), intent(in) :: ctx
    integer(i64), intent(in) :: size_bytes
    type(metal_buffer) :: buffer
    
    if (.not. ctx%initialized) then
      call sporkle_error_sub("Metal context not initialized", .false.)
      return
    end if
    
    buffer%buffer = c_metal_create_buffer(ctx%device, int(size_bytes, c_size_t))
    
    if (c_associated(buffer%buffer)) then
      buffer%size_bytes = size_bytes
      buffer%allocated = .true.
      ! Removed verbose logging for bulk allocations
    else
      call sporkle_error_sub("Failed to create Metal buffer", .false.)
    end if
    
  end function create_metal_buffer
  
  ! Copy data to/from Metal buffer
  subroutine metal_memcpy(buffer, host_ptr, size_bytes, to_device)
    type(metal_buffer), intent(in) :: buffer
    type(c_ptr), intent(in) :: host_ptr
    integer(i64), intent(in) :: size_bytes
    logical, intent(in) :: to_device
    
    if (.not. buffer%allocated) then
      call sporkle_error_sub("Metal buffer not allocated", .false.)
      return
    end if
    
    if (to_device) then
      call c_metal_copy_to_buffer(buffer%buffer, host_ptr, int(size_bytes, c_size_t))
      print '(A,F0.2,A)', "   Copied ", real(size_bytes) / real(1024**2), " MB to GPU"
    else
      call c_metal_copy_from_buffer(buffer%buffer, host_ptr, int(size_bytes, c_size_t))
      print '(A,F0.2,A)', "   Copied ", real(size_bytes) / real(1024**2), " MB from GPU"
    end if
    
  end subroutine metal_memcpy
  
  ! Compile Metal kernel from source
  function compile_metal_kernel(ctx, source, kernel_name) result(kernel)
    type(metal_context), intent(in) :: ctx
    character(len=*), intent(in) :: source
    character(len=*), intent(in) :: kernel_name
    type(metal_kernel) :: kernel
    
    character(kind=c_char, len=len(source)+1) :: c_source
    character(kind=c_char, len=len(kernel_name)+1) :: c_name
    
    if (.not. ctx%initialized) then
      call sporkle_error_sub("Metal context not initialized", .false.)
      return
    end if
    
    ! Convert to C strings
    c_source = trim(source) // c_null_char
    c_name = trim(kernel_name) // c_null_char
    
    ! Compile through C wrapper
    kernel%pipeline = c_metal_compile_kernel(ctx%device, c_source, c_name)
    
    if (c_associated(kernel%pipeline)) then
      kernel%compiled = .true.
      kernel%name = kernel_name
      print '(A,A)', "   Compiled Metal kernel: ", trim(kernel_name)
    else
      call sporkle_error_sub("Failed to compile Metal kernel", .false.)
    end if
    
  end function compile_metal_kernel
  
  ! Dispatch Metal kernel
  subroutine dispatch_metal_kernel(ctx, kernel, buffers, global_size, local_size)
    type(metal_context), intent(in) :: ctx
    type(metal_kernel), intent(in) :: kernel
    type(metal_buffer), intent(in) :: buffers(:)
    integer, intent(in) :: global_size(:)
    integer, intent(in), optional :: local_size(:)
    
    type(c_ptr) :: c_buffers(size(buffers))
    integer(c_size_t) :: c_global(3), c_local(3)
    integer :: i
    
    if (.not. kernel%compiled) then
      call sporkle_error_sub("Kernel not compiled", .false.)
      return
    end if
    
    ! Prepare buffer array
    do i = 1, size(buffers)
      c_buffers(i) = buffers(i)%buffer
    end do
    
    ! Set dimensions
    c_global = 1
    c_global(1:size(global_size)) = int(global_size, c_size_t)
    
    if (present(local_size)) then
      c_local = 1
      c_local(1:size(local_size)) = int(local_size, c_size_t)
    else
      c_local = [int(kernel%threads_per_group, c_size_t), 1_c_size_t, 1_c_size_t]
    end if
    
    print '(A,A)', "🚀 Dispatching Metal kernel: ", trim(kernel%name)
    print '(A,3(I0,1X))', "   Global size: ", c_global
    print '(A,3(I0,1X))', "   Local size: ", c_local
    
    ! Dispatch through C wrapper
    call c_metal_dispatch_kernel(ctx%device, kernel%pipeline, &
                                 c_buffers, size(buffers), c_global, c_local)
    
    ! Wait for completion
    call c_metal_wait_idle(ctx%device)
    
  end subroutine dispatch_metal_kernel
  
  ! Cleanup Metal context
  subroutine destroy_metal_context(ctx)
    type(metal_context), intent(inout) :: ctx
    
    if (ctx%initialized) then
      call c_metal_destroy_context(ctx%device)
      ctx%initialized = .false.
      print *, "🧹 Metal context destroyed"
    end if
    
  end subroutine destroy_metal_context

end module sporkle_gpu_metal