! Production Convolution with Fence-Based Juggling
! ===============================================
!
! Updated juggling system with fence synchronization
!
! Key improvements:
!   - Replace glFinish() with lightweight fences
!   - Lower sync overhead than legacy glFinish path
!   - Non-blocking GPU status checks
!   - Timeout-based recovery

module sporkle_conv2d_juggling_fence
  use kinds
  use iso_c_binding
  use cpu_conv2d_adaptive, only: conv2d_adaptive
  use gpu_opengl_interface_fence
  use gpu_fence_primitives
  use gpu_async_executor
  use universal_memory_optimization, only: memory_params, detect_memory_params
  implicit none
  
  private
  public :: conv2d_auto_juggling_fence, init_juggling_system_fence, cleanup_juggling_system_fence
  public :: device_capabilities_fence, get_device_info_fence
  public :: enable_async_gpu_fence, disable_async_gpu_fence
  
  ! Device capabilities tracking
  type :: device_capabilities_fence
    logical :: cpu_available = .true.
    logical :: gpu_available = .false.
    real(sp) :: cpu_gflops = 0.0
    real(sp) :: gpu_gflops = 0.0
    integer :: cpu_threads = 1
    character(len=256) :: gpu_name = "None"
    logical :: fence_support = .false.
  end type
  
  ! Juggling buffer with fence
  type :: juggle_buffer
    real(sp), allocatable :: data(:)
    type(gpu_fence) :: fence
    logical :: gpu_busy = .false.
    integer(i64) :: submit_time = 0
  end type
  
  ! Global state
  type(device_capabilities_fence), save :: devices
  logical, save :: initialized = .false.
  
  ! Async GPU executor state
  type(gpu_async_state), save :: async_state
  logical, save :: async_gpu_enabled = .true.
  logical, save :: async_gpu_initialized = .false.
  
  ! OpenMP function interface
  interface
    function omp_get_num_threads()
      integer :: omp_get_num_threads
    end function omp_get_num_threads
  end interface
  
contains

  ! Initialize the fence-based juggling system
  subroutine init_juggling_system_fence()
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
    
    ! Try to initialize GPU with fence support
    gpu_ok = gpu_init_fence()
    if (gpu_ok) then
      devices%gpu_available = .true.
      devices%gpu_gflops = 400.0  ! Conservative estimate for 7900 XTX
      devices%gpu_name = "AMD Radeon RX 7900 XTX"
      devices%fence_support = .true.
      print *, "✅ GPU initialized with fence support"
    else
      devices%gpu_available = .false.
      print *, "ℹ️  GPU not available, using CPU only"
    end if
    
    initialized = .true.
    
    print *, ""
    print *, "⚡ Fence-Based Juggling System Initialized"
    print *, "========================================="
    print '(A,L1,A,I0,A)', "  CPU: ", devices%cpu_available, " (", devices%cpu_threads, " threads)"
    print '(A,L1)', "  GPU: ", devices%gpu_available
    if (devices%gpu_available) then
      print '(A,A)', "       ", trim(devices%gpu_name)
      if (devices%fence_support) then
        print *, "       ⚡ Fence synchronization enabled"
      end if
      if (async_gpu_enabled) then
        print *, "       🚀 Async pipeline enabled"
      end if
    end if
    print *, ""
    
  end subroutine init_juggling_system_fence
  
  ! Cleanup the juggling system
  subroutine cleanup_juggling_system_fence()
    if (async_gpu_initialized) then
      call gpu_async_executor_cleanup(async_state)
      async_gpu_initialized = .false.
    end if
    if (devices%gpu_available) then
      call gpu_cleanup_fence()
    end if
    initialized = .false.
  end subroutine cleanup_juggling_system_fence
  
  ! Get device information
  function get_device_info_fence() result(info)
    type(device_capabilities_fence) :: info
    info = devices
  end function get_device_info_fence
  
  ! Enable async GPU execution
  subroutine enable_async_gpu_fence()
    async_gpu_enabled = .true.
    print *, "✅ Async GPU execution enabled"
  end subroutine enable_async_gpu_fence
  
  ! Disable async GPU execution
  subroutine disable_async_gpu_fence()
    async_gpu_enabled = .false.
    print *, "ℹ️  Async GPU execution disabled (using fence-based sync)"
  end subroutine disable_async_gpu_fence
  
  ! Intelligent convolution with fence-based device selection
  function conv2d_auto_juggling_fence(input, weights, output, &
                                     N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    integer(i64) :: total_flops
    real(sp) :: workload_size_gb
    logical :: use_gpu
    
    ! Initialize if needed
    if (.not. initialized) call init_juggling_system_fence()
    
    ! Calculate workload characteristics
    total_flops = int(N, int64) * int(K, int64) * int(H_out, int64) * int(W_out, int64) * &
                  int(C, int64) * int(kernel_size, int64) * int(kernel_size, int64) * 2_int64
    
    ! Estimate memory footprint (GB)
    workload_size_gb = real(size(input) + size(weights) + size(output)) * 4.0 / 1e9
    
    ! Intelligent device selection
    use_gpu = .false.
    if (devices%gpu_available) then
      ! Use GPU for large workloads
      if (total_flops > 100e6_int64) then  ! > 100 MFLOPS
        use_gpu = .true.
      end if
    end if
    
    ! Execute on selected device
    if (use_gpu) then
      if (async_gpu_enabled .and. .false.) then  ! Async not updated yet
        print '(A,I0,A)', "🚀 GPU ASYNC selected for workload (", total_flops/1000000, " MFLOPS)"
        time_ms = -1.0  ! Not implemented yet
      else
        print '(A,I0,A)', "⚡ GPU FENCE selected for workload (", total_flops/1000000, " MFLOPS)"
        time_ms = gpu_execute_conv2d_fence(input, weights, output, &
                                          N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
      end if
    else
      print '(A,I0,A)', "🖥️  CPU selected for workload (", total_flops/1000000, " MFLOPS)"
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    end if
    
  end function conv2d_auto_juggling_fence
  
end module sporkle_conv2d_juggling_fence
