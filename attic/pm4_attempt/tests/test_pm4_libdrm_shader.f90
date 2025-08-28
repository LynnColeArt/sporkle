program test_pm4_libdrm_shader
  ! PM4 LibDRM Shader Test
  ! ======================
  ! Uses libdrm's exact shader binary and initialization sequence
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: ib_buffer, data_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), data(:)
  integer(i32) :: status, i, poll_count, idx
  logical :: success
  
  ! LibDRM's shader binary that writes 42u
  integer(i32), parameter :: shader_bin(15) = [ &
    int(z'800082BE', i32), int(z'02FF08BF', i32), int(z'7F969800', i32), int(z'040085BF', i32), &
    int(z'02810281', i32), int(z'02FF08BF', i32), int(z'7F969800', i32), int(z'FCFF84BF', i32), &
    int(z'FF0083BE', i32), int(z'00F00000', i32), int(z'C10082BE', i32), int(z'AA02007E', i32), &
    int(z'000070E0', i32), int(z'00000080', i32), int(z'000081BF', i32) &
  ]
  
  integer(i32), parameter :: CODE_OFFSET = 512  ! dwords offset
  integer(i32), parameter :: DATA_OFFSET = 1024 ! dwords offset
  
  print *, "======================================="
  print *, "PM4 LibDRM Shader Test"
  print *, "======================================="
  print *, "Using libdrm's exact shader and init sequence"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate large IB buffer like libdrm (8192 bytes)
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  
  ! Allocate data buffer for results
  call data_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  ! Map buffers
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  call c_f_pointer(data_buffer%get_cpu_ptr(), data, [1024])
  
  ! Clear data buffer
  data = 0
  
  ! Copy shader to CODE_OFFSET in IB (like libdrm)
  do i = 1, 15
    ib_data(CODE_OFFSET + i) = shader_bin(i)
  end do
  
  ! Build PM4 commands at start of IB
  idx = 1
  
  ! Dispatch minimal init config and verify it's executed (libdrm comment)
  ! CONTEXT_CONTROL - exact libdrm values
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_CONTEXT_CONTROL))
  ib_data(idx+1) = int(z'80000000', i32)
  ib_data(idx+2) = int(z'80000000', i32)
  idx = idx + 3
  
  ! CLEAR_STATE - exact libdrm
  ib_data(idx) = ior(ishft(3_i32, 30), PM4_CLEAR_STATE)
  ib_data(idx+1) = int(z'80000000', i32)
  idx = idx + 2
  
  ! Program compute regs (libdrm comment)
  ! COMPUTE_PGM_LO/HI
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_LO
  ib_data(idx+2) = int(ishft(ib_buffer%get_va() + CODE_OFFSET * 4, -8), c_int32_t)
  ib_data(idx+3) = int(ishft(ib_buffer%get_va() + CODE_OFFSET * 4, -40), c_int32_t)
  idx = idx + 4
  
  print '(A,Z16)', "Shader VA: 0x", ib_buffer%get_va() + CODE_OFFSET * 4
  print '(A,Z8,A,Z8)', "PGM_LO: 0x", ib_data(idx-2), " PGM_HI: 0x", ib_data(idx-1)
  
  ! COMPUTE_PGM_RSRC1/2 - exact libdrm values with comments
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_RSRC1
  ib_data(idx+2) = int(z'002C0040', i32)  ! VGPRS=0, SGPRS=1, FLOAT_MODE=192, DX10_CLAMP=1
  ib_data(idx+3) = int(z'00000010', i32)  ! USER_SGPR=8
  idx = idx + 4
  
  ! COMPUTE_TMPRING_SIZE - libdrm value
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_TMPRING_SIZE
  ib_data(idx+2) = int(z'00000100', i32)  ! WAVES=256
  idx = idx + 3
  
  ! COMPUTE_USER_DATA_0/1 - pointer to data
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_USER_DATA_0
  ib_data(idx+2) = int(data_buffer%get_va(), c_int32_t)
  ib_data(idx+3) = int(ishft(data_buffer%get_va(), -32), c_int32_t)
  idx = idx + 4
  
  ! COMPUTE_RESOURCE_LIMITS
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_RESOURCE_LIMITS
  ib_data(idx+2) = 0
  idx = idx + 3
  
  ! COMPUTE_NUM_THREAD_X/Y/Z
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_NUM_THREAD_X
  ib_data(idx+2) = 1
  ib_data(idx+3) = 1
  ib_data(idx+4) = 1
  idx = idx + 5
  
  ! Dispatch (libdrm comment)
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
  ib_data(idx+1) = 1
  ib_data(idx+2) = 1
  ib_data(idx+3) = 1
  ib_data(idx+4) = int(z'00000045', i32)  ! DISPATCH DIRECT field (libdrm comment)
  idx = idx + 4
  
  ! Pad with NOPs to align (like libdrm)
  do while (mod(idx-1, 8) /= 0)
    ib_data(idx) = int(z'FFFF1000', i32)  ! type3 nop packet
    idx = idx + 1
  end do
  
  print '(A,I0)', "Total PM4 dwords: ", idx-1
  print *, ""
  print *, "Submitting exact libdrm sequence..."
  
  ! Submit with data buffer in BO list
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, idx-1, [&
                                data_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status", status
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Fence signaled"
  
  ! Check if shader wrote 42 (0x2A)
  success = .false.
  do poll_count = 1, 100
    if (data(1) == 42) then
      success = .true.
      exit
    end if
    call execute_command_line("sleep 0.001", wait=.true.)
  end do
  
  print *, ""
  if (success) then
    print *, "🎉 SUCCESS! Shader wrote 42 - waves executed!"
    print *, "LibDRM's initialization sequence works!"
  else
    print *, "❌ No write detected"
    print '(A,Z8)', "data[0] = 0x", data(1)
  end if
  
  ! Dump first few dwords for debug
  print *, ""
  print *, "First 8 data dwords:"
  do i = 1, 8
    print '(A,I0,A,Z8)', "  data[", i-1, "] = 0x", data(i)
  end do
  
  call sp_pm4_cleanup(ctx_ptr)

end program test_pm4_libdrm_shader