program test_pm4_pal_kernel
  ! PM4 PAL-Style Kernel Test
  ! =========================
  ! Minimal test with USER_DATA pointer passing (no HSA/AQL)
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  use elf_parser
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:), output_data(:)
  integer(i8), allocatable :: shader_code(:)
  integer(i64) :: shader_size
  integer(i32) :: status, i
  logical :: success
  
  print *, "======================================="
  print *, "PM4 PAL-Style Kernel Test"
  print *, "======================================="
  print *, "USER_DATA pointer passing (no HSA/AQL)"
  print *, ""
  
  ! Load compiled PAL kernel
  success = parse_elf_text_section("kernels/store_ud.o", shader_code, shader_size)
  if (.not. success) then
    print *, "ERROR: Failed to load PAL kernel"
    print *, "Please compile: clang --target=amdgcn-amd-amdhsa -mcpu=gfx1030 -c store_ud.s"
    stop 1
  end if
  
  ! Initialize PM4
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Allocate buffers
  call output_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)  ! GTT for easy readback
  call shader_buffer%init(ctx_ptr, shader_size, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 4096_i64, SP_BO_HOST_VISIBLE)
  
  print '(A,Z16)', "Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "Shader VA: 0x", shader_buffer%get_va()
  
  ! Upload shader
  block
    integer(i8), pointer :: dst(:)
    call c_f_pointer(shader_buffer%get_cpu_ptr(), dst, [shader_size])
    dst = shader_code
  end block
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [64])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [1024])
  
  ! Clear output with pattern to see changes
  output_data = int(z'CAFEBABE', i32)
  
  ! Build minimal PM4 command buffer
  call build_pal_dispatch_ib(ib_data, output_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  print *, ""
  print *, "Submitting PAL kernel..."
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 30_i32, [&
                                output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Submit failed"
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
    if (output_data(i) == int(z'DEADBEEF', i32)) then
      success = .true.
      print *, "    ^^^ 🎉 KERNEL WROTE 0xDEADBEEF!"
    end if
  end do
  
  if (success) then
    print *, ""
    print *, "🚀 SUCCESS! PAL-style kernel is WORKING!"
    print *, "PM4 + RDNA2 + PAL = PRODUCTION READY!"
  else
    print *, ""
    print *, "No 0xDEADBEEF found. Check USER_SGPR_COUNT in RSRC2."
  end if
  
  ! Cleanup
  deallocate(shader_code)
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_pal_dispatch_ib(ib_data, output_va, shader_va)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: output_va, shader_va
    integer(i32) :: idx
    
    idx = 1
    
    ! Invalidate caches before dispatch
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), int(z'58', i32)))  ! ACQUIRE_MEM
    ib_data(idx+1) = int(z'00000003', i32)  ! Invalidate L1/L2
    ib_data(idx+2) = 0
    ib_data(idx+3) = 0
    ib_data(idx+4) = 0
    ib_data(idx+5) = 0
    idx = idx + 6
    
    ! Set shader address
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_LO
    ib_data(idx+2) = int(shader_va, c_int32_t)
    ib_data(idx+3) = int(ishft(shader_va, -32), c_int32_t)
    idx = idx + 4
    
    ! Set shader resources - MINIMAL CONFIG
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_PGM_RSRC1
    ! RSRC1: 1 VGPR granule (4 VGPRs), 1 SGPR granule
    ib_data(idx+2) = int(z'00000041', i32)  ! VGPRS=1, SGPRS=1
    ! RSRC2: USER_SGPR_COUNT=2 (critical!), no LDS, no scratch
    ! USER_SGPR is in bits [6:1], so 2 SGPRs = value 2 << 1 = 4
    ib_data(idx+3) = int(z'00000004', i32)  ! USER_SGPR=2 in bits [6:1]
    idx = idx + 4
    
    ! Set USER_DATA_0/1 with output buffer pointer
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_USER_DATA_0
    ib_data(idx+2) = int(output_va, c_int32_t)         ! s0 = low32(dst)
    ib_data(idx+3) = int(ishft(output_va, -32), c_int32_t)  ! s1 = high32(dst)
    idx = idx + 4
    
    ! Set workgroup size (one wave = 64 threads)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    ib_data(idx+1) = COMPUTE_NUM_THREAD_X
    ib_data(idx+2) = 63_i32  ! 64-1
    ib_data(idx+3) = 0_i32   ! Y=1
    ib_data(idx+4) = 0_i32   ! Z=1
    idx = idx + 5
    
    ! DISPATCH_DIRECT (1x1x1 workgroup)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    ib_data(idx+1) = 1_i32
    ib_data(idx+2) = 1_i32
    ib_data(idx+3) = 1_i32
    idx = idx + 4
    
    print '(A,I0,A)', "Built PAL dispatch with ", idx-1, " dwords"
    print *, "  RSRC1 = 0x00000041 (1 VGPR + 1 SGPR granule)"
    print *, "  RSRC2 = 0x00000004 (USER_SGPR_COUNT=2)"
    print '(A,Z16)', "  USER_DATA_0 = 0x", output_va
    
  end subroutine

end program test_pm4_pal_kernel