module sporkle_platform
  ! Platform detection and build configuration
  ! The Sporkle Way: Know your hardware, build accordingly
  
  use kinds
  implicit none
  private
  
  public :: detect_platform, platform_info
  public :: PLATFORM_LINUX, PLATFORM_MACOS, PLATFORM_WINDOWS
  public :: PLATFORM_UNKNOWN
  public :: GPU_AMD, GPU_NVIDIA, GPU_INTEL, GPU_APPLE, GPU_NONE
  
  ! Platform constants
  integer, parameter :: PLATFORM_UNKNOWN = 0
  integer, parameter :: PLATFORM_LINUX = 1
  integer, parameter :: PLATFORM_MACOS = 2
  integer, parameter :: PLATFORM_WINDOWS = 3
  integer, parameter :: PLATFORM_BSD = 4
  
  ! GPU vendor constants  
  integer, parameter :: GPU_NONE = 0
  integer, parameter :: GPU_AMD = 1
  integer, parameter :: GPU_NVIDIA = 2
  integer, parameter :: GPU_INTEL = 3
  integer, parameter :: GPU_APPLE = 4
  
  type :: platform_info
    integer :: platform = PLATFORM_UNKNOWN
    character(len=64) :: platform_name = "Unknown"
    character(len=64) :: kernel_version = "Unknown"
    integer :: primary_gpu = GPU_NONE
    character(len=64) :: gpu_string = "None"
    logical :: has_opengl = .false.
    logical :: has_vulkan = .false.
    logical :: has_metal = .false.
    logical :: has_direct_gpu = .false.
    character(len=256) :: build_flags = ""
  end type platform_info
  
contains

  function detect_platform() result(info)
    type(platform_info) :: info
    character(len=256) :: uname_s, uname_r
    character(len=512) :: uname_s_path, uname_r_path
    integer :: status
    integer :: file_unit
    integer :: io_status
    logical :: exists
    
    ! Try uname first (Unix-like systems)
    uname_s_path = resolve_temp_path("sporkle_uname_s.txt")
    uname_r_path = resolve_temp_path("sporkle_uname_r.txt")
    
    call execute_command_line("uname -s > '" // trim(uname_s_path) // "'", exitstat=status)
    
    if (status == 0) then
      ! Read the output
      open(newunit=file_unit, file=trim(uname_s_path), status='old', action='read', iostat=io_status)
      if (io_status == 0) then
        read(file_unit, '(A)') uname_s
        close(file_unit)
      end if
      call execute_command_line("rm -f '" // trim(uname_s_path) // "'", exitstat=status)
      
      ! Get kernel version too
      call execute_command_line("uname -r > '" // trim(uname_r_path) // "'", exitstat=status)
      if (status == 0) then
        open(newunit=file_unit, file=trim(uname_r_path), status='old', action='read', iostat=io_status)
        if (io_status == 0) then
          read(file_unit, '(A)') uname_r
          close(file_unit)
        end if
        call execute_command_line("rm -f '" // trim(uname_r_path) // "'", exitstat=status)
      end if
      
      if (index(uname_s, "Linux") > 0) then
        info%platform = PLATFORM_LINUX
        info%platform_name = "Linux"
        info%kernel_version = trim(adjustl(uname_r))
        call detect_linux_gpu(info)
        
      else if (index(uname_s, "Darwin") > 0) then
        info%platform = PLATFORM_MACOS
        info%platform_name = "macOS"
        info%kernel_version = trim(adjustl(uname_r))
        call detect_macos_gpu(info)
        
      else if (index(uname_s, "BSD") > 0) then
        info%platform = PLATFORM_BSD
        info%platform_name = "BSD"
        info%kernel_version = trim(adjustl(uname_r))
        call detect_bsd_gpu(info)
      end if
      
    else
      ! Might be Windows
      inquire(file="C:\Windows\System32", exist=exists)
      if (exists) then
        info%platform = PLATFORM_WINDOWS
        info%platform_name = "Windows"
        call detect_windows_gpu(info)
      end if
    end if
    
    ! Set build flags based on platform and GPU
    call set_build_flags(info)
    
  end function detect_platform
  
  subroutine detect_linux_gpu(info)
    type(platform_info), intent(inout) :: info
    character(len=256) :: gpu_info
    integer :: status
    logical :: exists
    
    ! Check for AMD GPU via sysfs
    inquire(file="/sys/class/drm/card0/device/vendor", exist=exists)
    if (exists) then
      open(unit=10, file="/sys/class/drm/card0/device/vendor", status='old')
      read(10, '(A)') gpu_info
      close(10)
      
      if (trim(gpu_info) == "0x1002") then  ! AMD vendor ID
        info%primary_gpu = GPU_AMD
        info%gpu_string = "AMD GPU"
        
        ! Check for direct AMDGPU driver
        inquire(file="/dev/dri/card0", exist=info%has_direct_gpu)
        
      else if (trim(gpu_info) == "0x10de") then  ! NVIDIA
        info%primary_gpu = GPU_NVIDIA
        info%gpu_string = "NVIDIA GPU"
        
      else if (trim(gpu_info) == "0x8086") then  ! Intel
        info%primary_gpu = GPU_INTEL
        info%gpu_string = "Intel GPU"
      end if
    end if
    
    ! Check for graphics libraries
    call check_library_exists("/usr/lib/x86_64-linux-gnu/libGL.so.1", info%has_opengl)
    call check_library_exists("/usr/lib/x86_64-linux-gnu/libvulkan.so.1", info%has_vulkan)
    
  end subroutine detect_linux_gpu
  
  subroutine detect_macos_gpu(info)
    type(platform_info), intent(inout) :: info
    
    ! On macOS, we always have Metal
    info%has_metal = .true.
    info%primary_gpu = GPU_APPLE
    info%gpu_string = "Apple GPU"
    info%has_direct_gpu = .true.
    
    ! OpenGL is deprecated but available
    info%has_opengl = .true.
    
  end subroutine detect_macos_gpu
  
  subroutine detect_windows_gpu(info)
    type(platform_info), intent(inout) :: info
    
    ! Windows GPU detection would go here
    ! For now, assume DirectX is available
    info%gpu_string = "Windows GPU"
    
  end subroutine detect_windows_gpu
  
  subroutine detect_bsd_gpu(info)
    type(platform_info), intent(inout) :: info
    
    ! BSD GPU detection similar to Linux
    call detect_linux_gpu(info)  ! Often similar paths
    
  end subroutine detect_bsd_gpu
  
  subroutine set_build_flags(info)
    type(platform_info), intent(inout) :: info
    
    ! Base flags
    info%build_flags = "-O2 -march=native"
    
    ! Platform-specific flags
    select case(info%platform)
    case(PLATFORM_LINUX)
      if (info%primary_gpu == GPU_AMD) then
        if (info%has_direct_gpu) then
          info%build_flags = trim(info%build_flags) // " -DSPORKLE_AMD_DIRECT"
        end if
        if (info%has_vulkan) then
          info%build_flags = trim(info%build_flags) // " -DSPORKLE_HAS_VULKAN"
        end if
      end if
      if (info%has_opengl) then
        info%build_flags = trim(info%build_flags) // " -DSPORKLE_HAS_OPENGL"
      end if
      
    case(PLATFORM_MACOS)
      info%build_flags = trim(info%build_flags) // &
        " -DSPORKLE_HAS_METAL -framework Metal -framework Foundation"
        
    case(PLATFORM_WINDOWS)
      info%build_flags = trim(info%build_flags) // " -DSPORKLE_HAS_DIRECTX"
    end select
    
  end subroutine set_build_flags
  
  subroutine check_library_exists(path, exists)
    character(len=*), intent(in) :: path
    logical, intent(out) :: exists
    
    inquire(file=path, exist=exists)
    
  end subroutine check_library_exists

  function resolve_temp_path(file_name) result(path)
    character(len=*), intent(in) :: file_name
    character(len=512) :: path
    character(len=256) :: tmp_dir
    integer :: io_status
    
    call get_environment_variable("TMPDIR", tmp_dir, status=io_status)
    if (io_status /= 0 .or. len_trim(tmp_dir) == 0) then
      call get_environment_variable("TEMP", tmp_dir, status=io_status)
    end if
    if (io_status /= 0 .or. len_trim(tmp_dir) == 0) then
      call get_environment_variable("TMP", tmp_dir, status=io_status)
    end if
    if (io_status /= 0 .or. len_trim(tmp_dir) == 0) then
      tmp_dir = "/tmp"
    end if
    
    if (tmp_dir(len_trim(tmp_dir):len_trim(tmp_dir)) /= '/') tmp_dir = trim(tmp_dir) // "/"
    path = trim(tmp_dir) // trim(file_name)
    
  end function resolve_temp_path
  
  subroutine print_platform_info(info)
    type(platform_info), intent(in) :: info
    
    print *, "🔍 Sporkle Platform Detection"
    print *, "============================"
    print '(A,A)', " Platform: ", trim(info%platform_name)
    print '(A,A)', " Kernel: ", trim(info%kernel_version)
    print '(A,A)', " Primary GPU: ", trim(info%gpu_string)
    print *, ""
    print *, "Available backends:"
    if (info%has_opengl) print *, "  ✓ OpenGL"
    if (info%has_vulkan) print *, "  ✓ Vulkan"
    if (info%has_metal) print *, "  ✓ Metal"
    if (info%has_direct_gpu) print *, "  ✓ Direct GPU access"
    print *, ""
    print '(A,A)', " Build flags: ", trim(info%build_flags)
    
  end subroutine print_platform_info

end module sporkle_platform
