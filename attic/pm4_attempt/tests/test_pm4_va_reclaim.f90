program test_pm4_va_reclaim
  ! Test that VA space is properly reclaimed after buffer free
  
  use kinds
  use iso_c_binding
  use pm4_submit
  implicit none
  
  type(c_ptr) :: ctx
  type(c_ptr) :: buffers(100)
  integer :: i, cycle
  integer, parameter :: BUFFER_SIZE = 1024 * 1024  ! 1MB
  integer, parameter :: NUM_CYCLES = 10
  
  print *, "PM4 VA Space Reclamation Test"
  print *, "============================="
  print *, ""
  
  ! Initialize PM4 context
  ctx = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  print '(A,I0,A)', "Allocating and freeing ", NUM_CYCLES, " cycles of 100 buffers..."
  
  ! Test VA reclamation by allocating and freeing many times
  do cycle = 1, NUM_CYCLES
    print '(A,I0,A)', "Cycle ", cycle, ": allocating 100 buffers"
    
    ! Allocate 100 buffers
    do i = 1, 100
      buffers(i) = sp_buffer_alloc(ctx, int(BUFFER_SIZE, c_size_t), SP_BO_DEVICE_LOCAL)
      if (.not. c_associated(buffers(i))) then
        print '(A,I0,A,I0)', "ERROR: Failed to allocate buffer ", i, " in cycle ", cycle
        print *, "VA space may be exhausted!"
        stop 1
      end if
    end do
    
    ! Free all buffers
    print '(A,I0,A)', "Cycle ", cycle, ": freeing 100 buffers"
    do i = 1, 100
      call sp_buffer_free(ctx, buffers(i))
    end do
  end do
  
  print *, ""
  print *, "✓ Successfully completed all allocation cycles!"
  print *, "  VA space is being properly reclaimed"
  
  ! Cleanup
  call sp_pm4_cleanup(ctx)
  
  print *, ""
  print *, "Test complete!"
  
end program test_pm4_va_reclaim