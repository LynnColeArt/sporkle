module spirv_shaders
  ! Pre-compiled SPIR-V shaders for Kronos
  ! ======================================
  ! This module contains embedded SPIR-V bytecode
  
  use iso_c_binding
  use kinds
  implicit none
  private
  
  public :: get_vector_add_spirv, get_conv2d_spirv
  
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
  integer(c_int32_t), parameter :: vector_add_spirv(*) = [ &
    int(z'07230203', c_int32_t), & ! Magic
    int(z'00010000', c_int32_t), & ! Version 1.0
    int(z'00000000', c_int32_t), & ! Generator
    int(z'00000030', c_int32_t), & ! Bound
    int(z'00000000', c_int32_t), & ! Schema
    ! ... minimal SPIR-V for vector add would go here ...
    ! For now, just a placeholder
    int(z'00000000', c_int32_t)  &
  ]
  
  ! Conv2D shader placeholder
  integer(c_int32_t), parameter :: conv2d_spirv(*) = [ &
    int(z'07230203', c_int32_t), & ! Magic
    int(z'00010000', c_int32_t), & ! Version 1.0
    int(z'00000000', c_int32_t), & ! Generator
    int(z'00000100', c_int32_t), & ! Bound
    int(z'00000000', c_int32_t), & ! Schema
    ! ... Conv2D SPIR-V would go here ...
    int(z'00000000', c_int32_t)  &
  ]
  
contains
  
  subroutine get_vector_add_spirv(spirv_ptr, spirv_size)
    integer(c_int8_t), pointer, intent(out) :: spirv_ptr(:)
    integer(c_size_t), intent(out) :: spirv_size
    
    spirv_size = size(vector_add_spirv) * 4_c_size_t
    spirv_ptr => transfer(c_loc(vector_add_spirv), spirv_ptr, [spirv_size])
    
  end subroutine get_vector_add_spirv
  
  subroutine get_conv2d_spirv(spirv_ptr, spirv_size)
    integer(c_int8_t), pointer, intent(out) :: spirv_ptr(:)
    integer(c_size_t), intent(out) :: spirv_size
    
    spirv_size = size(conv2d_spirv) * 4_c_size_t
    spirv_ptr => transfer(c_loc(conv2d_spirv), spirv_ptr, [spirv_size])
    
  end subroutine get_conv2d_spirv
  
end module spirv_shaders