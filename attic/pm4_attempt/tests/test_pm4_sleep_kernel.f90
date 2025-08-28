program test_pm4_sleep_kernel
  ! PM4 Sleep Kernel Test
  ! =====================
  ! Minimal s_sleep kernel to verify dispatch works
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  use time_utils
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), shader_data(:)
  integer(i32) :: status
  real(f64) :: start_time, end_time, elapsed_ns
  
  print *, "======================================="
  print *, "PM4 Sleep Kernel Test"
  print *, "======================================="
  print *, "Verifying GPU dispatch with s_sleep"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  
  ! Create minimal sleep kernel (from objdump)
  shader_data = 0
  shader_data(1) = int(z'BF8E0064', i32)  ! s_sleep 100
  shader_data(2) = int(z'BF810000', i32)  ! s_endpgm
  
  print *, "Sleep kernel (8 bytes):"
  print '(A,Z8)', "  [0] = 0x", shader_data(1)
  print '(A,Z8)', "  [1] = 0x", shader_data(2)
  
  ! Build PM4 with complete preamble
  call build_sleep_dispatch_ib(ib_data, shader_buffer%get_va())
  
  ! Get start time
  start_time = get_time()
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 100_i32, [&
                                shader_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status:", status
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  
  ! Get end time
  end_time = get_time()
  elapsed_ns = (end_time - start_time) * 1.0e9_f64
  
  print *, ""
  print '(A,F8.3,A)', "✅ Dispatch completed in ", real(elapsed_ns, f64)/1.0e6_f64, " ms"
  
  if (elapsed_ns > 1.0e6_f64) then  ! > 1ms
    print *, "🎉 SUCCESS! Sleep kernel executed (measurable delay)"
    print *, "GPU is executing shaders - dispatch works!"
  else
    print *, "⚠️  Dispatch too fast - sleep might not be executing"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_sleep_dispatch_ib(ib_data, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! Set GRBM_GFX_INDEX to broadcast mode
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
    
    ! No scratch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_TMPRING_SIZE
    ib_data(idx+2) = 0
    idx = idx + 3
    
    ! SH_MEM_CONFIG
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = SH_MEM_CONFIG
    ib_data(idx+2) = 0
    idx = idx + 3
    
    ! Set shader
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(shader_va, c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -32), c_int32_t)
    idx = idx + 4
    
    ! RSRC1/2 - minimal, no VGPRs, no USER_SGPRs
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ib_data(idx+2) = int(z'00000000', i32)  ! 0 VGPRs, 0 SGPRs
    ib_data(idx+3) = int(z'00000000', i32)  ! No USER_SGPRs
    idx = idx + 4
    
    ! Workgroup size
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 0_i32   ! 1 thread
    ib_data(idx+3) = 0_i32   ! Y=1
    ib_data(idx+4) = 0_i32   ! Z=1
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
    
    print '(A,I0)', "Total PM4 dwords: ", idx-1_i32
    
  end subroutine

end program test_pm4_sleep_kernel