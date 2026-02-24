! Production Convolution with Intelligent Device Juggling
! ======================================================
!
! This module integrates:
!   - CPU: Adaptive K×N tiling with AVX-512
!   - GPU: OpenGL reference implementation
!   - GPU: Async pipeline with triple buffering (status in telemetry only)
!   - Intelligent device selection and workload distribution
!   - Universal memory optimization principles

module sporkle_conv2d_juggling
  use kinds
  use iso_c_binding
  use cpu_conv2d_adaptive, only: conv2d_adaptive
  use gpu_opengl_interface, only: gpu_init, gpu_cleanup, gpu_execute_conv2d_ref, &
                                  gpu_get_program_id
  use gpu_async_executor
  use universal_memory_optimization, only: memory_params, detect_memory_params
  implicit none
  
  private
  public :: conv2d_auto_juggling, init_juggling_system, cleanup_juggling_system
  public :: device_capabilities, get_device_info
  public :: enable_async_gpu, disable_async_gpu
  
  ! Simple device capabilities tracking
  type :: device_capabilities
    logical :: cpu_available = .true.
    logical :: gpu_available = .false.
    real(sp) :: cpu_gflops = 0.0
    real(sp) :: gpu_gflops = 0.0
    integer :: cpu_threads = 1
    character(len=256) :: gpu_name = "None"
  end type
  
  ! Global state
  type(device_capabilities), save :: devices
  logical, save :: initialized = .false.
  
  ! Async GPU executor state
  type(gpu_async_state), save :: async_state
  logical, save :: async_gpu_enabled = .true.
  logical, save :: async_gpu_initialized = .false.
  integer, save :: gpu_weight_buffer = 0
  integer(i64), save :: weight_hash = 0  ! Simple hash to detect weight changes
  
  ! OpenMP function interface
  interface
    function omp_get_num_threads()
      integer :: omp_get_num_threads
    end function omp_get_num_threads
  end interface
  
  ! OpenGL interface for weight buffer
  interface
    subroutine glGenBuffers(n, buffers) bind(C, name="glGenBuffers")
      import :: c_int
      integer(c_int), value :: n
      integer(c_int), intent(out) :: buffers
    end subroutine glGenBuffers
    
    subroutine glDeleteBuffers(n, buffers) bind(C, name="glDeleteBuffers")
      import :: c_int
      integer(c_int), value :: n
      integer(c_int), intent(in) :: buffers
    end subroutine glDeleteBuffers
    
    subroutine glBindBuffer(target, buffer) bind(C, name="glBindBuffer")
      import :: c_int
      integer(c_int), value :: target, buffer
    end subroutine glBindBuffer
    
    subroutine glBufferData(target, size, data, usage) bind(C, name="glBufferData")
      import :: c_int, c_size_t, c_ptr
      integer(c_int), value :: target, usage
      integer(c_size_t), value :: size
      type(c_ptr), value :: data
    end subroutine glBufferData
  end interface
  
  ! OpenGL constants
  integer(c_int), parameter :: GL_SHADER_STORAGE_BUFFER = int(z'90D2', c_int)
  integer(c_int), parameter :: GL_STATIC_DRAW = int(z'88E4', c_int)
  
contains

  ! Initialize the juggling system
  subroutine init_juggling_system()
    logical :: gpu_ok
    integer :: max_threads
    
    if (initialized) return
    
    ! Detect CPU capabilities
    !$omp parallel
    !$omp single
    devices%cpu_threads = omp_get_num_threads()
    !$omp end single
    !$omp end parallel
    
    devices%cpu_available = .true.
    devices%cpu_gflops = 100.0  ! Conservative estimate
    
    ! Try to initialize GPU
    gpu_ok = gpu_init()
    if (gpu_ok) then
      devices%gpu_available = .true.
      devices%gpu_gflops = 400.0  ! Conservative estimate for 7900 XTX
      devices%gpu_name = "AMD Radeon RX 7900 XTX"
      print *, "✅ GPU initialized successfully"
    else
      devices%gpu_available = .false.
      print *, "ℹ️  GPU not available, using CPU only"
    end if
    
    initialized = .true.
    
    print *, ""
    print *, "🧠 Intelligent Device Juggling System Initialized"
    print *, "================================================"
    print '(A,L1,A,I0,A)', "  CPU: ", devices%cpu_available, " (", devices%cpu_threads, " threads)"
    print '(A,L1)', "  GPU: ", devices%gpu_available
    if (devices%gpu_available) then
      print '(A,A)', "       ", trim(devices%gpu_name)
      if (async_gpu_enabled) then
        print *, "       🚀 Async pipeline enabled"
      end if
    end if
    print *, ""
    
  end subroutine init_juggling_system
  
  ! Cleanup the juggling system
  subroutine cleanup_juggling_system()
    if (async_gpu_initialized) then
      call gpu_async_executor_cleanup(async_state)
      if (gpu_weight_buffer /= 0) then
        call glDeleteBuffers(1, gpu_weight_buffer)
      end if
      async_gpu_initialized = .false.
    end if
    if (devices%gpu_available) then
      call gpu_cleanup()
    end if
    initialized = .false.
  end subroutine cleanup_juggling_system
  
  ! Get device information
  function get_device_info() result(info)
    type(device_capabilities) :: info
    info = devices
  end function get_device_info
  
  ! Intelligent convolution with device selection
  function conv2d_auto_juggling(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    integer(i64) :: total_flops
    real(sp) :: workload_size_gb
    logical :: use_gpu
    
    ! Initialize if needed
    if (.not. initialized) call init_juggling_system()
    
    ! Calculate workload characteristics
    total_flops = int(N, int64) * int(K, int64) * int(H_out, int64) * int(W_out, int64) * &
                  int(C, int64) * int(kernel_size, int64) * int(kernel_size, int64) * 2_int64
    
    ! Estimate memory footprint (GB)
    workload_size_gb = real(size(input) + size(weights) + size(output)) * 4.0 / 1e9
    
    ! Intelligent device selection
    use_gpu = .false.
    if (devices%gpu_available) then
      ! Use GPU for large workloads
      ! CPU is better for small workloads due to kernel launch overhead
      if (total_flops > 100e6_int64) then  ! > 100 MFLOPS
        use_gpu = .true.
      end if
    end if
    
    ! Execute on selected device
    if (use_gpu) then
      if (async_gpu_enabled) then
        print '(A,I0,A)', "🚀 GPU ASYNC selected for workload (", total_flops/1000000, " MFLOPS)"
        time_ms = execute_gpu_async(input, weights, output, &
                                   N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
      else
        print '(A,I0,A)', "🎮 GPU selected for workload (", total_flops/1000000, " MFLOPS)"
        time_ms = gpu_execute_conv2d_ref(input, weights, output, &
                                        N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
      end if
    else
      print '(A,I0,A)', "🖥️  CPU selected for workload (", total_flops/1000000, " MFLOPS)"
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    end if
    
  end function conv2d_auto_juggling
  
  ! Enable async GPU execution
  subroutine enable_async_gpu()
    async_gpu_enabled = .true.
    print *, "✅ Async GPU execution enabled"
  end subroutine enable_async_gpu
  
  ! Disable async GPU execution
  subroutine disable_async_gpu()
    async_gpu_enabled = .false.
    print *, "ℹ️  Async GPU execution disabled (using synchronous GPU path)"
  end subroutine disable_async_gpu
  
  ! Simple hash function for weight change detection
  function compute_weight_hash(weights) result(hash)
    real(sp), intent(in) :: weights(:)
    integer(i64) :: hash
    integer :: i
    
    ! Simple hash: sum of first, last, and every 100th element
    hash = 0
    if (size(weights) > 0) then
      hash = transfer(weights(1), 0_int64)
      hash = hash + transfer(weights(size(weights)), 0_int64)
      do i = 100, size(weights), 100
        hash = hash + transfer(weights(i), 0_int64)
      end do
    end if
  end function compute_weight_hash
  
  ! Private helper function for async GPU execution
  function execute_gpu_async(input, weights, output, &
                            N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in), target :: input(:), weights(:)
    real(sp), intent(out), target :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    integer :: compute_program
    integer(i64) :: weight_size, new_hash
    integer(i64) :: start_time, end_time
    real(dp) :: clock_rate
    
    ! Check if weights have changed
    new_hash = compute_weight_hash(weights)
    
    ! Initialize async executor if needed
    if (.not. async_gpu_initialized) then
      ! Get compute program from GPU interface
      compute_program = gpu_get_program_id()
      
      ! Create and upload weight buffer
      weight_size = int(size(weights), int64) * 4  ! sizeof(float)
      call glGenBuffers(1, gpu_weight_buffer)
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, gpu_weight_buffer)
      call glBufferData(GL_SHADER_STORAGE_BUFFER, weight_size, &
                       c_loc(weights), GL_STATIC_DRAW)
      
      ! Initialize async executor
      call gpu_async_executor_init(async_state, compute_program, gpu_weight_buffer)
      async_gpu_initialized = .true.
      weight_hash = new_hash
    else if (new_hash /= weight_hash) then
      ! Weights have changed - update buffer
      print *, "ℹ️  Weights changed, updating GPU buffer..."
      weight_size = int(size(weights), int64) * 4
      call glBindBuffer(GL_SHADER_STORAGE_BUFFER, gpu_weight_buffer)
      call glBufferData(GL_SHADER_STORAGE_BUFFER, weight_size, &
                       c_loc(weights), GL_STATIC_DRAW)
      weight_hash = new_hash
    end if
    
    ! Execute using async pipeline
    call system_clock(start_time, count_rate=clock_rate)
    
    call gpu_async_conv2d(async_state, input, weights, output, &
                         N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    
    call system_clock(end_time)
    time_ms = real((end_time - start_time) / clock_rate * 1000.0, real32)
    
  end function execute_gpu_async
  
end module sporkle_conv2d_juggling
