module sporkle_amdgpu_shaders
  use iso_c_binding
  use sporkle_types
  use sporkle_amdgpu_direct
  use sporkle_amdgpu_shader_binary
  use sporkle_amdgpu_memory
  implicit none
  
  private
  public :: amdgpu_shader, create_vector_add_shader, create_gemm_shader
  public :: dispatch_compute_shader, embed_shader_in_ib
  
  ! PM4 packet definitions
  integer(c_int32_t), parameter :: PACKET3_SET_SH_REG = int(z'76', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_DISPATCH_DIRECT = int(z'15', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_EVENT_WRITE = int(z'46', c_int32_t)
  integer(c_int32_t), parameter :: PACKET3_ACQUIRE_MEM = int(z'58', c_int32_t)
  
  ! Compute shader registers - these are OFFSETS from SH_REG_BASE (0x2C00)
  ! For GFX9, SH registers start at 0x2C00, so we subtract that
  integer(c_int32_t), parameter :: SH_REG_BASE = int(z'2C00', c_int32_t)
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_LO = int(z'2C48', c_int32_t) - SH_REG_BASE  ! 0x48
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_HI = int(z'2C4C', c_int32_t) - SH_REG_BASE  ! 0x4C
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_RSRC1 = int(z'2C50', c_int32_t) - SH_REG_BASE  ! 0x50
  integer(c_int32_t), parameter :: mmCOMPUTE_PGM_RSRC2 = int(z'2C54', c_int32_t) - SH_REG_BASE  ! 0x54
  integer(c_int32_t), parameter :: mmCOMPUTE_NUM_THREAD_X = int(z'2C6C', c_int32_t) - SH_REG_BASE  ! 0x6C
  integer(c_int32_t), parameter :: mmCOMPUTE_NUM_THREAD_Y = int(z'2C70', c_int32_t) - SH_REG_BASE  ! 0x70
  integer(c_int32_t), parameter :: mmCOMPUTE_NUM_THREAD_Z = int(z'2C74', c_int32_t) - SH_REG_BASE  ! 0x74
  ! User data registers for kernel arguments
  integer(c_int32_t), parameter :: mmCOMPUTE_USER_DATA_0 = int(z'2C40', c_int32_t) - SH_REG_BASE  ! 0x40
  integer(c_int32_t), parameter :: mmCOMPUTE_USER_DATA_1 = int(z'2C44', c_int32_t) - SH_REG_BASE  ! 0x44
  
  ! Shader binary structure
  type :: amdgpu_shader
    integer(c_int64_t) :: gpu_addr        ! GPU virtual address of shader code
    integer(c_size_t) :: code_size        ! Size of shader binary
    integer(c_int32_t) :: num_sgprs       ! Scalar registers used
    integer(c_int32_t) :: num_vgprs       ! Vector registers used
    integer(c_int32_t) :: lds_size        ! Local data share size
    integer(c_int32_t) :: scratch_size    ! Scratch memory per thread
    type(c_ptr) :: code_ptr               ! CPU pointer to shader code
    logical :: is_loaded
  end type amdgpu_shader
  
contains

  function packet3(opcode, count) result(header)
    integer(c_int32_t), intent(in) :: opcode
    integer(c_int32_t), intent(in) :: count
    integer(c_int32_t) :: header
    
    ! PACKET3 header format: [31:30]=3, [29:16]=count-1, [15:8]=opcode
    header = ior(int(z'C0000000', c_int32_t), &
                 ior(shiftl(count - 1, 16), shiftl(opcode, 8)))
  end function packet3

  function create_vector_add_shader() result(shader)
    type(amdgpu_shader) :: shader
    
    ! Using shader binary based on AMD's GCN ISA documentation
    ! Credit: Binary format follows AMD ROCm compiler conventions
    ! This demonstrates how we'd embed a real compiled shader
    
    shader%code_size = vector_add_shader_size
    shader%num_sgprs = vector_add_num_sgprs
    shader%num_vgprs = vector_add_num_vgprs
    shader%lds_size = vector_add_lds_size
    shader%scratch_size = vector_add_scratch_size
    shader%code_ptr = c_loc(vector_add_shader_data)
    shader%is_loaded = .false.
    shader%gpu_addr = 0
    
    print *, "Created vector_add shader:"
    print *, "  Based on AMD GCN3 ISA documentation"
    print *, "  Size:", shader%code_size, "bytes"
    print *, "  SGPRs:", shader%num_sgprs
    print *, "  VGPRs:", shader%num_vgprs
    
  end function create_vector_add_shader

  function create_gemm_shader() result(shader)
    type(amdgpu_shader) :: shader
    
    ! Placeholder for GEMM shader
    ! This would contain optimized GCN assembly for matrix multiplication
    
    shader%code_size = 4096  ! Larger for complex kernel
    shader%num_sgprs = 16
    shader%num_vgprs = 64
    shader%lds_size = 16384  ! 16KB LDS for tiling
    shader%scratch_size = 0
    shader%is_loaded = .false.
    shader%gpu_addr = 0
    
  end function create_gemm_shader

  subroutine embed_shader_in_ib(ib_ptr, ib_offset, shader, kernel_args_addr, &
                                workgroup_x, workgroup_y, workgroup_z, &
                                thread_x, thread_y, thread_z)
    type(c_ptr), intent(in) :: ib_ptr
    integer(c_size_t), intent(inout) :: ib_offset
    type(amdgpu_shader), intent(in) :: shader
    integer(c_int64_t), intent(in) :: kernel_args_addr
    integer(c_int32_t), intent(in) :: workgroup_x, workgroup_y, workgroup_z
    integer(c_int32_t), intent(in) :: thread_x, thread_y, thread_z
    
    integer(c_int32_t), pointer :: ib(:)
    integer :: idx
    
    call c_f_pointer(ib_ptr, ib, [8192])  ! Max IB size
    idx = int(ib_offset / 4) + 1  ! Convert byte offset to dword index
    
    ! Set shader program address
    ib(idx) = packet3(PACKET3_SET_SH_REG, 2)
    ib(idx+1) = mmCOMPUTE_PGM_LO
    ib(idx+2) = int(shader%gpu_addr, c_int32_t)  ! Lower 32 bits
    ib(idx+3) = int(shiftr(shader%gpu_addr, 32), c_int32_t)  ! Upper 32 bits
    idx = idx + 4
    
    ! Set shader resources
    ib(idx) = packet3(PACKET3_SET_SH_REG, 2)
    ib(idx+1) = mmCOMPUTE_PGM_RSRC1
    ! RSRC1: VGPRS, SGPRS, Priority, Float mode, etc.
    ib(idx+2) = ior(shader%num_vgprs - 1, shiftl(shader%num_sgprs / 8 - 1, 6))
    ! RSRC2: Scratch enable, User SGPR, TGID enable, etc.
    ! Bit 1: Enable SGPR for kernel args (USER_SGPR_MSB)
    ! Bit 7: Enable TGID_X
    ib(idx+3) = int(z'00000092', c_int32_t)  ! Enable USER_SGPR and TGID in X
    idx = idx + 4
    
    ! Set workgroup dimensions
    ib(idx) = packet3(PACKET3_SET_SH_REG, 3)
    ib(idx+1) = mmCOMPUTE_NUM_THREAD_X
    ib(idx+2) = thread_x - 1
    ib(idx+3) = thread_y - 1
    ib(idx+4) = thread_z - 1
    idx = idx + 5
    
    ! Set kernel arguments pointer (user SGPRs)
    ! This sets up s[4:5] with kernel args address (64-bit pointer)
    ib(idx) = packet3(PACKET3_SET_SH_REG, 2)
    ib(idx+1) = mmCOMPUTE_USER_DATA_0
    ib(idx+2) = int(kernel_args_addr, c_int32_t)  ! Lower 32 bits
    ib(idx+3) = int(shiftr(kernel_args_addr, 32), c_int32_t)  ! Upper 32 bits
    idx = idx + 4
    
    print '(A,Z16)', "  Setting kernel args addr: 0x", kernel_args_addr
    
    ! Dispatch the compute shader
    ib(idx) = packet3(PACKET3_DISPATCH_DIRECT, 3)
    ib(idx+1) = workgroup_x
    ib(idx+2) = workgroup_y
    ib(idx+3) = workgroup_z
    idx = idx + 4
    
    ! Memory barrier - ensure compute completes
    ib(idx) = packet3(PACKET3_ACQUIRE_MEM, 5)
    ib(idx+1) = int(z'00000002', c_int32_t)  ! Mem fence
    ib(idx+2) = 0  ! Size low
    ib(idx+3) = 0  ! Size high  
    ib(idx+4) = 0  ! Addr low
    ib(idx+5) = 0  ! Addr high
    idx = idx + 6
    
    ! Update offset
    ib_offset = int((idx - 1) * 4, c_size_t)
    
  end subroutine embed_shader_in_ib

  function dispatch_compute_shader(device, shader, args_buffer, &
                                  workgroup_x, workgroup_y, workgroup_z, &
                                  thread_x, thread_y, thread_z) result(status)
    type(amdgpu_device), intent(in) :: device
    type(amdgpu_shader), intent(inout) :: shader
    type(amdgpu_buffer), intent(in) :: args_buffer
    integer(c_int32_t), intent(in) :: workgroup_x, workgroup_y, workgroup_z
    integer(c_int32_t), intent(in) :: thread_x, thread_y, thread_z
    integer :: status
    
    type(amdgpu_buffer) :: shader_buffer
    type(amdgpu_command_buffer) :: cmd_buf
    integer(c_size_t) :: ib_offset
    integer(c_int32_t) :: handles(5)
    integer :: num_buffers
    
    ! Allocate buffer for shader code if not already loaded
    if (.not. shader%is_loaded) then
      shader_buffer = amdgpu_allocate_buffer(device, shader%code_size)
      if (shader_buffer%handle == 0) then
        print *, "Failed to allocate shader buffer"
        status = -1
        return
      end if
      
      ! Copy shader code to GPU buffer
      status = amdgpu_write_buffer(device, shader_buffer, shader%code_ptr, shader%code_size)
      if (status /= 0) then
        print *, "Failed to copy shader code to GPU"
        return
      end if
      
      ! Use the buffer's GPU address
      shader%gpu_addr = shader_buffer%gpu_addr
      shader%is_loaded = .true.
      
      print *, "Loaded shader to GPU:"
      print *, "  Handle:", shader_buffer%handle
      print *, "  GPU addr:", shader_buffer%gpu_addr
      print *, "  Size:", shader%code_size, "bytes"
    end if
    
    ! Allocate command buffer
    cmd_buf%ib_buffer = amdgpu_allocate_buffer(device, 8192_c_size_t)
    if (cmd_buf%ib_buffer%handle == 0) then
      print *, "Failed to create command buffer"
      status = -1
      return
    end if
    
    ! Map command buffer for CPU access
    status = amdgpu_map_buffer(device, cmd_buf%ib_buffer)
    if (status /= 0) then
      print *, "Failed to map command buffer"
      return
    end if
    
    cmd_buf%ib_cpu_ptr = cmd_buf%ib_buffer%cpu_ptr
    
    ! Set context ID (assuming device has it)
    cmd_buf%ctx_id = 1  ! We created context with ID 1 in test program
    
    ! Create BO list with all our buffers
    num_buffers = 0
    if (shader_buffer%handle /= 0) then
      num_buffers = num_buffers + 1
      handles(num_buffers) = shader_buffer%handle
    end if
    if (args_buffer%handle /= 0) then
      num_buffers = num_buffers + 1  
      handles(num_buffers) = args_buffer%handle
    end if
    if (cmd_buf%ib_buffer%handle /= 0) then
      num_buffers = num_buffers + 1
      handles(num_buffers) = cmd_buf%ib_buffer%handle
    end if
    
    cmd_buf%bo_list_handle = amdgpu_create_bo_list(device, handles, num_buffers)
    if (cmd_buf%bo_list_handle == 0) then
      print *, "WARNING: Failed to create BO list"
    end if
    
    ! Build PM4 packets
    ib_offset = 0
    ! Use VA address if mapped, otherwise gpu_addr
    if (args_buffer%is_va_mapped) then
      call embed_shader_in_ib(cmd_buf%ib_cpu_ptr, ib_offset, shader, &
                             args_buffer%va_addr, &
                             workgroup_x, workgroup_y, workgroup_z, &
                             thread_x, thread_y, thread_z)
    else
      call embed_shader_in_ib(cmd_buf%ib_cpu_ptr, ib_offset, shader, &
                             args_buffer%gpu_addr, &
                             workgroup_x, workgroup_y, workgroup_z, &
                             thread_x, thread_y, thread_z)
    end if
    
    ! Set command buffer size
    cmd_buf%ib_size = ib_offset
    
    print *, "Command buffer setup:"
    print *, "  Context ID:", cmd_buf%ctx_id
    print *, "  BO List handle:", cmd_buf%bo_list_handle
    print *, "  IB size:", cmd_buf%ib_size, "bytes"
    print *, "  Shader GPU addr:", shader%gpu_addr
    
    ! Submit command buffer
    status = amdgpu_submit_command_buffer(device, cmd_buf)
    if (status /= 0) then
      print *, "Failed to submit compute shader"
      return
    end if
    
    ! Wait for completion
    status = amdgpu_wait_buffer_idle(device, cmd_buf%ib_buffer, int(10_8**9, c_int64_t))  ! 1 second timeout
    
    ! Cleanup - free buffer
    ! In real implementation, would have proper cleanup
    
  end function dispatch_compute_shader

end module sporkle_amdgpu_shaders