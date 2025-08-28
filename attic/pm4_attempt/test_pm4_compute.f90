program test_pm4_compute
  use kinds
  use sporkle_pm4_compute
  use sporkle_pm4_packets
  implicit none
  
  logical :: success
  integer :: i
  real(sp) :: input(256), output(256), expected(256)
  real(sp) :: time_ms
  integer :: N, H, W, C, K, kernel_size, stride, pad
  integer :: H_out, W_out
  
  print *, "🧪 PM4 Compute Test"
  print *, "==================="
  print *, ""
  
  ! Test 1: Initialize PM4 compute
  print *, "🚀 Test 1: PM4 Compute Initialization"
  success = pm4_init_compute()
  if (.not. success) then
    print *, "❌ Failed to initialize PM4 compute"
    print *, "   Make sure you have an AMD GPU and proper permissions"
    stop 1
  end if
  print *, "✅ PM4 compute initialized!"
  print *, ""
  
  ! Test 2: Compile a shader
  print *, "🔨 Test 2: Shader Compilation"
  block
    integer(i64) :: shader_addr
    
    shader_addr = pm4_compile_shader("test_shader", "s_endpgm")
    if (shader_addr == 0) then
      print *, "❌ Failed to compile shader"
    else
      print '(A,Z16)', "✅ Shader compiled at address: 0x", shader_addr
    end if
  end block
  print *, ""
  
  ! Test 3: Simple convolution test
  print *, "🏃 Test 3: Conv2D Test"
  print *, "   Testing very small conv2d..."
  
  ! Setup tiny test case
  N = 1
  H = 4
  W = 4  
  C = 1
  K = 1
  kernel_size = 3
  stride = 1
  pad = 1
  H_out = (H + 2*pad - kernel_size) / stride + 1
  W_out = (W + 2*pad - kernel_size) / stride + 1
  
  ! Initialize test data
  input = 1.0
  output = 0.0
  
  print *, "   Input shape:", N, "x", C, "x", H, "x", W
  print *, "   Output shape:", N, "x", K, "x", H_out, "x", W_out
  print *, "   Kernel:", kernel_size, "x", kernel_size
  
  time_ms = pm4_conv2d_direct(input(1:N*C*H*W), &
                             input(1:K*C*kernel_size*kernel_size), &  ! Dummy weights
                             output(1:N*K*H_out*W_out), &
                             N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
                             
  if (time_ms >= 0.0) then
    print '(A,F0.3,A)', "✅ Conv2D completed in ", time_ms, " ms"
    print *, "   Output values:", output(1:min(5, N*K*H_out*W_out))
  else
    print *, "❌ Conv2D failed"
    print *, "   This is expected - we need real ISA shaders"
  end if
  
  ! Cleanup
  print *, ""
  print *, "🧹 Cleaning up..."
  call pm4_cleanup_compute()
  
  print *, ""
  print *, "✅ PM4 compute test complete!"
  print *, ""
  print *, "Next steps:"
  print *, "1. Implement real GCN/RDNA ISA assembly"
  print *, "2. Create proper conv2d compute shader" 
  print *, "3. Add buffer management and BO lists"
  print *, "4. Benchmark against OpenGL implementation"
  
end program test_pm4_compute