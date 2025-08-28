program test_pm4_hex_dump
  ! PM4 Hex Dump Test
  ! =================
  ! Dumps exact hex values to debug shader encoding
  
  use kinds
  use iso_c_binding
  use pm4_submit
  use pm4_buffer_raii
  implicit none
  
  type(c_ptr) :: ctx_ptr
  type(gpu_buffer) :: ib_buffer
  type(sp_fence) :: fence
  
  integer(c_int32_t), pointer :: ib_data(:)
  integer(i32) :: status, i, idx
  
  ! LibDRM's shader binary that writes 42u - with SWAP_32 applied
  integer(i32), parameter :: shader_bin_swapped(15) = [ &
    int(z'BE8200B0', i32), int(z'BF08FF02', i32), int(z'0098967F', i32), int(z'BF850004', i32), &
    int(z'81028102', i32), int(z'BF08FF02', i32), int(z'0098967F', i32), int(z'BF84FFFC', i32), &
    int(z'BE8300FF', i32), int(z'0000F000', i32), int(z'BE8200C1', i32), int(z'7E0002AA', i32), &
    int(z'E0700000', i32), int(z'80000000', i32), int(z'BF810000', i32) &
  ]
  
  print *, "======================================="
  print *, "PM4 Hex Dump Test"
  print *, "======================================="
  print *, ""
  
  ! Dump shader binary in both formats
  print *, "LibDRM shader_bin (original - big endian):"
  print '(4(A,Z8,A))', "  0x", int(z'800082BE', i32), " ", "0x", int(z'02FF08BF', i32), " ", &
                        "0x", int(z'7F969800', i32), " ", "0x", int(z'040085BF', i32), " "
  print '(4(A,Z8,A))', "  0x", int(z'02810281', i32), " ", "0x", int(z'02FF08BF', i32), " ", &
                        "0x", int(z'7F969800', i32), " ", "0x", int(z'FCFF84BF', i32), " "
  print '(4(A,Z8,A))', "  0x", int(z'FF0083BE', i32), " ", "0x", int(z'00F00000', i32), " ", &
                        "0x", int(z'C10082BE', i32), " ", "0x", int(z'AA02007E', i32), " "
  print '(3(A,Z8,A))', "  0x", int(z'000070E0', i32), " ", "0x", int(z'00000080', i32), " ", &
                        "0x", int(z'000081BF', i32), " "
  
  print *, ""
  print *, "After SWAP_32 (little endian for GPU):"
  do i = 1, 15
    if (mod(i-1, 4) == 0) write(*, '(A)', advance='no') "  "
    write(*, '(A,Z8,A)', advance='no') "0x", shader_bin_swapped(i), " "
    if (mod(i, 4) == 0) write(*, *)
  end do
  write(*, *)
  
  print *, ""
  print *, "Our simple s_endpgm: 0xBF810000"
  print *, ""
  
  ctx_ptr = sp_pm4_init("/dev/dri/renderD129")
  if (.not. c_associated(ctx_ptr)) stop 1
  
  ! Small test to verify shader upload
  call ib_buffer%init(ctx_ptr, 1024_i64, SP_BO_HOST_VISIBLE)
  call c_f_pointer(ib_buffer%get_cpu_ptr(), ib_data, [256])
  
  ! Put s_endpgm at start
  ib_data(1) = int(z'BF810000', i32)
  
  ! Build minimal dispatch
  idx = 10
  
  ! CONTEXT_CONTROL
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_CONTEXT_CONTROL))
  ib_data(idx+1) = int(z'80000000', i32)
  ib_data(idx+2) = int(z'80000000', i32)
  idx = idx + 3
  
  ! Set shader
  ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(2_i32, 16), PM4_SET_SH_REG))
  ib_data(idx+1) = COMPUTE_PGM_LO
  ib_data(idx+2) = int(ishft(ib_buffer%get_va(), -8), c_int32_t)
  ib_data(idx+3) = int(ishft(ib_buffer%get_va(), -40), c_int32_t)
  idx = idx + 4
  
  print '(A,Z16)', "IB VA: 0x", ib_buffer%get_va()
  print '(A,Z8)', "Shader at offset 0: 0x", ib_data(1)
  print '(A,Z16)', "Shader VA (offset 0): 0x", ib_buffer%get_va()
  print '(A,Z8,A,Z8)', "PGM_LO: 0x", ib_data(idx-2), " PGM_HI: 0x", ib_data(idx-1)
  
  ! Check shift correctness
  print *, ""
  print *, "Shift verification:"
  print '(A,Z16)', "  Original VA: 0x", ib_buffer%get_va()
  print '(A,Z16)', "  VA >> 8:     0x", ishft(ib_buffer%get_va(), -8)
  print '(A,Z16)', "  VA >> 40:    0x", ishft(ib_buffer%get_va(), -40)
  print '(A,Z16)', "  Reconstructed: 0x", &
    ior(ishft(int(ishft(ib_buffer%get_va(), -40), i64), 40), &
        ishft(int(ishft(ib_buffer%get_va(), -8), i64), 8))
  
  call sp_pm4_cleanup(ctx_ptr)

end program test_pm4_hex_dump