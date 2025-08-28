program test_pm4_raii
  ! Test RAII buffer management
  ! ===========================
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  integer :: test_status
  
  print *, "======================================="
  print *, "PM4 RAII Test"
  print *, "======================================="
  
  ! Initialize context
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  test_status = 0
  
  ! Test 1: Basic allocation and cleanup
  print *, ""
  print *, "Test 1: Basic RAII cleanup"
  call test_basic_raii()
  
  ! Test 2: Nested scope cleanup
  print *, ""
  print *, "Test 2: Nested scope cleanup"
  call test_nested_scope()
  
  ! Test 3: Manual release
  print *, ""
  print *, "Test 3: Manual release"
  call test_manual_release()
  
  ! Cleanup
  call sp_pm4_cleanup(ctx_ptr)
  
  if (test_status == 0) then
    print *, ""
    print *, "ALL TESTS PASSED!"
  else
    print *, ""
    print *, "SOME TESTS FAILED!"
  end if
  
contains

  subroutine test_basic_raii()
    type(gpu_buffer) :: buffer
    
    print *, "  Allocating buffer..."
    call buffer%init(ctx_ptr, int(4096, i64), SP_BO_HOST_VISIBLE)
    
    if (buffer%is_valid()) then
      print '(A,Z16)', "  Buffer allocated at VA: 0x", buffer%get_va()
      print *, "  Buffer will be freed automatically"
    else
      print *, "  ERROR: Buffer allocation failed"
      test_status = 1
    end if
    ! Buffer freed here automatically
  end subroutine
  
  subroutine test_nested_scope()
    type(gpu_buffer) :: outer_buffer
    
    call outer_buffer%init(ctx_ptr, int(4096, i64), SP_BO_HOST_VISIBLE)
    print '(A,Z16)', "  Outer buffer VA: 0x", outer_buffer%get_va()
    
    block
      type(gpu_buffer) :: inner_buffer
      call inner_buffer%init(ctx_ptr, int(4096, i64), SP_BO_DEVICE_LOCAL)
      print '(A,Z16)', "  Inner buffer VA: 0x", inner_buffer%get_va()
      print *, "  Inner buffer will be freed at end of block"
    end block
    
    print *, "  Outer buffer still valid:", outer_buffer%is_valid()
    ! Outer buffer freed here
  end subroutine
  
  subroutine test_manual_release()
    type(gpu_buffer) :: buffer
    
    call buffer%init(ctx_ptr, int(4096, i64), SP_BO_HOST_VISIBLE)
    print '(A,Z16)', "  Buffer VA before release: 0x", buffer%get_va()
    
    print *, "  Manually releasing..."
    call buffer%release()
    
    print *, "  Buffer valid after release:", buffer%is_valid()
    print '(A,Z16)', "  Buffer VA after release: 0x", buffer%get_va()
  end subroutine

end program test_pm4_raii