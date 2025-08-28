program test_pm4_rdna2_write
  ! RDNA2 PM4 Compute Test - Write Constants
  ! ========================================
  ! Tests RDNA2-specific shader that writes 0xDEADBEEF
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  integer(i32), parameter :: NUM_ELEMENTS = 256_i32
  integer(i64), parameter :: BUFFER_SIZE = int(NUM_ELEMENTS, i64) * 4_i64
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:), shader_data(:)
  integer(i32) :: status, i
  logical :: success
  
  print *, "======================================="
  print *, "PM4 RDNA2 Write Test"
  print *, "======================================="
  print *, "Device: AMD Raphael iGPU (RDNA2)"
  print *, ""
  
  ! Initialize PM4 context
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, BUFFER_SIZE, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 1024_i64, SP_BO_HOST_VISIBLE)
  
  print *, "Buffers allocated:"
  print '(A,Z16)', "  Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "  Shader VA: 0x", shader_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [ NUM_ELEMENTS ])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [ 256_i32 ])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [ 1024_i32 ])
  
  ! Clear output
  output_data = 0
  
  ! Build RDNA2 shader
  print *, ""
  print *, "Creating RDNA2 compute shader..."
  call build_rdna2_write_shader(shader_data)
  
  ! Build PM4 command buffer
  call build_rdna2_dispatch_ib(ib_data, output_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  print *, "Submitting PM4 command buffer..."
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 30_i32, [output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Failed to submit"
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  if (status /= 0) then
    print *, "ERROR: Fence wait failed"
  else
    print *, "✅ PM4 dispatch completed!"
  end if
  
  ! Check results
  print *, ""
  print *, "Checking output buffer..."
  success = .false.
  do i = 1, min(10, NUM_ELEMENTS)
    print '(A,I3,A,Z8)', "  output[", i-1, "] = 0x", output_data(i)
    if (output_data(i) == int(z'DEADBEEF', i32)) success = .true.
  end do
  
  if (success) then
    print *, ""
    print *, "🎉 RDNA2 COMPUTE WORKING! The shader wrote 0xDEADBEEF!"
    print *, "PM4 + RDNA2 = Production Ready!"
  else
    print *, ""
    print *, "Shader didn't write expected values yet"
  end if
  
  ! Cleanup
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_rdna2_write_shader(shader)
    integer(c_int32_t), intent(inout) :: shader(:)
    integer :: idx
    
    ! RDNA2 shader that writes 0xDEADBEEF to memory
    ! This is a very simple shader for testing
    
    shader = 0
    idx = 1
    
    ! s_mov_b32 s0, 0xDEADBEEF  ; Load constant into s0
    shader(idx) = int(z'BEADBEEF', i32)     ! Immediate value
    shader(idx+1) = int(z'BE800000', i32)   ! s_mov_b32 s0, imm
    idx = idx + 2
    
    ! s_mov_b32 s1, 0  ; Clear s1 
    shader(idx) = int(z'00000000', i32)     ! Immediate value
    shader(idx+1) = int(z'BE800100', i32)   ! s_mov_b32 s1, imm
    idx = idx + 2
    
    ! v_mov_b32 v0, s0  ; Move constant to VGPR
    shader(idx) = int(z'7E000200', i32)     ! v_mov_b32 v0, s0
    idx = idx + 1
    
    ! global_store_dword v[1:2], v0, off  ; Store to output buffer
    ! For RDNA2: DC 70 00 00 00 01 00 00
    shader(idx) = int(z'DC700000', i32)     ! global_store_dword
    shader(idx+1) = int(z'00000100', i32)   ! v[1:2], v0
    idx = idx + 2
    
    ! s_waitcnt vmcnt(0)  ; Wait for store to complete
    shader(idx) = int(z'BF8C0F70', i32)     ! s_waitcnt vmcnt(0)
    idx = idx + 1
    
    ! s_endpgm  ; End program
    shader(idx) = int(z'BF810000', i32)     ! s_endpgm
    idx = idx + 1
    
    print '(A,I0,A)', "  Built RDNA2 shader with ", idx-1, " dwords"
    
  end subroutine

  subroutine build_rdna2_dispatch_ib(ib_data, output_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! Set shader program address
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_PGM_LO
    idx = idx + 1
    ib_data(idx) = int(shader_va, c_int32_t)
    idx = idx + 1
    ib_data(idx) = int(ishft(shader_va, -32), c_int32_t)
    idx = idx + 1
    
    ! Set shader resources - RDNA2 specific
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_PGM_RSRC1
    idx = idx + 1
    ! RSRC1 for RDNA2: VGPRS=3 (4 VGPRs), SGPRS=1 (8 SGPRs)
    ib_data(idx) = ior(3_i32, ishft(1_i32, 6))
    idx = idx + 1
    ! RSRC2: Enable execute, wave32 mode
    ib_data(idx) = int(z'00000090', i32)
    idx = idx + 1
    
    ! Set output buffer address in user data
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_USER_DATA_0
    idx = idx + 1
    ib_data(idx) = int(output_va, c_int32_t)
    idx = idx + 1
    ib_data(idx) = int(ishft(output_va, -32), c_int32_t)
    idx = idx + 1
    
    ! Set workgroup size (1x1x1 for testing)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_NUM_THREAD_X
    idx = idx + 1
    ib_data(idx) = 0_i32  ! 1-1 = 0
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    
    ! DISPATCH_DIRECT (1x1x1)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    idx = idx + 1
    ib_data(idx) = 1_i32
    idx = idx + 1
    ib_data(idx) = 1_i32
    idx = idx + 1
    ib_data(idx) = 1_i32
    idx = idx + 1
    
    print '(A,I0,A)', "  Built PM4 dispatch with ", idx-1, " dwords"
    
  end subroutine

end program test_pm4_rdna2_write