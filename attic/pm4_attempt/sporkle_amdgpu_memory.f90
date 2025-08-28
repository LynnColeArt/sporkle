module sporkle_amdgpu_memory
  use iso_c_binding
  use sporkle_types
  use sporkle_amdgpu_direct
  implicit none
  
  private
  public :: amdgpu_write_buffer, amdgpu_read_buffer
  
contains

  function amdgpu_write_buffer(device, buffer, data, size) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_buffer), intent(inout) :: buffer
    type(c_ptr), intent(in) :: data
    integer(c_size_t), intent(in) :: size
    integer :: status
    
    integer(c_int8_t), pointer :: src(:), dst(:)
    integer :: n
    
    status = -1
    
    ! First, try to map the buffer if not already mapped
    if (.not. c_associated(buffer%cpu_ptr)) then
      status = amdgpu_map_buffer(device, buffer)
      if (status /= 0) then
        print *, "Failed to map buffer for writing"
        return
      end if
    end if
    
    ! Copy data to mapped buffer
    if (c_associated(buffer%cpu_ptr) .and. c_associated(data)) then
      n = int(size)  ! default kind

      call c_f_pointer(buffer%cpu_ptr, dst, [n])
      call c_f_pointer(data,          src, [n])
      
      ! Simple byte copy
      dst(1:n) = src(1:n)
      
      status = 0
      print *, "Wrote", size, "bytes to GPU buffer"
    else
      print *, "ERROR: Invalid pointers for buffer write"
    end if
    
  end function amdgpu_write_buffer
  
  function amdgpu_read_buffer(device, buffer, data, size) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_buffer), intent(in) :: buffer
    type(c_ptr), intent(in) :: data
    integer(c_size_t), intent(in) :: size
    integer :: status
    
    integer(c_int8_t), pointer :: src(:), dst(:)
    integer :: n
    
    status = -1
    
    ! Buffer must be mapped to read
    if (.not. c_associated(buffer%cpu_ptr)) then
      print *, "Buffer not mapped for reading"
      return
    end if
    
    ! Copy data from mapped buffer
    if (c_associated(buffer%cpu_ptr) .and. c_associated(data)) then
      n = int(size)  ! default kind

      call c_f_pointer(buffer%cpu_ptr, src, [n])
      call c_f_pointer(data,          dst, [n])
      
      ! Simple byte copy
      dst(1:n) = src(1:n)
      
      status = 0
      print *, "Read", size, "bytes from GPU buffer"
    else
      print *, "ERROR: Invalid pointers for buffer read"
    end if
    
  end function amdgpu_read_buffer

end module sporkle_amdgpu_memory