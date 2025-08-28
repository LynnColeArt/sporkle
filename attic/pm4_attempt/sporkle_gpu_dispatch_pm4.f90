module sporkle_gpu_dispatch_pm4
  ! PM4-based GPU dispatch - Real GPU execution via direct kernel interface
  ! No OpenGL, no Mesa, just pure PM4 packets to the kernel driver
  
  use kinds
  use iso_c_binding
  use sporkle_types
  use sporkle_amdgpu_direct
  use sporkle_pm4_compute
  use sporkle_gpu_va_allocator
  implicit none
  private
  
  public :: gpu_device_pm4, gpu_memory_pm4
  public :: init_gpu_pm4, cleanup_gpu_pm4
  public :: gpu_malloc_pm4, gpu_free_pm4
  public :: gpu_execute_compute_pm4
  
  ! Global PM4 context
  type(pm4_context), save :: g_pm4_ctx
  logical, save :: g_initialized = .false.
  
  type :: gpu_device_pm4
    integer :: device_id = 0
    type(amdgpu_device_handle) :: device
    character(len=256) :: name = "AMD GPU (PM4)"
    logical :: initialized = .false.
  end type gpu_device_pm4
  
  type :: gpu_memory_pm4
    type(amdgpu_buffer) :: buffer
    integer(i64) :: size_bytes = 0
    logical :: allocated = .false.
  end type gpu_memory_pm4
  
contains

  function init_gpu_pm4() result(device)
    type(gpu_device_pm4) :: device
    integer :: status
    
    if (g_initialized) then
      device%initialized = .true.
      return
    end if
    
    ! Initialize PM4 context
    status = pm4_init_context(g_pm4_ctx)
    if (status /= 0) then
      print *, "❌ Failed to initialize PM4 context"
      device%initialized = .false.
      return
    end if
    
    device%device_id = 0
    device%device = g_pm4_ctx%device
    device%name = "AMD GPU (PM4 Direct)"
    device%initialized = .true.
    g_initialized = .true.
    
    print *, "✅ PM4 GPU initialized"
    
  end function init_gpu_pm4
  
  subroutine cleanup_gpu_pm4()
    if (g_initialized) then
      call pm4_cleanup_context(g_pm4_ctx)
      g_initialized = .false.
    end if
  end subroutine cleanup_gpu_pm4

  function gpu_malloc_pm4(size_bytes) result(mem)
    integer(i64), intent(in) :: size_bytes
    type(gpu_memory_pm4) :: mem
    
    if (.not. g_initialized) then
      print *, "❌ GPU not initialized"
      mem%allocated = .false.
      return
    end if
    
    ! Allocate GPU buffer in GTT (system memory visible to GPU)
    mem%buffer = amdgpu_allocate_buffer(g_pm4_ctx%device, size_bytes, AMDGPU_GEM_DOMAIN_GTT)
    
    if (mem%buffer%handle == 0) then
      print *, "❌ Failed to allocate GPU buffer"
      mem%allocated = .false.
      return
    end if
    
    ! Map to GPU VA if not already mapped
    if (mem%buffer%va_addr == 0) then
      ! Allocate VA space
      mem%buffer%va_addr = allocate_gpu_va(size_bytes)
      
      ! Map buffer to VA
      if (amdgpu_map_va(g_pm4_ctx%device, mem%buffer, mem%buffer%va_addr) /= 0) then
        print *, "❌ Failed to map GPU VA"
        mem%allocated = .false.
        return
      end if
    end if
    
    ! Map for CPU access
    if (amdgpu_map_buffer(g_pm4_ctx%device, mem%buffer) /= 0) then
      print *, "❌ Failed to map buffer for CPU access"
      mem%allocated = .false.
      return
    end if
    
    mem%size_bytes = size_bytes
    mem%allocated = .true.
    
    print '(A,F0.2,A,Z16)', "✅ Allocated ", real(size_bytes) / (1024.0**2), " MB at VA 0x", mem%buffer%va_addr
    
  end function gpu_malloc_pm4
  
  subroutine gpu_free_pm4(mem)
    type(gpu_memory_pm4), intent(inout) :: mem
    
    if (mem%allocated .and. mem%buffer%handle /= 0) then
      ! TODO: Implement buffer cleanup
      ! - Unmap VA
      ! - Free buffer handle
      ! - Release VA allocation
      
      mem%allocated = .false.
      mem%buffer%handle = 0
      mem%buffer%va_addr = 0
      mem%size_bytes = 0
    end if
    
  end subroutine gpu_free_pm4
  
  function gpu_execute_compute_pm4(shader_name, buffers, num_buffers, &
                                  workgroups_x, workgroups_y, workgroups_z) result(status)
    character(len=*), intent(in) :: shader_name
    type(gpu_memory_pm4), intent(in) :: buffers(:)
    integer, intent(in) :: num_buffers
    integer, intent(in) :: workgroups_x, workgroups_y, workgroups_z
    integer :: status
    
    integer(i64) :: shader_addr
    type(amdgpu_buffer), allocatable :: data_buffers(:)
    integer :: i
    
    if (.not. g_initialized) then
      print *, "❌ GPU not initialized"
      status = -1
      return
    end if
    
    ! Compile shader
    shader_addr = pm4_compile_shader(shader_name, "")
    if (shader_addr == 0) then
      print *, "❌ Failed to compile shader"
      status = -1
      return
    end if
    
    ! Prepare buffer list
    allocate(data_buffers(num_buffers))
    do i = 1, num_buffers
      data_buffers(i) = buffers(i)%buffer
    end do
    
    ! Execute compute shader
    status = pm4_execute_compute(g_pm4_ctx, shader_addr, data_buffers, &
                                workgroups_x, workgroups_y, workgroups_z)
    
    if (status == 0) then
      print '(A,A,A,I0,A,I0,A,I0,A)', "✅ Executed ", trim(shader_name), &
            " with workgroups (", workgroups_x, ",", workgroups_y, ",", workgroups_z, ")"
    else
      print *, "❌ Compute execution failed"
    end if
    
    deallocate(data_buffers)
    
  end function gpu_execute_compute_pm4

end module sporkle_gpu_dispatch_pm4