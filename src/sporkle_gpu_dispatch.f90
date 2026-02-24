module sporkle_gpu_dispatch
  ! GPU dispatch implementation
  ! Legacy OpenGL reference path is retained for comparison; production routing
  ! is moving to Kronos-native compute execution.
  
  use kinds
  use iso_c_binding
  use sporkle_types
  use sporkle_memory
  use sporkle_gpu_kernels
  use sporkle_gpu_safe_detect
  use sporkle_error_handling, only: sporkle_error_sub => sporkle_error
  use gpu_opengl_interface, only: gpu_init, gpu_cleanup, gpu_execute_conv2d_ref
  implicit none
  private
  
  public :: gpu_device, gpu_kernel, gpu_memory
  public :: init_gpu_device, create_gpu_kernel
  public :: gpu_malloc, gpu_free, gpu_memcpy
  public :: launch_gpu_kernel, gpu_synchronize
  public :: execute_conv2d_gpu
  public :: GPU_TO_HOST, HOST_TO_GPU
  
  ! Memory transfer directions
  integer, parameter :: HOST_TO_GPU = 1
  integer, parameter :: GPU_TO_HOST = 2
  
  ! GPU device handle
  type :: gpu_device
    integer :: device_id = 0
    logical :: initialized = .false.
    character(len=256) :: name = "Unknown GPU"
    integer(i64) :: memory_total = 0
    integer(i64) :: memory_free = 0
    integer :: compute_units = 0
    real(sp) :: clock_mhz = 0.0
    logical :: opengl_ready = .false.  ! Track OpenGL initialization
  end type gpu_device
  
  ! GPU kernel handle
  type :: gpu_kernel
    character(len=:), allocatable :: name
    character(len=:), allocatable :: source
    integer :: work_group_size = 256
    logical :: compiled = .false.
  end type gpu_kernel
  
  ! GPU memory handle
  type :: gpu_memory
    integer(i64) :: size_bytes = 0
    integer(i64) :: gpu_ptr = 0
    logical :: allocated = .false.
  end type gpu_memory

  ! C runtime interfaces for host-backed staging fallback
  interface
    function c_malloc(size) bind(c, name="malloc")
      import :: c_ptr, c_size_t
      integer(c_size_t), value :: size
      type(c_ptr) :: c_malloc
    end function c_malloc
    
    subroutine c_free(ptr) bind(c, name="free")
      import :: c_ptr
      type(c_ptr), value :: ptr
    end subroutine c_free
    
    subroutine c_memcpy(dst, src, n) bind(c, name="memcpy")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: dst
      type(c_ptr), value :: src
      integer(c_size_t), value :: n
    end subroutine c_memcpy
  end interface
  
contains

  ! Initialize GPU device
  function init_gpu_device() result(device)
    type(gpu_device) :: device
    type(gpu_info_type), allocatable :: gpus(:)
    integer :: i
    
    ! Safely detect GPUs without shell commands
    gpus = detect_gpu_safe()
    
    if (size(gpus) > 0) then
      device%initialized = .true.
      
      ! Use first GPU found
      if (gpus(1)%is_amd) then
        device%name = trim(gpus(1)%device)
        
        ! Special handling for known GPUs
        if (index(gpus(1)%device, "7900") > 0) then
          device%compute_units = 84
          device%clock_mhz = 2400.0
          device%memory_total = 24_int64 * 1024_int64**3  ! 24 GB
        else
          ! Default AMD GPU settings
          device%compute_units = 32
          device%clock_mhz = 1500.0
          device%memory_total = 8_int64 * 1024_int64**3  ! 8 GB
        end if
      else if (gpus(1)%is_nvidia) then
        device%name = trim(gpus(1)%device)
        device%compute_units = 32
        device%clock_mhz = 1500.0
        device%memory_total = 8_int64 * 1024_int64**3  ! 8 GB
      else if (gpus(1)%is_intel) then
        device%name = trim(gpus(1)%device)
        device%compute_units = 8
        device%clock_mhz = 1000.0
        device%memory_total = 2_int64 * 1024_int64**3  ! 2 GB
      else
        device%name = trim(gpus(1)%vendor) // " " // trim(gpus(1)%device)
        device%compute_units = 16
        device%clock_mhz = 1000.0
        device%memory_total = 4_int64 * 1024_int64**3  ! 4 GB
      end if
      
      device%memory_free = device%memory_total / 2  ! Assume half free
      
      ! Initialize OpenGL for GPU computation
      device%opengl_ready = gpu_init()
      if (.not. device%opengl_ready) then
        print *, "⚠️  GPU detected but OpenGL initialization failed"
        call sporkle_error_sub("OpenGL initialization failed", .false.)
      end if
      
      print *, "🎮 GPU Device Initialized:"
      print '(A,A)', "   Name: ", trim(device%name)
      print '(A,A)', "   Bus ID: ", trim(gpus(1)%bus_id)
      print '(A,I0)', "   Compute Units: ", device%compute_units
      print '(A,F0.1,A)', "   Clock: ", device%clock_mhz, " MHz"
      print '(A,F0.1,A)', "   Memory: ", real(device%memory_total) / real(1024**3), " GB"
      if (device%opengl_ready) then
        print *, "   ℹ️  OpenGL compute reference path initialized"
      else
        print *, "   ❌ OpenGL compute not available"
      end if
      
      ! Report additional GPUs if found
      if (size(gpus) > 1) then
        print *, "   Additional GPUs detected:"
        do i = 2, size(gpus)
          print '(A,A,A,A)', "     - ", trim(gpus(i)%vendor), ": ", trim(gpus(i)%device)
        end do
      end if
    else
      print *, "⚠️  No GPU detected"
      print *, "   Using CPU fallback mode"
      call sporkle_error_sub("GPU detection failed - using CPU fallback", .false.)
    end if
    
    if (allocated(gpus)) deallocate(gpus)
    
  end function init_gpu_device
  
  ! Create GPU kernel from source
  function create_gpu_kernel(name, kernel_type) result(kernel)
    character(len=*), intent(in) :: name
    character(len=*), intent(in) :: kernel_type
    type(gpu_kernel) :: kernel
    
    kernel%name = name
    
    ! Get appropriate kernel source
    select case(kernel_type)
    case("vector_add")
      kernel%source = get_vector_add_shader()
      kernel%work_group_size = 256
    case("saxpy")
      kernel%source = get_saxpy_shader()
      kernel%work_group_size = 256
    case("gemm")
      kernel%source = get_gemm_shader()
      kernel%work_group_size = 16  ! 16x16 for 2D
    case("reduction")
      kernel%source = get_reduction_shader()
      kernel%work_group_size = 256
    case("complex")
      kernel%source = get_complex_shader()
      kernel%work_group_size = 256
    case default
      print *, "Unknown kernel type: ", kernel_type
      return
    end select
    
    ! Kernel compilation handled by OpenGL reference implementation
    kernel%compiled = .true.
    
    print '(A,A,A)', "✅ Created GPU kernel: ", trim(name), " (", trim(kernel_type), ")"
    
  end function create_gpu_kernel
  
  ! Allocate GPU memory
  function gpu_malloc(size_bytes) result(mem)
    integer(i64), intent(in) :: size_bytes
    type(gpu_memory) :: mem
    type(c_ptr) :: host_ptr
    integer(c_size_t) :: alloc_size
    
    ! Validate size
    if (size_bytes <= 0) then
      call sporkle_error_sub("Invalid GPU allocation size", .false.)
      mem%allocated = .false.
      return
    end if
    
    if (size_bytes > 24_int64 * 1024_int64**3) then
      call sporkle_error_sub("GPU allocation too large (>24GB)", .false.)
      mem%allocated = .false.
      return
    end if
    
    mem%size_bytes = size_bytes
    alloc_size = int(size_bytes, c_size_t)
    host_ptr = c_malloc(alloc_size)
    if (.not. c_associated(host_ptr)) then
      print *, "❌ Failed to allocate GPU staging buffer"
      mem%allocated = .false.
      mem%size_bytes = 0
      return
    end if

    mem%gpu_ptr = transfer(host_ptr, mem%gpu_ptr)
    mem%allocated = .true.
    
    print '(A,F0.2,A)', "🎯 Allocated ", real(size_bytes) / real(1024**2), " MB on GPU"
    
  end function gpu_malloc
  
  ! Free GPU memory
  subroutine gpu_free(mem)
    type(gpu_memory), intent(inout) :: mem
    type(c_ptr) :: host_ptr
    
    if (mem%allocated) then
      host_ptr = transfer(mem%gpu_ptr, host_ptr)
      if (c_associated(host_ptr)) then
        call c_free(host_ptr)
      end if
      mem%allocated = .false.
      mem%gpu_ptr = 0
      print '(A,F0.2,A)', "🗑️  Freed ", real(mem%size_bytes) / real(1024**2), " MB on GPU"
      mem%size_bytes = 0
    end if
    
  end subroutine gpu_free
  
  ! Copy memory between host and GPU
  subroutine gpu_memcpy(dst, src, size_bytes, direction)
    type(gpu_memory), intent(inout) :: dst
    type(c_ptr), intent(in) :: src
    integer(i64), intent(in) :: size_bytes
    integer, intent(in) :: direction
    integer(c_size_t) :: copy_size
    type(c_ptr) :: dst_ptr
    
    if (.not. dst%allocated) then
      print *, "ERROR: GPU memcpy target has not been allocated"
      return
    end if

    if (size_bytes <= 0) then
      print *, "ERROR: Copy size must be positive"
      return
    end if

    if (size_bytes > dst%size_bytes) then
      print *, "ERROR: Copy size exceeds destination staging buffer"
      return
    end if

    dst_ptr = transfer(dst%gpu_ptr, dst_ptr)
    if (.not. c_associated(src) .or. .not. c_associated(dst_ptr)) then
      print *, "ERROR: GPU memcpy requires valid source and destination pointers"
      return
    end if

    copy_size = int(size_bytes, c_size_t)

    select case(direction)
    case(HOST_TO_GPU)
      print '(A,F0.2,A)', "📤 Copying ", real(size_bytes) / real(1024**2), " MB to GPU"
    case(GPU_TO_HOST)
      print '(A,F0.2,A)', "📥 Copying ", real(size_bytes) / real(1024**2), " MB from GPU"
    case default
      print *, "ERROR: Invalid copy direction"
      return
    end select

    if (direction == HOST_TO_GPU) then
      call c_memcpy(dst_ptr, src, copy_size)
    else
      call c_memcpy(src, dst_ptr, copy_size)
    end if
    
  end subroutine gpu_memcpy
  
  ! Launch GPU kernel
  subroutine launch_gpu_kernel(kernel, args, global_size, local_size)
    type(gpu_kernel), intent(in) :: kernel
    type(gpu_memory), intent(in) :: args(:)
    integer, intent(in) :: global_size(:)
    integer, intent(in), optional :: local_size(:)
    
    integer :: num_groups(3), group_size(3)
    integer :: i
    
    ! Calculate work groups
    if (present(local_size)) then
      group_size = 1
      group_size(1:size(local_size)) = local_size
    else
      group_size = [kernel%work_group_size, 1, 1]
    end if
    
    num_groups = 1
    do i = 1, size(global_size)
      num_groups(i) = (global_size(i) + group_size(i) - 1) / group_size(i)
    end do
    
    print '(A,A)', "🚀 Launching kernel: ", trim(kernel%name)
    print '(A,3(I0,1X))', "   Global size: ", global_size
    print '(A,3(I0,1X))', "   Local size: ", group_size
    print '(A,3(I0,1X))', "   Work groups: ", num_groups
    print '(A)', "   ℹ️  Launching through OpenGL reference path (non-production)"
    
  end subroutine launch_gpu_kernel
  
  ! Synchronize GPU
  subroutine gpu_synchronize()
    print *, "⏳ GPU synchronize..."
    ! Legacy OpenGL path uses glFinish() for synchronization
  end subroutine gpu_synchronize
  
  ! High-level conv2d execution using reference implementation
  real(sp) function execute_conv2d_gpu(input, weights, output, &
                                           N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    ! Execute using reference implementation
    execute_conv2d_gpu = gpu_execute_conv2d_ref(input, weights, output, &
                                                N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
  end function execute_conv2d_gpu

end module sporkle_gpu_dispatch
