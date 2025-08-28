module sporkle_gpu_benchmark
  ! Real GPU benchmarking with accurate timing
  use kinds
  use iso_c_binding
  use gl_constants
  use sporkle_gpu_executor
  use sporkle_shader_parser_v2
  use sporkle_fortran_params
  implicit none
  private
  
  public :: benchmark_kernel, gpu_benchmark_param_methods
  public :: measure_arithmetic_intensity, profile_kernel, kernel_profile
  
  type :: kernel_profile
    real(dp) :: time_ms = 0.0
    real(dp) :: gflops = 0.0
    real(dp) :: bandwidth_gb_s = 0.0
    real(dp) :: arithmetic_intensity = 0.0
    integer :: optimal_local_size = 64
    integer :: optimal_param_method = PARAMS_BUFFER
  end type kernel_profile
  
contains

  function get_gpu_timestamp() result(timestamp)
    integer(c_int64_t) :: timestamp
    integer(c_int) :: query_ids(1)
    integer(c_int) :: query_result
    
    ! Create and execute timestamp query
    call glGenQueries(1, query_ids)
    call glQueryCounter(query_ids(1), GL_TIMESTAMP)
    
    ! Wait for result
    query_result = 0
    do while (query_result == 0)
      call glGetQueryObjectiv(query_ids(1), GL_QUERY_RESULT_AVAILABLE, query_result)
    end do
    
    ! Get timestamp
    call glGetQueryObjecti64v(query_ids(1), GL_QUERY_RESULT, timestamp)
    call glDeleteQueries(1, query_ids)
  end function get_gpu_timestamp
  
  function benchmark_kernel(exec, kernel, work_size, params, iterations) result(time_ms)
    type(gpu_executor), intent(inout) :: exec
    type(shader_kernel_v2), intent(in) :: kernel
    integer, intent(in) :: work_size
    real(sp), dimension(:), intent(in) :: params
    integer, intent(in) :: iterations
    real(dp) :: time_ms
    
    integer(c_int64_t) :: start_time, end_time
    integer :: i
    
    ! Warmup run
    call execute_kernel(exec, kernel, work_size, params)
    call glFinish()
    
    ! Timed runs
    start_time = get_gpu_timestamp()
    
    do i = 1, iterations
      call execute_kernel(exec, kernel, work_size, params)
    end do
    
    call glFinish()
    end_time = get_gpu_timestamp()
    
    ! Convert nanoseconds to milliseconds
    time_ms = real(end_time - start_time, real64) / 1.0e6_real64 / real(iterations, real64)
  end function benchmark_kernel
  
  function gpu_benchmark_param_methods(kernel, work_size, params) result(best_method)
    type(shader_kernel_v2), intent(inout) :: kernel
    integer, intent(in) :: work_size
    real(sp), dimension(:), intent(in) :: params
    integer :: best_method
    
    type(gpu_executor) :: exec_uniform, exec_buffer, exec_inline
    real(dp) :: time_uniform, time_buffer, time_inline
    real(dp) :: best_time
    
    best_time = huge(1.0_real64)
    best_method = PARAMS_BUFFER
    
    ! Benchmark UNIFORM method
    kernel%param_method = PARAMS_UNIFORM
    call initialize_executor(exec_uniform, kernel)
    if (exec_uniform%initialized) then
      time_uniform = benchmark_kernel(exec_uniform, kernel, work_size, params, 100)
      print '(A,F10.4,A)', "  UNIFORM method: ", time_uniform, " ms"
      if (time_uniform < best_time) then
        best_time = time_uniform
        best_method = PARAMS_UNIFORM
      end if
      call cleanup_executor(exec_uniform)
    end if
    
    ! Benchmark BUFFER method
    kernel%param_method = PARAMS_BUFFER
    call initialize_executor(exec_buffer, kernel)
    if (exec_buffer%initialized) then
      time_buffer = benchmark_kernel(exec_buffer, kernel, work_size, params, 100)
      print '(A,F10.4,A)', "  BUFFER method:  ", time_buffer, " ms"
      if (time_buffer < best_time) then
        best_time = time_buffer
        best_method = PARAMS_BUFFER
      end if
      call cleanup_executor(exec_buffer)
    end if
    
    ! TODO: Benchmark INLINE method when implemented
    ! For now, INLINE would require shader recompilation
    
    select case (best_method)
    case (PARAMS_UNIFORM)
      print *, "  Best method: UNIFORM"
    case (PARAMS_BUFFER)
      print *, "  Best method: BUFFER"
    case (PARAMS_INLINE)
      print *, "  Best method: INLINE"
    end select
  end function gpu_benchmark_param_methods
  
  function measure_arithmetic_intensity(kernel, work_size) result(intensity)
    type(shader_kernel_v2), intent(in) :: kernel
    integer, intent(in) :: work_size
    real(dp) :: intensity
    
    integer :: flops, bytes_accessed
    integer :: num_arrays, num_scalars
    
    ! Count arrays and scalars
    num_arrays = 0
    num_scalars = 0
    if (allocated(kernel%args)) then
      num_arrays = count(.not. kernel%args%is_scalar)
      num_scalars = count(kernel%args%is_scalar)
    end if
    
    ! Estimate based on kernel type
    if (index(kernel%name, "gemm") > 0) then
      ! GEMM: 2*M*N*K FLOPs
      flops = 2 * work_size * 256  ! Rough estimate
      bytes_accessed = num_arrays * work_size * 4  ! float size
    else if (index(kernel%name, "im2col") > 0) then
      ! im2col: Mostly memory bound
      flops = work_size * 10  ! Few ops per element
      bytes_accessed = work_size * 4 * 3  ! Read input, write output
    else if (index(kernel%name, "conv") > 0) then
      ! Convolution: Variable based on kernel size
      flops = work_size * 100  ! Estimate
      bytes_accessed = work_size * 4 * 4
    else
      ! Default estimate
      flops = work_size * 50
      bytes_accessed = work_size * 4 * num_arrays
    end if
    
    intensity = real(flops, real64) / real(bytes_accessed, real64)
    print '(A,F8.2)', "  Arithmetic intensity: ", intensity
  end function measure_arithmetic_intensity
  
  function profile_kernel(kernel, work_size, params) result(profile)
    type(shader_kernel_v2), intent(inout) :: kernel
    integer, intent(in) :: work_size
    real(sp), dimension(:), intent(in) :: params
    type(kernel_profile) :: profile
    
    type(gpu_executor) :: exec
    integer :: test_sizes(5) = [32, 64, 128, 256, 512]
    real(dp) :: test_time, best_time
    integer :: i, original_size
    
    print *, "Profiling kernel: ", trim(kernel%name)
    
    ! Measure arithmetic intensity
    profile%arithmetic_intensity = measure_arithmetic_intensity(kernel, work_size)
    
    ! Find best parameter method
    profile%optimal_param_method = gpu_benchmark_param_methods(kernel, work_size, params)
    kernel%param_method = profile%optimal_param_method
    
    ! Find optimal local size
    print *, "Testing local_size configurations:"
    original_size = kernel%local_size_x
    best_time = huge(1.0_real64)
    
    do i = 1, size(test_sizes)
      if (mod(work_size, test_sizes(i)) == 0 .or. &
          work_size > test_sizes(i) * 2) then
        kernel%local_size_x = test_sizes(i)
        call initialize_executor(exec, kernel)
        
        if (exec%initialized) then
          test_time = benchmark_kernel(exec, kernel, work_size, params, 50)
          print '(A,I4,A,F10.4,A)', "  local_size=", test_sizes(i), ": ", test_time, " ms"
          
          if (test_time < best_time) then
            best_time = test_time
            profile%optimal_local_size = test_sizes(i)
            profile%time_ms = test_time
          end if
          
          call cleanup_executor(exec)
        end if
      end if
    end do
    
    ! Calculate performance metrics
    if (profile%time_ms > 0) then
      ! Estimate GFLOPS
      profile%gflops = real(work_size, real64) * profile%arithmetic_intensity / &
                       (profile%time_ms * 1.0e6_real64)
      
      ! Estimate bandwidth
      profile%bandwidth_gb_s = real(work_size * 4 * 3, real64) / &  ! Rough estimate
                               (profile%time_ms * 1.0e6_real64)
    end if
    
    ! Restore original size
    kernel%local_size_x = original_size
    
    print '(A,I4)', "  Optimal local_size: ", profile%optimal_local_size
    print '(A,F10.2,A)', "  Performance: ", profile%gflops, " GFLOPS"
    print '(A,F10.2,A)', "  Bandwidth: ", profile%bandwidth_gb_s, " GB/s"
  end function profile_kernel

end module sporkle_gpu_benchmark