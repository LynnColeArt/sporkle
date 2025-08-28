program test_pm4_eop_signal
  ! PM4 EOP Signal Test
  ! ===================
  ! Tests if CS actually completes using RELEASE_MEM EOP
  
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
  print *, "PM4 EOP Signal Test"
  print *, "======================================="
  print *, "Testing CP parsing vs CS completion"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers - all in GTT for easy debugging
  call output_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  call signal_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Signal VA: 0x", signal_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [1024])
  call c_f_pointer(signal_buffer%get_cpu_ptr(), signal_data, [64])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  
  ! Clear buffers
  output_data = int(z'CAFECAFE', i32)
  signal_data = 0  ! EOP will write 1 here
  
  ! Create PAL shader (from store_ud.o objdump)
  shader_data = 0
  shader_data(1) = int(z'7E000200', i32)  ! v_mov_b32 v0, s0
  shader_data(2) = int(z'7E020201', i32)  ! v_mov_b32 v1, s1
  shader_data(3) = int(z'7E0402FF', i32)  ! v_mov_b32 v2, 0xFF
  shader_data(4) = int(z'DEADBEEF', i32)  ! literal: 0xDEADBEEF
  shader_data(5) = int(z'DC700080', i32)  ! global_store_dword v[0:1], v2, off
  shader_data(6) = int(z'007D0200', i32)
  shader_data(7) = int(z'BF8C0070', i32)  ! s_waitcnt vmcnt(0) lgkmcnt(0)
  shader_data(8) = int(z'BF810000', i32)  ! s_endpgm
  
  print *, ""
  print *, "PAL shader loaded (32 bytes)"
  
  ! Build PM4 with EOP signal
  call build_eop_test_ib(ib_data, output_buffer%get_va(), &
                         signal_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 120_i32, [&
                                output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status:", status
    stop 1
  end if
  
  ! Wait for fence (CP parsing complete)
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ PM4 parsing complete (fence signaled)"
  
  ! Now poll for EOP signal (CS completion)
  print *, ""
  print *, "Polling for EOP signal..."
  eop_signaled = .false.
  do poll_count = 1, 1000
    if (signal_data(1) == 1) then
      eop_signaled = .true.
      exit
    end if
    ! Small delay
    call execute_command_line("sleep 0.001", wait=.true.)
  end do
  
  if (eop_signaled) then
    print '(A,I0,A)', "✅ EOP signaled after ", poll_count, " polls - CS completed!"
  else
    print *, "❌ EOP never signaled - CS never completed"
  end if
  
  ! Check if shader wrote
  print *, ""
  print *, "Checking shader output:"
  shader_wrote = .false.
  do i = 1, 16
    if (mod(i-1, 4) == 0) write(*, '(A,I3,A)', advance='no') "  [", i-1, "] "
    write(*, '(Z8,A)', advance='no') output_data(i), " "
    if (mod(i, 4) == 0) write(*, *)
    
    if (output_data(i) == int(z'DEADBEEF', i32)) then
      shader_wrote = .true.
    end if
  end do
  
  print *, ""
  print *, "=== RESULTS ==="
  if (eop_signaled .and. shader_wrote) then
    print *, "🎉 SUCCESS! Both EOP and shader write detected"
    print *, "CS is executing properly!"
  else if (eop_signaled .and. .not. shader_wrote) then
    print *, "⚠️  EOP signaled but no shader write"
    print *, "Memory/coherency issue (caches, VA mapping)"
  else
    print *, "❌ No EOP signal - waves never launched"
    print *, "Check HQD/doorbell/VMID setup"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_eop_test_ib(ib_data, output_va, signal_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, signal_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! Standard compute preamble
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
    
    ! Minimal state setup
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_TMPRING_SIZE
    ib_data(idx+2) = 0
    idx = idx + 3
    
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = SH_MEM_CONFIG
    ib_data(idx+2) = 0
    idx = idx + 3
    
    ! Cache invalidate
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_ACQUIRE_MEM))
    ib_data(idx+1) = int(z'00000003', i32)
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
    ib_data(idx+2) = int(z'00000041', i32)
    ib_data(idx+3) = int(z'00000004', i32)
    idx = idx + 4
    
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
    
    ! RELEASE_MEM with EOP signal
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(6_i32, 16), PM4_RELEASE_MEM))
    ! event_type = CACHE_FLUSH_AND_INV_TS_EVENT
    ! event_index = EVENT_INDEX_EOP (5)
    ! tc_action_ena = 1, tc_wb_action_ena = 1 (flush L2)
    ib_data(idx+1) = ior(ishft(CACHE_FLUSH_AND_INV_TS_EVENT, 0), &
                         ior(ishft(EVENT_INDEX_EOP, 8), &
                         ior(ishft(1_i32, 17), ishft(1_i32, 18))))  ! tc bits
    ! dst_sel = DST_SEL_MEM (2)
    ! int_sel = INT_SEL_NONE (0)
    ! data_sel = DATA_SEL_IMMEDIATE_32 (1)
    ib_data(idx+2) = ior(ishft(DST_SEL_MEM, 16), &
                         ior(ishft(INT_SEL_NONE, 24), &
                             ishft(DATA_SEL_IMMEDIATE_32, 29)))
    ! Address low
    ib_data(idx+3) = int(signal_va, c_int32_t)
    ! Address high
    ib_data(idx+4) = int(ishft(signal_va, -32), c_int32_t)
    ! Immediate data = 1
    ib_data(idx+5) = 1_i32
    ! Upper 32 bits (unused for 32-bit immediate)
    ib_data(idx+6) = 0_i32
    idx = idx + 7
    
    print '(A,I0)', "Total PM4 dwords: ", idx-1
    print *, "✓ RELEASE_MEM EOP added after dispatch"
    
  end subroutine

end program test_pm4_eop_signal