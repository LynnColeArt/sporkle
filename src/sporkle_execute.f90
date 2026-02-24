module sporkle_execute
  use kinds
  use sporkle_types
  use sporkle_memory
  use sporkle_mesh_types
  use sporkle_kernels
  use sporkle_scheduler
  implicit none
  private
  
  public :: sporkle_run, sporkle_run_async, sporkle_run_quiet
  public :: execution_context, create_context
  
  type :: execution_context
    type(mesh_topology), pointer :: mesh => null()
    logical :: async_mode = .false.
    logical :: quiet_mode = .false.  ! Suppress output during benchmarks
    integer :: preferred_device = -1  ! -1 means auto-select
  contains
    procedure :: execute => context_execute_kernel
  end type execution_context
  
contains

  ! Create execution context
  function create_context(mesh) result(ctx)
    type(mesh_topology), target, intent(in) :: mesh
    type(execution_context) :: ctx
    
    ctx%mesh => mesh
    ctx%async_mode = .false.
    ctx%preferred_device = -1
    
  end function create_context
  
  ! Simple synchronous execution
  subroutine sporkle_run(kernel, mesh)
    type(sporkle_kernel), intent(inout) :: kernel
    type(mesh_topology), intent(inout) :: mesh
    
    type(execution_context) :: ctx
    
    ctx = create_context(mesh)
    call ctx%execute(kernel)
    
  end subroutine sporkle_run
  
  ! Asynchronous execution (returns immediately)
  subroutine sporkle_run_async(kernel, mesh)
    type(sporkle_kernel), intent(inout) :: kernel
    type(mesh_topology), intent(inout) :: mesh
    
    type(execution_context) :: ctx
    
    ctx = create_context(mesh)
    ctx%async_mode = .true.
    call ctx%execute(kernel)
    
  end subroutine sporkle_run_async
  
  ! Quiet execution (for benchmarking)
  subroutine sporkle_run_quiet(kernel, mesh)
    type(sporkle_kernel), intent(inout) :: kernel
    type(mesh_topology), intent(inout) :: mesh
    
    type(execution_context) :: ctx
    
    ctx = create_context(mesh)
    ctx%quiet_mode = .true.
    call ctx%execute(kernel)
    
  end subroutine sporkle_run_quiet
  
  ! Main execution logic
  subroutine context_execute_kernel(this, kernel)
    class(execution_context), intent(inout) :: this
    type(sporkle_kernel), intent(inout) :: kernel
    
    type(schedule_choice) :: schedule
    integer :: i, device_idx
    integer(i64) :: offset, chunk_size
    logical :: has_gpu_target
    
    ! Set argument shapes from memory handles
    call kernel_set_argument_shapes(kernel)
    
    ! Validate kernel
    if (.not. kernel%validate()) then
      print *, "ERROR: Invalid kernel configuration"
      return
    end if
    
    ! Get execution plan
    schedule = plan_shards(this%mesh, kernel%work_items, "compute")
    
    if (.not. this%quiet_mode) then
      print '(A,A,A)', "🚀 Executing kernel '", kernel%name, "'"
      print '(A,I0,A)', "   Distributing ", kernel%work_items, " work items"
    end if
    
    ! Check if we can run on GPU
    if (.not. this%quiet_mode) then
      print *, "   NOTE: GPU execution uses hard-fail policy when enabled devices are scheduled."
    end if
    
    ! Production policy: execute only on CPU until the GPU Kronos-native path is explicitly re-enabled.
    has_gpu_target = .false.
    do i = 1, size(schedule%device_ids)
      device_idx = schedule%device_ids(i) + 1  ! Convert to 1-based
      if (device_idx > this%mesh%num_devices) then
        has_gpu_target = .true.
        exit
      end if
      
      if (this%mesh%devices(device_idx)%caps%kind /= KIND_CPU) then
        has_gpu_target = .true.
        exit
      end if
    end do
    
    if (has_gpu_target) then
      if (.not. this%quiet_mode) then
        print *, "❌ Hard-fail: GPU scheduling detected while GPU execution is not active."
        print *, "   Update device routing for Kronos-native dispatch before retrying."
      end if
      error stop "GPU execution path is not active in this recovery build. Enable Kronos dispatch integration."
    end if
    
    ! For now, execute on CPU devices only
    offset = 0
    do i = 1, size(schedule%device_ids)
      device_idx = schedule%device_ids(i) + 1  ! Convert to 1-based
      chunk_size = schedule%shards(i)
      
      if (device_idx <= this%mesh%num_devices) then
        if (this%mesh%devices(device_idx)%caps%kind == KIND_CPU) then
          ! Execute on CPU
          call execute_kernel_cpu(kernel, offset, chunk_size)
        end if
      end if
      
      offset = offset + chunk_size
    end do
    
    if (.not. this%quiet_mode) then
      print *, "✓ Kernel execution complete"
    end if
    
  end subroutine context_execute_kernel
  
  ! Execute kernel on CPU slice
  subroutine execute_kernel_cpu(kernel, offset, count)
    type(sporkle_kernel), intent(inout) :: kernel
    integer(i64), intent(in) :: offset, count
    
    ! For now, we'll create a simple wrapper that calls the Fortran procedure
    ! In a real implementation, this would:
    ! 1. Set up argument slices based on offset/count
    ! 2. Call the Fortran procedure
    ! 3. Handle any necessary synchronization
    
    if (associated(kernel%fortran_proc)) then
      ! For this recovery pass, execute the kernel with current arguments directly.
      ! TODO: add deterministic slicing by offset/count before enabling multi-device execution.
      call kernel%fortran_proc(kernel%arguments)
    end if
    
  end subroutine execute_kernel_cpu
  
end module sporkle_execute
