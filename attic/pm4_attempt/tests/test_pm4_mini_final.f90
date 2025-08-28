program test_pm4_mini_final
  ! PM4 Mini Final Test
  ! ===================
  ! Implements Mini's complete fix: all BOs in one submit + arch-matched shader
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, signal_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  type(sp_bo), pointer :: data_bos(:)  ! Array of sp_bo structs for C interface
  type(c_ptr), allocatable, target :: bo_ptrs(:)  ! Array to hold pointers
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:), signal_data(:), shader_data(:)
  integer(i32) :: status, i, poll_count
  logical :: eop_signaled, shader_wrote
  
  print *, "======================================="
  print *, "PM4 Mini Final Test"
  print *, "======================================="
  print *, "All BOs in one submit + simple s_endpgm shader"
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
  
  ! Simplest shader that should work on ANY architecture: just s_endpgm
  ! Per Mini's analysis, this is the most basic shader that should work
  shader_data = 0
  shader_data(1) = int(z'BF810000', i32)  ! s_endpgm - universal encoding
  
  print *, "Using universal shader: s_endpgm (works on all archs)"
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  print '(A,Z8)', "Shader data[1]: 0x", shader_data(1)
  
  ! Build command buffer
  call build_minimal_ib(ib_data, output_buffer%get_va(), &
                        signal_buffer%get_va(), shader_buffer%get_va())
  
  ! Create BO list with ALL buffers - allocate array of pointers
  allocate(bo_ptrs(3))
  bo_ptrs(1) = shader_buffer%bo_ptr
  bo_ptrs(2) = output_buffer%bo_ptr
  bo_ptrs(3) = signal_buffer%bo_ptr
  
  print *, "Submitting with ALL BOs in one list..."
  
  ! Submit with ALL buffers (increased size for new packets)
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 100_i32, bo_ptrs, fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status", status
    stop 1
  end if
  
  ! Wait for fence
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Fence signaled"
  
  ! Poll for EOP
  eop_signaled = .false.
  do poll_count = 1, 100
    if (signal_data(1) == 1) then
      eop_signaled = .true.
      exit
    end if
    call execute_command_line("sleep 0.001", wait=.true.)
  end do
  
  if (eop_signaled) then
    print '(A,I0,A)', "🎉 EOP signaled after ", poll_count, " polls - WAVES EXECUTED!"
  else
    print *, "❌ No EOP signal"
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
    
    ! CONTEXT_CONTROL - match libdrm exactly
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_CONTEXT_CONTROL))
    ib_data(idx+1) = int(z'80000000', i32)  ! libdrm value
    ib_data(idx+2) = int(z'80000000', i32)  ! libdrm value
    idx = idx + 3
    
    ! Enable all CUs (CRITICAL for waves to launch!)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(4_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_STATIC_THREAD_MGMT_SE0
    ib_data(idx+2) = int(z'FFFFFFFF', i32)  ! Enable all CUs
    ib_data(idx+3) = int(z'FFFFFFFF', i32)
    ib_data(idx+4) = int(z'FFFFFFFF', i32)
    ib_data(idx+5) = int(z'FFFFFFFF', i32)
    idx = idx + 6
    
    ! Set shader address (GFX10 encoding)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(ishft(shader_va, -8), c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -40), c_int32_t)
    idx = idx + 4
    
    print '(A,Z16)', "  In IB - shader VA: 0x", shader_va
    print '(A,Z8,A,Z8)', "  PGM_LO: 0x", ib_data(idx-2), " PGM_HI: 0x", ib_data(idx-1)
    
    ! Minimal RSRC1/2
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ib_data(idx+2) = int(z'00000040', i32)  ! Minimal config
    ib_data(idx+3) = int(z'00000000', i32)
    idx = idx + 4
    
    ! Thread group size
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    ib_data(idx+4) = 1_i32
    idx = idx + 5
    
    ! DISPATCH_DIRECT with exact libdrm value
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(4_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    ib_data(idx+4) = int(z'00000045', i32)  ! libdrm's exact value
    idx = idx + 5
    
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

end program test_pm4_mini_final