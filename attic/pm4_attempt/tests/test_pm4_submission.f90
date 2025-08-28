program test_pm4_submission
  use sporkle_pm4_compute
  use sporkle_gpu_va_allocator
  implicit none
  
  real :: data_in(1024), data_out(1024)
  integer :: i, status
  real :: time_ms
  
  print *, "🚀 Testing PM4 Direct GPU Submission"
  print *, "===================================="
  
  ! Initialize test data
  do i = 1, 1024
    data_in(i) = real(i)
  end do
  data_out = 0.0
  
  ! Initialize PM4 compute system
  call pm4_init_compute()
  
  ! Execute simple copy shader via PM4
  time_ms = pm4_execute_compute(data_in, size(data_in), &
                               data_out, size(data_out))
  
  if (time_ms < 0.0) then
    print *, "❌ PM4 execution failed!"
  else
    print *, "✅ PM4 execution completed in", time_ms, "ms"
    
    ! Verify results
    status = 0
    do i = 1, min(10, size(data_out))
      if (abs(data_out(i) - data_in(i)) > 0.001) then
        print *, "❌ Mismatch at", i, ":", data_out(i), "vs", data_in(i)
        status = 1
      else
        print *, "✅ data_out(", i, ") =", data_out(i)
      end if
    end do
    
    if (status == 0) then
      print *, ""
      print *, "🎉 PM4 DIRECT SUBMISSION WORKS!"
      print *, "We're bypassing Mesa/ROCm and talking directly to the GPU!"
    end if
  end if
  
  ! Cleanup
  call pm4_cleanup_compute()
  
end program test_pm4_submission