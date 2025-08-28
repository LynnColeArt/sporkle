program test_pm4_libdrm_swapped
  ! PM4 LibDRM Swapped Shader Test
  ! ==============================
  ! Uses libdrm's shader with proper byte swapping
  
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
  
  ! LibDRM's shader binary with SWAP_32 applied (little endian for GPU)
  integer(i32), parameter :: shader_bin(15) = [ &
    int(z'BE8200B0', i32), int(z'BF08FF02', i32), int(z'0098967F', i32), int(z'BF850004', i32), &
    int(z'81028102', i32), int(z'BF08FF02', i32), int(z'0098967F', i32), int(z'BF84FFFC', i32), &
    int(z'BE8300FF', i32), int(z'0000F000', i32), int(z'BE8200C1', i32), int(z'7E0002AA', i32), &
    int(z'E0700000', i32), int(z'80000000', i32), int(z'BF810000', i32) &
  ]
  
  integer(i32), parameter :: CODE_OFFSET = 512  ! dwords offset
  integer(i32), parameter :: DATA_OFFSET = 1024 ! dwords offset
  
  print *, "======================================="
  print *, "PM4 LibDRM Swapped Shader Test"
  print *, "======================================="
  print *, "Using byte-swapped shader binary"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call ib_buffer%init(ctx_ptr, 8192_i64, SP_BO_HOST_VISIBLE)
  call data_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  ! Map buffers
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [2048])
  call c_f_pointer(data_buffer%get_cpu_ptr(), data, [1024])
  
  ! Clear buffers
  ib_data = 0
  data = 0
  
  ! Copy swapped shader to CODE_OFFSET
  do i = 1, 15
    ib_data(CODE_OFFSET + i) = shader_bin(i)
  end do
  
  print *, "Shader instructions (swapped):"
  do i = 1, 15
    if (mod(i-1, 4) == 0) write(*, '(A,I2,A)', advance='no') "  [", CODE_OFFSET+i-1, "] "
    write(*, '(Z8,A)', advance='no') ib_data(CODE_OFFSET + i), " "
    if (mod(i, 4) == 0) write(*, *)
  end do
  write(*, *)
  
  ! Build PM4 commands
  idx = 1
  
  ! CONTEXT_CONTROL
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_CONTEXT_CONTROL))
  ib_data(idx+1) = int(z'80000000', i32)
  ib_data(idx+2) = int(z'80000000', i32)
  idx = idx + 3
  
  ! CLEAR_STATE
  ib_data(idx) = ior(ishft(3_i32, 30), PM4_CLEAR_STATE)
  ib_data(idx+1) = int(z'80000000', i32)
  idx = idx + 2
  
  ! COMPUTE_PGM_LO/HI
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_LO
  ib_data(idx+2) = int(ishft(ib_buffer%get_va() + CODE_OFFSET * 4, -8), c_int32_t)
  ib_data(idx+3) = int(ishft(ib_buffer%get_va() + CODE_OFFSET * 4, -40), c_int32_t)
  idx = idx + 4
  
  ! COMPUTE_PGM_RSRC1/2
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_RSRC1
  ib_data(idx+2) = int(z'002C0040', i32)
  ib_data(idx+3) = int(z'00000010', i32)
  idx = idx + 4
  
  ! COMPUTE_TMPRING_SIZE
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_TMPRING_SIZE
  ib_data(idx+2) = int(z'00000100', i32)
  idx = idx + 3
  
  ! COMPUTE_USER_DATA_0/1
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
  
  ! DISPATCH_DIRECT
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
  ib_data(idx+1) = 1
  ib_data(idx+2) = 1
  ib_data(idx+3) = 1
  ib_data(idx+4) = int(z'00000045', i32)
  idx = idx + 4
  
  ! Pad with NOPs
  do while (mod(idx-1, 8) /= 0)
    ib_data(idx) = int(z'FFFF1000', i32)
    idx = idx + 1
  end do
  
  print *, ""
  print '(A,Z16)', "Shader VA: 0x", ib_buffer%get_va() + CODE_OFFSET * 4
  print '(A,I0)', "Total PM4 dwords: ", idx-1
  print *, "Submitting with swapped shader..."
  
  ! Submit
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, idx-1, [&
                                data_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed with status", status
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Fence signaled"
  
  ! Check for write
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
    print *, "🎉 SUCCESS! Shader wrote 42 - GCN shader works on RDNA2?!"
  else
    print *, "❌ No write detected"
    print '(A,Z8,A,I0)', "data[0] = 0x", data(1), " (", data(1), ")"
  end if
  
  ! Dump results
  print *, ""
  print *, "First 8 data dwords:"
  do i = 1, 8
    print '(A,I0,A,Z8)', "  data[", i-1, "] = 0x", data(i)
  end do
  
  call sp_pm4_cleanup(ctx_ptr)

end program test_pm4_libdrm_swapped