program test_pm4_vector_add_native
  ! Native PM4 Vector Add with Real Compute Shader
  ! ==============================================
  ! This tests actual compute shader execution via PM4 DISPATCH_DIRECT
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  use sporkle_amdgpu_shader_binary
  implicit none
  
  ! Test configuration
  integer(i32), parameter :: NUM_ELEMENTS = 1024_i32 * 1024_i32  ! 1M elements
  integer(i64), parameter :: ELEMENT_SIZE = 4_i64  ! sizeof(float)
  integer(i64), parameter :: BUFFER_SIZE = int(NUM_ELEMENTS, i64) * ELEMENT_SIZE
  
  ! PM4 constants are imported from pm4_submit module
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: input_a_buffer, input_b_buffer, output_buffer
  type(gpu_buffer) :: ib_buffer, timer_buffer, shader_buffer
  real(sp), pointer :: input_a_data(:), input_b_data(:), output_data(:)
  integer(i64), pointer :: timer_data(:)
  integer(c_int32_t), pointer :: ib_data(:)
  integer(i32), pointer :: shader_data(:)
  integer(i32) :: status, i
  type(sp_fence) :: fence
  real(sp) :: expected, actual, max_diff
  logical :: test_passed
  
  print *, "======================================="
  print *, "PM4 Native Vector Add Compute Test"
  print *, "======================================="
  print '(A,I0,A)', "Testing ", NUM_ELEMENTS, " elements"
  print *, ""
  
  ! Initialize PM4 context
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) then
    print *, "ERROR: Failed to initialize PM4 context"
    stop 1
  end if
  
  ! Allocate buffers
  print *, "Allocating GPU buffers..."
  call input_a_buffer%init(ctx_ptr, BUFFER_SIZE, SP_BO_HOST_VISIBLE)
  call input_b_buffer%init(ctx_ptr, BUFFER_SIZE, SP_BO_HOST_VISIBLE)  
  call output_buffer%init(ctx_ptr, BUFFER_SIZE, SP_BO_HOST_VISIBLE)
  call ib_buffer%init(ctx_ptr, 1024_i64 * 4_i64, SP_BO_HOST_VISIBLE)  ! IB buffer
  call timer_buffer%init(ctx_ptr, 16_i64, SP_BO_HOST_VISIBLE)  ! 2 timestamps
  call shader_buffer%init(ctx_ptr, 1024_i64 * 4_i64, SP_BO_HOST_VISIBLE)  ! Shader binary
  
  ! Map buffers for CPU access
  call c_f_pointer(input_a_buffer%get_cpu_ptr(), input_a_data, [ NUM_ELEMENTS ])
  call c_f_pointer(input_b_buffer%get_cpu_ptr(), input_b_data, [ NUM_ELEMENTS ])
  call c_f_pointer(output_buffer%get_cpu_ptr(), output_data, [ NUM_ELEMENTS ])
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [ 1024_i32 ])
  call c_f_pointer(timer_buffer%get_cpu_ptr(), timer_data, [ 2_i32 ])
  call c_f_pointer(shader_buffer%get_cpu_ptr(), shader_data, [ 1024_i32 ])
  
  print *, "✅ Buffers allocated successfully:"
  print '(A,Z16)', "  Input A VA:  0x", input_a_buffer%get_va()
  print '(A,Z16)', "  Input B VA:  0x", input_b_buffer%get_va() 
  print '(A,Z16)', "  Output VA:   0x", output_buffer%get_va()
  print '(A,Z16)', "  Shader VA:   0x", shader_buffer%get_va()
  print '(A,Z16)', "  Timer VA:    0x", timer_buffer%get_va()
  print *, ""
  
  ! Initialize test data
  print *, "Initializing test data..."
  do i = 1, NUM_ELEMENTS
    input_a_data(i) = real(i, sp)
    input_b_data(i) = real(i * 2, sp)
    output_data(i) = 0.0_sp
  end do
  
  ! Upload real GCN vector add shader 
  print *, "Uploading real GCN vector add shader..."
  call upload_gcn_vector_add_shader(shader_data)
  
  ! Build PM4 command buffer with actual compute dispatch
  print *, "Building PM4 command buffer with compute dispatch..."
  call build_vector_add_ib(ib_data, &
                          input_a_buffer%get_va(), &
                          input_b_buffer%get_va(), &
                          output_buffer%get_va(), &
                          shader_buffer%get_va(), &
                          timer_buffer%get_va(), &
                          NUM_ELEMENTS)
  
  ! Submit and execute
  print *, "Submitting PM4 command buffer..."
  timer_data(1) = 0_i64
  timer_data(2) = 0_i64
  
  status = sp_submit_ib_with_bos(ctx_ptr, ib_buffer%bo_ptr, 50_i32, [&
                                timer_buffer%bo_ptr], fence)
  if (status /= 0) then
    print *, "ERROR: Failed to submit PM4 command buffer"
    stop 1
  end if
  
  ! Wait for completion
  print *, "Waiting for GPU completion..."
  status = sp_fence_wait(ctx_ptr, fence, 5000000000_i64)  ! 5 second timeout
  if (status /= 0) then
    print *, "ERROR: GPU execution timeout or failure"
    stop 1
  end if
  
  ! Check GPU timestamps
  print '(A,Z16,A,Z16)', "GPU timestamps: T0=0x", timer_data(1), " T1=0x", timer_data(2)
  
  if (timer_data(1) > 0_i64 .and. timer_data(2) > timer_data(1)) then
    print *, "✅ GPU compute shader executed successfully!"
  else
    print *, "⚠️  GPU timestamps not working, but compute may have run"
  end if
  
  ! Verify results
  print *, ""
  print *, "Verifying computation results..."
  test_passed = .true.
  max_diff = 0.0_sp
  
  do i = 1, min(NUM_ELEMENTS, 1000_i32)  ! Check first 1000 elements
    expected = input_a_data(i) + input_b_data(i)
    actual = output_data(i)
    max_diff = max(max_diff, abs(actual - expected))
    
    if (abs(actual - expected) > 1.0e-5_sp) then
      if (test_passed) then
        print '(A,I0,A,F8.2,A,F8.2)', "❌ First mismatch at element ", i, &
               ": expected ", expected, ", got ", actual
      end if
      test_passed = .false.
    end if
  end do
  
  if (test_passed) then
    print *, "✅ Vector add computation SUCCESSFUL!"
    print '(A,E10.3)', "   Maximum difference: ", max_diff
    print *, ""
    print *, "🎉 NATIVE PM4 COMPUTE WORKING!"
  else
    print *, "❌ Vector add computation FAILED!"
    print '(A,E10.3)', "   Maximum difference: ", max_diff
  end if
  
  ! Cleanup
  call sp_pm4_cleanup(ctx_ptr)
  print *, "Test complete!"
  
contains

  ! Upload real GCN vector add shader machine code
  subroutine upload_gcn_vector_add_shader(shader)
    integer(i32), intent(inout) :: shader(:)
    integer :: i
    
    ! Copy the real GCN machine code from our shader binary module
    print '(A,I0,A)', "  Copying ", vector_add_shader_size, " bytes of GCN machine code"
    print '(A,I0,A)', "  SGPRs: ", vector_add_num_sgprs, " VGPRs: ", vector_add_num_vgprs
    
    ! Zero out shader buffer first
    shader = 0_i32
    
    ! Copy the machine code (28 dwords)
    do i = 1, size(vector_add_shader_data)
      shader(i) = vector_add_shader_data(i)
    end do
    
  end subroutine upload_gcn_vector_add_shader
  
  ! Build PM4 command buffer with real compute dispatch
  subroutine build_vector_add_ib(ib_data, input_a_va, input_b_va, output_va, shader_va, timer_va, num_elements)
    integer(c_int32_t), intent(inout) :: ib_data(:)
    integer(i64), intent(in) :: input_a_va, input_b_va, output_va, shader_va, timer_va
    integer(i32), intent(in) :: num_elements
    integer(i32) :: idx
    
    ! Use PM4 constants from module - no need to redefine
    
    idx = 1
    
    ! Start timestamp (T0)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_RELEASE_MEM))
    idx = idx + 1
    ib_data(idx) = ior(ior(CS_DONE, ishft(EVENT_INDEX_EOP, 8)), ishft(DST_SEL_MEM, 16))
    idx = idx + 1
    ib_data(idx) = ior(DATA_SEL_TIMESTAMP, ishft(INT_SEL_NONE, 8))
    idx = idx + 1
    ib_data(idx) = int(timer_va, c_int32_t)
    idx = idx + 1
    ib_data(idx) = int(ishft(timer_va, -32), c_int32_t)
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    
    ! === COMPUTE STATE SETUP ===
    
    ! Set shader program address
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_PGM_LO
    idx = idx + 1
    ib_data(idx) = int(shader_va, c_int32_t)  ! Lower 32 bits
    idx = idx + 1
    ib_data(idx) = int(ishft(shader_va, -32), c_int32_t)  ! Upper 32 bits
    idx = idx + 1
    
    ! Set shader resources (RSRC1 and RSRC2)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_PGM_RSRC1
    idx = idx + 1
    ! RSRC1: VGPRS(8:0) = 8, SGPRS(9:6) = 1 (16 SGPRs = 1*8+8-1)  
    ib_data(idx) = ior(8_i32, ishft(1_i32, 6))  ! VGPRs=9-1=8, SGPRs=16/8-1=1
    idx = idx + 1
    ! RSRC2: Enable USER_SGPR(1) and TGID_X(7)
    ib_data(idx) = int(z'00000092', i32)  ! USER_SGPR + TGID_X
    idx = idx + 1
    
    ! Set workgroup dimensions (64 threads per workgroup)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_NUM_THREAD_X
    idx = idx + 1
    ib_data(idx) = 63_i32  ! 64-1 threads in X
    idx = idx + 1
    ib_data(idx) = 0_i32   ! 1-1 threads in Y  
    idx = idx + 1
    ib_data(idx) = 0_i32   ! 1-1 threads in Z
    idx = idx + 1
    
    ! Set kernel arguments (s[4:5] = kernel args pointer)
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
    idx = idx + 1
    ib_data(idx) = COMPUTE_USER_DATA_0
    idx = idx + 1
    ib_data(idx) = int(input_a_va, c_int32_t)  ! For now, just pass input_a
    idx = idx + 1
    ib_data(idx) = int(ishft(input_a_va, -32), c_int32_t)
    idx = idx + 1
    
    ! DISPATCH_DIRECT: Launch the compute shader
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(3_i32, 16), PM4_DISPATCH_DIRECT))
    idx = idx + 1
    ib_data(idx) = (num_elements + 63) / 64  ! X workgroups (round up)
    idx = idx + 1
    ib_data(idx) = 1_i32  ! Y workgroups
    idx = idx + 1  
    ib_data(idx) = 1_i32  ! Z workgroups
    idx = idx + 1
    
    ! End timestamp (T1)  
    ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(5_i32, 16), PM4_RELEASE_MEM))
    idx = idx + 1
    ib_data(idx) = ior(ior(CS_DONE, ishft(EVENT_INDEX_EOP, 8)), ishft(DST_SEL_MEM, 16))
    idx = idx + 1
    ib_data(idx) = ior(DATA_SEL_TIMESTAMP, ishft(INT_SEL_NONE, 8))
    idx = idx + 1
    ib_data(idx) = int(timer_va + 8_i64, c_int32_t)
    idx = idx + 1
    ib_data(idx) = int(ishft(timer_va + 8_i64, -32), c_int32_t)
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    ib_data(idx) = 0_i32
    idx = idx + 1
    
    print '(A,I0,A)', "Built PM4 IB with ", idx-1, " dwords (real compute dispatch)"
    
  end subroutine build_vector_add_ib

end program test_pm4_vector_add_native