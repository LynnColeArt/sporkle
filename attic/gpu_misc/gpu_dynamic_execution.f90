module gpu_dynamic_execution
  use iso_c_binding
  use sporkle_types
  use sporkle_dynamic_shader_system
  use sporkle_glsl_generator
  use gpu_opengl_interface
  use sporkle_rdna_shader_generator
  use kinds
  implicit none
  
  private
  public :: gpu_execute_with_dynamic_shader, gpu_benchmark_shader_variants
  
  interface
    ! Interface to C function that can compile and execute arbitrary shader source
    function gpu_execute_conv2d_with_shader_c(input, weights, output, &
                                             N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, &
                                             shader_source) &
                                             bind(C, name="gpu_execute_conv2d_with_shader") result(time_ms)
      use iso_c_binding
      implicit none
      type(c_ptr), value :: input, weights, output
      integer(c_int), value :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
      type(c_ptr), value :: shader_source
      real(c_float) :: time_ms
    end function
  end interface
  
contains

  ! Execute convolution with dynamically generated shader
  function gpu_execute_with_dynamic_shader(shader_sys, input, weights, output, &
                                          N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    type(shader_system), intent(inout) :: shader_sys
    real(sp), intent(in), target :: input(*)
    real(sp), intent(in), target :: weights(*)
    real(sp), intent(out), target :: output(*)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    type(convolution_config) :: conv_cfg
    character(len=:), allocatable :: shader_source
    character(len=1), allocatable, target :: shader_c(:)
    integer :: i
    
    ! Setup convolution config
    conv_cfg%input_height = H
    conv_cfg%input_width = W
    conv_cfg%input_channels = C
    conv_cfg%kernel_height = kernel_size
    conv_cfg%kernel_width = kernel_size
    conv_cfg%output_height = H_out
    conv_cfg%output_width = W_out
    conv_cfg%output_channels = K
    conv_cfg%stride_y = stride
    conv_cfg%stride_x = stride
    conv_cfg%pad_y = pad
    conv_cfg%pad_x = pad
    conv_cfg%tile_size = 16
    conv_cfg%use_fp16 = .false.
    
    ! Get optimal shader from dynamic system
    shader_source = get_optimal_shader(shader_sys, "conv2d", conv_cfg)
    
    ! Convert to C string
    allocate(shader_c(len(shader_source) + 1))
    do i = 1, len(shader_source)
      shader_c(i) = shader_source(i:i)
    end do
    shader_c(len(shader_source) + 1) = c_null_char
    
    ! Execute on GPU with dynamic shader
    time_ms = gpu_execute_conv2d_with_shader_c( &
      c_loc(input), c_loc(weights), c_loc(output), &
      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, &
      c_loc(shader_c))
    
    ! Update performance in learning system
    if (shader_sys%auto_tune) then
      call update_performance_system(shader_sys, "conv2d", "dynamic", time_ms, N*K*H_out*W_out)
    end if
    
    deallocate(shader_c)
    
  end function gpu_execute_with_dynamic_shader
  
  ! Benchmark different shader variants
  subroutine gpu_benchmark_shader_variants(input, weights, output, &
                                          N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    real(sp), dimension(:), intent(in), target :: input
    real(sp), dimension(:), intent(in), target :: weights
    real(sp), dimension(:), intent(out), target :: output
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    type(shader_system) :: shader_sys
    type(convolution_config) :: conv_cfg
    type(rdna_config) :: rdna_cfg
    character(len=:), allocatable :: shader_source
    character(len=1), allocatable, target :: shader_c(:)
    real(sp) :: time_ms, best_time
    real(dp) :: gflops
    integer(c_int64_t) :: flop_count
    integer :: i
    character(len=64) :: variant_name
    
    ! Calculate FLOPs
    flop_count = int(N, c_int64_t) * int(K, c_int64_t) * &
                 int(H_out, c_int64_t) * int(W_out, c_int64_t) * &
                 int(C, c_int64_t) * int(kernel_size, c_int64_t) * &
                 int(kernel_size, c_int64_t) * 2_c_int64_t
    
    ! Initialize shader system
    call init_shader_system(shader_sys, 0)
    
    ! Setup convolution config
    conv_cfg%input_height = H
    conv_cfg%input_width = W
    conv_cfg%input_channels = C
    conv_cfg%kernel_height = kernel_size
    conv_cfg%kernel_width = kernel_size
    conv_cfg%output_height = H_out
    conv_cfg%output_width = W_out
    conv_cfg%output_channels = K
    conv_cfg%stride_y = stride
    conv_cfg%stride_x = stride
    conv_cfg%pad_y = pad
    conv_cfg%pad_x = pad
    conv_cfg%tile_size = 16
    conv_cfg%use_fp16 = .false.
    
    print *, ""
    print *, "=== Benchmarking Shader Variants on GPU ==="
    print *, ""
    
    best_time = 1000.0  ! Large initial value
    
    ! Test 1: Reference implementation
    print *, "1. Reference Implementation (hardcoded):"
    time_ms = gpu_execute_conv2d_ref(input, weights, output, &
                                     N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    gflops = real(flop_count, real64) / (real(time_ms, real64) * 1.0e6)
    print '(A,F8.2,A,F8.1,A)', "   Time: ", time_ms, " ms, Performance: ", gflops, " GFLOPS"
    best_time = min(best_time, time_ms)
    
    ! Test 2: RDNA Wave32 basic (64 threads)
    print *, ""
    print *, "2. RDNA Wave32 Basic (64 threads):"
    rdna_cfg%arch = detect_rdna_arch(0)
    rdna_cfg%workgroup_size = 64
    rdna_cfg%waves_per_cu = 4
    rdna_cfg%use_lds = .false.
    rdna_cfg%use_dual_issue = .false.
    shader_source = generate_rdna_conv_shader(rdna_cfg, conv_cfg)
    
    ! Convert and execute
    allocate(shader_c(len(shader_source) + 1))
    do i = 1, len(shader_source)
      shader_c(i) = shader_source(i:i)
    end do
    shader_c(len(shader_source) + 1) = c_null_char
    
    time_ms = gpu_execute_conv2d_with_shader_c( &
      c_loc(input), c_loc(weights), c_loc(output), &
      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, &
      c_loc(shader_c))
    
    gflops = real(flop_count, real64) / (real(time_ms, real64) * 1.0e6)
    print '(A,F8.2,A,F8.1,A)', "   Time: ", time_ms, " ms, Performance: ", gflops, " GFLOPS"
    if (time_ms < best_time) then
      print *, "   ⭐ New best!"
      best_time = time_ms
    end if
    deallocate(shader_c)
    
    ! Test 3: RDNA3 Dual-issue
    print *, ""
    print *, "3. RDNA3 Dual-Issue Optimized:"
    rdna_cfg%use_dual_issue = .true.
    shader_source = generate_rdna_conv_shader(rdna_cfg, conv_cfg)
    
    allocate(shader_c(len(shader_source) + 1))
    do i = 1, len(shader_source)
      shader_c(i) = shader_source(i:i)
    end do
    shader_c(len(shader_source) + 1) = c_null_char
    
    time_ms = gpu_execute_conv2d_with_shader_c( &
      c_loc(input), c_loc(weights), c_loc(output), &
      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, &
      c_loc(shader_c))
    
    gflops = real(flop_count, real64) / (real(time_ms, real64) * 1.0e6)
    print '(A,F8.2,A,F8.1,A)', "   Time: ", time_ms, " ms, Performance: ", gflops, " GFLOPS"
    if (time_ms < best_time) then
      print *, "   ⭐ New best!"
      best_time = time_ms
    end if
    deallocate(shader_c)
    
    ! Test 4: Large workgroup (256 threads)
    print *, ""
    print *, "4. Large Workgroup (256 threads = 8 waves):"
    rdna_cfg%workgroup_size = 256
    rdna_cfg%use_dual_issue = .false.
    shader_source = generate_rdna_conv_shader(rdna_cfg, conv_cfg)
    
    allocate(shader_c(len(shader_source) + 1))
    do i = 1, len(shader_source)
      shader_c(i) = shader_source(i:i)
    end do
    shader_c(len(shader_source) + 1) = c_null_char
    
    time_ms = gpu_execute_conv2d_with_shader_c( &
      c_loc(input), c_loc(weights), c_loc(output), &
      N, C, H, W, K, kernel_size, stride, pad, H_out, W_out, &
      c_loc(shader_c))
    
    gflops = real(flop_count, real64) / (real(time_ms, real64) * 1.0e6)
    print '(A,F8.2,A,F8.1,A)', "   Time: ", time_ms, " ms, Performance: ", gflops, " GFLOPS"
    deallocate(shader_c)
    
    print *, ""
    print *, "=== Summary ==="
    gflops = real(flop_count, real64) / (real(best_time, real64) * 1.0e6)
    print '(A,F8.2,A,F8.1,A)', "Best time: ", best_time, " ms (", gflops, " GFLOPS)"
    print *, ""
    
  end subroutine gpu_benchmark_shader_variants

end module gpu_dynamic_execution