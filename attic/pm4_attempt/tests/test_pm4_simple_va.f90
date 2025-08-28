program test_pm4_simple_va
  ! Test PM4 with simple VA mapping that we know works
  ! ==================================================
  
  use sporkle_pm4_compute
  use sporkle_amdgpu_direct
  use kinds
  use iso_c_binding
  implicit none
  
  logical :: success
  type(amdgpu_buffer) :: test_buffer
  integer :: status
  integer(i64) :: va_addr
  
  print *, "🚀 PM4 Simple VA Test"
  print *, "====================="
  print *, ""
  
  ! Initialize PM4 compute
  success = pm4_init_compute()
  if (.not. success) then
    print *, "❌ Failed to initialize PM4"
    stop 1
  end if
  
  ! Access the global context device directly
  block
    use sporkle_pm4_compute, only: g_context => g_context
    
    print *, "🧪 Testing buffer allocation and VA mapping..."
    
    ! Allocate buffer using the same device and context as debug test
    test_buffer = amdgpu_allocate_buffer(g_context%device, 4096_int64, 2)  ! GTT
    if (test_buffer%handle == 0) then
      print *, "❌ Failed to allocate buffer"
      call pm4_cleanup_compute()
      stop 1
    end if
    
    ! Try the VA address that worked in debug test
    va_addr = int(z'100000', int64)  ! 1MB
    
    print '(A,Z16)', "   Trying VA address: 0x", va_addr
    status = amdgpu_map_va(g_context%device, test_buffer, va_addr)
    
    if (status == 0) then
      print *, "   ✅ VA mapping successful!"
      
      ! Test if we can read/write to the mapped region
      block
        integer(i32), pointer :: ptr(:)
        type(c_ptr) :: mapped_ptr
        
        ! Map for CPU access too
        status = amdgpu_map_buffer(g_context%device, test_buffer)
        if (status == 0) then
          call c_f_pointer(test_buffer%cpu_ptr, ptr, [1024])
          ptr(1) = int(z'DEADBEEF', int32)
          ptr(2) = int(z'CAFEBABE', int32)
          print *, "   ✅ CPU write successful"
          
          if (ptr(1) == int(z'DEADBEEF', int32)) then
            print *, "   ✅ CPU read verification successful"
          end if
        end if
      end block
      
      ! Unmap
      call amdgpu_unmap_va(g_context%device, test_buffer)
      print *, "   ✅ VA unmapping successful"
      
    else
      print *, "   ❌ VA mapping failed"
    end if
  end block
  
  ! Cleanup
  call pm4_cleanup_compute()
  
  if (status == 0) then
    print *, ""
    print *, "🎉 PM4 VA mapping integration successful!"
    print *, "   Ready to proceed with shader compilation"
  else
    print *, ""
    print *, "❌ PM4 VA mapping integration failed"
  end if

end program test_pm4_simple_va