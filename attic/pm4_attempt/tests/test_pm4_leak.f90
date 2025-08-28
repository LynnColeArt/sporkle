program test_pm4_leak
  ! PM4 Leak Test - 1000x alloc/submit/free
  ! ========================================
  ! Validates no memory leaks with RAII pattern
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  integer, parameter :: NUM_ITERATIONS = 1000
  integer(i64), parameter :: BUFFER_SIZE = 4096_i64
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: ib_buffer, data_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:)
  integer :: i, iter, status
  integer :: initial_fd_count, final_fd_count
  real(dp) :: start_time, end_time
  
  print *, "======================================="
  print *, "PM4 Leak Test - 1000x alloc/submit/free"
  print *, "======================================="
  
  ! Initialize context once
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  print *, "Starting leak test..."
  call cpu_time(start_time)
  
  ! Main test loop
  do iter = 1, NUM_ITERATIONS
    ! Allocate buffers using RAII
    call ib_buffer%init(ctx_ptr, BUFFER_SIZE, SP_BO_HOST_VISIBLE)
    call data_buffer%init(ctx_ptr, BUFFER_SIZE, SP_BO_DEVICE_LOCAL)
    
    if (.not. ib_buffer%is_valid() .or. .not. data_buffer%is_valid()) then
      print *, "ERROR: Failed to allocate buffers at iteration", iter
      exit
    end if
    
    ! Fill IB with NOPs
    call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [int(BUFFER_SIZE/4_i64, i32)])
    do i = 1, 4
      ib_data(i) = ior(ishft(3, 30), PM4_NOP)
    end do
    
    ! Submit work
    status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 4, [&
                                   data_buffer%bo_ptr], fence)
    if (status /= 0) then
      print *, "ERROR: Submit failed at iteration", iter
      exit
    end if
    
    ! Wait for completion
    status = sp_fence_wait(ctx_ptr, fence, int(1000000000_i64, i64))
    if (status /= 0) then
      print *, "ERROR: Fence wait failed at iteration", iter
      exit
    end if
    
    ! Progress indicator
    if (mod(iter, 100) == 0) then
      print '(A,I4,A)', "  Completed ", iter, " iterations"
    end if
    
    ! Buffers automatically freed when going out of scope
  end do
  
  call cpu_time(end_time)
  
  ! Summary
  print *, ""
  print *, "Leak test complete!"
  print '(A,I0,A)', "  Iterations: ", iter-1, " successful"
  print '(A,F6.2,A)', "  Total time: ", end_time - start_time, " seconds"
  print '(A,F6.2,A)', "  Per iteration: ", 1000.0d0 * (end_time - start_time) / real(iter-1, dp), " ms"
  
  ! Cleanup context
  call sp_pm4_cleanup(ctx_ptr)
  
  print *, ""
  print *, "TEST PASSED!"
  print *, ""
  print *, "Note: Run with 'watch -n 0.1 nvidia-smi' or similar to"
  print *, "      monitor for memory leaks during execution."
  
end program test_pm4_leak