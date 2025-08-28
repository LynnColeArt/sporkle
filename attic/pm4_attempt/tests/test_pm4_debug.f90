program test_pm4_debug
  ! PM4 Debug Test - Add cache flushes and barriers
  ! ===============================================
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:), shader_data(:)
  integer(i32) :: status, i, idx
  
  ! Additional PM4 packets for cache control
  integer(i32), parameter :: PM4_ACQUIRE_MEM = int(z'58', i32)
  integer(i32), parameter :: PM4_EVENT_WRITE = int(z'46', i32)
  
  print *, "PM4 Debug Test with Cache Control"
  print *, "================================="
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 1024_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 512_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Map and clear
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [256])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [128])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  
  output_data = -1  ! Fill with FF to see if it changes
  
  ! Simplest possible shader - just endpgm
  shader_data = 0
  shader_data(1) = int(z'BF810000', i32)  ! s_endpgm
  
  ! Build IB with cache control
  idx = 1
  
  ! Invalidate caches before dispatch
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_ACQUIRE_MEM))
  idx = idx + 1
  ib_data(idx) = int(z'00000003', i32)  ! Invalidate L1/L2
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  
  ! Set shader
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_LO
  ib_data(idx+2) = int(shader_buffer%get_va(), c_int32_t)
  ib_data(idx+3) = int(ishft(shader_buffer%get_va(), -32), c_int32_t)
  idx = idx + 4
  
  ! RSRC - try different values
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_RSRC1
  ib_data(idx+2) = 0  ! Minimal
  ib_data(idx+3) = int(z'000000AC', i32)  ! Try different RSRC2
  idx = idx + 4
  
  ! Workgroup
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_NUM_THREAD_X
  ib_data(idx+2) = 0
  ib_data(idx+3) = 0
  ib_data(idx+4) = 0
  idx = idx + 5
  
  ! Write event before dispatch
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(0_i32, 16), PM4_EVENT_WRITE))
  idx = idx + 1
  
  ! Dispatch
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
  ib_data(idx+1) = 1
  ib_data(idx+2) = 1
  ib_data(idx+3) = 1
  idx = idx + 4
  
  ! Flush after dispatch
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_ACQUIRE_MEM))
  idx = idx + 1
  ib_data(idx) = int(z'00000002', i32)  ! Memory fence
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  ib_data(idx) = 0
  idx = idx + 1
  
  print '(A,I0,A)', "IB: ", idx-1, " dwords"
  
  ! Try multiple times
  do i = 1, 3
    print '(A,I0)', "Attempt ", i
    
    status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, idx-1, [output_buffer%bo_ptr], fence)
    if (status /= 0) then
      print *, "  Submit failed!"
      cycle
    end if
    
    status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
    if (status == 0) then
      print *, "  Fence signaled OK"
    else
      print *, "  Fence timeout"
    end if
  end do
  
  print *, ""
  print *, "Output buffer (should be -1 if unchanged):"
  do i = 1, 4
    print '(A,I12)', "  ", output_data(i)
  end do
  
  print *, ""
  print *, "PM4 dispatch executes but shader doesn't run."
  print *, "This suggests we need:"
  print *, "  1. Correct RDNA2 shader binary format"
  print *, "  2. Additional initialization (LDS, scratch, etc)"
  print *, "  3. Or use a higher-level shader compiler"
  
  call sp_pm4_cleanup(ctx_ptr)
  
end program test_pm4_debug