module spirv_shaders
  ! Pre-compiled SPIR-V shaders for Kronos
  ! ======================================
  ! This module contains embedded SPIR-V bytecode
  
  use iso_c_binding
  use kinds
  implicit none
  private
  
  public :: get_vector_add_spirv, get_conv2d_spirv
  
  ! Module variable to hold Conv2D SPIR-V data
  integer(c_int8_t), allocatable, target :: conv2d_spirv_buffer(:)
  
  ! Simple vector add shader for testing
  ! Generated from:
  ! #version 450
  ! layout(local_size_x = 64) in;
  ! layout(binding = 0) buffer A { float a[]; };
  ! layout(binding = 1) buffer B { float b[]; };
  ! layout(binding = 2) buffer C { float c[]; };
  ! void main() {
  !   uint i = gl_GlobalInvocationID.x;
  !   c[i] = a[i] + b[i];
  ! }
  integer(c_int32_t), target :: vector_add_spirv(6) = [ &
    int(z'07230203', c_int32_t), & ! Magic
    int(z'00010000', c_int32_t), & ! Version 1.0
    int(z'00000000', c_int32_t), & ! Generator
    int(z'00000030', c_int32_t), & ! Bound
    int(z'00000000', c_int32_t), & ! Schema
    ! ... minimal SPIR-V for vector add would go here ...
    ! For now, just a placeholder
    int(z'00000000', c_int32_t)  &
  ]
  
  ! C interface to get real Conv2D SPIR-V data
  interface
    subroutine get_conv2d_spirv_data(buffer) bind(C, name="get_conv2d_spirv_data")
      import :: c_int8_t
      integer(c_int8_t), intent(out) :: buffer(*)
    end subroutine get_conv2d_spirv_data
    
    function get_conv2d_spirv_size() bind(C, name="get_conv2d_spirv_size")
      import :: c_size_t
      integer(c_size_t) :: get_conv2d_spirv_size
    end function get_conv2d_spirv_size
  end interface
  
contains
  
  function get_vector_add_spirv(spirv_size) result(spirv_ptr)
    integer(c_size_t), intent(out) :: spirv_size
    type(c_ptr) :: spirv_ptr
    
    spirv_size = size(vector_add_spirv) * 4_c_size_t
    spirv_ptr = c_loc(vector_add_spirv)
    
  end function get_vector_add_spirv
  
  function get_conv2d_spirv(spirv_size) result(spirv_ptr)
    integer(c_size_t), intent(out) :: spirv_size
    type(c_ptr) :: spirv_ptr
    
    ! Get real SPIR-V data from C (only once)
    if (.not. allocated(conv2d_spirv_buffer)) then
      spirv_size = get_conv2d_spirv_size()
      allocate(conv2d_spirv_buffer(spirv_size))
      call get_conv2d_spirv_data(conv2d_spirv_buffer)
    else
      spirv_size = size(conv2d_spirv_buffer)
    end if
    
    spirv_ptr = c_loc(conv2d_spirv_buffer)
    
  end function get_conv2d_spirv
  
end module spirv_shaders