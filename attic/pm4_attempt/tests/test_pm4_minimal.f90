program test_pm4_minimal
  ! Minimal PM4 Test - Just NOPs
  ! =============================
  ! Submit simplest possible PM4 command stream
  
  use kinds
  use iso_c_binding
  use pm4_submit
  implicit none
  
  ! Test parameters
  integer(i64), parameter :: IB_SIZE = 4096_i64
  
  ! PM4 context and buffers
  type(c_ptr) :: ctx_ptr
  type(c_ptr) :: ib_bo_ptr
  type(sp_bo), pointer :: ib_bo
  type(sp_fence) :: fence
  
  ! IB data
  integer(c_int32_t), pointer :: ib_data(:)
  integer :: status, i
  
  print *, "======================================="
  print *, "PM4 Minimal Test - Just NOPs"
  print *, "======================================="
  
  ! Initialize PM4 context
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  print *, "PM4 context initialized"
  
  ! Allocate indirect buffer
  ib_bo_ptr = sp_buffer_alloc(ctx_ptr, IB_SIZE, SP_BO_HOST_VISIBLE)
  if (.not. c_associated(ib_bo_ptr)) then
    print *, "ERROR: Failed to allocate IB"
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  call c_f_pointer(ib_bo_ptr, ib_bo)
  
  print '(A,Z16)', "IB GPU VA: 0x", ib_bo%gpu_va
  
  ! Map IB and fill with NOPs
  if (.not. c_associated(ib_bo%cpu_ptr)) then
    print *, "ERROR: IB not CPU mapped"
    call sp_buffer_free(ctx_ptr, ib_bo_ptr)
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  
  call c_f_pointer(ib_bo%cpu_ptr, ib_data, [int(IB_SIZE/4)])
  
  ! Fill with just 4 NOPs
  do i = 1, 4
    ib_data(i) = ior(ishft(3, 30), PM4_NOP)  ! Type 3 NOP
  end do
  
  print *, "IB contents:"
  do i = 1, 4
    print '(A,I2,A,Z8)', "  [", i, "] = 0x", ib_data(i)
  end do
  
  ! Submit the minimal IB using unified API
  print *, "Submitting minimal IB..."
  ! For minimal test, we have no data BOs
  status = sp_submit_ib_with_bos(ctx_ptr, ib_bo_ptr, 4, [c_ptr::], fence)
  if (status /= 0) then
    print *, "ERROR: IB submission failed:", status
    call sp_buffer_free(ctx_ptr, ib_bo_ptr)
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  
  print '(A,I0)', "Submitted! Fence: ", fence%fence
  
  ! Wait for completion
  status = sp_fence_wait(ctx_ptr, fence, int(1000000000_i64, i64))
  if (status /= 0) then
    print *, "ERROR: Fence wait failed:", status
  else
    print *, "GPU execution complete!"
  end if
  
  ! Cleanup
  call sp_buffer_free(ctx_ptr, ib_bo_ptr)
  call sp_pm4_cleanup(ctx_ptr)
  
  print *, "TEST PASSED!"
  
end program test_pm4_minimal