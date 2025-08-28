module sporkle_gpu_backend_detect
  ! Enhanced GPU backend detection
  ! The Sporkle Way: Know what you're working with!
  
  use kinds
  use iso_c_binding
  use sporkle_error_handling
  implicit none
  private
  
  public :: detect_opengl_version, detect_vulkan_version
  public :: detect_rocm_version, detect_cuda_version
  public :: check_compute_capability
  public :: opengl_info
  
  ! OpenGL version info
  type :: opengl_info
    integer :: major = 0
    integer :: minor = 0
    logical :: has_compute = .false.
    logical :: has_bindless = .false.
    integer :: max_compute_groups(3) = 0
    integer :: max_compute_invocations = 0
  end type opengl_info
  
contains

  ! Detect OpenGL version and compute capabilities
  function detect_opengl_version() result(info)
    type(opengl_info) :: info
    character(len=256) :: glxinfo_path
    integer :: unit, iostat
    character(len=512) :: line
    logical :: found_version
    
    ! First check if we can query OpenGL
    ! Try to read from glxinfo output file if it exists
    glxinfo_path = "/tmp/sporkle_glxinfo.txt"
    
    ! In a real implementation, we'd create a minimal GL context
    ! For now, let's check if the libraries exist and parse any cached info
    
    inquire(file=glxinfo_path, exist=found_version)
    if (found_version) then
      open(newunit=unit, file=glxinfo_path, status='old', action='read', iostat=iostat)
      if (iostat == 0) then
        do
          read(unit, '(A)', iostat=iostat) line
          if (iostat /= 0) exit
          
          ! Parse OpenGL version
          if (index(line, "OpenGL version string:") > 0) then
            call parse_gl_version(line, info%major, info%minor)
          end if
          
          ! Check for compute shader extension
          if (index(line, "GL_ARB_compute_shader") > 0) then
            info%has_compute = .true.
          end if
        end do
        close(unit)
      end if
    end if
    
    ! OpenGL 4.3+ has compute shaders
    if (info%major > 4 .or. (info%major == 4 .and. info%minor >= 3)) then
      info%has_compute = .true.
      ! Typical limits for modern GPUs
      info%max_compute_groups = [65535, 65535, 65535]
      info%max_compute_invocations = 1024
    end if
    
    ! For testing, let's check via library existence
    if (info%major == 0) then
      if (check_gl_library()) then
        ! Assume modern OpenGL if library exists
        info%major = 4
        info%minor = 6
        info%has_compute = .true.
        info%max_compute_groups = [65535, 65535, 65535]
        info%max_compute_invocations = 1024
      end if
    end if
    
  end function detect_opengl_version
  
  ! Parse OpenGL version from string
  subroutine parse_gl_version(version_string, major, minor)
    character(len=*), intent(in) :: version_string
    integer, intent(out) :: major, minor
    integer :: pos, dot_pos
    character(len=10) :: version_part
    
    major = 0
    minor = 0
    
    ! Find version number after "OpenGL version string:"
    pos = index(version_string, ":")
    if (pos > 0) then
      version_part = adjustl(version_string(pos+1:))
      dot_pos = index(version_part, ".")
      if (dot_pos > 0) then
        read(version_part(1:dot_pos-1), *, iostat=pos) major
        read(version_part(dot_pos+1:dot_pos+1), *, iostat=pos) minor
      end if
    end if
    
  end subroutine parse_gl_version
  
  ! Check if OpenGL library is available
  function check_gl_library() result(available)
    logical :: available
    character(len=256) :: lib_paths(4)
    integer :: i
    
    lib_paths = [character(len=256) :: &
      "/usr/lib/x86_64-linux-gnu/libGL.so.1", &
      "/usr/lib64/libGL.so.1", &
      "/usr/lib/libGL.so.1", &
      "/usr/lib/x86_64-linux-gnu/libGL.so"]
    
    available = .false.
    do i = 1, size(lib_paths)
      inquire(file=trim(lib_paths(i)), exist=available)
      if (available) exit
    end do
    
  end function check_gl_library
  
  ! Detect Vulkan version
  function detect_vulkan_version() result(version)
    character(len=32) :: version
    character(len=256) :: vk_path
    logical :: exists
    
    version = "Unknown"
    
    ! Check for Vulkan ICD files
    vk_path = "/usr/share/vulkan/icd.d/"
    inquire(file=trim(vk_path), exist=exists)
    
    if (exists) then
      version = "Vulkan 1.3+"  ! Assume recent version if ICDs exist
    else
      vk_path = "/etc/vulkan/icd.d/"
      inquire(file=trim(vk_path), exist=exists)
      if (exists) then
        version = "Vulkan 1.2+"
      end if
    end if
    
  end function detect_vulkan_version
  
  ! Detect ROCm version
  function detect_rocm_version() result(version)
    character(len=32) :: version
    character(len=256) :: rocm_path, version_file
    integer :: unit, iostat
    
    version = "Unknown"
    
    ! Check ROCM_PATH environment variable
    call get_environment_variable("ROCM_PATH", rocm_path)
    
    if (len_trim(rocm_path) == 0) then
      rocm_path = "/opt/rocm"
    end if
    
    ! Read version from .info/version file
    version_file = trim(rocm_path) // "/.info/version"
    block
      logical :: file_exists
      inquire(file=version_file, exist=file_exists)
      
      if (file_exists) then
        open(newunit=unit, file=version_file, status='old', action='read', iostat=iostat)
        if (iostat == 0) then
          read(unit, '(A)', iostat=iostat) version
          close(unit)
        end if
      else
        ! Try version-dev file
        version_file = trim(rocm_path) // "/.info/version-dev"
        inquire(file=version_file, exist=file_exists)
        if (file_exists) then
          open(newunit=unit, file=version_file, status='old', action='read', iostat=iostat)
          if (iostat == 0) then
            read(unit, '(A)', iostat=iostat) version
            close(unit)
          end if
        end if
      end if
    end block
    
  end function detect_rocm_version
  
  ! Detect CUDA version
  function detect_cuda_version() result(version)
    character(len=32) :: version
    character(len=256) :: cuda_path, version_file
    integer :: unit, iostat
    character(len=256) :: line
    
    version = "Unknown"
    
    ! Check CUDA_PATH or standard location
    call get_environment_variable("CUDA_PATH", cuda_path)
    if (len_trim(cuda_path) == 0) then
      cuda_path = "/usr/local/cuda"
    end if
    
    ! Read version from version.txt
    version_file = trim(cuda_path) // "/version.txt"
    block
      logical :: file_exists
      inquire(file=version_file, exist=file_exists)
      
      if (file_exists) then
      open(newunit=unit, file=version_file, status='old', action='read', iostat=iostat)
      if (iostat == 0) then
        read(unit, '(A)', iostat=iostat) line
        close(unit)
        ! Parse "CUDA Version X.Y.Z" format
        if (index(line, "CUDA Version") > 0) then
          version = trim(line)
        end if
      end if
      else
        ! Try version.json for newer CUDA
        version_file = trim(cuda_path) // "/version.json"
        inquire(file=version_file, exist=file_exists)
        if (file_exists) then
          version = "CUDA 11.0+"  ! Newer versions use JSON
        end if
      end if
    end block
    
  end function detect_cuda_version
  
  ! Check compute capability of a backend
  function check_compute_capability(backend_name) result(capable)
    character(len=*), intent(in) :: backend_name
    logical :: capable
    type(opengl_info) :: gl_info
    
    capable = .false.
    
    select case(trim(backend_name))
    case("opengl", "OpenGL")
      gl_info = detect_opengl_version()
      capable = gl_info%has_compute
      
    case("vulkan", "Vulkan")
      capable = detect_vulkan_version() /= "Unknown"
      
    case("rocm", "ROCm")
      capable = detect_rocm_version() /= "Unknown"
      
    case("cuda", "CUDA")
      capable = detect_cuda_version() /= "Unknown"
      
    end select
    
  end function check_compute_capability
  
  ! Helper removed - was conflicting with intrinsic

end module sporkle_gpu_backend_detect