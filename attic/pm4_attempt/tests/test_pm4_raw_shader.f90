program test_pm4_raw_shader
  ! PM4 Raw Shader Test
  ! ===================
  ! Uses hardcoded RDNA2 shader bytes
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:), shader_data(:)
  integer(i32) :: status, i
  logical :: success
  
  print *, "======================================="
  print *, "PM4 Raw Shader Test"
  print *, "======================================="
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [64])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [1024])
  
  ! Clear output
  output_data = int(z'CAFECAFE', i32)
  
  ! Create minimal RDNA2 shader with correct encoding (from objdump)
  shader_data = 0
  ! v_mov_b32 v0, s0
  shader_data(1) = int(z'7E000200', i32)
  ! v_mov_b32 v1, s1  
  shader_data(2) = int(z'7E020201', i32)
  ! v_mov_b32 v2, 0xFF (literal encoding)
  shader_data(3) = int(z'7E0402FF', i32)
  shader_data(4) = int(z'DEADBEEF', i32)
  ! global_store_dword v[0:1], v2, off
  shader_data(5) = int(z'DC700080', i32)
  shader_data(6) = int(z'007D0200', i32)
  ! s_waitcnt vmcnt(0) lgkmcnt(0)
  shader_data(7) = int(z'BF8C0070', i32)
  ! s_endpgm
  shader_data(8) = int(z'BF810000', i32)
  
  print *, ""
  print *, "Raw shader (32 bytes):"
  do i = 1, 8
    print '(A,I2,A,Z8)', "  [", i-1, "] = 0x", shader_data(i)
  end do
  
  ! Build PM4 with proper USER_SGPR setup
  call build_raw_dispatch(ib_data, output_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 45_i32, [&
                                output_buffer%bo_ptr], fence)
  if (status /= 0) stop 1
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  
  ! Check
  print *, ""
  print *, "Output:"
  success = .false.
  do i = 1, 8
    print '(A,I3,A,Z8)', "  [", i-1, "] = 0x", output_data(i)
    if (output_data(i) == int(z'DEADBEEF', i32)) then
      success = .true.
      print *, "    ^^^ 🎉 SUCCESS!"
    end if
  end do
  
  if (.not. success) then
    print *, ""
    print *, "Still no write. Possible issues:"
    print *, "  - Need different PM4 initialization"
    print *, "  - Memory coherency/permissions"
    print *, "  - Missing GPU state setup"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_raw_dispatch(ib_data, output_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! Invalidate caches before dispatch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), int(z'58', i32)))  ! ACQUIRE_MEM
    ib_data(idx+1) = int(z'00000003', i32)  ! Invalidate L1/L2
    ib_data(idx+2) = 0
    ib_data(idx+3) = 0
    ib_data(idx+4) = 0
    ib_data(idx+5) = 0
    idx = idx + 6
    
    ! Set shader
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(shader_va, c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -32), c_int32_t)
    idx = idx + 4
    
    ! RSRC1/2 with USER_SGPR_COUNT=2
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ib_data(idx+2) = int(z'00000041', i32)  ! 1 VGPR + 1 SGPR granule
    ib_data(idx+3) = int(z'00000004', i32)  ! USER_SGPR=2 (bits [6:1])
    idx = idx + 4
    
    ! Set COMPUTE_RESOURCE_LIMITS (may be required)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_RESOURCE_LIMITS
    ib_data(idx+2) = 0  ! Default limits
    idx = idx + 3
    
    ! USER_DATA_0/1
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_USER_DATA_0
    ib_data(idx+2) = int(output_va, c_int32_t)
    ib_data(idx+3) = int(ishft(output_va, -32), c_int32_t)
    idx = idx + 4
    
    ! Workgroup
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 63_i32
    ib_data(idx+3) = 0_i32
    ib_data(idx+4) = 0_i32
    idx = idx + 5
    
    ! Dispatch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    idx = idx + 4
    
    ! Memory barrier after dispatch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), int(z'58', i32)))  ! ACQUIRE_MEM
    ib_data(idx+1) = int(z'00000002', i32)  ! Write back L2
    ib_data(idx+2) = 0
    ib_data(idx+3) = 0
    ib_data(idx+4) = 0
    ib_data(idx+5) = 0
    idx = idx + 6
    
    print '(A,Z8)', "RSRC2 = 0x", int(z'00000004', i32)
    print '(A,I0)', "Total PM4 dwords: ", idx-1
    
  end subroutine

end program test_pm4_raw_shader