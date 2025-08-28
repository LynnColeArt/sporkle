program test_pm4_basic
  use sporkle_pm4_compute_simple
  implicit none
  
  logical :: success
  
  print *, "🚀 PM4 Basic Test"
  print *, "================="
  print *, ""
  
  success = pm4_test_basic()
  
  if (success) then
    print *, ""
    print *, "🎉 PM4 TEST PASSED!"
    print *, "We successfully built and submitted PM4 packets!"
  else
    print *, ""
    print *, "❌ PM4 test failed"
  end if
  
end program test_pm4_basic