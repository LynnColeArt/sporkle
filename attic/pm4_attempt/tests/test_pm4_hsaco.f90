program test_pm4_hsaco
  ! PM4 Test with Compiled HSACO Kernel
  ! ====================================
  ! Uses real RDNA2 compiled kernel from RGA/clang
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  use hsaco_loader
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  type(hsaco_kernel) :: kernel
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:)
  integer(i32) :: status, i
  logical :: success
  
  print *, "======================================="
  print *, "PM4 HSACO Kernel Test"
  print *, "======================================="
  
  ! First check if we have a compiled kernel
  inquire(file="kernels/out/kernel.hsaco", exist=success)
  if (.not. success) then
    print *, ""
    print *, "No compiled kernel found!"
    print *, "Please run:"
    print *, "  ./tools/compile_kernel.sh kernels/poke.cl"
    print *, ""
    print *, "If RGA is not installed, you can get it from:"
    print *, "  https://gpuopen.com/rga/"
    print *, ""
    print *, "Or use clang with:"
    print *, "  ./tools/compile_kernel.sh --backend clang kernels/poke.cl"
    stop 1
  end if
  
  ! Load kernel
  print *, "Loading compiled kernel..."
  kernel = load_hsaco_kernel("kernels/out/kernel.hsaco")
  if (kernel%code_size == 0) then
    print *, "ERROR: Failed to load kernel"
    stop 1
  end if
  
  ! Initialize PM4
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)
  call shader_buffer%init(ctx_ptr, kernel%code_size, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  print *, ""
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Upload kernel code to GPU
  block
    integer(i8), pointer :: src(:), dst(:)
    integer :: i
    call c_f_pointer(kernel%code_ptr, src, [kernel%code_size])
    call c_f_pointer(shader_buffer%get_cpu_ptr(), dst, [kernel%code_size])
    do i = 1, int(kernel%code_size)
      dst(i) = src(i)
    end do
  end block
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [1024])
  
  ! Clear output
  output_data = 0
  
  ! Build PM4 command buffer
  call build_hsaco_dispatch_ib(ib_data, output_buffer%get_va(), &
                               shader_buffer%get_va(), kernel)
  
  ! Submit
  print *, ""
  print *, "Submitting PM4 command buffer..."
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 30_i32, [&
                                output_buffer%bo_ptr], fence)
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
  do i = 1, 8
    print '(A,I3,A,Z8)', "  output[", i-1, "] = 0x", output_data(i)
    if (output_data(i) == int(z'DEADBEEF', i32)) success = .true.
  end do
  
  if (success) then
    print *, ""
    print *, "🎉 SUCCESS! RDNA2 kernel executed!"
    print *, "The compiled kernel wrote 0xDEADBEEF!"
    print *, ""
    print *, "PM4 + RDNA2 = PRODUCTION READY! 🚀"
  else
    print *, ""
    print *, "Kernel didn't write expected value"
    print *, "This could mean:"
    print *, "  - Need to adjust kernel args passing"
    print *, "  - Need PAL ABI instead of HSA ABI"
  end if
  
  ! Cleanup
  call free_hsaco_kernel(kernel)
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_hsaco_dispatch_ib(ib_data, output_va, shader_va, kernel)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, shader_va
    type(hsaco_kernel), intent(in) :: kernel
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
    
    ! Set shader resources from metadata
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_PGM_RSRC1
    idx = idx + 1
    ib_data(idx) = kernel%rsrc1
    idx = idx + 1
    ib_data(idx) = kernel%rsrc2
    idx = idx + 1
    
    ! Set kernel argument (output buffer pointer)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_USER_DATA_0
    idx = idx + 1
    ib_data(idx) = int(output_va, c_int32_t)
    idx = idx + 1
    ib_data(idx) = int(ishft(output_va, -32), c_int32_t)
    idx = idx + 1
    
    ! Set workgroup size (64 threads = 1 wave on RDNA2)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_NUM_THREAD_X
    idx = idx + 1
    ib_data(idx) = 63_i32  ! 64-1
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    
    ! DISPATCH_DIRECT (1x1x1 workgroup)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    idx = idx + 1
    ib_data(idx) = 1_i32
    idx = idx + 1
    ib_data(idx) = 1_i32
    idx = idx + 1
    ib_data(idx) = 1_i32
    idx = idx + 1
    
    print '(A,I0,A)', "Built PM4 dispatch with ", idx-1, " dwords"
    print '(A,Z8)', "  Using RSRC1: 0x", kernel%rsrc1
    print '(A,Z8)', "  Using RSRC2: 0x", kernel%rsrc2
    
  end subroutine

end program test_pm4_hsaco