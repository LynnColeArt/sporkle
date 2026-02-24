module sporkle_execute
  use kinds
  use iso_c_binding, only: c_associated, c_f_pointer, c_loc, c_ptr, c_sizeof
  use sporkle_types
  use sporkle_memory
  use sporkle_mesh_types
  use sporkle_kernels
  use sporkle_scheduler
  use sporkle_api_v2, only: sporkle_init, sporkle_create_device, sporkle_destroy_device
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
    logical :: has_cpu_target
    logical :: has_kronos_target
    logical :: has_mixed_targets
    logical :: schedule_ok
    integer :: reason_device
    integer :: num_cpu_slots
    integer :: num_kronos_slots
    integer(i64) :: total_scheduled
    integer(i64) :: kronos_work_shards
    integer :: first_cpu_device_idx
    integer :: first_kronos_device_id
    real(sp) :: elapsed_ms
    character(len=256) :: reject_reason
    
    ! Set argument shapes from memory handles
    call kernel_set_argument_shapes(kernel)
    
    ! Validate kernel
    if (.not. kernel%validate()) then
      print *, "ERROR: Invalid kernel configuration"
      error stop "Execution blocked: invalid kernel configuration"
    end if

    if (kernel%work_items <= 0_i64) then
      print *, "ERROR: Kernel has no work items to execute"
      error stop "Execution blocked: kernel work_items must be positive"
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
    
    ! Production policy: execute on CPU unless a single explicit Kronos device is selected.
    has_cpu_target = .false.
    has_kronos_target = .false.
    has_mixed_targets = .false.
    schedule_ok = .true.
    reason_device = -1
    reject_reason = ""
    num_cpu_slots = 0
    num_kronos_slots = 0
    total_scheduled = 0_i64
    kronos_work_shards = 0_i64
    first_cpu_device_idx = -1
    first_kronos_device_id = -1
    elapsed_ms = 0.0_sp

    do i = 1, size(schedule%device_ids)
      if (schedule%device_ids(i) < 0) cycle
      device_idx = this%mesh%find_device(schedule%device_ids(i))
      if (device_idx < 1 .or. device_idx > this%mesh%num_devices) then
        schedule_ok = .false.
        reason_device = schedule%device_ids(i)
        reject_reason = "invalid mesh device index in schedule"
        exit
      end if
      
      if (.not. this%mesh%devices(device_idx)%healthy) then
        schedule_ok = .false.
        reason_device = schedule%device_ids(i)
        reject_reason = "device is marked unhealthy in the schedule"
        exit
      end if

      if (allocated(this%mesh%devices(device_idx)%caps%kind) .and. &
          trim(this%mesh%devices(device_idx)%caps%kind) == KIND_CPU) then
        has_cpu_target = .true.
        if (schedule%shards(i) > 0_i64) then
          num_cpu_slots = num_cpu_slots + 1
          total_scheduled = total_scheduled + schedule%shards(i)
          if (first_cpu_device_idx < 0) first_cpu_device_idx = device_idx
        end if
      else
        has_kronos_target = .true.
        if (schedule%shards(i) > 0_i64) then
          num_kronos_slots = num_kronos_slots + 1
          total_scheduled = total_scheduled + schedule%shards(i)
          if (first_kronos_device_id < 0) then
            first_kronos_device_id = schedule%device_ids(i)
            kronos_work_shards = schedule%shards(i)
          end if
        end if
      end if
    end do

    if (.not. schedule_ok) then
      if (.not. this%quiet_mode) then
        print *, "❌ Hard-fail: schedule integrity check failed."
        if (reason_device >= 0) print '(A,I0,A,A)', "   Device ", reason_device, " -> ", trim(reject_reason)
      end if
      error stop "Execution blocked: invalid schedule entry encountered."
    end if
    
    has_mixed_targets = has_cpu_target .and. has_kronos_target
    if (has_mixed_targets) then
      if (.not. this%quiet_mode) then
        print *, "❌ Hard-fail: mixed CPU and non-CPU scheduling is not supported in recovery mode."
        if (reason_device >= 0) print '(A,I0)', "   Rejecting schedule slot: ", reason_device
      end if
      error stop "Execution blocked: mixed CPU/non-CPU device scheduling is not supported."
    end if

    if (total_scheduled /= kernel%work_items) then
      if (.not. this%quiet_mode) then
        print *, "❌ Hard-fail: schedule shard total does not match kernel work-items."
        print '(A,I0,A,I0)', "   Scheduled shards: ", total_scheduled, " vs work-items: ", kernel%work_items
      end if
      error stop "Execution blocked: schedule and kernel work-item counts are inconsistent."
    end if

    if (has_kronos_target) then
      if (num_kronos_slots /= 1) then
        if (.not. this%quiet_mode) then
          print *, "❌ Hard-fail: Kronos execution requires one non-CPU target."
          print '(A,I0)', "   Rejected schedule shards:", num_kronos_slots
        end if
        error stop "Execution blocked: Kronos execution requires single-target scheduling."
      end if
      if (first_kronos_device_id < 0) then
        error stop "Execution blocked: failed to resolve non-CPU scheduled device."
      end if

      if (.not. this%quiet_mode) then
        print *, "🚀 Routing kernel through Kronos bridge."
      end if
      if (kronos_work_shards <= 0_i64) then
        print *, "❌ Hard-fail: Kronos schedule produced no work shards."
        error stop "Execution blocked: Kronos schedule has zero shards."
      end if
      call execute_kernel_kronos_bridge(kernel, first_kronos_device_id, kronos_work_shards, elapsed_ms, this%quiet_mode)
      if (.not. this%quiet_mode) print '(A,F0.3,A)', "   Kronos execution latency (reported): ", elapsed_ms, " ms"
      if (.not. this%quiet_mode) print *, "✓ Kernel execution complete"
      return
    end if
    
    ! For now, execute on CPU devices only and do not do partial sharding.
    if (num_cpu_slots == 0) then
      error stop "Execution blocked: no healthy CPU target was scheduled."
    end if
    if (num_cpu_slots > 1) then
      error stop "Execution blocked: multi-device CPU scheduling requires sliced execution, which is not yet implemented."
    end if
    if (total_scheduled /= kernel%work_items) then
      error stop "Execution blocked: CPU partition does not cover the expected number of work items."
    end if
    if (first_cpu_device_idx < 0) then
      error stop "Execution blocked: failed to resolve scheduled CPU device."
    end if

    call execute_kernel_cpu(kernel, 0_i64, total_scheduled)

    if (.not. this%quiet_mode) then
      print *, "✓ Kernel execution complete"
    end if
    
  end subroutine context_execute_kernel
  
  ! Execute kernel on CPU slice
  subroutine execute_kernel_cpu(kernel, offset, count)
    type(sporkle_kernel), intent(inout) :: kernel
    integer(i64), intent(in) :: offset, count
    
    ! NOTE: This path is intentionally single-slice (offset/count are telemetry-only today).
    
    if (associated(kernel%fortran_proc)) then
      ! For this recovery pass, execute the kernel with current arguments directly.
      call kernel%fortran_proc(kernel%arguments)
    end if
    
  end subroutine execute_kernel_cpu
  
  ! Execute kernel through Kronos bridge with strict metadata checks
  subroutine execute_kernel_kronos_bridge(kernel, device_id, schedule_shards, elapsed_ms, quiet_mode)
    type(sporkle_kernel), intent(inout) :: kernel
    integer, intent(in) :: device_id
    integer(i64), intent(in) :: schedule_shards
    real(sp), intent(out) :: elapsed_ms
    logical, intent(in) :: quiet_mode
    
    integer(i32) :: status
    integer(i32), target :: packed_params(8)
    integer(i32), pointer :: param_pack(:)
    integer(i32), pointer :: p_n => null()
    integer(i32), pointer :: p_c => null()
    integer(i32), pointer :: p_h => null()
    integer(i32), pointer :: p_w => null()
    integer(i32), pointer :: p_k => null()
    integer(i32), pointer :: p_kern_size => null()
    integer(i32), pointer :: p_stride => null()
    integer(i32), pointer :: p_pad => null()
    integer(i32), pointer :: p_h_out => null()
    integer(i32), pointer :: p_w_out => null()
    integer(i32) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    logical :: metadata_ok
    integer(i64) :: input_count
    integer(i64) :: weight_count
    integer(i64) :: output_count
    real(sp), parameter :: float_scale = 1.0_sp
    integer(i64) :: float_bytes
    integer(i64) :: safe_block_size
    integer(i64) :: dispatch_elements
    type(c_ptr) :: arg_input
    type(c_ptr) :: arg_weights
    type(c_ptr) :: arg_output
    type(c_ptr), allocatable :: args(:)
    integer(i32) :: grid_size(3)
    integer(i32) :: block_size(3)
    class(compute_device), allocatable :: kronos_device
    
    elapsed_ms = 0.0_sp
    metadata_ok = .false.

    if (trim(kernel%name) /= "conv2d" .and. trim(kernel%name) /= "convolution") then
      print *, "❌ Hard-fail: Kronos bridge currently supports only conv2d-like kernels."
      error stop "Execution blocked: unsupported kernel for non-CPU schedule"
    end if
    
    if (.not. allocated(kernel%arguments) .or. size(kernel%arguments) < 3) then
      print *, "❌ Hard-fail: conv2d bridge needs at least input, weight, output buffers."
      error stop "Execution blocked: invalid conv2d argument shape"
    end if

    arg_input = kernel%arguments(1)%data%ptr
    arg_weights = kernel%arguments(2)%data%ptr
    arg_output = kernel%arguments(3)%data%ptr
    if (.not. kernel%arguments(1)%data%is_allocated .or. .not. c_associated(arg_input) .or. &
        .not. kernel%arguments(2)%data%is_allocated .or. .not. c_associated(arg_weights) .or. &
        .not. kernel%arguments(3)%data%is_allocated .or. .not. c_associated(arg_output)) then
      print *, "❌ Hard-fail: conv2d requires host-visible allocated buffers for all 3 arrays."
      error stop "Execution blocked: missing conv2d data buffers"
    end if
    
    if (size(kernel%arguments) >= 4 .and. kernel%arguments(4)%data%is_allocated .and. c_associated(kernel%arguments(4)%data%ptr)) then
      if (kernel%arguments(4)%data%size >= int(8 * c_sizeof(p_n), i64)) then
        call c_f_pointer(kernel%arguments(4)%data%ptr, param_pack, [8])
        if (associated(param_pack)) then
          N = param_pack(1)
          C = param_pack(2)
          H = param_pack(3)
          W = param_pack(4)
          K = param_pack(5)
          kernel_size = param_pack(6)
          stride = param_pack(7)
          pad = param_pack(8)
          H_out = (H + 2 * pad - kernel_size) / stride + 1
          W_out = (W + 2 * pad - kernel_size) / stride + 1
          metadata_ok = .true.
        end if
      end if
    end if
    
    if (.not. metadata_ok .and. size(kernel%arguments) >= 13 .and. &
        kernel%arguments(4)%data%is_allocated .and. c_associated(kernel%arguments(4)%data%ptr) .and. &
        kernel%arguments(5)%data%is_allocated .and. c_associated(kernel%arguments(5)%data%ptr) .and. &
        kernel%arguments(6)%data%is_allocated .and. c_associated(kernel%arguments(6)%data%ptr) .and. &
        kernel%arguments(7)%data%is_allocated .and. c_associated(kernel%arguments(7)%data%ptr) .and. &
        kernel%arguments(8)%data%is_allocated .and. c_associated(kernel%arguments(8)%data%ptr) .and. &
        kernel%arguments(9)%data%is_allocated .and. c_associated(kernel%arguments(9)%data%ptr) .and. &
        kernel%arguments(10)%data%is_allocated .and. c_associated(kernel%arguments(10)%data%ptr) .and. &
        kernel%arguments(11)%data%is_allocated .and. c_associated(kernel%arguments(11)%data%ptr) .and. &
        kernel%arguments(12)%data%is_allocated .and. c_associated(kernel%arguments(12)%data%ptr) .and. &
        kernel%arguments(13)%data%is_allocated .and. c_associated(kernel%arguments(13)%data%ptr)) then
      call c_f_pointer(kernel%arguments(4)%data%ptr, p_n)
      call c_f_pointer(kernel%arguments(5)%data%ptr, p_c)
      call c_f_pointer(kernel%arguments(6)%data%ptr, p_h)
      call c_f_pointer(kernel%arguments(7)%data%ptr, p_w)
      call c_f_pointer(kernel%arguments(8)%data%ptr, p_k)
      call c_f_pointer(kernel%arguments(9)%data%ptr, p_kern_size)
      call c_f_pointer(kernel%arguments(10)%data%ptr, p_stride)
      call c_f_pointer(kernel%arguments(11)%data%ptr, p_pad)
      call c_f_pointer(kernel%arguments(12)%data%ptr, p_h_out)
      call c_f_pointer(kernel%arguments(13)%data%ptr, p_w_out)

      if (associated(p_n) .and. associated(p_c) .and. associated(p_h) .and. associated(p_w) .and. associated(p_k) .and. &
          associated(p_kern_size) .and. associated(p_stride) .and. associated(p_pad) .and. associated(p_h_out) .and. &
          associated(p_w_out)) then
        N = p_n
        C = p_c
        H = p_h
        W = p_w
        K = p_k
        kernel_size = p_kern_size
        stride = p_stride
        pad = p_pad
        H_out = p_h_out
        W_out = p_w_out
        metadata_ok = .true.
      end if
    end if
    
    if (.not. metadata_ok) then
      print *, "❌ Hard-fail: conv2d launch metadata missing or malformed."
      error stop "Execution blocked: unsupported conv2d launch metadata"
    end if
    
    if (N <= 0 .or. C <= 0 .or. H <= 0 .or. W <= 0 .or. K <= 0 .or. kernel_size <= 0 .or. stride <= 0) then
      print *, "❌ Hard-fail: invalid conv2d dimensions."
      error stop "Execution blocked: invalid conv2d dimensions"
    end if

    if (mod(H + 2 * pad - kernel_size, stride) /= 0 .or. mod(W + 2 * pad - kernel_size, stride) /= 0) then
      print *, "❌ Hard-fail: conv2d output geometry is not an integer grid for given stride/pad."
      error stop "Execution blocked: conv2d geometry invalid"
    end if

    H_out = (H + 2 * pad - kernel_size) / stride + 1
    W_out = (W + 2 * pad - kernel_size) / stride + 1
    if (H_out <= 0 .or. W_out <= 0) then
      print *, "❌ Hard-fail: computed conv2d output dimensions are invalid."
      error stop "Execution blocked: conv2d output dimensions invalid"
    end if
    
    input_count = int(N, i64) * int(C, i64) * int(H, i64) * int(W, i64)
    weight_count = int(K, i64) * int(C, i64) * int(kernel_size, i64) * int(kernel_size, i64)
    output_count = int(N, i64) * int(K, i64) * int(H_out, i64) * int(W_out, i64)
    float_bytes = int(c_sizeof(float_scale), i64)

    if (kernel%arguments(1)%data%size /= input_count * float_bytes .or. &
        kernel%arguments(2)%data%size /= weight_count * float_bytes .or. &
        kernel%arguments(3)%data%size /= output_count * float_bytes) then
      print *, "❌ Hard-fail: tensor buffer sizes do not match decoded metadata."
      print *, "   Expected input bytes:", input_count * float_bytes
      print *, "   Expected weight bytes:", weight_count * float_bytes
      print *, "   Expected output bytes:", output_count * float_bytes
      error stop "Execution blocked: conv2d metadata does not match buffer sizes"
    end if
    
    packed_params = [N, C, H, W, K, kernel_size, stride, pad]
    allocate(args(4))
    args(1) = arg_input
    args(2) = arg_weights
    args(3) = arg_output
    args(4) = c_loc(packed_params)

    safe_block_size = kernel%block_size
    if (safe_block_size < 1_i64) safe_block_size = 1_i64
    if (safe_block_size > int(huge(block_size(1)), i64)) then
      print *, "❌ Hard-fail: kernel block size exceeds supported backend range."
      error stop "Execution blocked: block size overflow"
    end if
    if (safe_block_size > 1024_i64) then
      print *, "❌ Hard-fail: kernel block size exceeds conservative backend limit of 1024."
      error stop "Execution blocked: kernel block size exceeds backend limit"
    end if
    block_size = [int(safe_block_size, i32), 1_i32, 1_i32]
    dispatch_elements = output_count
    if (schedule_shards > 0_i64) dispatch_elements = schedule_shards
    if (dispatch_elements <= 0_i64) then
      print *, "❌ Hard-fail: no dispatch elements resolved for Kronos bridge."
      error stop "Execution blocked: dispatch size is not positive"
    end if
    grid_size = [max(1_i32, int((dispatch_elements + safe_block_size - 1_i64) / safe_block_size, i32)), 1_i32, 1_i32]
    
    call sporkle_init()
    kronos_device = sporkle_create_device(device_id)
    status = kronos_device%execute("conv2d", args, grid_size, block_size)
    if (status /= SPORKLE_SUCCESS) then
      call sporkle_destroy_device(kronos_device)
      error stop "Execution blocked: Kronos bridge execute returned non-success"
    end if
    status = kronos_device%synchronize()
    if (status /= SPORKLE_SUCCESS) then
      call sporkle_destroy_device(kronos_device)
      error stop "Execution blocked: Kronos bridge synchronize returned non-success"
    end if
    call sporkle_destroy_device(kronos_device)

    elapsed_ms = 0.0_sp
    if (.not. quiet_mode) print *, "✅ Conv2D dispatch accepted by Kronos bridge."
    
  end subroutine execute_kernel_kronos_bridge
  
end module sporkle_execute
