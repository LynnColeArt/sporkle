program test_pm4_rdna2_minimal
  ! Minimal RDNA2 PM4 Test
  ! ======================
  ! Absolutely minimal shader to verify compute execution
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer, args_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:), shader_data(:)
  integer(i64), pointer :: args_data(:)
  integer(i32) :: status, i
  
  print *, "======================================="
  print *, "PM4 RDNA2 Minimal Test"
  print *, "======================================="
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call args_buffer%init(ctx_ptr, 16_i64, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  print '(A,Z16)', "Args VA:   0x", args_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [64])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [64])
  call c_f_pointer(args_buffer%get_cpu_ptr(), args_data, [2])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [1024])
  
  ! Clear output
  output_data = 0
  
  ! Set kernel args (output buffer address)
  args_data(1) = output_buffer%get_va()
  args_data(2) = 0
  
  ! Create minimal RDNA2 shader
  ! Just write thread ID to memory
  shader_data = 0
  i = 1
  
  ! s_load_dwordx2 s[0:1], s[4:5], 0x0  ; Load output addr from kernel args
  shader_data(i) = int(z'C0060002', i32)   ! SMEM load instruction
  shader_data(i+1) = int(z'00000000', i32) ! offset 0
  i = i + 2
  
  ! s_waitcnt lgkmcnt(0)  ; Wait for load
  shader_data(i) = int(z'BF8C007F', i32)
  i = i + 1
  
  ! v_mov_b32 v1, 0x42  ; Move constant to v1
  shader_data(i) = int(z'7E020280', i32)  ! v_mov_b32 v1, 0x42
  shader_data(i+1) = int(z'00000042', i32)
  i = i + 2
  
  ! v_mov_b32 v2, s0  ; Move address low to v2
  shader_data(i) = int(z'7E040200', i32)  ! v_mov_b32 v2, s0
  i = i + 1
  
  ! v_mov_b32 v3, s1  ; Move address high to v3
  shader_data(i) = int(z'7E060201', i32)  ! v_mov_b32 v3, s1
  i = i + 1
  
  ! global_store_dword v[2:3], v1, off  ; Store constant
  shader_data(i) = int(z'DC700000', i32)
  shader_data(i+1) = int(z'00000102', i32)
  i = i + 2
  
  ! s_waitcnt vmcnt(0)
  shader_data(i) = int(z'BF8C0F70', i32)
  i = i + 1
  
  ! s_endpgm
  shader_data(i) = int(z'BF810000', i32)
  i = i + 1
  
  print '(A,I0,A)', "Built shader with ", i-1, " dwords"
  
  ! Build IB
  i = 1
  
  ! Set shader address
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(i+1) = COMPUTE_PGM_LO
  ib_data(i+2) = int(shader_buffer%get_va(), c_int32_t)
  ib_data(i+3) = int(ishft(shader_buffer%get_va(), -32), c_int32_t)
  i = i + 4
  
  ! Set RSRC1/2
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(i+1) = COMPUTE_PGM_RSRC1
  ib_data(i+2) = ior(4_i32, ishft(1_i32, 6))  ! 5 VGPRs, 8 SGPRs
  ib_data(i+3) = int(z'00000092', i32)  ! USER_SGPR + TGID_X
  i = i + 4
  
  ! Set kernel args pointer
  ib_data(i) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(i+1) = COMPUTE_USER_DATA_0
  ib_data(i+2) = int(args_buffer%get_va(), c_int32_t)
  ib_data(i+3) = int(ishft(args_buffer%get_va(), -32), c_int32_t)
  i = i + 4
  
  ! Set workgroup size
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
  
  print '(A,I0,A)', "Built IB with ", i-1, " dwords"
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, i-1, [output_buffer%bo_ptr], fence)
  if (status /= 0) stop 1
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  
  ! Check
  print *, ""
  print *, "Output values:"
  do i = 1, 8
    print '(A,I0,A,Z8)', "  [", i-1, "] = 0x", output_data(i)
  end do
  
  if (output_data(1) == int(z'42', i32)) then
    print *, ""
    print *, "🎉 SUCCESS! RDNA2 shader executed and wrote 0x42!"
  end if
  
  call sp_pm4_cleanup(ctx_ptr)
  
end program test_pm4_rdna2_minimal