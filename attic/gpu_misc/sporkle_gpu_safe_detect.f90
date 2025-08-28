module sporkle_gpu_safe_detect
  ! Safe GPU detection without shell commands
  ! The Sporkle Way: Direct and secure
  
  use kinds
  use sporkle_error_handling
  implicit none
  private
  
  public :: detect_gpu_safe, gpu_info_type
  
  type :: gpu_info_type
    character(len=256) :: vendor = "Unknown"
    character(len=256) :: device = "Unknown"
    character(len=16) :: bus_id = ""
    logical :: is_amd = .false.
    logical :: is_nvidia = .false.
    logical :: is_intel = .false.
  end type gpu_info_type
  
contains

  ! Safely detect GPUs by reading /sys filesystem
  function detect_gpu_safe() result(gpus)
    type(gpu_info_type), allocatable :: gpus(:)
    
    integer :: num_gpus, i, unit, iostat
    character(len=512) :: line, path
    character(len=256) :: vendor_path, device_path
    character(len=16) :: pci_id
    logical :: exists
    
    ! Count PCI devices
    num_gpus = 0
    
    ! Check common PCI slots (simplified approach)
    do i = 0, 31
      write(pci_id, '(I2.2,A)') i, ":00.0"
      path = "/sys/bus/pci/devices/0000:" // trim(pci_id) // "/class"
      
      inquire(file=path, exist=exists)
      if (.not. exists) cycle
      
      open(newunit=unit, file=path, status='old', action='read', iostat=iostat)
      if (iostat /= 0) cycle
      
      read(unit, '(A)', iostat=iostat) line
      close(unit)
      
      if (iostat == 0) then
        ! Check if it's a VGA controller (class 0x030000)
        if (line(1:6) == "0x0300") then
          num_gpus = num_gpus + 1
        end if
      end if
    end do
    
    ! Allocate result array
    if (num_gpus == 0) then
      allocate(gpus(0))
      return
    end if
    
    allocate(gpus(num_gpus))
    
    ! Read GPU information
    num_gpus = 0
    do i = 0, 31
      write(pci_id, '(I2.2,A)') i, ":00.0"
      path = "/sys/bus/pci/devices/0000:" // trim(pci_id) // "/class"
      
      inquire(file=path, exist=exists)
      if (.not. exists) cycle
      
      open(newunit=unit, file=path, status='old', action='read', iostat=iostat)
      if (iostat /= 0) cycle
      
      read(unit, '(A)', iostat=iostat) line
      close(unit)
      
      if (iostat == 0 .and. line(1:6) == "0x0300") then
        num_gpus = num_gpus + 1
        if (num_gpus > size(gpus)) exit
        
        gpus(num_gpus)%bus_id = "0000:" // trim(pci_id)
        
        ! Read vendor ID
        vendor_path = "/sys/bus/pci/devices/0000:" // trim(pci_id) // "/vendor"
        call read_file_line(vendor_path, line)
        
        select case(trim(line))
        case("0x1002")  ! AMD
          gpus(num_gpus)%vendor = "AMD/ATI"
          gpus(num_gpus)%is_amd = .true.
        case("0x10de")  ! NVIDIA
          gpus(num_gpus)%vendor = "NVIDIA"
          gpus(num_gpus)%is_nvidia = .true.
        case("0x8086")  ! Intel
          gpus(num_gpus)%vendor = "Intel"
          gpus(num_gpus)%is_intel = .true.
        case default
          gpus(num_gpus)%vendor = "Unknown (ID: " // trim(line) // ")"
        end select
        
        ! Read device ID
        device_path = "/sys/bus/pci/devices/0000:" // trim(pci_id) // "/device"
        call read_file_line(device_path, line)
        
        ! Map known devices
        if (gpus(num_gpus)%is_amd) then
          select case(trim(line))
          case("0x73bf", "0x73df")  ! Navi 31
            gpus(num_gpus)%device = "Radeon RX 7900 XT/XTX"
          case("0x164e")  ! Raphael
            gpus(num_gpus)%device = "Raphael (Integrated)"
          case default
            gpus(num_gpus)%device = "AMD GPU (ID: " // trim(line) // ")"
          end select
        else
          gpus(num_gpus)%device = "Device ID: " // trim(line)
        end if
      end if
    end do
    
  end function detect_gpu_safe
  
  ! Helper to read a single line from a file
  subroutine read_file_line(filename, line)
    character(len=*), intent(in) :: filename
    character(len=*), intent(out) :: line
    
    integer :: unit, iostat
    logical :: exists
    
    line = ""
    
    inquire(file=filename, exist=exists)
    if (.not. exists) return
    
    open(newunit=unit, file=filename, status='old', action='read', iostat=iostat)
    if (iostat /= 0) return
    
    read(unit, '(A)', iostat=iostat) line
    close(unit)
    
  end subroutine read_file_line

end module sporkle_gpu_safe_detect