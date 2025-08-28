program test_pm4_nop_only
  ! Test with sp_submit_ib_with_bo
  use kinds
  use iso_c_binding
  use pm4_submit
  implicit none
  
  integer(i64), parameter :: IB_SIZE = 4096_i64
  integer(i64), parameter :: BUFFER_SIZE = 4096_i64
  
  type(c_ptr) :: ctx_ptr
  type(c_ptr) :: ib_bo_ptr, output_bo_ptr
  type(sp_bo), pointer :: ib_bo, output_bo
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:)
  integer :: status, i
  
  print *, "======================================="
  print *, "PM4 Test - NOPs with output buffer"
  print *, "======================================="
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  ! Allocate IB
  ib_bo_ptr = sp_buffer_alloc(ctx_ptr, IB_SIZE, SP_BO_HOST_VISIBLE)
  if (.not. c_associated(ib_bo_ptr)) then
    print *, "ERROR: Failed to allocate IB"
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  call c_f_pointer(ib_bo_ptr, ib_bo)
  
  ! Allocate output buffer
  output_bo_ptr = sp_buffer_alloc(ctx_ptr, BUFFER_SIZE, SP_BO_DEVICE_LOCAL)
  if (.not. c_associated(output_bo_ptr)) then
    print *, "ERROR: Failed to allocate output buffer"
    call sp_buffer_free(ctx_ptr, ib_bo_ptr)
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  call c_f_pointer(output_bo_ptr, output_bo)
  
  print '(A,Z16)', "IB VA:     0x", ib_bo%gpu_va
  print '(A,Z16)', "Output VA: 0x", output_bo%gpu_va
  
  ! Fill with NOPs
  call c_f_pointer(ib_bo%cpu_ptr, ib_data, [int(IB_SIZE/4)])
  do i = 1, 4
    ib_data(i) = ior(ishft(3, 30), PM4_NOP)
  end do
  
  ! Submit with both buffers in BO list
  print *, "Submitting IB with output buffer in BO list..."
  status = sp_submit_ib_with_bos(ctx_ptr, ib_bo_ptr, 4, [output_bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: IB submission failed:", status
  else
    print '(A,I0)', "Submitted! Fence: ", fence%fence
    
    status = sp_fence_wait(ctx_ptr, fence, int(1000000000_i64, i64))
    if (status /= 0) then
      print *, "ERROR: Fence wait failed:", status
    else
      print *, "GPU execution complete!"
    end if
  end if
  
  ! Cleanup
  call sp_buffer_free(ctx_ptr, output_bo_ptr)
  call sp_buffer_free(ctx_ptr, ib_bo_ptr)
  call sp_pm4_cleanup(ctx_ptr)
  
  if (status == 0) then
    print *, "TEST PASSED!"
  else
    print *, "TEST FAILED!"
  end if
  
end program test_pm4_nop_only