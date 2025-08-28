program test_minimal_pm4
  use iso_c_binding
  use sporkle_amdgpu_direct
  use sporkle_amdgpu_shaders
  use sporkle_amdgpu_memory
  implicit none
  
  type(amdgpu_device) :: device
  type(amdgpu_buffer) :: result_buffer, shader_buffer, ib_buffer
  type(amdgpu_command_buffer) :: cmd_buf
  integer :: status, i, nargs
  integer(c_int32_t) :: context_id, bo_list
  integer(c_int64_t) :: result_addr
  integer(c_int32_t), allocatable, target :: result_data(:)
  integer(c_int32_t), target :: expected
  integer(c_int32_t), target :: bo_handles(3)
  character(len=256) :: arg, device_path
  logical :: safe_mode, once_mode, dry_run_mode
  
  ! PM4 constants
  integer(c_int32_t), parameter :: PACKET3_SET_SH_REG = int(z'76', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_DISPATCH_DIRECT = int(z'15', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_EVENT_WRITE_EOP = int(z'47', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_RELEASE_MEM = int(z'49', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_ACQUIRE_MEM = int(z'58', c_int32_t)
  
  integer(c_int32_t), parameter :: SH_REG_BASE = int(z'2C00', c_int32_t)
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_LO = int(z'48', c_int32_t)  ! 0x2C48 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_HI = int(z'4C', c_int32_t)  ! 0x2C4C - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_RSRC1 = int(z'50', c_int32_t)  ! 0x2C50 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_RSRC2 = int(z'54', c_int32_t)  ! 0x2C54 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_NUM_THREAD_X = int(z'6C', c_int32_t)  ! 0x2C6C - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_NUM_THREAD_Y = int(z'70', c_int32_t)  ! 0x2C70 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_NUM_THREAD_Z = int(z'74', c_int32_t)  ! 0x2C74 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_USER_DATA_0 = int(z'40', c_int32_t)  ! 0x2C40 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_USER_DATA_1 = int(z'44', c_int32_t)  ! 0x2C44 - 0x2C00
  
  ! Memory configuration registers (one-time preamble)
  integer(c_int32_t), parameter :: mmSH_MEM_CONFIG = int(z'8C', c_int32_t)  ! 0x2C8C - 0x2C00
  integer(c_int32_t), parameter :: mmSH_MEM_BASES = int(z'8F', c_int32_t)  ! 0x2C8F - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_RESOURCE_LIMITS = int(z'85', c_int32_t)  ! 0x2C85 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_STATIC_THREAD_MGMT_SE0 = int(z'58', c_int32_t)  ! 0x2C58 - 0x2C00
  integer(c_int32_t), parameter :: mmCOMPUTE_STATIC_THREAD_MGMT_SE1 = int(z'59', c_int32_t)  ! 0x2C59 - 0x2C00
  
  ! Minimal shader that stores 0xDEADBEEF to address in s[0:1]
  ! This is the simplest possible shader - no descriptors, no LDS, no scratch
  integer(c_int8_t), target :: minimal_shader(44) = [ &
    ! s_load_dwordx2 s[0:1], s[4:5], 0x0
    int(z'C0', c_int8_t), int(z'06', c_int8_t), int(z'00', c_int8_t), int(z'04', c_int8_t), &
    int(z'00', c_int8_t), int(z'00', c_int8_t), int(z'00', c_int8_t), int(z'00', c_int8_t), &
    ! s_waitcnt lgkmcnt(0)
    int(z'BF', c_int8_t), int(z'C0', c_int8_t), int(z'00', c_int8_t), int(z'70', c_int8_t), &
    ! v_mov_b32 v0, 0xDEADBEEF
    int(z'7E', c_int8_t), int(z'00', c_int8_t), int(z'02', c_int8_t), int(z'82', c_int8_t), &
    int(z'EF', c_int8_t), int(z'BE', c_int8_t), int(z'AD', c_int8_t), int(z'DE', c_int8_t), &
    ! v_mov_b32 v1, s0
    int(z'7E', c_int8_t), int(z'02', c_int8_t), int(z'02', c_int8_t), int(z'00', c_int8_t), &
    ! v_mov_b32 v2, s1
    int(z'7E', c_int8_t), int(z'04', c_int8_t), int(z'02', c_int8_t), int(z'01', c_int8_t), &
    ! flat_store_dword v[1:2], v0
    int(z'DC', c_int8_t), int(z'70', c_int8_t), int(z'00', c_int8_t), int(z'00', c_int8_t), &
    int(z'01', c_int8_t), int(z'00', c_int8_t), int(z'80', c_int8_t), int(z'00', c_int8_t), &
    ! s_waitcnt vmcnt(0) & lgkmcnt(0)
    int(z'BF', c_int8_t), int(z'C0', c_int8_t), int(z'00', c_int8_t), int(z'70', c_int8_t), &
    ! s_endpgm
    int(z'BF', c_int8_t), int(z'81', c_int8_t), int(z'00', c_int8_t), int(z'00', c_int8_t) &
  ]
  
  ! Parse command line arguments
  safe_mode = .false.
  once_mode = .false.
  dry_run_mode = .false.
  
  nargs = command_argument_count()
  do i = 1, nargs
    call get_command_argument(i, arg)
    select case(trim(arg))
    case("--safe")
      safe_mode = .true.
    case("--once")
      once_mode = .true.
    case("--dry-run")
      dry_run_mode = .true.
    end select
  end do
  
  ! Get device from environment or use default
  call get_environment_variable("SPORKLE_DRI", device_path, status=status)
  if (status /= 0) then
    device_path = "/dev/dri/renderD129"  ! Default to iGPU
  end if
  
  print *, "=== Mini's Minimal PM4 Literal Store Test ==="
  print *, ""
  print *, "Testing simplest possible kernel:"
  print *, "  - One 64-bit pointer in USER_DATA[0:1]"
  print *, "  - Stores literal 0xDEADBEEF to [ptr]"
  print *, "  - No descriptors, no LDS, no scratch"
  if (safe_mode) print *, "  - SAFE MODE: 1x1x1 dispatch, small IB"
  if (dry_run_mode) print *, "  - DRY RUN: Will not submit to GPU"
  print *, ""
  
  ! Open device
  device = amdgpu_open_device(trim(device_path))
  if (device%fd < 0) then
    print *, "Failed to open device"
    stop 1
  end if
  print *, "✅ Opened device"
  print '(A,A)', "  Selected device path: ", trim(device_path)
  
  ! Print device major:minor
  block
    integer :: fstat_result
    integer(c_long) :: stat_buf(18)  ! Simplified stat structure
    integer :: major_num, minor_num
    
    interface
      function fstat(fd, buf) bind(C, name="fstat")
        import :: c_int, c_long
        integer(c_int), value :: fd
        integer(c_long) :: buf(*)
        integer(c_int) :: fstat
      end function
    end interface
    
    fstat_result = fstat(device%fd, stat_buf)
    if (fstat_result == 0) then
      ! st_rdev is at offset 24 bytes (3rd c_long on 64-bit)
      major_num = int(iand(shiftr(stat_buf(3), 8), int(z'FFF', c_long)))
      minor_num = int(iand(stat_buf(3), int(z'FF', c_long)))
      print '(A,I0,A,I0,A,A,A)', "  Render node devnum: ", major_num, ":", minor_num, &
        " (matches ", trim(device_path), ")"
    end if
  end block
  
  ! Create context
  context_id = amdgpu_create_context(device)
  if (context_id < 0) then
    print *, "Failed to create context"
    stop 1
  end if
  print *, "✅ Created context:", context_id
  
  ! Allocate result buffer (one dword)
  result_buffer = amdgpu_allocate_buffer(device, 4_c_size_t)
  if (result_buffer%handle == 0) then
    print *, "Failed to allocate result buffer"
    stop 1
  end if
  print *, "✅ Allocated result buffer, handle:", result_buffer%handle
  
  ! Map result buffer
  status = amdgpu_map_buffer(device, result_buffer)
  if (status /= 0) then
    print *, "Failed to map result buffer"
    stop 1
  end if
  
  ! Use VA address if already mapped
  if (result_buffer%is_va_mapped) then
    result_addr = result_buffer%va_addr
  else
    result_addr = result_buffer%gpu_addr
  end if
  
  if (result_addr == 0) then
    print *, "No valid address for result buffer"
    stop 1
  end if
  print '(A,Z16)', "✅ Result buffer addr: 0x", result_addr
  
  ! Initialize with BAD0BAD0 to see change
  allocate(result_data(1))
  result_data(1) = int(z'BAD0BAD0', c_int32_t)
  status = amdgpu_write_buffer(device, result_buffer, c_loc(result_data), 4_c_size_t)
  print *, "✅ Initialized buffer with 0xBAD0BAD0"
  
  ! Upload shader
  shader_buffer = amdgpu_allocate_buffer(device, 44_c_size_t)  ! Size of minimal_shader
  if (shader_buffer%handle == 0) then
    print *, "Failed to allocate shader buffer"
    stop 1
  end if
  status = amdgpu_map_buffer(device, shader_buffer)
  if (status /= 0) then
    print *, "Failed to map shader buffer"
    stop 1
  end if
  
  ! Get shader buffer address
  print '(A,Z16)', "✅ Shader buffer GPU addr: 0x", shader_buffer%gpu_addr
  
  status = amdgpu_write_buffer(device, shader_buffer, c_loc(minimal_shader), 44_c_size_t)
  print *, "✅ Uploaded shader, size: 44 bytes"
  
  ! Allocate command buffer
  ib_buffer = amdgpu_allocate_buffer(device, 4096_c_size_t)
  status = amdgpu_map_buffer(device, ib_buffer)
  
  ! Create BO list
  bo_handles(1) = result_buffer%handle
  bo_handles(2) = shader_buffer%handle
  bo_handles(3) = ib_buffer%handle
  bo_list = amdgpu_create_bo_list(device, bo_handles, 3)
  print *, "✅ Created BO list:", bo_list
  
  ! Build PM4 command buffer
  cmd_buf%ctx_id = context_id
  cmd_buf%bo_list_handle = bo_list
  cmd_buf%ib_buffer = ib_buffer
  
  block
    integer(c_int32_t), pointer :: ib(:)
    integer :: idx
    type(amdgpu_shader) :: shader
    
    call c_f_pointer(ib_buffer%cpu_ptr, ib, [1024])
    idx = 1
    
    shader%gpu_addr = shader_buffer%gpu_addr  ! Use GPU address
    shader%code_size = 44_c_size_t
    shader%num_sgprs = 6   ! s[0:5]
    shader%num_vgprs = 3   ! v[0:2]
    shader%lds_size = 0     ! No LDS
    shader%scratch_size = 0 ! No scratch!
    
    ! Clear IB
    ib = 0
    
    ! Memory configuration preamble (one-time setup)
    ! PACKET3_SET_SH_REG, count=1 (2 DWORDs total)
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmSH_MEM_CONFIG
    ib(idx+2) = 0  ! SH_MEM_CONFIG = 0 (default)
    idx = idx + 3
    
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmSH_MEM_BASES
    ib(idx+2) = 0  ! SH_MEM_BASES = 0 (private/group bases 0)
    idx = idx + 3
    
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_RESOURCE_LIMITS
    ib(idx+2) = 0  ! COMPUTE_RESOURCE_LIMITS = 0 (safe default)
    idx = idx + 3
    
    ! Set static thread management
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_STATIC_THREAD_MGMT_SE0
    ib(idx+2) = int(z'FFFFFFFF', c_int32_t)  ! All CUs enabled
    idx = idx + 3
    
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_STATIC_THREAD_MGMT_SE1
    ib(idx+2) = int(z'FFFFFFFF', c_int32_t)  ! All CUs enabled
    idx = idx + 3
    
    ! Set shader program address
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(2-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_PGM_LO
    ib(idx+2) = int(shader%gpu_addr, c_int32_t)
    ib(idx+3) = int(shiftr(shader%gpu_addr, 32), c_int32_t)
    idx = idx + 4
    
    ! Set PGM_RSRC1 (VGPRS, SGPRS, etc.)
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_PGM_RSRC1
    ib(idx+2) = ior(ior(ishft(5, 0), ishft(2, 6)), ishft(0, 24))  ! VGPRS=5, SGPRS=2
    idx = idx + 3
    
    ! Set PGM_RSRC2 (scratch disabled, user SGPRs=2)
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(1-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_PGM_RSRC2
    ib(idx+2) = int(z'00000002', c_int32_t)  ! USER_SGPR = 2 (bits [5:1])
    idx = idx + 3
    
    ! Set workgroup size
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(3-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_NUM_THREAD_X
    ib(idx+2) = 1  ! X threads
    ib(idx+3) = 1  ! Y threads
    ib(idx+4) = 1  ! Z threads
    idx = idx + 5
    
    ! Set kernel argument pointer
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(2-1, 16), ishft(PACKET3_SET_SH_REG, 8)))
    ib(idx+1) = mmCOMPUTE_USER_DATA_0
    ib(idx+2) = int(result_addr, c_int32_t)
    ib(idx+3) = int(shiftr(result_addr, 32), c_int32_t)
    idx = idx + 4
    
    ! Acquire memory before dispatch
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(7-1, 16), ishft(PACKET3_ACQUIRE_MEM, 8)))
    ib(idx+1) = int(z'00000000', c_int32_t)  ! CP_COHER_CNTL
    ib(idx+2) = int(z'FFFFFFFF', c_int32_t)  ! CP_COHER_SIZE
    ib(idx+3) = int(z'00000000', c_int32_t)  ! CP_COHER_SIZE_HI  
    ib(idx+4) = int(z'00000000', c_int32_t)  ! CP_COHER_BASE
    ib(idx+5) = int(z'00000000', c_int32_t)  ! CP_COHER_BASE_HI
    ib(idx+6) = int(z'0000000A', c_int32_t)  ! POLL_INTERVAL
    idx = idx + 7
    
    ! Dispatch
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(3, 16), ishft(PACKET3_DISPATCH_DIRECT, 8)))
    ib(idx+1) = 1  ! X groups
    ib(idx+2) = 1  ! Y groups  
    ib(idx+3) = 1  ! Z groups
    ib(idx+4) = int(z'00000101', c_int32_t)  ! COMPUTE_SHADER_EN | FORCE_START_AT_000
    idx = idx + 5
    
    ! RELEASE_MEM with TC flush for APU coherency
    ib(idx) = ior(int(z'C0000000', c_int32_t), ior(ishft(6-1, 16), ishft(PACKET3_RELEASE_MEM, 8)))
    ib(idx+1) = int(z'00030005', c_int32_t)  ! EVENT_TYPE=CACHE_FLUSH_AND_INV_TS_EVENT, EVENT_INDEX=5
    ib(idx+2) = int(z'00000118', c_int32_t)  ! DATA_SEL=send 64bit data, INT_SEL=write_confirm, DST_SEL=TC_L2
    ib(idx+3) = 0  ! ADDR_LO (fence address) - we'll use 0 for now 
    ib(idx+4) = 0  ! ADDR_HI
    ib(idx+5) = int(z'DEADBEEF', c_int32_t)  ! DATA_LO (fence value)
    ib(idx+6) = int(z'CAFEBABE', c_int32_t)  ! DATA_HI
    idx = idx + 7
    
    cmd_buf%ib_size = (idx - 1) * 4
    print *, "✅ Built PM4 commands, size:", cmd_buf%ib_size
    
    ! In dry-run mode, dump the IB and exit
    if (dry_run_mode) then
      print *, ""
      print *, "=== IB HEXDUMP (DRY RUN) ==="
      do i = 1, idx-1
        write(*, '(A,I3,A,Z8.8)') "  IB[", i-1, "] = 0x", ib(i)
      end do
      print *, "=== END HEXDUMP ==="
      print *, ""
      print *, "Dry run complete - not submitting to GPU"
      stop 0
    end if
  end block
  
  ! Submit
  status = amdgpu_submit_command_buffer(device, cmd_buf)
  if (status /= 0) then
    print *, "❌ Submit failed:", status
    stop 1
  end if
  print *, "✅ Submitted command"
  
  ! Wait (shorter timeout in safe mode)
  if (safe_mode) then
    status = amdgpu_wait_buffer_idle(device, ib_buffer, 100000000_c_int64_t)  ! 100ms
  else
    status = amdgpu_wait_buffer_idle(device, ib_buffer, 5000000000_c_int64_t)  ! 5s
  end if
  print *, "✅ Command completed"
  
  ! Read result
  status = amdgpu_read_buffer(device, result_buffer, c_loc(result_data), 4_c_size_t)
  
  expected = int(z'DEADBEEF', c_int32_t)
  print *, ""
  print '(A,Z8,A,Z8)', "Result: 0x", result_data(1), " (expected: 0x", expected, ")"
  
  if (result_data(1) == expected) then
    print *, ""
    print *, "✅ SUCCESS! GPU compute is working!"
    print *, "Mini was right - we were one state packet away!"
  else if (result_data(1) == int(z'BAD0BAD0', c_int32_t)) then
    print *, ""
    print *, "❌ Value unchanged - shader didn't execute"
    print *, "Still missing some state"
  else
    print *, ""
    print *, "⚠️ Got unexpected value"
  end if
  
  ! Cleanup
  deallocate(result_data)
  call amdgpu_close_device(device)
  
end program test_minimal_pm4