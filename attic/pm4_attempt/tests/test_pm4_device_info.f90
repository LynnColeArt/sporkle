program test_pm4_device_info
  use kinds
  use pm4_device_discovery
  implicit none
  
  type(pm4_device), allocatable :: devices(:)
  integer :: i
  
  print *, "PM4 Device Discovery Information"
  print *, "================================"
  
  devices = discover_pm4_devices()
  
  if (size(devices) == 0) then
    print *, "No PM4 devices found!"
    stop 1
  end if
  
  do i = 1, size(devices)
    print *, ""
    print '(A,I0)', "Device ", i
    print '(A,A)', "  Path: ", trim(devices(i)%device_path)
    print '(A,A)', "  Name: ", trim(devices(i)%device_name)
    print '(A,Z8)', "  Device ID: 0x", devices(i)%device_id
    print '(A,I0)', "  Family ID: ", devices(i)%family
    print '(A,I0)', "  Compute Units: ", devices(i)%compute_units
    print '(A,I0)', "  Shader Engines: ", devices(i)%shader_engines
    print '(A,F4.1)', "  VRAM (GB): ", devices(i)%vram_size_gb
    print '(A,I0)', "  Bus Width: ", devices(i)%memory_bus_width
    print '(A,F6.2,A)', "  Max Clock: ", devices(i)%max_engine_clock_ghz, " GHz"
    
    ! Identify architecture
    print *, "  Architecture: "
    if (devices(i)%family == 145 .or. devices(i)%family == 148) then
      print *, "    RDNA3"
    else if (devices(i)%family >= 143 .and. devices(i)%family <= 151) then
      print *, "    RDNA2"
    else if (devices(i)%family >= 141) then
      print *, "    GCN5 (Vega)"
    else if (devices(i)%family >= 130) then
      print *, "    GCN3/4"
    else
      print *, "    GCN (older)"
    end if
  end do
  
end program test_pm4_device_info