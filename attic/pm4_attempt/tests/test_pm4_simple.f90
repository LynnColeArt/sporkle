program test_pm4_simple
  use iso_c_binding
  use sporkle_amdgpu_direct
  use sporkle_pm4_builder
  use sporkle_rdna3_isa
  implicit none
  
  type(amdgpu_device) :: device
  type(amdgpu_buffer) :: cmd_buf
  type(pm4_command_builder) :: builder
  integer :: status
  integer(i32) :: cmd_buffer(1024)
  integer :: cmd_size
  
  print *, "🚀 Testing PM4 Command Building"
  print *, "=============================="
  
  ! Open device
  device = amdgpu_open_device("/dev/dri/renderD128")
  if (device%fd < 0) then
    print *, "❌ Failed to open device"
    stop 1
  end if
  
  print *, "✅ Opened device successfully"
  
  ! Initialize command builder
  call builder%init(cmd_buffer, size(cmd_buffer))
  
  ! Add PM4 commands
  call builder%add_set_sh_reg(0x2C0A, int(z'00000010', int32))  ! COMPUTE_DIM_X
  call builder%add_set_sh_reg(0x2C0B, int(z'00000001', int32))  ! COMPUTE_DIM_Y
  call builder%add_set_sh_reg(0x2C0C, int(z'00000001', int32))  ! COMPUTE_DIM_Z
  
  ! Add simple dispatch
  call builder%add_dispatch_direct(16, 1, 1)
  
  ! Finalize
  cmd_size = builder%finalize()
  
  print *, "✅ Built PM4 command buffer with", cmd_size, "dwords"
  print *, ""
  print *, "Command buffer contents:"
  do status = 1, min(10, cmd_size)
    print '(A,I3,A,Z8)', "  [", status, "] = 0x", cmd_buffer(status)
  end do
  
  ! Now let's try to allocate a GPU buffer for the commands
  cmd_buf = amdgpu_allocate_buffer(device, int(cmd_size * 4, c_int64_t))
  if (cmd_buf%handle == 0) then
    print *, "❌ Failed to allocate command buffer"
  else
    print *, "✅ Allocated GPU buffer for commands"
    
    ! Map and copy commands
    status = amdgpu_map_buffer(device, cmd_buf)
    if (status == 0 .and. c_associated(cmd_buf%cpu_ptr)) then
      block
        integer(i32), pointer :: gpu_cmds(:)
        call c_f_pointer(cmd_buf%cpu_ptr, gpu_cmds, [cmd_size])
        gpu_cmds(1:cmd_size) = cmd_buffer(1:cmd_size)
        print *, "✅ Copied PM4 commands to GPU buffer"
      end block
    end if
  end if
  
  ! Cleanup
  if (cmd_buf%handle /= 0) then
    call amdgpu_free_buffer(device, cmd_buf)
  end if
  call amdgpu_close_device(device)
  
  print *, ""
  print *, "🎉 PM4 command building works!"
  
end program test_pm4_simple