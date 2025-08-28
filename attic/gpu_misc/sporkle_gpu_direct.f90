module sporkle_gpu_direct
  ! Direct GPU access via kernel DRM interface
  ! No vendor SDKs - just kernel drivers
  ! This is The Sporkle Way™
  
  use iso_c_binding
  use kinds
  implicit none
  private
  
  public :: gpu_context, gpu_buffer
  public :: gpu_init, gpu_cleanup, gpu_allocate, gpu_deallocate
  public :: gpu_map, gpu_unmap, gpu_copy_to_device, gpu_copy_from_device
  public :: test_gpu_direct
  
  ! GPU context - wraps the C structure
  type :: gpu_context
    type(c_ptr) :: ptr = c_null_ptr
    logical :: is_valid = .false.
    character(len=:), allocatable :: device_path
    character(len=:), allocatable :: name
    integer(i64) :: vram_size = 0
    integer(i64) :: gart_size = 0
  end type gpu_context
  
  ! GPU buffer - memory on the GPU
  type :: gpu_buffer
    type(c_ptr) :: ptr = c_null_ptr
    type(c_ptr) :: cpu_ptr = c_null_ptr
    integer(i64) :: size = 0
    integer(i64) :: gpu_addr = 0
    logical :: is_mapped = .false.
  end type gpu_buffer
  
  ! C interfaces
  interface
    ! Initialize GPU context
    function sporkle_gpu_init_c(device_path) bind(c, name="sporkle_gpu_init")
      import :: c_ptr, c_char
      character(kind=c_char), dimension(*) :: device_path
      type(c_ptr) :: sporkle_gpu_init_c
    end function
    
    ! Cleanup GPU context
    subroutine sporkle_gpu_cleanup_c(ctx) bind(c, name="sporkle_gpu_cleanup")
      import :: c_ptr
      type(c_ptr), value :: ctx
    end subroutine
    
    ! Allocate GPU memory
    function sporkle_gpu_alloc_c(ctx, size) bind(c, name="sporkle_gpu_alloc")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: ctx
      integer(c_size_t), value :: size
      type(c_ptr) :: sporkle_gpu_alloc_c
    end function
    
    ! Map GPU buffer to CPU
    function sporkle_gpu_map_c(ctx, buf) bind(c, name="sporkle_gpu_map")
      import :: c_ptr
      type(c_ptr), value :: ctx, buf
      type(c_ptr) :: sporkle_gpu_map_c
    end function
    
    ! Free GPU buffer
    subroutine sporkle_gpu_free_c(ctx, buf) bind(c, name="sporkle_gpu_free")
      import :: c_ptr
      type(c_ptr), value :: ctx, buf
    end subroutine
    
    ! Test function
    subroutine sporkle_gpu_test_c() bind(c, name="sporkle_gpu_test")
    end subroutine
  end interface
  
contains

  function gpu_init(device_path) result(ctx)
    character(len=*), intent(in) :: device_path
    type(gpu_context) :: ctx
    
    character(kind=c_char), dimension(len(device_path)+1) :: c_path
    integer :: i
    
    ! Convert Fortran string to C string
    do i = 1, len(device_path)
      c_path(i) = device_path(i:i)
    end do
    c_path(len(device_path)+1) = c_null_char
    
    ctx%ptr = sporkle_gpu_init_c(c_path)
    ctx%is_valid = c_associated(ctx%ptr)
    
    if (ctx%is_valid) then
      ctx%device_path = device_path
      ! In real implementation, we'd extract more info from C struct
      ctx%name = "AMD GPU"  ! Placeholder
    end if
    
  end function gpu_init
  
  subroutine gpu_cleanup(ctx)
    type(gpu_context), intent(inout) :: ctx
    
    if (ctx%is_valid .and. c_associated(ctx%ptr)) then
      call sporkle_gpu_cleanup_c(ctx%ptr)
      ctx%ptr = c_null_ptr
      ctx%is_valid = .false.
    end if
    
  end subroutine gpu_cleanup
  
  function gpu_allocate(ctx, size) result(buffer)
    type(gpu_context), intent(in) :: ctx
    integer(i64), intent(in) :: size
    type(gpu_buffer) :: buffer
    
    if (ctx%is_valid) then
      buffer%ptr = sporkle_gpu_alloc_c(ctx%ptr, int(size, c_size_t))
      if (c_associated(buffer%ptr)) then
        buffer%size = size
        ! GPU address would be extracted from C struct
      end if
    end if
    
  end function gpu_allocate
  
  subroutine gpu_deallocate(ctx, buffer)
    type(gpu_context), intent(in) :: ctx
    type(gpu_buffer), intent(inout) :: buffer
    
    if (ctx%is_valid .and. c_associated(buffer%ptr)) then
      if (buffer%is_mapped) then
        call gpu_unmap(ctx, buffer)
      end if
      call sporkle_gpu_free_c(ctx%ptr, buffer%ptr)
      buffer%ptr = c_null_ptr
      buffer%size = 0
    end if
    
  end subroutine gpu_deallocate
  
  function gpu_map(ctx, buffer) result(ptr)
    type(gpu_context), intent(in) :: ctx
    type(gpu_buffer), intent(inout) :: buffer
    type(c_ptr) :: ptr
    
    ptr = c_null_ptr
    
    if (ctx%is_valid .and. c_associated(buffer%ptr) .and. .not. buffer%is_mapped) then
      ptr = sporkle_gpu_map_c(ctx%ptr, buffer%ptr)
      if (c_associated(ptr)) then
        buffer%cpu_ptr = ptr
        buffer%is_mapped = .true.
      end if
    else if (buffer%is_mapped) then
      ptr = buffer%cpu_ptr
    end if
    
  end function gpu_map
  
  subroutine gpu_unmap(ctx, buffer)
    type(gpu_context), intent(in) :: ctx
    type(gpu_buffer), intent(inout) :: buffer
    
    ! For now, mapping persists until buffer is freed
    ! In a real implementation we might have explicit unmap
    buffer%is_mapped = .false.
    
  end subroutine gpu_unmap
  
  subroutine gpu_copy_to_device(ctx, buffer, data, size)
    type(gpu_context), intent(in) :: ctx
    type(gpu_buffer), intent(inout) :: buffer
    type(c_ptr), intent(in) :: data
    integer(i64), intent(in) :: size
    
    type(c_ptr) :: device_ptr
    
    device_ptr = gpu_map(ctx, buffer)
    if (c_associated(device_ptr)) then
      ! Direct memory copy
      call c_f_pointer(device_ptr, device_ptr)
      call c_f_pointer(data, data)
      ! In real implementation, use memcpy
      print *, "Would copy", size, "bytes to GPU"
    end if
    
  end subroutine gpu_copy_to_device
  
  subroutine gpu_copy_from_device(ctx, buffer, data, size)
    type(gpu_context), intent(in) :: ctx
    type(gpu_buffer), intent(in) :: buffer
    type(c_ptr), intent(out) :: data
    integer(i64), intent(in) :: size
    
    type(c_ptr) :: device_ptr
    
    if (buffer%is_mapped) then
      device_ptr = buffer%cpu_ptr
      ! In real implementation, use memcpy
      print *, "Would copy", size, "bytes from GPU"
    end if
    
  end subroutine gpu_copy_from_device
  
  subroutine test_gpu_direct()
    print *, "🚀 Testing direct GPU access (The Sporkle Way)"
    call sporkle_gpu_test_c()
  end subroutine test_gpu_direct

end module sporkle_gpu_direct