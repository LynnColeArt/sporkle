module sporkle_scheduler
  use sporkle_mesh_types
  use kinds
  implicit none
  private
  
  public :: plan_shards, explain_schedule, estimate_runtime
  
  ! Cost model parameters (tunable)
  real(rk64), parameter :: TRANSFER_OVERHEAD = 0.1_rk64  ! 10% overhead
  real(rk64), parameter :: SYNC_COST_US = 100.0_rk64    ! Synchronization cost
  
contains

  ! Plan how to shard work across devices
  function plan_shards(mesh, work_size, work_type) result(choice)
    type(mesh_topology), intent(in) :: mesh
    integer(i64), intent(in) :: work_size  ! Total work (e.g., matrix elements)
    character(len=*), intent(in), optional :: work_type
    type(schedule_choice) :: choice
    
    real(rk64), allocatable :: device_scores(:)
    real(rk64) :: total_compute_power, work_per_gflop
    integer :: i, num_healthy
    character(len=32) :: wtype
    
    wtype = "gemm"  ! Default work type
    if (present(work_type)) wtype = work_type
    
    ! Count healthy devices
    num_healthy = 0
    do i = 1, mesh%num_devices
      if (mesh%devices(i)%healthy) num_healthy = num_healthy + 1
    end do
    
    if (num_healthy == 0) then
      choice%rationale = "No healthy devices available!"
      return
    end if
    
    ! Allocate arrays
    allocate(device_scores(mesh%num_devices))
    allocate(choice%device_ids(num_healthy))
    allocate(choice%shards(num_healthy))
    choice%device_ids = -1
    choice%shards = 0
    
    ! Calculate device scores (higher = better)
    total_compute_power = 0.0_rk64
    do i = 1, mesh%num_devices
      if (mesh%devices(i)%healthy) then
        ! Score based on compute capability and current load
        device_scores(i) = mesh%devices(i)%caps%peak_gflops * &
                          (1.0_rk64 - real(mesh%devices(i)%load, rk64))
        
        ! Penalty for non-unified memory devices (need transfers)
        if (.not. mesh%devices(i)%caps%unified_mem) then
          device_scores(i) = device_scores(i) * 0.8_rk64
        end if
        
        total_compute_power = total_compute_power + device_scores(i)
      else
        device_scores(i) = 0.0_rk64
      end if
    end do
    
    ! Distribute work proportionally to scores
    if (total_compute_power > 0.0_rk64) then
      num_healthy = 0
      do i = 1, mesh%num_devices
        if (device_scores(i) > 0.0_rk64) then
          num_healthy = num_healthy + 1
          choice%device_ids(num_healthy) = mesh%devices(i)%id
          
          ! Calculate shard size proportional to device capability
          choice%shards(num_healthy) = int(work_size * &
                                      (device_scores(i) / total_compute_power), int32)
        end if
      end do
      
      ! Ensure all work is assigned (handle rounding)
      choice%shards(num_healthy) = choice%shards(num_healthy) + &
                                  (work_size - sum(choice%shards))
    else
      ! Fallback: if all computed scores are zero or unavailable, route to first healthy device.
      do i = 1, mesh%num_devices
        if (mesh%devices(i)%healthy) then
          choice%device_ids(1) = mesh%devices(i)%id
          choice%shards(1) = work_size
          num_healthy = 1
          exit
        end if
      end do
    end if
    
    ! Estimate runtime
    choice%est_ms = estimate_runtime(mesh, choice, work_type)
    
    ! Build rationale
    allocate(character(len=200) :: choice%rationale)
    write(choice%rationale, '(A,I0,A,F0.1,A)') &
      "Distributed work across ", num_healthy, &
      " devices. Estimated runtime: ", choice%est_ms, " ms"
    
  end function plan_shards
  
  ! Estimate runtime for a given schedule
  function estimate_runtime(mesh, choice, work_type) result(time_ms)
    type(mesh_topology), intent(in) :: mesh
    type(schedule_choice), intent(in) :: choice
    character(len=*), intent(in), optional :: work_type
    real(rk64) :: time_ms
    
    real(rk64) :: max_compute_time, transfer_time
    real(rk64) :: flops_per_element
    integer :: i, dev_idx
    
    ! Estimate FLOPS per work element
    if (present(work_type) .and. work_type == "gemm") then
      flops_per_element = 2.0_rk64  ! 2N^3 for NxN GEMM
    else
      flops_per_element = 1.0_rk64  ! Generic
    end if
    
    max_compute_time = 0.0_rk64
    transfer_time = 0.0_rk64
    
    ! Find slowest device (determines overall runtime)
    do i = 1, size(choice%device_ids)
      if (choice%device_ids(i) < 0) cycle
      dev_idx = mesh%find_device(choice%device_ids(i))
      if (dev_idx > 0) then
        associate(dev => mesh%devices(dev_idx))
          block
            ! Compute time for this device's shard
            real(rk64) :: device_time
            real(rk64) :: bytes_to_transfer
            
            device_time = (choice%shards(i) * flops_per_element) / &
                         (dev%caps%sustained_gflops * 1.0e9_rk64) * 1000.0_rk64  ! Convert to ms
            
            ! Add transfer overhead if not unified memory
            if (.not. dev%caps%unified_mem) then
              ! Assume we need to transfer the shard size in bytes
              bytes_to_transfer = choice%shards(i) * 8_rk64  ! 8 bytes per float64
              transfer_time = transfer_time + &
                            (bytes_to_transfer / (dev%caps%mem_bw_gbs * 1.0e9_rk64)) * &
                            1000.0_rk64 * (1.0_rk64 + TRANSFER_OVERHEAD)
            end if
            
            max_compute_time = max(max_compute_time, device_time)
          end block
        end associate
      end if
    end do
    
    ! Total time = compute + transfer + sync overhead
    time_ms = max_compute_time + transfer_time + SYNC_COST_US / 1000.0_rk64
    
  end function estimate_runtime
  
  ! Explain scheduling decision (introspection)
  subroutine explain_schedule(mesh, choice)
    type(mesh_topology), intent(in) :: mesh
    type(schedule_choice), intent(in) :: choice
    integer :: i, dev_idx
    real(rk64) :: total_work
    
    print *, "=== Sporkle Schedule Explanation ==="
    print '(A,A)', "Rationale: ", choice%rationale
    print *, ""
    
    if (allocated(choice%shards)) then
      total_work = real(sum(choice%shards), rk64)
      
      print *, "Work distribution:"
      do i = 1, size(choice%device_ids)
        if (choice%device_ids(i) < 0) cycle
        dev_idx = mesh%find_device(choice%device_ids(i))
        if (dev_idx > 0) then
          associate(dev => mesh%devices(dev_idx))
            print '(A,I0,A,A,A)', "  Device ", dev%id, " (", dev%caps%kind, "):"
            print '(A,I0,A,F0.1,A)', "    Shard size: ", choice%shards(i), &
                                     " (", 100.0 * choice%shards(i) / total_work, "%)"
            print '(A,F0.1,A)', "    Capability: ", dev%caps%peak_gflops, " GFLOPS"
            print '(A,F0.1,A)', "    Current load: ", dev%load * 100.0, "%"
          end associate
        end if
      end do
      
      print *, ""
      print '(A,F0.1,A)', "Estimated runtime: ", choice%est_ms, " ms"
    else
      print *, "No devices scheduled!"
    end if
    print *, ""
    
  end subroutine explain_schedule
  
end module sporkle_scheduler
