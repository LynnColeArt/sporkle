program test_pm4_inline_shader
  ! PM4 Inline Shader Test
  ! ======================
  ! Simplest possible RDNA2 shader inline
  
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
  print *, "PM4 Inline Shader Test"
  print *, "======================================="
  print *, "Testing simplest possible RDNA2 shader"
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
  
  ! Simplest possible shader - just s_endpgm
  shader_data = 0
  shader_data(1) = int(z'BF810000', i32)  ! s_endpgm
  
  print *, "Using simplest shader: just s_endpgm"
  
  ! Build command buffer
  call build_minimal_ib(ib_data, output_buffer%get_va(), &
                        signal_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit with shader buffer first
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 100_i32, [&
                                shader_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status", status
    stop 1
  end if
  
  ! Wait for fence
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Fence signaled"
  
  ! Poll for EOP - should signal immediately since shader does nothing
  eop_signaled = .false.
  do poll_count = 1, 100
    if (signal_data(1) == 1) then
      eop_signaled = .true.
      exit
    end if
    call execute_command_line("sleep 0.001", wait=.true.)
  end do
  
  if (eop_signaled) then
    print '(A,I0,A)', "✅ EOP signaled after ", poll_count, " polls"
  else
    print *, "❌ No EOP signal - waves never executed!"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_minimal_ib(ib_data, output_va, signal_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, signal_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! CLEAR_STATE
    ib_data(idx) = ior(ishft(3_i32, 30), PM4_CLEAR_STATE)
    ib_data(idx+1) = 0
    idx = idx + 2
    
    ! Set shader address
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(ishft(shader_va, -8), c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -40), c_int32_t)
    idx = idx + 4
    
    print '(A,Z16)', "Shader VA: 0x", shader_va
    print '(A,Z8,A,Z8)', "PGM_LO: 0x", ib_data(idx-2), " PGM_HI: 0x", ib_data(idx-1)
    
    ! Minimal RSRC1/2 - just enough to run
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ib_data(idx+2) = int(z'00000040', i32)  ! Minimal VGPR/SGPR
    ib_data(idx+3) = int(z'00000000', i32)  ! No user SGPRs
    idx = idx + 4
    
    ! Thread group size
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 1_i32   ! Just 1 thread
    ib_data(idx+3) = 1_i32
    ib_data(idx+4) = 1_i32
    idx = idx + 5
    
    ! DISPATCH_DIRECT
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(4_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32  ! 1 group
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    ib_data(idx+4) = ior(int(z'00000001', i32), ishft(1_i32, 12))  ! EN | DATA_ATC
    idx = idx + 5
    
    print *, "✓ Minimal dispatch: 1x1x1 groups, 1x1x1 threads"
    
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

end program test_pm4_inline_shader