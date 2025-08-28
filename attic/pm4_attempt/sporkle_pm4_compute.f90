module sporkle_pm4_compute
  ! PM4 Direct GPU Compute Submission
  ! =================================
  !
  ! This module implements direct GPU compute submission using PM4 packets,
  ! bypassing OpenGL/Mesa/ROCm entirely. We talk directly to the kernel!
  
  use kinds
  use iso_c_binding
  use sporkle_amdgpu_direct
  use sporkle_pm4_packets
  use sporkle_gpu_va_allocator
  use sporkle_rdna3_shaders, only: shader_code, get_simple_copy_shader, get_vector_add_shader
  implicit none
  private
  
  ! Re-export from amdgpu_direct
  integer, parameter :: AMDGPU_GEM_DOMAIN_GTT = 2
  
  public :: pm4_compute_context
  public :: pm4_init_compute, pm4_cleanup_compute
  public :: pm4_compile_shader, pm4_execute_compute
  public :: pm4_conv2d_direct
  public :: g_context  ! Export global context for debugging
  
  ! Simple device info
  type :: amdgpu_device_info
    character(len=256) :: name = "AMD GPU"
    integer :: chip_class = 10  ! GFX10/RDNA
    integer :: num_compute_units = 84
    integer :: max_engine_clock = 2500
  end type amdgpu_device_info
  
  ! PM4 compute context
  type :: pm4_compute_context
    type(amdgpu_device) :: device
    type(amdgpu_device_info) :: device_info
    integer(i32) :: ctx_id = 0
    integer(i32) :: bo_list_id = 0
    logical :: initialized = .false.
    
    ! Shader cache
    integer :: num_shaders = 0
    integer(i64), allocatable :: shader_addresses(:)
    character(len=256), allocatable :: shader_names(:)
  contains
    procedure :: find_shader => pm4_find_shader
    procedure :: add_shader => pm4_add_shader
  end type pm4_compute_context
  
  ! Global context (for now)
  type(pm4_compute_context), save :: g_context
  
contains

  ! Initialize PM4 compute
  function pm4_init_compute() result(success)
    logical :: success
    integer :: status
    
    success = .false.
    
    ! Open device
    g_context%device = amdgpu_open_device("/dev/dri/renderD128")
    if (g_context%device%fd <= 0) then
      print *, "❌ Failed to open AMDGPU device"
      return
    end if
    
    ! Set device info (hardcoded for now)
    g_context%device_info%name = "AMD Radeon RX 7900 XTX"
    
    print *, "🚀 PM4 Compute initialized on", trim(g_context%device_info%name)
    print *, "   Chip class:", g_context%device_info%chip_class
    print *, "   Compute units:", g_context%device_info%num_compute_units
    print *, "   Max clock:", g_context%device_info%max_engine_clock, "MHz"
    
    ! Create context
    g_context%ctx_id = amdgpu_create_context(g_context%device)
    if (g_context%ctx_id < 0) then
      print *, "❌ Failed to create GPU context"
      call amdgpu_close_device(g_context%device)
      return
    end if
    
    ! Initialize VA allocator
    call gpu_va_init()
    
    g_context%initialized = .true.
    success = .true.
    
  end function pm4_init_compute
  
  ! Cleanup PM4 compute
  subroutine pm4_cleanup_compute()
    integer :: status
    
    if (.not. g_context%initialized) return
    
    ! Destroy BO list if created
    if (g_context%bo_list_id /= 0) then
      call amdgpu_destroy_bo_list(g_context%device, g_context%bo_list_id)
    end if
    
    ! Destroy context
    if (g_context%ctx_id /= 0) then
      call amdgpu_destroy_context(g_context%device, g_context%ctx_id)
    end if
    
    ! Close device
    call amdgpu_close_device(g_context%device)
    
    g_context%initialized = .false.
    
    print *, "🧹 PM4 compute cleaned up"
    
  end subroutine pm4_cleanup_compute
  
  ! Find shader by name
  function pm4_find_shader(this, name) result(addr)
    class(pm4_compute_context), intent(in) :: this
    character(len=*), intent(in) :: name
    integer(i64) :: addr
    
    integer :: i
    
    addr = 0
    do i = 1, this%num_shaders
      if (trim(this%shader_names(i)) == trim(name)) then
        addr = this%shader_addresses(i)
        return
      end if
    end do
  end function pm4_find_shader
  
  ! Add shader to cache
  subroutine pm4_add_shader(this, name, addr)
    class(pm4_compute_context), intent(inout) :: this
    character(len=*), intent(in) :: name
    integer(i64), intent(in) :: addr
    
    integer(i64), allocatable :: new_addrs(:)
    character(len=256), allocatable :: new_names(:)
    
    if (this%num_shaders == 0) then
      allocate(this%shader_addresses(10))
      allocate(this%shader_names(10))
    else if (this%num_shaders >= size(this%shader_addresses)) then
      ! Grow arrays
      allocate(new_addrs(size(this%shader_addresses) * 2))
      allocate(new_names(size(this%shader_names) * 2))
      new_addrs(1:this%num_shaders) = this%shader_addresses(1:this%num_shaders)
      new_names(1:this%num_shaders) = this%shader_names(1:this%num_shaders)
      call move_alloc(new_addrs, this%shader_addresses)
      call move_alloc(new_names, this%shader_names)
    end if
    
    this%num_shaders = this%num_shaders + 1
    this%shader_addresses(this%num_shaders) = addr
    this%shader_names(this%num_shaders) = name
    
  end subroutine pm4_add_shader
  
  ! Compile shader (placeholder - would compile ISA in real implementation)
  function pm4_compile_shader(name, source) result(shader_addr)
    character(len=*), intent(in) :: name
    character(len=*), intent(in) :: source  ! Would be ISA assembly
    integer(i64) :: shader_addr
    
    type(amdgpu_buffer) :: shader_buffer
    integer :: status
    integer(i32), pointer :: shader_code_ptr(:)
    type(c_ptr) :: mapped_ptr
    integer :: code_size
    
    ! For now, create a simple test shader
    ! In reality, we'd assemble the ISA here
    code_size = 256  ! 256 dwords = 1KB
    
    ! Check if already compiled
    shader_addr = g_context%find_shader(name)
    if (shader_addr /= 0) then
      print '(A,A)', "✅ Shader already compiled: ", trim(name)
      return
    end if
    
    ! Allocate shader buffer
    shader_buffer = amdgpu_allocate_buffer(g_context%device, &
                                          int(code_size * 4, int64), &
                                          AMDGPU_GEM_DOMAIN_GTT)
    if (shader_buffer%handle == 0) then
      print *, "❌ Failed to allocate shader buffer"
      shader_addr = 0
      return
    end if
    
    ! Map and write shader code
    status = amdgpu_map_buffer(g_context%device, shader_buffer)
    if (status /= 0) then
      print *, "❌ Failed to map shader buffer"
      shader_addr = 0
      return
    end if
    
    mapped_ptr = shader_buffer%cpu_ptr
    
    call c_f_pointer(mapped_ptr, shader_code_ptr, [code_size])
    
    ! Get real ISA shader based on name
    if (name == "test_shader" .or. name == "copy_shader") then
      block
        type(shader_code) :: isa_shader
        
        isa_shader = get_simple_copy_shader()
        
        ! Copy shader code
        shader_code_ptr(1:isa_shader%size_dwords) = isa_shader%code(1:isa_shader%size_dwords)
        shader_code_ptr(isa_shader%size_dwords+1:) = 0
      end block
    else if (name == "vector_add") then
      block
        type(shader_code) :: isa_shader
        
        isa_shader = get_vector_add_shader()
        
        ! Copy shader code
        shader_code_ptr(1:isa_shader%size_dwords) = isa_shader%code(1:isa_shader%size_dwords)
        shader_code_ptr(isa_shader%size_dwords+1:) = 0
      end block
    else
      ! Default: just s_endpgm
      shader_code_ptr(1) = int(z'BF810000', int32)  ! s_endpgm
      shader_code_ptr(2:) = 0
    end if
    
    ! Unmap buffer
    ! TODO: Add unmap function
    
    ! Map to GPU address space using known working address
    ! Start shaders at 2MB to avoid conflicts with our test buffer at 1MB
    shader_buffer%va_addr = int(z'200000', int64)  ! 2MB
    
    status = amdgpu_map_va(g_context%device, shader_buffer, shader_buffer%va_addr)
    if (status /= 0) then
      print *, "❌ Failed to map shader VA"
      ! Try alternative addresses
      shader_buffer%va_addr = int(z'300000', int64)  ! 3MB
      status = amdgpu_map_va(g_context%device, shader_buffer, shader_buffer%va_addr)
      if (status /= 0) then
        shader_buffer%va_addr = int(z'400000', int64)  ! 4MB
        status = amdgpu_map_va(g_context%device, shader_buffer, shader_buffer%va_addr)
        if (status /= 0) then
          print *, "❌ Failed to map shader VA at any address"
          shader_addr = 0
          return
        end if
      end if
    end if
    
    shader_addr = shader_buffer%va_addr  ! Use the VA address
    call g_context%add_shader(name, shader_addr)
    
    print '(A,A,A,Z16)', "✅ Compiled shader: ", trim(name), " at 0x", shader_addr
    
  end function pm4_compile_shader
  
  ! Execute compute shader
  function pm4_execute_compute(shader_addr, &
                              threads_x, threads_y, threads_z, &
                              grid_x, grid_y, grid_z, &
                              buffers, num_buffers) result(time_ms)
    integer(i64), intent(in) :: shader_addr
    integer, intent(in) :: threads_x, threads_y, threads_z
    integer, intent(in) :: grid_x, grid_y, grid_z
    type(amdgpu_buffer), intent(in) :: buffers(:)
    integer, intent(in) :: num_buffers
    real(sp) :: time_ms
    
    type(pm4_packet_builder) :: builder
    type(amdgpu_buffer) :: cmd_buf
    integer(i32), allocatable :: cmd_data(:)
    integer :: status, cmd_size
    integer(i32) :: user_data(16)
    integer :: i
    real :: start_time, end_time
    
    time_ms = -1.0
    
    if (.not. g_context%initialized) then
      print *, "❌ PM4 compute not initialized"
      return
    end if
    
    ! Initialize packet builder
    call builder%init(512)
    
    ! Build user data (buffer addresses)
    user_data = 0
    do i = 1, min(num_buffers, 8)
      ! Each buffer takes 2 SGPRs (64-bit address)
      user_data(i*2-1) = int(buffers(i)%gpu_addr, int32)
      user_data(i*2) = int(shiftr(buffers(i)%gpu_addr, 32), int32)
    end do
    
    ! Build compute dispatch
    call pm4_build_compute_dispatch(builder, &
                                   shader_addr, &
                                   threads_x, threads_y, threads_z, &
                                   grid_x, grid_y, grid_z, &
                                   user_data)
    
    ! Get command buffer
    cmd_data = builder%get_buffer()
    cmd_size = builder%get_size()
    
    ! Allocate command buffer
    cmd_buf = amdgpu_allocate_buffer(g_context%device, &
                                    int(cmd_size * 4, int64), &
                                    AMDGPU_GEM_DOMAIN_GTT)
    if (cmd_buf%handle == 0) then
      print *, "❌ Failed to allocate command buffer"
      call builder%cleanup()
      return
    end if
    
    ! Map and copy commands
    block
      integer(i32), pointer :: cmd_ptr(:)
      type(c_ptr) :: mapped_ptr
      
      status = amdgpu_map_buffer(g_context%device, cmd_buf)
      if (status /= 0) then
        print *, "❌ Failed to map command buffer"
        call builder%cleanup()
        return
      end if
      
      mapped_ptr = cmd_buf%cpu_ptr
      
      call c_f_pointer(mapped_ptr, cmd_ptr, [cmd_size])
      cmd_ptr(1:cmd_size) = cmd_data(1:cmd_size)
    end block
    
    ! Map command buffer to GPU VA
    cmd_buf%va_addr = gpu_va_allocate(cmd_buf%size)
    status = amdgpu_map_va(g_context%device, cmd_buf, cmd_buf%va_addr)
    if (status /= 0) then
      print *, "❌ Failed to map command buffer VA"
      call builder%cleanup()
      return
    end if
    
    ! Create BO list with all buffers
    if (g_context%bo_list_id == 0) then
      ! TODO: Create BO list with buffers
      ! For now, we'll submit without a BO list
    end if
    
    ! Submit command buffer
    call cpu_time(start_time)
    
    ! Create a command buffer structure for submission
    block
      type(amdgpu_command_buffer) :: submit_cmd
      
      submit_cmd%ib_buffer = cmd_buf
      submit_cmd%ib_size = int(cmd_size * 4, int64)  ! Size in bytes
      submit_cmd%ctx_id = g_context%ctx_id
      submit_cmd%bo_list_handle = g_context%bo_list_id
      
      status = amdgpu_submit_command_buffer(g_context%device, submit_cmd)
      if (status /= 0) then
        print *, "❌ Command submission failed with status:", status
        call builder%cleanup()
        return
      end if
    end block
    
    ! Wait for completion
    status = amdgpu_wait_buffer_idle(g_context%device, cmd_buf)
    if (status /= 0) then
      print *, "❌ Wait failed with status:", status
      call builder%cleanup()
      return
    end if
    
    call cpu_time(end_time)
    time_ms = (end_time - start_time) * 1000.0
    
    ! Cleanup
    call builder%cleanup()
    
  end function pm4_execute_compute
  
  ! Direct PM4 convolution implementation
  function pm4_conv2d_direct(input, weights, output, &
                            N, C, H, W, K, kernel_size, stride, pad, H_out, W_out) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    real(sp) :: time_ms
    
    type(amdgpu_buffer) :: input_buf, weight_buf, output_buf
    integer :: status
    integer(i64) :: shader_addr
    integer :: grid_x, grid_y, grid_z
    type(amdgpu_buffer) :: buffers(3)
    
    time_ms = -1.0
    
    ! Compile shader if needed
    shader_addr = pm4_compile_shader("conv2d_direct", "")
    if (shader_addr == 0) then
      print *, "❌ Failed to compile conv2d shader"
      return
    end if
    
    ! Allocate buffers
    input_buf = amdgpu_allocate_buffer(g_context%device, &
                                      int(size(input) * 4, int64), &
                                      AMDGPU_GEM_DOMAIN_GTT)
    if (input_buf%handle == 0) return
    
    weight_buf = amdgpu_allocate_buffer(g_context%device, &
                                       int(size(weights) * 4, int64), &
                                       AMDGPU_GEM_DOMAIN_GTT)
    if (weight_buf%handle == 0) return
    
    output_buf = amdgpu_allocate_buffer(g_context%device, &
                                       int(size(output) * 4, int64), &
                                       AMDGPU_GEM_DOMAIN_GTT)
    if (output_buf%handle == 0) return
    
    ! Map buffers to GPU address space
    input_buf%va_addr = gpu_va_allocate(input_buf%size)
    status = amdgpu_map_va(g_context%device, input_buf, input_buf%va_addr)
    if (status /= 0) return
    
    weight_buf%va_addr = gpu_va_allocate(weight_buf%size)
    status = amdgpu_map_va(g_context%device, weight_buf, weight_buf%va_addr)
    if (status /= 0) return
    
    output_buf%va_addr = gpu_va_allocate(output_buf%size)
    status = amdgpu_map_va(g_context%device, output_buf, output_buf%va_addr)
    if (status /= 0) return
    
    ! Copy input data
    block
      real(sp), pointer :: ptr(:)
      type(c_ptr) :: mapped_ptr
      
      status = amdgpu_map_buffer(g_context%device, input_buf)
      if (status == 0) then
        call c_f_pointer(input_buf%cpu_ptr, ptr, shape(input))
        ptr = input
      end if
      
      status = amdgpu_map_buffer(g_context%device, weight_buf)
      if (status == 0) then
        call c_f_pointer(weight_buf%cpu_ptr, ptr, shape(weights))
        ptr = weights
      end if
    end block
    
    ! Calculate grid dimensions
    grid_x = (H_out * W_out + 63) / 64
    grid_y = K
    grid_z = N
    
    ! Execute
    buffers = [input_buf, weight_buf, output_buf]
    time_ms = pm4_execute_compute(shader_addr, &
                                 64, 1, 1, &  ! threads per group
                                 grid_x, grid_y, grid_z, &
                                 buffers, 3)
    
    ! Copy output data
    if (time_ms >= 0.0) then
      block
        real(sp), pointer :: ptr(:)
        type(c_ptr) :: mapped_ptr
        
        status = amdgpu_map_buffer(g_context%device, output_buf)
        if (status == 0) then
          call c_f_pointer(output_buf%cpu_ptr, ptr, shape(output))
          output = ptr
        end if
      end block
    end if
    
    ! TODO: Free buffers
    
  end function pm4_conv2d_direct
  
end module sporkle_pm4_compute