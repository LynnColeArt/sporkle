program test_pm4_discovery_simple
  ! Simple test of PM4 device discovery module
  
  use kinds
  use pm4_device_discovery
  implicit none
  
  type(pm4_device), allocatable :: devices(:)
  integer :: i, count
  
  print *, "PM4 Device Discovery Module Test"
  print *, "================================"
  print *, ""
  
  ! Get device count
  count = get_pm4_device_count()
  print '(A,I0,A)', "Found ", count, " AMD GPU(s)"
  print *, ""
  
  ! Get device details
  devices = discover_pm4_devices()
  
  do i = 1, size(devices)
    print '(A,I0,A)', "Device ", i, ":"
    print '(A,A)', "  Path: ", trim(devices(i)%device_path)
    print '(A,A)', "  Name: ", trim(devices(i)%device_name)
    print '(A,Z4)', "  Device ID: 0x", devices(i)%device_id
    print '(A,I0)', "  Compute Units: ", devices(i)%compute_units
    print '(A,F0.1,A)', "  Theoretical Performance: ", devices(i)%theoretical_gflops/1000.0_sp, " TFLOPS"
    print '(A,F0.1,A)', "  Memory Bandwidth: ", devices(i)%memory_bandwidth_gb, " GB/s"
    print '(A,F0.1,A)', "  VRAM: ", devices(i)%vram_size_gb, " GB"
    print *, ""
  end do
  
  print *, "Test complete!"
  
end program test_pm4_discovery_simple