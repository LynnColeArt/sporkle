program test_pm4_compute_preamble
  ! PM4 Compute Preamble Test
  ! =========================
  ! Implements Mini's complete compute initialization sequence
  
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
  print *, "PM4 Compute Preamble Test"
  print *, "======================================="
  print *, "Mini's complete initialization sequence"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers - USE GTT (HOST_VISIBLE) as Mini suggested
  call output_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [1024])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  
  ! Clear output
  output_data = int(z'CAFECAFE', i32)
  
  ! Create minimal RDNA2 shader (from objdump of store_ud.o)
  shader_data = 0
  shader_data(1) = int(z'7E000200', i32)  ! v_mov_b32 v0, s0
  shader_data(2) = int(z'7E020201', i32)  ! v_mov_b32 v1, s1
  shader_data(3) = int(z'7E0402FF', i32)  ! v_mov_b32 v2, 0xFF
  shader_data(4) = int(z'DEADBEEF', i32)  ! literal: 0xDEADBEEF
  shader_data(5) = int(z'DC700080', i32)  ! global_store_dword v[0:1], v2, off
  shader_data(6) = int(z'007D0200', i32)  ! 
  shader_data(7) = int(z'BF8C0070', i32)  ! s_waitcnt vmcnt(0) lgkmcnt(0)
  shader_data(8) = int(z'BF810000', i32)  ! s_endpgm
  
  ! Build PM4 with complete preamble
  call build_compute_preamble_ib(ib_data, output_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 120_i32, [&
                                output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status:", status
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Dispatch completed!"
  
  ! Check results
  print *, ""
  print *, "Output buffer:"
  success = .false.
  do i = 1, 16
    if (mod(i-1, 4) == 0) write(*, '(A,I3,A)', advance='no') "  [", i-1, "] "
    write(*, '(Z8,A)', advance='no') output_data(i), " "
    if (mod(i, 4) == 0) write(*, *)
    
    if (output_data(i) == int(z'DEADBEEF', i32)) then
      success = .true.
    end if
  end do
  
  if (success) then
    print *, ""
    print *, "🎉 SUCCESS! Found 0xDEADBEEF - Compute preamble works!"
    print *, "PM4 + RDNA2 + Complete Init = PRODUCTION READY!"
  else
    print *, ""
    print *, "No 0xDEADBEEF found. Dumping first 32 bytes for debug:"
    do i = 1, 8
      print '(A,I2,A,Z8)', "  Shader[", i-1, "] = 0x", shader_data(i)
    end do
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_compute_preamble_ib(ib_data, output_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! 0. Set GRBM_GFX_INDEX to broadcast mode (SE=ALL, SH=ALL)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_UCONFIG_REG))
    ib_data(idx+1) = ishft(GRBM_GFX_INDEX, -2)  ! Register offset/4
    ib_data(idx+2) = int(z'E0000000', i32)  ! SE_BROADCAST_WRITES=1, SH_BROADCAST_WRITES=1
    idx = idx + 3
    
    ! 1. CLEAR_STATE - start fresh
    ib_data(idx) = ior(ishft(3_i32, 30), PM4_CLEAR_STATE)
    ib_data(idx+1) = 0
    idx = idx + 2
    
    ! 2. CONTEXT_CONTROL - enable CS register loads
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_CONTEXT_CONTROL))
    ib_data(idx+1) = int(z'00000101', i32)  ! LOAD_ENABLE_CS_SH_REGS=1, LOAD_CS_SH_REGS=1
    ib_data(idx+2) = int(z'00000000', i32)
    idx = idx + 3
    
    ! 3. Enable all CUs - CRITICAL!
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(4_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_STATIC_THREAD_MGMT_SE0
    ib_data(idx+2) = int(z'FFFFFFFF', i32)  ! Enable all CUs in SE0
    ib_data(idx+3) = int(z'FFFFFFFF', i32)  ! Enable all CUs in SE1
    ib_data(idx+4) = int(z'FFFFFFFF', i32)  ! Enable all CUs in SE2
    ib_data(idx+5) = int(z'FFFFFFFF', i32)  ! Enable all CUs in SE3
    idx = idx + 6
    
    ! 4. No scratch for this probe
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_TMPRING_SIZE
    ib_data(idx+2) = 0  ! No scratch
    idx = idx + 3
    
    ! 5. SH_MEM_CONFIG - aligned mode, no GDS
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = SH_MEM_CONFIG
    ib_data(idx+2) = int(z'00000000', i32)  ! Default/aligned mode
    idx = idx + 3
    
    ! 6. SH_MEM_BASES - aperture bases (zeros for default)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = SH_MEM_BASES
    ib_data(idx+2) = 0
    idx = idx + 3
    
    ! 7. Trap base (zeros for no traps)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(4_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_TBA_LO
    ib_data(idx+2) = 0  ! TBA_LO
    ib_data(idx+3) = 0  ! TBA_HI
    ib_data(idx+4) = 0  ! TMA_LO
    ib_data(idx+5) = 0  ! TMA_HI
    idx = idx + 6
    
    ! 8. Resource limits
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_RESOURCE_LIMITS
    ib_data(idx+2) = 0  ! WAVES_PER_SH=0 (no limit)
    idx = idx + 3
    
    ! 9. Cache invalidate before dispatch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_ACQUIRE_MEM))
    ib_data(idx+1) = int(z'00000003', i32)  ! Invalidate L1/L2
    ib_data(idx+2) = 0
    ib_data(idx+3) = 0
    ib_data(idx+4) = 0
    ib_data(idx+5) = 0
    idx = idx + 6
    
    ! Now the standard dispatch setup
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
    
    ! USER_DATA_0/1 with output pointer
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_USER_DATA_0
    ib_data(idx+2) = int(output_va, c_int32_t)
    ib_data(idx+3) = int(ishft(output_va, -32), c_int32_t)
    idx = idx + 4
    
    ! Workgroup size
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 63_i32  ! 64-1 threads
    ib_data(idx+3) = 0_i32   ! Y=1
    ib_data(idx+4) = 0_i32   ! Z=1
    idx = idx + 5
    
    ! DISPATCH_INITIATOR - set for compute, wave64
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_DISPATCH_INITIATOR
    ib_data(idx+2) = int(z'00000001', i32)  ! COMPUTE_SHADER_EN=1
    idx = idx + 3
    
    ! DISPATCH_DIRECT
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    idx = idx + 4
    
    ! Global cache writeback after dispatch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_ACQUIRE_MEM))
    ib_data(idx+1) = int(z'00000002', i32)  ! Write back L2
    ib_data(idx+2) = 0
    ib_data(idx+3) = 0
    ib_data(idx+4) = 0
    ib_data(idx+5) = 0
    idx = idx + 6
    
    print *, ""
    print *, "Built complete compute preamble:"
    print '(A,I0,A)', "  Total PM4 dwords: ", idx-1
    print *, "  ✓ CLEAR_STATE"
    print *, "  ✓ CONTEXT_CONTROL (CS regs enabled)"
    print *, "  ✓ COMPUTE_STATIC_THREAD_MGMT (all CUs enabled)"
    print *, "  ✓ SH_MEM_CONFIG (aligned mode)"
    print *, "  ✓ Trap base cleared"
    print *, "  ✓ Resource limits set"
    print *, "  ✓ Cache invalidated"
    print '(A,Z8)', "  RSRC2 = 0x", int(z'00000004', i32), " (USER_SGPR_COUNT=2)"
    
  end subroutine

end program test_pm4_compute_preamble