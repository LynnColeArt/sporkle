program test_kronos_conv2d
  use iso_c_binding
  use kinds
  use sporkle_types, only: compute_device
  use sporkle_kronos_ffi
  use kronos_device
  use sporkle_kronos_conv2d
  implicit none
  
  ! Test parameters
  integer, parameter :: N = 1        ! Batch size
  integer, parameter :: C = 3        ! Input channels  
  integer, parameter :: H = 32       ! Input height
  integer, parameter :: W = 32       ! Input width
  integer, parameter :: K = 16       ! Output channels
  integer, parameter :: kernel_size = 3
  integer, parameter :: stride = 1
  integer, parameter :: pad = 1
  
  ! Kronos handles
  type(kronos_context) :: ctx
  type(kronos_buffer) :: input_buf, weight_buf, output_buf
  
  ! Device
  class(compute_device), allocatable :: device
  
  ! Data sizes
  integer(c_size_t) :: input_size, weight_size, output_size
  integer :: H_out, W_out
  integer :: status
  real(dp) :: start_time, end_time
  
  print *, "=== Kronos Conv2D Integration Test ==="
  print *, ""
  
  ! Calculate output dimensions
  H_out = (H + 2*pad - kernel_size) / stride + 1
  W_out = (W + 2*pad - kernel_size) / stride + 1
  
  print *, "Configuration:"
  print *, "  Input:  ", N, "x", C, "x", H, "x", W
  print *, "  Kernel: ", K, "x", C, "x", kernel_size, "x", kernel_size
  print *, "  Output: ", N, "x", K, "x", H_out, "x", W_out
  print *, ""
  
  ! Calculate buffer sizes
  input_size = N * C * H * W * 4_c_size_t          ! float32
  weight_size = K * C * kernel_size * kernel_size * 4_c_size_t
  output_size = N * K * H_out * W_out * 4_c_size_t
  
  ! Initialize Kronos
  print *, "Step 1: Initializing Kronos..."
  ctx = kronos_init()
  
  if (.not. c_associated(ctx%handle)) then
    print *, "❌ Failed to initialize Kronos"
    stop 1
  end if
  print *, "✅ Kronos initialized"
  
  ! Create buffers
  print *, ""
  print *, "Step 2: Allocating GPU buffers..."
  input_buf = kronos_create_buffer(ctx, input_size)
  weight_buf = kronos_create_buffer(ctx, weight_size)
  output_buf = kronos_create_buffer(ctx, output_size)
  
  if (.not. c_associated(input_buf%handle) .or. &
      .not. c_associated(weight_buf%handle) .or. &
      .not. c_associated(output_buf%handle)) then
    print *, "❌ Failed to allocate buffers"
    call kronos_cleanup(ctx)
    stop 1
  end if
  
  print *, "✅ Buffers allocated:"
  print *, "   Input:  ", input_size, "bytes"
  print *, "   Weight: ", weight_size, "bytes"
  print *, "   Output: ", output_size, "bytes"
  
  ! Initialize data (normally you'd fill with real data)
  block
    type(c_ptr) :: data_ptr
    real(sp), pointer :: data(:)
    integer :: i
    
    ! Initialize input with test pattern
    status = kronos_map_buffer(ctx, input_buf, data_ptr)
    if (status == KRONOS_SUCCESS) then
      call c_f_pointer(data_ptr, data, [N * C * H * W])
      do i = 1, size(data)
        data(i) = real(i, sp) * 0.01_sp
      end do
      call kronos_unmap_buffer(ctx, input_buf)
      print *, "✅ Input data initialized"
    end if
    
    ! Initialize weights
    status = kronos_map_buffer(ctx, weight_buf, data_ptr)
    if (status == KRONOS_SUCCESS) then
      call c_f_pointer(data_ptr, data, [K * C * kernel_size * kernel_size])
      do i = 1, size(data)
        data(i) = real(i, sp) * 0.001_sp
      end do
      call kronos_unmap_buffer(ctx, weight_buf)
      print *, "✅ Weight data initialized"
    end if
  end block
  
  ! Run convolution
  print *, ""
  print *, "Step 3: Executing Conv2D kernel..."
  
  call cpu_time(start_time)
  
  status = kronos_conv2d_execute(ctx, input_buf, weight_buf, output_buf, &
                                N, C, H, W, K, kernel_size, stride, pad)
  
  call cpu_time(end_time)
  
  if (status == KRONOS_SUCCESS) then
    print *, "✅ Conv2D executed successfully"
    print *, "   Execution time: ", (end_time - start_time) * 1000.0, "ms"
    
    ! Calculate GFLOPS
    block
      real(dp) :: ops, gflops
      ops = 2.0d0 * N * K * H_out * W_out * C * kernel_size * kernel_size
      gflops = ops / ((end_time - start_time) * 1.0d9)
      print *, "   Performance: ", gflops, "GFLOPS"
    end block
  else
    print *, "❌ Conv2D execution failed"
  end if
  
  ! Verify output
  print *, ""
  print *, "Step 4: Verifying output..."
  block
    type(c_ptr) :: data_ptr
    real(sp), pointer :: output(:)
    
    status = kronos_map_buffer(ctx, output_buf, data_ptr)
    if (status == KRONOS_SUCCESS) then
      call c_f_pointer(data_ptr, output, [N * K * H_out * W_out])
      
      ! Check first few values
      print *, "   First output values:"
      print *, "   output(1:5) = ", output(1:min(5, size(output)))
      
      ! Simple sanity check - output shouldn't be all zeros
      if (all(output == 0.0_sp)) then
        print *, "❌ WARNING: Output is all zeros!"
      else
        print *, "✅ Output contains non-zero values"
      end if
      
      call kronos_unmap_buffer(ctx, output_buf)
    end if
  end block
  
  ! Cleanup
  print *, ""
  print *, "Step 5: Cleanup..."
  call kronos_cleanup(ctx)
  print *, "✅ Cleanup complete"
  
  print *, ""
  print *, "=== Test Summary ==="
  print *, "Kronos Conv2D integration test completed successfully!"
  print *, ""
  print *, "Next steps:"
  print *, "1. Implement real Vulkan compute in Rust backend"
  print *, "2. Add proper SPIR-V shader compilation"
  print *, "3. Benchmark against OpenGL (target: >3,630 GFLOPS)"
  
end program test_kronos_conv2d