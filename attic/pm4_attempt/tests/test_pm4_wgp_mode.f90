program test_pm4_wgp_mode
  ! PM4 WGP Mode Test
  ! =================
  ! Tests with COMPUTE_PGM_RSRC3 WGP_MODE=1 for RDNA2
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, signal_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:), signal_data(:), shader_data(:)
  integer(i32) :: status, i, poll_count
  logical :: eop_signaled, shader_wrote
  
  print *, "======================================="
  print *, "PM4 WGP Mode Test"
  print *, "======================================="
  print *, "Testing with RSRC3 WGP_MODE=1 for RDNA2"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  call signal_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [1024])
  call c_f_pointer(signal_buffer%get_cpu_ptr(), signal_data, [64])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  
  ! Clear buffers
  output_data = int(z'CAFECAFE', i32)
  signal_data = 0
  
  ! Simple store shader
  shader_data = 0
  shader_data(1) = int(z'7E000200', i32)  ! v_mov_b32 v0, s0
  shader_data(2) = int(z'7E020201', i32)  ! v_mov_b32 v1, s1
  shader_data(3) = int(z'7E0402FF', i32)  ! v_mov_b32 v2, 0xFF
  shader_data(4) = int(z'DEADBEEF', i32)  ! literal
  shader_data(5) = int(z'DC700080', i32)  ! global_store_dword
  shader_data(6) = int(z'007D0200', i32)
  shader_data(7) = int(z'BF8C0070', i32)  ! s_waitcnt
  shader_data(8) = int(z'BF810000', i32)  ! s_endpgm
  
  ! Build command buffer with WGP_MODE
  call build_wgp_mode_ib(ib_data, output_buffer%get_va(), &
                         signal_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 120_i32, [&
                                output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed"
    stop 1
  end if
  
  ! Wait for fence
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Fence signaled"
  
  ! Poll for EOP
  eop_signaled = .false.
  do poll_count = 1, 1000
    if (signal_data(1) == 1) then
      eop_signaled = .true.
      exit
    end if
    call execute_command_line("sleep 0.001", wait=.true.)
  end do
  
  if (eop_signaled) then
    print '(A,I0,A)', "✅ EOP signaled after ", poll_count, " polls"
  else
    print *, "❌ No EOP signal"
  end if
  
  ! Check output
  shader_wrote = .false.
  do i = 1, 8
    if (output_data(i) == int(z'DEADBEEF', i32)) then
      shader_wrote = .true.
      print '(A,I0,A)', "🎉 Found 0xDEADBEEF at offset ", (i-1)*4, "!"
      exit
    end if
  end do
  
  if (.not. shader_wrote) then
    print *, "❌ No shader write detected"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_wgp_mode_ib(ib_data, output_va, signal_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, signal_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! GRBM_GFX_INDEX broadcast
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_UCONFIG_REG))
    ib_data(idx+1) = ishft(GRBM_GFX_INDEX, -2)
    ib_data(idx+2) = int(z'E0000000', i32)
    idx = idx + 3
    
    ! CLEAR_STATE
    ib_data(idx) = ior(ishft(3_i32, 30), PM4_CLEAR_STATE)
    ib_data(idx+1) = 0
    idx = idx + 2
    
    ! CONTEXT_CONTROL
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_CONTEXT_CONTROL))
    ib_data(idx+1) = int(z'00000101', i32)
    ib_data(idx+2) = int(z'00000000', i32)
    idx = idx + 3
    
    ! Enable all CUs
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(4_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_STATIC_THREAD_MGMT_SE0
    ib_data(idx+2) = int(z'FFFFFFFF', i32)
    ib_data(idx+3) = int(z'FFFFFFFF', i32)
    ib_data(idx+4) = int(z'FFFFFFFF', i32)
    ib_data(idx+5) = int(z'FFFFFFFF', i32)
    idx = idx + 6
    
    ! Set shader
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(shader_va, c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -32), c_int32_t)
    idx = idx + 4
    
    ! RSRC1/2/3 - including WGP_MODE
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ib_data(idx+2) = int(z'00000041', i32)  ! VGPR=1, SGPR=1
    ib_data(idx+3) = int(z'00000004', i32)  ! USER_SGPR=2
    ib_data(idx+4) = int(z'00080000', i32)  ! RSRC3: WGP_MODE=1 (bit 19)
    idx = idx + 5
    
    print *, "✓ Set RSRC3 with WGP_MODE=1"
    
    ! USER_DATA
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
    
    ! Resource limits
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_RESOURCE_LIMITS
    ib_data(idx+2) = 0
    idx = idx + 3
    
    ! DISPATCH_INITIATOR
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_DISPATCH_INITIATOR
    ib_data(idx+2) = int(z'00000001', i32)
    idx = idx + 3
    
    ! DISPATCH_DIRECT
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    idx = idx + 4
    
    ! RELEASE_MEM EOP
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(6_i32, 16), PM4_RELEASE_MEM))
    ib_data(idx+1) = ior(ishft(CACHE_FLUSH_AND_INV_TS_EVENT, 0), &
                         ior(ishft(EVENT_INDEX_EOP, 8), &
                         ior(ishft(1_i32, 17), ishft(1_i32, 18))))
    ib_data(idx+2) = ior(ishft(DST_SEL_MEM, 16), &
                         ior(ishft(INT_SEL_NONE, 24), &
                             ishft(DATA_SEL_IMMEDIATE_32, 29)))
    ib_data(idx+3) = int(signal_va, c_int32_t)
    ib_data(idx+4) = int(ishft(signal_va, -32), c_int32_t)
    ib_data(idx+5) = 1_i32
    ib_data(idx+6) = 0_i32
    idx = idx + 7
    
  end subroutine

end program test_pm4_wgp_mode