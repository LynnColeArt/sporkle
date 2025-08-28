program test_pm4_conv2d
  ! Test PM4 Direct Conv2D Submission
  ! =================================
  !
  ! Tests the Neo Geo style direct hardware submission
  
  use kinds
  use iso_c_binding
  use pm4_safe_submit
  use gpu_opengl_zero_copy, only: gpu_init_zero_copy, gpu_cleanup_zero_copy, &
                                  gpu_execute_conv2d_zero_copy
  implicit none
  
  ! Test parameters - same as before
  integer, parameter :: N = 8        ! Batch size
  integer, parameter :: C = 64       ! Input channels  
  integer, parameter :: H = 56       ! Height
  integer, parameter :: W = 56       ! Width
  integer, parameter :: K = 128      ! Output channels
  integer, parameter :: kernel_size = 3
  integer, parameter :: stride = 1
  integer, parameter :: pad = 1
  integer, parameter :: H_out = H    ! Same due to padding
  integer, parameter :: W_out = W
  
  ! Data arrays
  real(sp), allocatable :: input(:), weights(:), output(:)
  real(sp), allocatable :: output_ref(:)
  
  ! Timing
  real(sp) :: time_opengl, time_pm4
  integer :: i, test_runs = 5
  
  ! Performance stats
  integer(i64) :: total_flops
  real(sp) :: gflops_opengl, gflops_pm4
  
  print *, "🕹️  PM4 Direct Conv2D Test (Neo Geo Mode)"
  print *, "========================================"
  print *, ""
  
  ! Calculate workload size
  total_flops = int(N, int64) * int(K, int64) * int(H_out, int64) * int(W_out, int64) * &
                int(C, int64) * int(kernel_size, int64) * int(kernel_size, int64) * 2_int64
  
  print '(A,I0,A)', "Workload: ", total_flops / 1000000, " MFLOPS"
  print '(A,I0,A,I0,A,I0,A,I0)', "Input: ", N, "x", C, "x", H, "x", W
  print '(A,I0,A,I0,A,I0)', "Conv: ", K, " filters, ", kernel_size, "x", kernel_size
  print *, ""
  
  ! Allocate arrays
  allocate(input(N * C * H * W))
  allocate(weights(K * C * kernel_size * kernel_size))
  allocate(output(N * K * H_out * W_out))
  allocate(output_ref(N * K * H_out * W_out))
  
  ! Initialize with test data
  call random_number(input)
  call random_number(weights)
  input = input - 0.5
  weights = weights - 0.5
  
  ! Test 1: OpenGL reference (zero-copy)
  print *, "📊 Testing OpenGL zero-copy (reference)..."
  if (.not. gpu_init_zero_copy()) then
    print *, "❌ Failed to initialize zero-copy GPU"
    stop 1
  end if
  
  ! Warmup
  time_opengl = gpu_execute_conv2d_zero_copy(input, weights, output_ref, &
                                            N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
  
  ! Measure
  time_opengl = 0.0
  do i = 1, test_runs
    time_opengl = time_opengl + gpu_execute_conv2d_zero_copy(input, weights, output_ref, &
                                                             N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
  end do
  time_opengl = time_opengl / test_runs
  
  gflops_opengl = real(total_flops) / (time_opengl * 1.0e6)
  
  call gpu_cleanup_zero_copy()
  
  print '(A,F8.3,A)', "OpenGL time: ", time_opengl, " ms"
  print '(A,F8.1,A)', "OpenGL performance: ", gflops_opengl, " GFLOPS"
  
  ! Test 2: PM4 direct submission
  print *, ""
  print *, "🎮 Testing PM4 direct submission..."
  
  if (.not. pm4_safe_init()) then
    print *, "❌ Failed to initialize PM4 submission"
    print *, "   This is expected if not running as root or without GPU access"
    print *, "   Skipping PM4 test..."
  else
    ! Warmup
    time_pm4 = pm4_safe_conv2d(input, weights, output, &
                              N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    
    if (time_pm4 < 0) then
      print *, "❌ PM4 execution failed"
      print *, "   This might be due to missing shader binary or safety checks"
    else
      ! Measure
      time_pm4 = 0.0
      do i = 1, test_runs
        time_pm4 = time_pm4 + pm4_safe_conv2d(input, weights, output, &
                                              N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
      end do
      time_pm4 = time_pm4 / test_runs
      
      gflops_pm4 = real(total_flops) / (time_pm4 * 1.0e6)
      
      print '(A,F8.3,A)', "PM4 time: ", time_pm4, " ms"
      print '(A,F8.1,A)', "PM4 performance: ", gflops_pm4, " GFLOPS"
      
      ! Verify correctness
      print *, ""
      print *, "🔍 Verifying correctness..."
      block
        real(sp) :: max_diff, avg_diff
        integer :: j
        
        max_diff = 0.0
        avg_diff = 0.0
        do j = 1, size(output)
          max_diff = max(max_diff, abs(output(j) - output_ref(j)))
          avg_diff = avg_diff + abs(output(j) - output_ref(j))
        end do
        avg_diff = avg_diff / size(output)
        
        print '(A,E12.5)', "Max difference: ", max_diff
        print '(A,E12.5)', "Avg difference: ", avg_diff
        
        if (max_diff < 1e-3) then
          print *, "✅ Results match!"
        else
          print *, "❌ Results differ!"
        end if
      end block
      
      ! Performance comparison
      print *, ""
      print *, "📈 Performance Comparison:"
      print *, "========================"
      print '(A,F8.1,A)', "OpenGL (driver):  ", gflops_opengl, " GFLOPS"
      print '(A,F8.1,A)', "PM4 (direct):     ", gflops_pm4, " GFLOPS"
      print '(A,F8.2,A)', "Speedup:          ", gflops_pm4 / gflops_opengl, "x"
      
      if (gflops_pm4 > gflops_opengl * 2.0) then
        print *, ""
        print *, "🎉 Neo Geo mode achieved significant speedup!"
        print *, "   Direct hardware submission bypasses driver overhead"
      end if
    end if
    
    call pm4_safe_cleanup()
  end if
  
  ! Cleanup
  deallocate(input, weights, output, output_ref)
  
  print *, ""
  print *, "🏁 Test complete!"
  
end program test_pm4_conv2d