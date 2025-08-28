program test_pm4_hsa_kernel
  ! PM4 Test with HSA Kernel Args
  ! =============================
  ! Properly sets up kernel args for HSA ABI
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  use hsaco_loader
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer, kernarg_buffer
  type(sp_fence) :: fence
  type(hsaco_kernel) :: kernel
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:)
  integer(i64), pointer :: kernarg_data(:)
  integer(i32) :: status, i
  logical :: success
  
  print *, "======================================="
  print *, "PM4 HSA Kernel Test"
  print *, "======================================="
  
  ! Load kernel
  kernel = load_hsaco_kernel("kernels/out/kernel.hsaco")
  if (kernel%code_size == 0) then
    print *, "ERROR: Failed to load kernel"
    stop 1
  end if
  
  ! Initialize PM4
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, kernel%code_size, SP_BO_HOST_VISIBLE)
  call kernarg_buffer%init(ctx_ptr, 16_i64, SP_BO_HOST_VISIBLE)  ! Kernel args
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  print *, ""
  print '(A,Z16)', "Output VA:   0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA:   0x", shader_buffer%get_va()
  print '(A,Z16)', "Kernarg VA:  0x", kernarg_buffer%get_va()
  
  ! Upload kernel
  block
    integer(i8), pointer :: src(:), dst(:)
    call c_f_pointer(kernel%code_ptr, src, [kernel%code_size])
    call c_f_pointer(shader_buffer%get_cpu_ptr(), dst, [kernel%code_size])
    dst = src
  end block
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [64])
  call c_f_pointer(kernarg_buffer%get_cpu_ptr(), kernarg_data, [2])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [1024])
  
  ! Clear output
  output_data = 0
  
  ! Set up kernel args - HSA expects pointer as first arg
  kernarg_data(1) = output_buffer%get_va()
  kernarg_data(2) = 0  ! Padding for 64-bit alignment
  
  print *, ""
  print *, "Kernel args:"
  print '(A,Z16)', "  dst pointer: 0x", kernarg_data(1)
  
  ! Build PM4 command buffer
  call build_hsa_dispatch_ib(ib_data, shader_buffer%get_va(), &
                             kernarg_buffer%get_va(), kernel)
  
  ! Submit
  print *, ""
  print *, "Submitting PM4 command buffer..."
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 30_i32, [&
                                output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Failed to submit"
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  print *, "✅ Dispatch completed!"
  
  ! Check results
  print *, ""
  print *, "Output buffer:"
  success = .false.
  do i = 1, 8
    print '(A,I3,A,Z8)', "  [", i-1, "] = 0x", output_data(i)
    if (output_data(i) == int(z'DEADBEEF', i32)) success = .true.
  end do
  
  if (success) then
    print *, ""
    print *, "🎉 SUCCESS! HSA kernel wrote 0xDEADBEEF!"
    print *, ""
    print *, "PM4 + RDNA2 + HSA = WORKING! 🚀"
  else
    print *, ""
    print *, "No write yet. May need different register setup."
  end if
  
  ! Cleanup
  call free_hsaco_kernel(kernel)
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_hsa_dispatch_ib(ib_data, shader_va, kernarg_va, kernel)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: shader_va, kernarg_va
    type(hsaco_kernel), intent(in) :: kernel
    integer(i32) :: idx
    
    idx = 1
    
    ! Set shader program address
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(shader_va, c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -32), c_int32_t)
    idx = idx + 4
    
    ! Set shader resources
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ib_data(idx+2) = kernel%rsrc1
    ib_data(idx+3) = kernel%rsrc2
    idx = idx + 4
    
    ! HSA ABI: Set kernarg address in USER_DATA_0/1
    ! The shader expects kernel args pointer in s[4:5]
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_USER_DATA_0
    ib_data(idx+2) = int(kernarg_va, c_int32_t)
    ib_data(idx+3) = int(ishft(kernarg_va, -32), c_int32_t)
    idx = idx + 4
    
    ! Set workgroup size
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 63_i32  ! 64-1
    ib_data(idx+3) = 0_i32
    ib_data(idx+4) = 0_i32
    idx = idx + 5
    
    ! DISPATCH_DIRECT
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    idx = idx + 4
    
    print '(A,I0,A)', "Built HSA dispatch with ", idx-1, " dwords"
    
  end subroutine

end program test_pm4_hsa_kernel