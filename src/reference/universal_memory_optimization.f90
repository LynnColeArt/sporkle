! REFERENCE IMPLEMENTATION - DO NOT MODIFY WITHOUT DISCUSSION
!
! Universal Memory Optimization Patterns
! ======================================
!
! Core insight: The same memory optimization patterns that make GPUs fast
! also work on CPUs. This module implements universal patterns that achieve
! high performance across all compute architectures.
!
! Performance targets:
!   - CPU: [deferred target] GFLOPS
!   - GPU: [deferred target] GFLOPS
!
! Key principles:
!   1. Memory bandwidth optimization (cache-oblivious algorithms)
!   2. Arithmetic intensity amplification (fusion)
!   3. Cache-friendly data layouts (tiling)
!   4. Compute/memory overlap (parallelism)
!
! DO NOT MODIFY THIS FILE DIRECTLY

module universal_memory_optimization
  use kinds
  use flopcount, only: conv2d_flops
  implicit none
  
  private
  public :: memory_params, optimize_memory_layout
  public :: cache_optimal_tile_size, arithmetic_intensity
  public :: fused_conv2d_cpu, im2col_cache_optimal
  public :: gemm_universal_memory, detect_memory_params
  
  ! Universal memory optimization parameters
  type :: memory_params
    ! Cache hierarchy (auto-detected)
    integer :: l1_cache_kb = 32      ! L1 data cache size
    integer :: l2_cache_kb = 512     ! L2 cache size  
    integer :: l3_cache_kb = 32768   ! L3 cache size
    integer :: cache_line_bytes = 64 ! Cache line size
    
    ! Memory bandwidth characteristics
    real(dp) :: peak_bandwidth_gb = 100.0  ! Peak memory bandwidth
    real(dp) :: effective_bandwidth_gb = 80.0  ! Achievable bandwidth
    
    ! Parallelism
    integer :: num_cores = 16        ! Physical cores
    integer :: num_threads = 32      ! SMT threads
    
    ! Algorithm parameters
    integer :: tile_m = 64           ! Optimal tile size M dimension
    integer :: tile_n = 64           ! Optimal tile size N dimension  
    integer :: tile_k = 512          ! Optimal tile size K dimension
    logical :: use_hugepages = .false.  ! 2MB/1GB pages
    logical :: use_numa_opt = .false.   ! NUMA-aware allocation
  end type memory_params
  
contains

  ! Cache-aware blocking to optimize memory access patterns
  subroutine apply_cache_aware_blocking(input, output, data_size)
    real(sp), intent(in) :: input(:)
    real(sp), intent(out) :: output(:) 
    integer, intent(in) :: data_size
    
    integer :: block_size, num_blocks, i, j, start_idx, end_idx
    integer :: elements_per_cache_line, line_end
    
    ! Calculate optimal block size based on L2 cache (512KB default)
    elements_per_cache_line = 64 / 4  ! 64 bytes cache line / 4 bytes per real(sp)
    block_size = min(32 * 1024, data_size)  ! 32K elements ≈ 128KB
    
    ! Ensure block size is multiple of cache line for alignment
    block_size = (block_size / elements_per_cache_line) * elements_per_cache_line
    if (block_size == 0) block_size = elements_per_cache_line
    
    num_blocks = (data_size + block_size - 1) / block_size
    
    ! Copy data in cache-friendly blocks with prefetch optimization
    !$OMP PARALLEL DO PRIVATE(start_idx, end_idx, j)
    do i = 1, num_blocks
      start_idx = (i - 1) * block_size + 1
      end_idx = min(start_idx + block_size - 1, data_size)
      
      ! Process block with cache-line-aligned access
      do j = start_idx, end_idx, elements_per_cache_line
        ! Copy cache line worth of data at once
        line_end = min(j + elements_per_cache_line - 1, end_idx)
        
        ! Vectorized copy of cache line
        output(j:line_end) = input(j:line_end)
      end do
    end do
    !$OMP END PARALLEL DO
    
  end subroutine apply_cache_aware_blocking

  ! Get cache-aware tile sizes based on current memory_params
  subroutine get_cache_aware_tiles(params, m, n, k, tile_m, tile_n, tile_k)
    type(memory_params), intent(in) :: params
    integer, intent(in) :: m, n, k
    integer, intent(out) :: tile_m, tile_n, tile_k
    
    integer :: l2_elements, total_working_set
    real(sp) :: scale_factor
    
    ! Calculate L2 cache capacity in elements
    l2_elements = (params%l2_cache_kb * 1024) / 4  ! 4 bytes per real(sp)
    
    ! Start with current tile sizes
    tile_m = params%tile_m
    tile_n = params%tile_n  
    tile_k = params%tile_k
    
    ! Limit by problem dimensions
    tile_m = min(tile_m, m)
    tile_n = min(tile_n, n)
    tile_k = min(tile_k, k)
    
    ! Calculate working set: A_tile + B_tile + C_tile
    total_working_set = tile_m * tile_k + tile_k * tile_n + tile_m * tile_n
    
    ! If working set exceeds 80% of L2, scale down to fit
    if (total_working_set > int(l2_elements * 0.8)) then
      scale_factor = sqrt(real(l2_elements) * 0.8 / real(total_working_set))
      
      tile_m = max(32, int(tile_m * scale_factor))
      tile_n = max(32, int(tile_n * scale_factor))
      tile_k = max(32, int(tile_k * scale_factor))
    end if
    
    ! Align to cache line boundaries (16 elements = 64 bytes)
    tile_m = (tile_m / 16) * 16
    tile_n = (tile_n / 16) * 16
    tile_k = (tile_k / 16) * 16
    
    ! Ensure minimum viable sizes
    tile_m = max(tile_m, 16)
    tile_n = max(tile_n, 16)
    tile_k = max(tile_k, 16)
    
  end subroutine get_cache_aware_tiles

  ! Auto-detect optimal memory parameters for current hardware
  function detect_memory_params() result(params)
    type(memory_params) :: params
    
    ! TODO: Implement hardware detection
    ! TODO: Implement hardware detection
    ! For now, use conservative defaults for a generic x86-like profile
    params%l1_cache_kb = 32
    params%l2_cache_kb = 1024  
    params%l3_cache_kb = 65536
    params%num_cores = 16
    params%num_threads = 32
    params%peak_bandwidth_gb = 100.0
    
    ! Calculate optimal tile sizes based on cache
    params%tile_m = cache_optimal_tile_size(params%l1_cache_kb, 4)  ! 4 bytes per float
    params%tile_n = params%tile_m
    params%tile_k = min(512, params%l2_cache_kb / 4)  ! Use L2 for K dimension
    
    print *, "🧠 Memory optimization parameters:"
    print '(A,I0,A)', "   L1 cache: ", params%l1_cache_kb, " KB"
    print '(A,I0,A)', "   L2 cache: ", params%l2_cache_kb, " KB"  
    print '(A,I0,A)', "   L3 cache: ", params%l3_cache_kb, " KB"
    print '(A,I0,A)', "   Cores: ", params%num_cores
    print '(A,F0.1,A)', "   Peak bandwidth: ", params%peak_bandwidth_gb, " GB/s"
    print '(A,I0,A,I0,A,I0)', "   Optimal tiles: ", params%tile_m, "×", params%tile_n, "×", params%tile_k
  end function detect_memory_params
  
  ! Calculate cache-optimal tile size using cache-oblivious principles
  integer function cache_optimal_tile_size(cache_kb, element_bytes)
    integer, intent(in) :: cache_kb, element_bytes
    
    ! Cache-oblivious algorithm: use sqrt of available cache
    ! This works optimally for any cache level in hierarchy
    real(dp) :: cache_elements
    
    cache_elements = real(cache_kb * 1024, real64) / real(element_bytes, real64)
    cache_optimal_tile_size = int(sqrt(cache_elements / 3.0))  ! Leave room for 3 matrices
    
    ! Ensure multiple of 8 for vectorization
    cache_optimal_tile_size = 8 * ((cache_optimal_tile_size + 7) / 8)
    
    ! Reasonable bounds
    cache_optimal_tile_size = max(8, min(cache_optimal_tile_size, 128))
  end function cache_optimal_tile_size
  
  ! Calculate arithmetic intensity (FLOPS per byte accessed)
  real(dp) function arithmetic_intensity(flops, bytes_accessed)
    integer(i64), intent(in) :: flops, bytes_accessed
    
    arithmetic_intensity = real(flops, real64) / real(bytes_accessed, real64)
  end function arithmetic_intensity
  
  ! Optimize memory layout for cache efficiency
  subroutine optimize_memory_layout(data, m, n, optimized_data, layout)
    real(sp), intent(in) :: data(:)
    integer, intent(in) :: m, n
    real(sp), intent(out) :: optimized_data(:)
    character(len=*), intent(in) :: layout
    
    integer :: i, j, idx_in, idx_out
    
    select case(layout)
    case("row_major")
      ! Simple copy for now - in practice would do cache-friendly blocking
      optimized_data = data
      
    case("blocked")
      ! Cache-aware blocked layout for optimal memory access
      call apply_cache_aware_blocking(data, optimized_data, size(data))
      
    case default
      optimized_data = data
    end select
  end subroutine optimize_memory_layout
  
  ! High-performance im2col with cache optimization
  subroutine im2col_cache_optimal(input, output, N, C, H, W, &
                                 kernel_size, stride, pad, H_out, W_out)
    real(sp), intent(in) :: input(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, kernel_size, stride, pad, H_out, W_out
    
    integer :: n_idx, c_idx, h_out_idx, w_out_idx, kh_idx, kw_idx
    integer :: h_in, w_in, in_idx, out_idx
    integer :: col_idx
    
    ! Cache-optimal im2col: process in blocks to maximize cache reuse
    
    !$omp parallel do collapse(2) private(n_idx, c_idx, h_out_idx, w_out_idx, kh_idx, kw_idx, h_in, w_in, in_idx, out_idx, col_idx)
    do h_out_idx = 1, H_out
      do w_out_idx = 1, W_out
        out_idx = (h_out_idx-1)*W_out + w_out_idx
        
        do n_idx = 1, N
          do c_idx = 1, C  
            do kh_idx = 1, kernel_size
              do kw_idx = 1, kernel_size
                h_in = (h_out_idx-1)*stride + kh_idx - pad
                w_in = (w_out_idx-1)*stride + kw_idx - pad
                
                if (h_in >= 1 .and. h_in <= H .and. w_in >= 1 .and. w_in <= W) then
                  in_idx = ((n_idx-1)*C + (c_idx-1))*H*W + (h_in-1)*W + w_in
                  ! Column-major layout for optimal GEMM performance
                  col_idx = ((((kh_idx-1)*kernel_size + (kw_idx-1))*C + (c_idx-1))*N + (n_idx-1))*H_out*W_out + out_idx
                  output(col_idx) = input(in_idx)
                else
                  col_idx = ((((kh_idx-1)*kernel_size + (kw_idx-1))*C + (c_idx-1))*N + (n_idx-1))*H_out*W_out + out_idx
                  output(col_idx) = 0.0
                end if
              end do
            end do
          end do
        end do
      end do
    end do
    !$omp end parallel do
  end subroutine im2col_cache_optimal
  
  ! Universal memory-optimized GEMM with cache-aware tiling
  subroutine gemm_universal_memory(A, B, C, m, n, k, alpha, beta)
    real(sp), intent(in) :: A(:), B(:), alpha, beta
    real(sp), intent(inout) :: C(:)
    integer, intent(in) :: m, n, k
    
    integer :: tile_m, tile_n, tile_k, micro_tile
    integer :: i, j, kk, ii, jj, kk_tile
    type(memory_params) :: params
    integer :: i_end, j_end, kk_end
    real(sp) :: sum1, sum2, sum3, sum4
    
    ! Get cache-aware tile sizes for optimal performance
    params = detect_memory_params()
    call get_cache_aware_tiles(params, m, n, k, tile_m, tile_n, tile_k)
    micro_tile = 4     ! Unroll factor for better ILP
    
    ! Scale existing values first
    if (beta /= 1.0) then
      if (beta == 0.0) then
        !$OMP PARALLEL DO
        do i = 1, m*n
          C(i) = 0.0
        end do
        !$OMP END PARALLEL DO
      else
        !$OMP PARALLEL DO
        do i = 1, m*n
          C(i) = beta * C(i)
        end do
        !$OMP END PARALLEL DO
      end if
    end if
    
    ! Cache-aware blocked GEMM with optimized tile sizes
    !$OMP PARALLEL DO PRIVATE(ii,jj,kk_tile,i,j,kk,i_end,j_end,kk_end,sum1,sum2,sum3,sum4) SCHEDULE(DYNAMIC,1)
    do jj = 1, n, tile_n
      do ii = 1, m, tile_m
        do kk_tile = 1, k, tile_k
          
          ! Calculate cache-aware tile boundaries
          i_end = min(ii + tile_m - 1, m)
          j_end = min(jj + tile_n - 1, n)
          kk_end = min(kk_tile + tile_k - 1, k)
          
          ! Process tile with manual unrolling for better ILP
          do j = jj, j_end, micro_tile
            do kk = kk_tile, kk_end
              
              ! Unrolled inner loop for 4 columns at once
              !$OMP SIMD PRIVATE(sum1,sum2,sum3,sum4)
              do i = ii, i_end
                sum1 = 0.0
                sum2 = 0.0  
                sum3 = 0.0
                sum4 = 0.0
                
                ! Process up to 4 columns simultaneously
                if (j <= j_end) then
                  sum1 = A((kk-1)*m + i) * B((j-1)*k + kk)
                  C((j-1)*m + i) = C((j-1)*m + i) + alpha * sum1
                end if
                
                if (j+1 <= j_end) then
                  sum2 = A((kk-1)*m + i) * B(((j+1)-1)*k + kk)
                  C(((j+1)-1)*m + i) = C(((j+1)-1)*m + i) + alpha * sum2
                end if
                
                if (j+2 <= j_end) then
                  sum3 = A((kk-1)*m + i) * B(((j+2)-1)*k + kk)
                  C(((j+2)-1)*m + i) = C(((j+2)-1)*m + i) + alpha * sum3
                end if
                
                if (j+3 <= j_end) then
                  sum4 = A((kk-1)*m + i) * B(((j+3)-1)*k + kk)
                  C(((j+3)-1)*m + i) = C(((j+3)-1)*m + i) + alpha * sum4
                end if
              end do
              !$OMP END SIMD
              
            end do
          end do
          
        end do
      end do
    end do
    !$OMP END PARALLEL DO
  end subroutine gemm_universal_memory
  
  ! High-performance CPU convolution using universal memory patterns
  real(sp) function fused_conv2d_cpu(input, weights, output, &
                                         N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    real(sp), intent(in), target :: input(:), weights(:)
    real(sp), intent(out), target :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    ! Workspace for im2col transformation
    real(sp), allocatable :: input_matrix(:)
    integer :: input_matrix_rows, input_matrix_cols
    
    real(dp) :: start_time, end_time
    integer(i64) :: total_flops, bytes_accessed
    real(dp) :: gflops, intensity
    
    ! Calculate workspace size
    input_matrix_rows = C * kernel_size * kernel_size
    input_matrix_cols = N * H_out * W_out
    allocate(input_matrix(input_matrix_rows * input_matrix_cols))
    
    print *, "🚀 Fused CPU convolution with universal memory optimization"
    print '(A,I0,A,I0,A)', "   Matrix size: ", input_matrix_rows, " × ", input_matrix_cols
    
    call cpu_time(start_time)
    
    ! Step 1: Cache-optimal im2col transformation  
    call im2col_cache_optimal(input, input_matrix, N, C, H, W, &
                             kernel_size, stride, pad, H_out, W_out)
    
    ! Step 2: Universal memory-optimized GEMM
    ! C = weights * input_matrix
    call gemm_universal_memory(weights, input_matrix, output, &
                              K, input_matrix_cols, input_matrix_rows, &
                              1.0, 0.0)
    
    call cpu_time(end_time)
    
    ! Performance analysis
    fused_conv2d_cpu = real((end_time - start_time) * 1000.0, real32)
    
    ! Use Mini's safe FLOP counting
    total_flops = conv2d_flops(int(N, int64), int(H_out, int64), int(W_out, int64), &
                              int(K, int64), int(C, int64), &
                              int(kernel_size, int64), int(kernel_size, int64))
    
    bytes_accessed = (size(input) + size(weights) + size(output) + size(input_matrix)) * 4_int64
    
    gflops = real(total_flops, real64) / (real(fused_conv2d_cpu, real64) * 1.0d6)
    intensity = arithmetic_intensity(total_flops, bytes_accessed)
    
    print '(A,F6.2,A,F6.1,A)', "   Performance: ", fused_conv2d_cpu, " ms, ", gflops, " GFLOPS"
    print '(A,F6.1,A)', "   Arithmetic intensity: ", intensity, " FLOPS/byte"
    
    deallocate(input_matrix)
  end function fused_conv2d_cpu

end module universal_memory_optimization
