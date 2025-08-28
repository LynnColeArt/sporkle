module sporkle_gpu_backend
  ! GPU backend selection - VENDOR NEUTRAL ONLY
  ! ==========================================
  ! Sparkle philosophy: No proprietary SDKs!
  ! We use OpenGL, Vulkan, and direct hardware access (PM4)
  
  use kinds
  use iso_c_binding
  use sporkle_types
  use sporkle_error_handling, only: sporkle_warning
  use sporkle_gpu_backend_detect
  implicit none
  private
  
  public :: gpu_backend_type, gpu_backend_info
  public :: detect_gpu_backend, init_gpu_backend
  public :: GPU_BACKEND_NONE, GPU_BACKEND_OPENGL, GPU_BACKEND_VULKAN
  
  ! Supported GPU backends - VENDOR NEUTRAL ONLY
  integer, parameter :: GPU_BACKEND_NONE = 0
  integer, parameter :: GPU_BACKEND_OPENGL = 1    ! Cross-platform
  integer, parameter :: GPU_BACKEND_VULKAN = 2    ! Cross-platform
  
  ! GPU backend information
  type :: gpu_backend_info
    integer :: backend_type = GPU_BACKEND_NONE
    character(len=64) :: name = "None"
    logical :: available = .false.
    logical :: initialized = .false.
    character(len=256) :: version = "Unknown"
    character(len=512) :: reason = ""  ! Why not available
  end type gpu_backend_info
  
  ! GPU backend interface
  type :: gpu_backend_type
    type(gpu_backend_info) :: info
    ! Function pointers for backend operations
    procedure(backend_init_interface), pointer, nopass :: init => null()
    procedure(backend_cleanup_interface), pointer, nopass :: cleanup => null()
    procedure(backend_compile_interface), pointer, nopass :: compile_kernel => null()
    procedure(backend_execute_interface), pointer, nopass :: execute_kernel => null()
  contains
    procedure :: is_available => backend_is_available
  end type gpu_backend_type
  
  ! Backend function interfaces
  abstract interface
    function backend_init_interface() result(status)
      use kinds
      integer :: status
    end function
    
    subroutine backend_cleanup_interface()
    end subroutine
    
    function backend_compile_interface(source, source_type) result(kernel_id)
      use kinds
      character(len=*), intent(in) :: source
      integer, intent(in) :: source_type
      integer(i64) :: kernel_id
    end function
    
    function backend_execute_interface(kernel_id, args, grid_size, block_size) result(status)
      use kinds
      use iso_c_binding
      integer(i64), intent(in) :: kernel_id
      type(c_ptr), intent(in) :: args(:)
      integer, intent(in) :: grid_size(3), block_size(3)
      integer :: status
    end function
  end interface
  
contains

  ! Check if a library exists
  function check_library(lib_name) result(exists)
    character(len=*), intent(in) :: lib_name
    logical :: exists
    
    interface
      function dlopen(filename, flag) bind(C, name="dlopen")
        import :: c_ptr, c_char, c_int
        character(c_char), intent(in) :: filename(*)
        integer(c_int), value :: flag
        type(c_ptr) :: dlopen
      end function dlopen
      
      subroutine dlclose(handle) bind(C, name="dlclose")
        import :: c_ptr
        type(c_ptr), value :: handle
      end subroutine dlclose
    end interface
    
    type(c_ptr) :: handle
    integer, parameter :: RTLD_LAZY = 1
    
    ! Try to load the library
    handle = dlopen(trim(lib_name)//c_null_char, RTLD_LAZY)
    exists = c_associated(handle)
    
    ! Clean up if we opened it
    if (exists) call dlclose(handle)
    
  end function check_library

  ! Detect available GPU backends
  function detect_gpu_backend() result(backends)
    type(gpu_backend_info), allocatable :: backends(:)
    integer :: num_backends
    
    ! We only support vendor-neutral backends
    num_backends = 2
    allocate(backends(num_backends))
    
    backends(1) = check_opengl_backend()
    backends(2) = check_vulkan_backend()
    
  end function detect_gpu_backend
  
  ! Initialize GPU backend
  function init_gpu_backend(prefer_backend) result(backend)
    integer, intent(in), optional :: prefer_backend
    type(gpu_backend_type) :: backend
    type(gpu_backend_info), allocatable :: available_backends(:)
    integer :: i, preferred
    
    preferred = GPU_BACKEND_OPENGL  ! Default
    if (present(prefer_backend)) preferred = prefer_backend
    
    ! Get available backends
    available_backends = detect_gpu_backend()
    
    ! Try preferred backend first
    do i = 1, size(available_backends)
      if (available_backends(i)%backend_type == preferred .and. &
          available_backends(i)%available) then
        backend%info = available_backends(i)
        
        select case(backend%info%backend_type)
        case(GPU_BACKEND_OPENGL)
          ! Set OpenGL function pointers
          backend%init => init_opengl_backend
          backend%cleanup => cleanup_opengl_backend
          backend%compile_kernel => compile_opengl_kernel  
          backend%execute_kernel => execute_opengl_kernel
          backend%info%initialized = .true.
          
        case(GPU_BACKEND_VULKAN)
          ! Set Vulkan function pointers
          backend%init => init_vulkan_backend
          backend%cleanup => cleanup_vulkan_backend
          backend%compile_kernel => compile_vulkan_kernel  
          backend%execute_kernel => execute_vulkan_kernel
          backend%info%initialized = .true.
        end select
        
        exit
      end if
    end do
    
    ! If preferred not available, try any available
    if (backend%info%backend_type == GPU_BACKEND_NONE) then
      do i = 1, size(available_backends)
        if (available_backends(i)%available) then
          backend%info = available_backends(i)
          
          select case(backend%info%backend_type)
          case(GPU_BACKEND_OPENGL)
            backend%init => init_opengl_backend
            backend%cleanup => cleanup_opengl_backend
            backend%compile_kernel => compile_opengl_kernel
            backend%execute_kernel => execute_opengl_kernel
            backend%info%initialized = .true.
            
          case(GPU_BACKEND_VULKAN)
            backend%init => init_vulkan_backend
            backend%cleanup => cleanup_vulkan_backend
            backend%compile_kernel => compile_vulkan_kernel
            backend%execute_kernel => execute_vulkan_kernel
            backend%info%initialized = .true.
          end select
          
          exit
        end if
      end do
    end if
    
    if (backend%info%backend_type == GPU_BACKEND_NONE) then
      call sporkle_warning("No GPU backend available - using CPU fallback")
    end if
    
  end function init_gpu_backend
  
  ! Check if backend is available
  function backend_is_available(this) result(available)
    class(gpu_backend_type), intent(in) :: this
    logical :: available
    
    available = this%info%available .and. this%info%initialized
    
  end function backend_is_available
  
  ! Check for OpenGL support
  function check_opengl_backend() result(info)
    type(gpu_backend_info) :: info
    logical :: has_opengl
    
    info%backend_type = GPU_BACKEND_OPENGL
    info%name = "OpenGL Compute"
    
    ! Check for OpenGL libraries
    has_opengl = check_library("libGL.so") .or. check_library("libGL.so.1")
    
    if (has_opengl) then
      has_opengl = check_library("libEGL.so") .or. check_library("libEGL.so.1")
    end if
    
    info%available = has_opengl
    if (has_opengl) then
      info%version = "OpenGL 4.3+ Compute Shaders"
      info%reason = ""
    else
      info%reason = "OpenGL/EGL libraries not found"
    end if
    
  end function check_opengl_backend
  
  ! Check for Vulkan support
  function check_vulkan_backend() result(info)
    type(gpu_backend_info) :: info
    logical :: has_vulkan
    
    info%backend_type = GPU_BACKEND_VULKAN
    info%name = "Vulkan Compute"
    
    ! Check for Vulkan library
    has_vulkan = check_library("libvulkan.so") .or. check_library("libvulkan.so.1")
    
    info%available = has_vulkan
    if (has_vulkan) then
      info%version = "Vulkan 1.0+ Compute"
      info%reason = ""
    else
      info%reason = "Vulkan library not found"
    end if
    
  end function check_vulkan_backend
  
  ! Stub implementations for OpenGL backend
  function init_opengl_backend() result(status)
    integer :: status
    ! Real implementation in gpu_opengl_interface.f90
    status = SPORKLE_SUCCESS
  end function
  
  subroutine cleanup_opengl_backend()
    ! Real implementation in gpu_opengl_interface.f90
  end subroutine
  
  function compile_opengl_kernel(source, source_type) result(kernel_id)
    character(len=*), intent(in) :: source
    integer, intent(in) :: source_type
    integer(i64) :: kernel_id
    ! Real implementation in gpu_opengl_interface.f90
    kernel_id = -1
  end function
  
  function execute_opengl_kernel(kernel_id, args, grid_size, block_size) result(status)
    integer(i64), intent(in) :: kernel_id
    type(c_ptr), intent(in) :: args(:)
    integer, intent(in) :: grid_size(3), block_size(3)
    integer :: status
    ! Real implementation in gpu_opengl_interface.f90
    status = SPORKLE_ERROR
  end function
  
  ! Stub implementations for Vulkan backend
  function init_vulkan_backend() result(status)
    integer :: status
    ! Real implementation in gpu_vulkan_backend.c
    status = SPORKLE_SUCCESS
  end function
  
  subroutine cleanup_vulkan_backend()
    ! Real implementation in gpu_vulkan_backend.c
  end subroutine
  
  function compile_vulkan_kernel(source, source_type) result(kernel_id)
    character(len=*), intent(in) :: source
    integer, intent(in) :: source_type
    integer(i64) :: kernel_id
    ! Real implementation in gpu_vulkan_backend.c
    kernel_id = -1
  end function
  
  function execute_vulkan_kernel(kernel_id, args, grid_size, block_size) result(status)
    integer(i64), intent(in) :: kernel_id
    type(c_ptr), intent(in) :: args(:)
    integer, intent(in) :: grid_size(3), block_size(3)
    integer :: status
    ! Real implementation in gpu_vulkan_backend.c
    status = SPORKLE_ERROR
  end function
  
end module sporkle_gpu_backend