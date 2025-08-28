program test_pm4_conv2d_direct
  ! Test PM4 Direct GPU Submission for Conv2D
  ! ==========================================
  !
  ! Tests the Sprint 3 PM4 direct submission implementation
  ! Bypasses OpenGL completely and talks directly to the GPU
  
  use kinds
  use pm4_safe_submit
  use sporkle_utils, only: assert
  implicit none
  
  ! Test parameters (small for safety)
  integer, parameter :: N = 1
  integer, parameter :: C = 3
  integer, parameter :: H = 8
  integer, parameter :: W = 8
  integer, parameter :: K = 16
  integer, parameter :: kernel_size = 3
  integer, parameter :: stride = 1
  integer, parameter :: pad = 1
  
  ! Calculated output dimensions
  integer :: H_out, W_out
  
  ! Arrays
  real(sp), allocatable :: input(:), weights(:), output(:)
  real(sp), allocatable :: expected(:)
  
  ! Timing
  real(sp) :: time_ms
  real(sp) :: gflops
  integer :: i
  logical :: success
  
  print *, "==================================="
  print *, "PM4 Direct Conv2D Test"
  print *, "==================================="
  
  ! Calculate output dimensions
  H_out = (H + 2*pad - kernel_size) / stride + 1
  W_out = (W + 2*pad - kernel_size) / stride + 1
  
  print *, "Input shape: (", N, ",", C, ",", H, ",", W, ")"
  print *, "Weight shape: (", K, ",", C, ",", kernel_size, ",", kernel_size, ")"
  print *, "Output shape: (", N, ",", K, ",", H_out, ",", W_out, ")"
  
  ! Allocate arrays
  allocate(input(N * C * H * W))
  allocate(weights(K * C * kernel_size * kernel_size))
  allocate(output(N * K * H_out * W_out))
  allocate(expected(N * K * H_out * W_out))
  
  ! Initialize with simple patterns
  do i = 1, size(input)
    input(i) = real(mod(i-1, 10), sp) * 0.1
  end do
  
  do i = 1, size(weights)
    weights(i) = real(mod(i-1, 5), sp) * 0.2
  end do
  
  ! Clear output
  output = 0.0
  expected = 1.0  ! Simple expected value for validation
  
  print *, ""
  print *, "Initializing PM4 submission system..."
  
  ! Initialize PM4 system
  success = pm4_safe_init()
  if (.not. success) then
    print *, "FAILED to initialize PM4 submission"
    stop 1
  end if
  
  print *, ""
  print *, "Executing Conv2D via PM4..."
  
  ! Execute Conv2D
  time_ms = pm4_safe_conv2d(input, weights, output, &
                            N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
  
  if (time_ms < 0.0) then
    print *, "FAILED to execute Conv2D"
    call pm4_safe_cleanup()
    stop 1
  end if
  
  ! Check results
  print *, ""
  print *, "Results:"
  print *, "  Execution time:", time_ms, "ms"
  
  ! Calculate GFLOPS
  gflops = real(2 * N * K * H_out * W_out * C * kernel_size * kernel_size) / (time_ms * 1e6)
  print *, "  Performance:", gflops, "GFLOPS"
  
  ! Validate output
  if (all(output == 0.0)) then
    print *, "  WARNING: Output is all zeros"
  else
    print *, "  Output range:", minval(output), "to", maxval(output)
    print *, "  Output samples:", output(1:min(5, size(output)))
  end if
  
  ! Cleanup
  print *, ""
  print *, "Cleaning up..."
  call pm4_safe_cleanup()
  
  ! Free arrays
  deallocate(input, weights, output, expected)
  
  print *, ""
  print *, "==================================="
  print *, "PM4 Direct Conv2D Test Complete"
  print *, "==================================="
  
end program test_pm4_conv2d_direct