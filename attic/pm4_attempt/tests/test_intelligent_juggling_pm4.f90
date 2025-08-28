program test_intelligent_juggling_pm4
  ! Test PM4-enhanced intelligent device juggling
  
  use kinds
  use intelligent_device_juggling
  use intelligent_device_juggling_pm4
  implicit none
  
  type(juggling_strategy) :: strategy
  type(workload_partition) :: partition
  integer(i64) :: total_flops
  real(sp) :: workload_sizes(5) = [0.05, 0.5, 5.0, 50.0, 500.0]  ! GFLOPS
  integer :: i
  
  print *, "PM4-Enhanced Intelligent Device Juggling Test"
  print *, "==========================================="
  print *, ""
  
  ! Discover devices using PM4
  call discover_and_profile_devices_pm4(strategy)
  
  print *, ""
  print *, "Testing workload distribution strategies:"
  print *, "----------------------------------------"
  
  ! Test different workload sizes
  do i = 1, size(workload_sizes)
    total_flops = int(workload_sizes(i) * 1.0e9, i64)
    
    print *, ""
    print '(A,F0.1,A)', "Workload: ", workload_sizes(i), " GFLOPS"
    
    partition = optimize_workload_distribution(strategy, total_flops, "conv2d")
    
    ! Display partition details
    if (partition%use_cpu .and. partition%use_gpu) then
      print '(A,I0,A,I0,A)', "  Distribution: CPU ", partition%cpu_work_percent, &
                             "%, GPU ", partition%gpu_work_percent, "%"
    else if (partition%use_cpu) then
      print *, "  Distribution: CPU only"
    else if (partition%use_gpu) then
      print *, "  Distribution: GPU only"
    end if
    
    print '(A,F0.2,A,F0.1,A)', "  Predicted: ", partition%predicted_time_ms, &
                               " ms (", partition%predicted_gflops, " GFLOPS)"
  end do
  
  print *, ""
  print *, "Test complete!"
  
end program test_intelligent_juggling_pm4