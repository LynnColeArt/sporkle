program test_pm4_flat_store
  ! Test flat_store_dword instruction
  ! =================================
  
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
  
  print *, "PM4 Flat Store Test"
  print *, "==================="
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [64])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [1024])
  
  ! Clear output
  output_data = 0
  
  ! Build shader - just store a constant using flat addressing
  shader_data = 0
  i = 1
  
  ! Load output address into VGPRs
  ! v_mov_b32 v0, output_va_lo
  shader_data(i) = int(z'7E000280', i32)
  shader_data(i+1) = int(output_buffer%get_va(), i32)
  i = i + 2
  
  ! v_mov_b32 v1, output_va_hi
  shader_data(i) = int(z'7E020280', i32)
  shader_data(i+1) = int(ishft(output_buffer%get_va(), -32), i32)
  i = i + 2
  
  ! v_mov_b32 v2, 0x12345678  ; Value to store
  shader_data(i) = int(z'7E040280', i32)
  shader_data(i+1) = int(z'12345678', i32)
  i = i + 2
  
  ! flat_store_dword v[0:1], v2
  shader_data(i) = int(z'DC700000', i32)
  shader_data(i+1) = int(z'00000200', i32)
  i = i + 2
  
  ! s_waitcnt vmcnt(0) & lgkmcnt(0)
  shader_data(i) = int(z'BF8C0070', i32)
  i = i + 1
  
  ! s_endpgm
  shader_data(i) = int(z'BF810000', i32)
  i = i + 1
  
  print '(A,I0,A)', "Shader: ", i-1, " dwords"
  
  ! Build IB
  i = 1
  
  ! Shader address
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(i+1) = COMPUTE_PGM_LO
  ib_data(i+2) = int(shader_buffer%get_va(), c_int32_t)
  ib_data(i+3) = int(ishft(shader_buffer%get_va(), -32), c_int32_t)
  i = i + 4
  
  ! RSRC1/2
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(i+1) = COMPUTE_PGM_RSRC1
  ib_data(i+2) = 3_i32  ! 4 VGPRs
  ib_data(i+3) = int(z'00000090', i32)
  i = i + 4
  
  ! Workgroup size
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
  ib_data(i+1) = COMPUTE_NUM_THREAD_X
  ib_data(i+2) = 0_i32
  ib_data(i+3) = 0_i32
  ib_data(i+4) = 0_i32
  i = i + 5
  
  ! Dispatch
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
  ib_data(i+1) = 1_i32
  ib_data(i+2) = 1_i32
  ib_data(i+3) = 1_i32
  i = i + 4
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, i-1, [output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "Submit failed!"
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  
  ! Check
  print *, "Output:"
  do i = 1, 4
    print '(A,Z8)', "  ", output_data(i)
  end do
  
  if (output_data(1) == int(z'12345678', i32)) then
    print *, ""
    print *, "🎉 FLAT STORE WORKS!"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
end program test_pm4_flat_store