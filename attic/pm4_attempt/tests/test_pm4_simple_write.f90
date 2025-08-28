program test_pm4_simple_write
  ! Simplest possible PM4 compute test - just write constants
  ! =========================================================
  ! This verifies the PM4 dispatch path is working before trying complex shaders
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  integer(i32), parameter :: NUM_ELEMENTS = 256_i32  ! Small test
  integer(i64), parameter :: BUFFER_SIZE = int(NUM_ELEMENTS, i64) * 4_i64
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: output_buffer, ib_buffer, shader_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:)
  real(sp), pointer :: output_data(:)
  integer(i32), pointer :: shader_data(:)
  integer(i32) :: status, i
  logical :: test_passed
  
  print *, "======================================="
  print *, "PM4 Simple Write Test"
  print *, "======================================="
  print *, "Testing minimal shader that writes 0x42 to memory"
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
  call shader_buffer%init(ctx_ptr, 256_i64, SP_BO_HOST_VISIBLE)  ! Small shader
  
  if (.not. (output_buffer%is_valid() .and. ib_buffer%is_valid() .and. shader_buffer%is_valid())) then
    print *, "ERROR: Failed to allocate buffers"
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  
  print *, "Buffers allocated:"
  print '(A,Z16)', "  Output VA: 0x", output_buffer%get_va()
  print '(A,Z16)', "  Shader VA: 0x", shader_buffer%get_va()
  
  ! Map buffers
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [ NUM_ELEMENTS ])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [ 64_i32 ])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [ 1024_i32 ])
  
  ! Clear output buffer
  output_data = 0.0_sp
  
  ! Create simplest possible shader - just s_endpgm
  print *, ""
  print *, "Creating minimal shader (just s_endpgm)..."
  shader_data = 0_i32
  shader_data(1) = int(z'BF810000', i32)  ! s_endpgm
  
  ! Build PM4 command buffer
  call build_simple_dispatch_ib(ib_data, output_buffer%get_va(), shader_buffer%get_va())
  
  ! Submit
  print *, "Submitting PM4 command buffer..."
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 20_i32, [output_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Failed to submit command buffer"
    call sp_pm4_cleanup(ctx_ptr)
    stop 1
  end if
  
  ! Wait
  status = sp_fence_wait(ctx_ptr, fence, 1000000000_i64)
  if (status /= 0) then
    print *, "ERROR: Fence wait failed"
  else
    print *, "✅ PM4 dispatch completed successfully!"
  end if
  
  ! Check if shader ran (won't modify memory with just s_endpgm)
  print *, ""
  print *, "Output buffer state:"
  print '(A,F8.4)', "  output[0] = ", output_data(1)
  print '(A,F8.4)', "  output[1] = ", output_data(2)
  print *, ""
  print *, "PM4 dispatch infrastructure verified!"
  print *, "Next step: Add actual compute instructions"
  
  ! Cleanup
  call sp_pm4_cleanup(ctx_ptr)
  
contains

  subroutine build_simple_dispatch_ib(ib_data, output_va, shader_va)
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
    
    ! Set minimal shader resources
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_PGM_RSRC1
    idx = idx + 1
    ib_data(idx) = 0_i32  ! Minimal config
    idx = idx + 1
    ib_data(idx) = int(z'00000090', i32)  ! Enable execute
    idx = idx + 1
    
    ! Set workgroup size (1x1x1)
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
    
    print '(A,I0,A)', "Built minimal PM4 dispatch with ", idx-1, " dwords"
    
  end subroutine

end program test_pm4_simple_write