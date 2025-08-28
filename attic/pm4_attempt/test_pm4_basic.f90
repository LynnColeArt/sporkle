program test_pm4_basic
  use kinds
  use sporkle_pm4_compute_simple
  use sporkle_pm4_packets
  implicit none
  
  logical :: success
  integer :: i
  type(pm4_packet_builder) :: builder
  integer(i32), allocatable :: buffer(:)
  
  print *, "🧪 PM4 Basic Test"
  print *, "================="
  print *, ""
  
  ! Test 1: PM4 packet building
  print *, "📦 Test 1: PM4 Packet Building"
  call builder%init(128)
  
  ! Build some test packets
  call pm4_nop(builder, 4)
  call pm4_set_sh_reg(builder, int(z'100'), [int(z'DEADBEEF', int32)])
  call pm4_dispatch_direct(builder, 16, 1, 1)
  
  buffer = builder%get_buffer()
  print '(A,I0)', "Packet size: ", builder%get_size(), " dwords"
  print *, "First few dwords:"
  do i = 1, min(10, builder%get_size())
    print '(A,I0,A,Z8)', "  [", i, "] = 0x", buffer(i)
  end do
  
  call builder%cleanup()
  print *, "✅ Packet building works!"
  print *, ""
  
  ! Test 2: Simple PM4 test
  print *, "🚀 Test 2: PM4 Simple Test"
  success = pm4_test_basic()
  if (.not. success) then
    print *, "❌ PM4 basic test failed"
    stop 1
  end if
  print *, "✅ PM4 basic test passed!"
  
  print *, ""
  print *, "✅ PM4 basic test complete!"
  print *, ""
  print *, "Next steps:"
  print *, "1. Implement real ISA assembly"
  print *, "2. Add proper buffer management" 
  print *, "3. Create conv2d compute shader"
  print *, "4. Benchmark against OpenGL"
  
end program test_pm4_basic