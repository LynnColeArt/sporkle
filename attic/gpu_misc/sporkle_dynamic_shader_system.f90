module sporkle_dynamic_shader_system
  use iso_c_binding
  use sporkle_types
  use sporkle_glsl_generator
  use sporkle_rdna_shader_generator
  implicit none
  
  private
  public :: shader_system, init_shader_system, get_optimal_shader
  public :: gpu_architecture, detect_gpu_architecture
  public :: update_performance_system, find_in_cache_system
  
  ! GPU architecture information
  type :: gpu_architecture
    character(len=32) :: vendor          ! AMD, NVIDIA, Intel
    character(len=32) :: arch_name       ! GCN, RDNA1, RDNA2, RDNA3, etc
    integer :: wave_size                 ! 32 or 64
    integer :: compute_units             ! Number of CUs/SMs
    integer :: max_workgroup_size        ! Maximum threads per workgroup
    integer :: local_memory_size         ! LDS/shared memory size
    logical :: has_dual_issue            ! RDNA3 feature
    logical :: has_tensor_cores          ! NVIDIA feature
    integer :: cache_line_size           ! Usually 64 or 128 bytes
    real :: measured_bandwidth_gbps      ! Empirically measured
    real :: measured_tflops              ! Empirically measured
  end type gpu_architecture
  
  ! Shader variant with performance data
  type :: shader_variant
    character(len=:), allocatable :: source_code
    character(len=64) :: variant_id
    integer :: workgroup_size
    integer :: waves_per_workgroup
    logical :: uses_local_memory
    logical :: uses_dual_issue
    real :: performance_gflops
    integer :: test_runs
    real :: avg_execution_time_ms
  end type shader_variant
  
  ! Shader cache entry
  type :: shader_cache_entry
    character(len=64) :: kernel_type     ! conv2d, gemm, etc
    type(gpu_architecture) :: arch
    type(shader_variant), allocatable :: variants(:)
    integer :: best_variant_idx
    logical :: is_learning
    integer :: total_executions
  end type shader_cache_entry
  
  ! Main shader system
  type :: shader_system
    type(shader_cache_entry), allocatable :: cache(:)
    integer :: cache_size
    type(gpu_architecture) :: current_arch
    logical :: initialized = .false.
    logical :: auto_tune = .true.
    real :: exploration_rate = 0.1      ! 10% chance to try new variant
    character(len=256) :: cache_dir = "shader_cache/"
  contains
    procedure :: add_to_cache
    procedure :: find_in_cache
    procedure :: update_performance
    procedure :: save_cache
    procedure :: load_cache
  end type shader_system
  
contains

  ! Initialize the dynamic shader system
  subroutine init_shader_system(system, device_id)
    type(shader_system), intent(out) :: system
    integer, intent(in) :: device_id
    
    ! Detect GPU architecture
    system%current_arch = detect_gpu_architecture(device_id)
    
    ! Initialize cache
    allocate(system%cache(100))  ! Start with space for 100 kernel types
    system%cache_size = 0
    
    ! Try to load existing cache
    call system%load_cache()
    
    system%initialized = .true.
    
    print *, "=== Dynamic Shader System Initialized ==="
    print *, "GPU Vendor: ", trim(system%current_arch%vendor)
    print *, "Architecture: ", trim(system%current_arch%arch_name)
    print *, "Wave Size: ", system%current_arch%wave_size
    print *, "Compute Units: ", system%current_arch%compute_units
    print *, ""
    
  end subroutine init_shader_system
  
  ! Detect GPU architecture from device
  function detect_gpu_architecture(device_id) result(arch)
    integer, intent(in) :: device_id
    type(gpu_architecture) :: arch
    
    ! For now, hardcode for our test system
    ! In production, query actual device properties
    if (device_id == 0) then
      ! AMD RX 7900 XT
      arch%vendor = "AMD"
      arch%arch_name = "RDNA3"
      arch%wave_size = 32
      arch%compute_units = 84
      arch%max_workgroup_size = 1024
      arch%local_memory_size = 65536
      arch%has_dual_issue = .true.
      arch%has_tensor_cores = .false.
      arch%cache_line_size = 128
      arch%measured_bandwidth_gbps = 800.0
      arch%measured_tflops = 51.0
    else
      ! Default/unknown
      arch%vendor = "Unknown"
      arch%arch_name = "Generic"
      arch%wave_size = 64
      arch%compute_units = 32
      arch%max_workgroup_size = 1024
      arch%local_memory_size = 49152
      arch%has_dual_issue = .false.
      arch%has_tensor_cores = .false.
      arch%cache_line_size = 64
      arch%measured_bandwidth_gbps = 100.0
      arch%measured_tflops = 1.0
    end if
    
  end function detect_gpu_architecture
  
  ! Get optimal shader for given kernel and parameters
  function get_optimal_shader(system, kernel_type, params) result(shader_source)
    type(shader_system), intent(inout) :: system
    character(len=*), intent(in) :: kernel_type
    type(convolution_config), intent(in) :: params
    character(len=:), allocatable :: shader_source
    
    integer :: cache_idx
    type(shader_variant), allocatable :: new_variants(:)
    real :: rand_val
    integer :: selected_variant
    
    if (.not. system%initialized) then
      print *, "ERROR: Shader system not initialized!"
      shader_source = ""
      return
    end if
    
    ! Find or create cache entry
    cache_idx = system%find_in_cache(kernel_type)
    if (cache_idx == 0) then
      ! New kernel type - generate variants
      call system%add_to_cache(kernel_type, params)
      cache_idx = system%cache_size
    end if
    
    ! Decide whether to explore or exploit
    call random_number(rand_val)
    
    if (system%auto_tune .and. rand_val < system%exploration_rate) then
      ! Exploration: try a random variant
      selected_variant = 1 + mod(int(rand_val * 1000), size(system%cache(cache_idx)%variants))
      system%cache(cache_idx)%is_learning = .true.
    else
      ! Exploitation: use best known variant
      selected_variant = system%cache(cache_idx)%best_variant_idx
    end if
    
    ! Return the selected shader
    shader_source = system%cache(cache_idx)%variants(selected_variant)%source_code
    
  end function get_optimal_shader
  
  ! Add new kernel type to cache with generated variants
  subroutine add_to_cache(system, kernel_type, params)
    class(shader_system), intent(inout) :: system
    character(len=*), intent(in) :: kernel_type
    type(convolution_config), intent(in) :: params
    
    integer :: n_variants, i
    type(shader_cache_entry) :: new_entry
    type(rdna_config) :: rdna_cfg
    
    system%cache_size = system%cache_size + 1
    new_entry%kernel_type = kernel_type
    new_entry%arch = system%current_arch
    new_entry%total_executions = 0
    new_entry%is_learning = .true.
    
    ! Generate variants based on architecture
    select case (trim(system%current_arch%arch_name))
    case ("RDNA3", "RDNA2", "RDNA1")
      ! Generate RDNA-optimized variants
      n_variants = 4
      allocate(new_entry%variants(n_variants))
      
      ! Variant 1: Basic Wave32-aligned (64 threads = 2 waves)
      rdna_cfg%arch%wave_size = 32
      rdna_cfg%workgroup_size = 64
      rdna_cfg%use_lds = .false.
      rdna_cfg%use_dual_issue = .false.
      new_entry%variants(1)%source_code = generate_rdna_conv_shader(rdna_cfg, params)
      new_entry%variants(1)%variant_id = "rdna_basic_64"
      new_entry%variants(1)%workgroup_size = 64
      new_entry%variants(1)%waves_per_workgroup = 2
      
      ! Variant 2: Larger workgroup (256 threads = 8 waves)
      rdna_cfg%workgroup_size = 256
      new_entry%variants(2)%source_code = generate_rdna_conv_shader(rdna_cfg, params)
      new_entry%variants(2)%variant_id = "rdna_large_256"
      new_entry%variants(2)%workgroup_size = 256
      new_entry%variants(2)%waves_per_workgroup = 8
      
      ! Variant 3: LDS-optimized
      rdna_cfg%workgroup_size = 64
      rdna_cfg%use_lds = .true.
      new_entry%variants(3)%source_code = generate_rdna_conv_shader(rdna_cfg, params)
      new_entry%variants(3)%variant_id = "rdna_lds_64"
      new_entry%variants(3)%workgroup_size = 64
      new_entry%variants(3)%uses_local_memory = .true.
      
      ! Variant 4: Dual-issue optimized (RDNA3 only)
      if (system%current_arch%has_dual_issue) then
        rdna_cfg%use_dual_issue = .true.
        new_entry%variants(4)%source_code = generate_rdna_conv_shader(rdna_cfg, params)
        new_entry%variants(4)%variant_id = "rdna3_dual_issue"
        new_entry%variants(4)%uses_dual_issue = .true.
      else
        new_entry%variants(4) = new_entry%variants(1)  ! Fallback
      end if
      
    case default
      ! Generic/GCN variants
      n_variants = 2
      allocate(new_entry%variants(n_variants))
      
      ! Use original GLSL generator for generic
      new_entry%variants(1)%source_code = generate_conv_glsl_shader(params)
      new_entry%variants(1)%variant_id = "generic_256"
      new_entry%variants(1)%workgroup_size = 256
      
      ! Smaller workgroup variant
      block
        type(convolution_config) :: small_params
        small_params = params
        small_params%tile_size = 8
        new_entry%variants(2)%source_code = generate_conv_glsl_shader(small_params)
        new_entry%variants(2)%variant_id = "generic_64"
        new_entry%variants(2)%workgroup_size = 64
      end block
    end select
    
    ! Initialize performance metrics
    do i = 1, n_variants
      new_entry%variants(i)%performance_gflops = 0.0
      new_entry%variants(i)%test_runs = 0
      new_entry%variants(i)%avg_execution_time_ms = 0.0
    end do
    
    new_entry%best_variant_idx = 1  ! Start with first variant
    
    system%cache(system%cache_size) = new_entry
    
  end subroutine add_to_cache
  
  ! Find kernel in cache
  function find_in_cache(system, kernel_type) result(idx)
    class(shader_system), intent(in) :: system
    character(len=*), intent(in) :: kernel_type
    integer :: idx
    
    integer :: i
    
    idx = 0
    do i = 1, system%cache_size
      if (trim(system%cache(i)%kernel_type) == trim(kernel_type)) then
        idx = i
        return
      end if
    end do
    
  end function find_in_cache
  
  ! Find kernel in cache (standalone function)
  function find_in_cache_system(system, kernel_type) result(idx)
    type(shader_system), intent(in) :: system
    character(len=*), intent(in) :: kernel_type
    integer :: idx
    
    idx = system%find_in_cache(kernel_type)
  end function find_in_cache_system
  
  ! Update performance data after execution (standalone)
  subroutine update_performance_system(system, kernel_type, variant_id, execution_time_ms, problem_size)
    type(shader_system), intent(inout) :: system
    character(len=*), intent(in) :: kernel_type
    character(len=*), intent(in) :: variant_id
    real, intent(in) :: execution_time_ms
    integer, intent(in) :: problem_size
    
    call system%update_performance(kernel_type, variant_id, execution_time_ms, problem_size)
  end subroutine update_performance_system
  
  ! Update performance data after execution
  subroutine update_performance(system, kernel_type, variant_id, execution_time_ms, problem_size)
    class(shader_system), intent(inout) :: system
    character(len=*), intent(in) :: kernel_type
    character(len=*), intent(in) :: variant_id
    real, intent(in) :: execution_time_ms
    integer, intent(in) :: problem_size
    
    integer :: cache_idx, var_idx, i
    real :: gflops
    
    ! Find cache entry
    cache_idx = system%find_in_cache(kernel_type)
    if (cache_idx == 0) return
    
    ! Find variant
    var_idx = 0
    do i = 1, size(system%cache(cache_idx)%variants)
      if (trim(system%cache(cache_idx)%variants(i)%variant_id) == trim(variant_id)) then
        var_idx = i
        exit
      end if
    end do
    if (var_idx == 0) return
    
    ! Calculate GFLOPS (approximate for conv2d)
    ! Real calculation would depend on actual operation
    gflops = real(problem_size) * 2.0 / (execution_time_ms * 1.0e6)
    
    ! Update running average
    associate(var => system%cache(cache_idx)%variants(var_idx))
      var%test_runs = var%test_runs + 1
      var%avg_execution_time_ms = &
        (var%avg_execution_time_ms * (var%test_runs - 1) + execution_time_ms) / var%test_runs
      var%performance_gflops = &
        (var%performance_gflops * (var%test_runs - 1) + gflops) / var%test_runs
    end associate
    
    ! Update best variant if we have enough data
    if (system%cache(cache_idx)%variants(var_idx)%test_runs >= 5) then
      call update_best_variant(system%cache(cache_idx))
    end if
    
  end subroutine update_performance
  
  ! Update best variant based on performance data
  subroutine update_best_variant(entry)
    type(shader_cache_entry), intent(inout) :: entry
    integer :: i
    real :: best_perf
    
    best_perf = 0.0
    do i = 1, size(entry%variants)
      if (entry%variants(i)%test_runs >= 5 .and. &
          entry%variants(i)%performance_gflops > best_perf) then
        best_perf = entry%variants(i)%performance_gflops
        entry%best_variant_idx = i
      end if
    end do
    
    ! Reduce exploration once we have good data
    if (entry%total_executions > 100) then
      entry%is_learning = .false.
    end if
    
  end subroutine update_best_variant
  
  ! Save cache to disk
  subroutine save_cache(system)
    class(shader_system), intent(in) :: system
    ! TODO: Implement cache persistence
    print *, "Saving shader cache (not implemented yet)"
  end subroutine save_cache
  
  ! Load cache from disk
  subroutine load_cache(system)
    class(shader_system), intent(inout) :: system
    ! TODO: Implement cache loading
    print *, "Loading shader cache (not implemented yet)"
  end subroutine load_cache

end module sporkle_dynamic_shader_system