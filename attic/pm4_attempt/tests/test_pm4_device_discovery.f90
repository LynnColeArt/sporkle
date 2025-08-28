program test_pm4_device_discovery
  ! Test PM4 device discovery and info query
  
  use kinds
  use iso_c_binding
  use pm4_submit
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(sp_device_info) :: dev_info
  integer :: status, i
  character(len=64) :: device_name
  
  print *, "PM4 Device Discovery Test"
  print *, "========================"
  
  ! Try both render nodes
  do i = 0, 1
    write(*, '(A,I0,A)', advance='no') "Trying renderD", 128+i, "... "
    
    ! Build device path
    write(device_name, '(A,I0)') "/dev/dri/renderD", 128+i
    
    ctx_ptr = sp_pm4_init(trim(device_name))
    if (.not. c_associated(ctx_ptr)) then
      print *, "Failed to initialize"
      cycle
    end if
    
    print *, "Success!"
    
    ! Get device info
    status = sp_pm4_get_device_info(ctx_ptr, dev_info)
    if (status /= 0) then
      print *, "  ERROR: Failed to get device info"
      call sp_pm4_cleanup(ctx_ptr)
      cycle
    end if
    
    ! Convert C string to Fortran
    call c_string_to_fortran(dev_info%name, device_name)
    
    ! Display device info
    print *, ""
    print '(A,A)', "  Device Name: ", trim(device_name)
    print '(A,Z4)', "  Device ID: 0x", dev_info%device_id
    print '(A,I0)', "  Family: ", dev_info%family
    print '(A,I0)', "  Compute Units: ", dev_info%num_compute_units
    print '(A,I0)', "  Shader Engines: ", dev_info%num_shader_engines
    print '(A,F0.1,A)', "  Max Engine Clock: ", real(dev_info%max_engine_clock)/1000.0_sp, " MHz"
    print '(A,F0.1,A)', "  Max Memory Clock: ", real(dev_info%max_memory_clock)/1000.0_sp, " MHz"
    print '(A,I0)', "  VRAM Type: ", dev_info%vram_type
    print '(A,I0)', "  Memory Bus Width: ", dev_info%vram_bit_width
    print '(A,F0.1,A)', "  VRAM Size: ", real(dev_info%vram_size)/1024.0_sp**3, " GB"
    print '(A,F0.1,A)', "  GTT Size: ", real(dev_info%gtt_size)/1024.0_sp**3, " GB"
    print *, ""
    
    ! Cleanup
    call sp_pm4_cleanup(ctx_ptr)
  end do
  
  print *, "Test complete!"
  
contains

  subroutine c_string_to_fortran(c_str, f_str)
    character(kind=c_char), intent(in) :: c_str(*)
    character(len=*), intent(out) :: f_str
    integer :: i
    
    f_str = ' '
    do i = 1, len(f_str)
      if (c_str(i) == c_null_char) exit
      f_str(i:i) = c_str(i)
    end do
  end subroutine

end program test_pm4_device_discovery