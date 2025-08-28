module sporkle_rdna_shader_generator
  use iso_c_binding
  use sporkle_types
  use sporkle_glsl_generator, only: convolution_config
  implicit none
  
  private
  public :: generate_rdna_conv_shader, rdna_config, rdna_arch, detect_rdna_arch
  
  ! RDNA architecture variants
  type :: rdna_arch
    integer :: generation      ! 1, 2, or 3
    integer :: wave_size       ! 32 for all RDNA
    integer :: compute_units   ! Number of CUs
    integer :: dual_issue      ! 1 for RDNA1/2, 2 for RDNA3
    integer :: lds_size        ! Local data share size per CU
    integer :: vgpr_per_simd   ! Vector registers per SIMD
  end type rdna_arch
  
  ! Shader configuration optimized for RDNA
  type :: rdna_config
    type(rdna_arch) :: arch
    integer :: workgroup_size  ! Total threads (multiple of wave_size)
    integer :: waves_per_cu    ! Target occupancy
    logical :: use_lds         ! Use local data share for tiling
    logical :: use_dual_issue  ! Exploit RDNA3 dual-issue
    integer :: vgpr_usage      ! Target VGPR usage for occupancy
  end type rdna_config
  
contains

  ! Detect RDNA architecture from device info
  function detect_rdna_arch(device_id) result(arch)
    integer, intent(in) :: device_id
    type(rdna_arch) :: arch
    
    ! Default RDNA3 for 7900 XT (device_id 0x744c)
    ! In production, query actual device properties
    arch%generation = 3
    arch%wave_size = 32
    arch%compute_units = 84    ! 7900 XT has 84 CUs
    arch%dual_issue = 2        ! RDNA3 can dual-issue
    arch%lds_size = 65536      ! 64KB per CU
    arch%vgpr_per_simd = 1536  ! RDNA3 VGPR count
    
  end function detect_rdna_arch

  ! Generate optimized convolution shader for RDNA
  function generate_rdna_conv_shader(config, conv_params) result(shader_source)
    type(rdna_config), intent(in) :: config
    type(convolution_config), intent(in) :: conv_params
    character(len=:), allocatable :: shader_source
    character(len=16384) :: buffer
    integer :: pos
    integer :: local_x, local_y
    
    ! Optimize workgroup size for RDNA wave32
    ! Use 64 threads (2 waves) like the working reference
    ! Or 32 threads (1 wave) for perfect alignment
    if (config%workgroup_size == 64) then
      local_x = 64
      local_y = 1
    else if (config%workgroup_size == 256) then
      ! 8x32 = 256 threads = 8 waves (good occupancy)
      local_x = 32
      local_y = 8
    else
      ! Default: 32 threads = 1 wave (simplest)
      local_x = 32
      local_y = 1
    end if
    
    pos = 1
    
    ! GLSL header
    call append_line(buffer, pos, "#version 450")
    call append_line(buffer, pos, "#extension GL_ARB_compute_shader : enable")
    call append_line(buffer, pos, "#extension GL_ARB_shader_storage_buffer_object : enable")
    call append_line(buffer, pos, "")
    
    ! Architecture-specific optimizations
    if (config%arch%generation >= 3) then
      call append_line(buffer, pos, "// RDNA3 optimizations: dual-issue capable")
      call append_line(buffer, pos, "#extension GL_ARB_gpu_shader_fp64 : enable")
    end if
    call append_line(buffer, pos, "")
    
    ! Workgroup size - critical for performance
    write(buffer(pos:), '(A,I0,A,I0,A)') &
      "layout(local_size_x = ", local_x, ", local_size_y = ", local_y, ", local_size_z = 1) in;"
    pos = pos + len_trim(buffer(pos:)) + 1
    buffer(pos-1:pos-1) = new_line('A')
    call append_line(buffer, pos, "")
    
    ! Constants for RDNA optimization
    write(buffer(pos:), '(A,I0)') "#define WAVE_SIZE ", config%arch%wave_size
    pos = pos + len_trim(buffer(pos:)) + 1
    buffer(pos-1:pos-1) = new_line('A')
    
    if (config%use_lds) then
      ! LDS tile size for RDNA (optimize for 128-byte cache lines)
      call append_line(buffer, pos, "#define USE_LDS_TILING 1")
      call append_line(buffer, pos, "#define LDS_TILE_SIZE 32  // Matches wave size")
    end if
    call append_line(buffer, pos, "")
    
    ! Storage buffers - same as reference implementation
    call append_line(buffer, pos, "// Input buffer")
    call append_line(buffer, pos, "layout(std430, binding = 0) readonly buffer InputBuffer {")
    call append_line(buffer, pos, "  float data[];")
    call append_line(buffer, pos, "} input_buf;")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "// Weight buffer")
    call append_line(buffer, pos, "layout(std430, binding = 1) readonly buffer WeightBuffer {")
    call append_line(buffer, pos, "  float data[];")
    call append_line(buffer, pos, "} weight_buf;")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "// Output buffer")
    call append_line(buffer, pos, "layout(std430, binding = 2) writeonly buffer OutputBuffer {")
    call append_line(buffer, pos, "  float data[];")
    call append_line(buffer, pos, "} output_buf;")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "// Convolution parameters")
    call append_line(buffer, pos, "layout(std430, binding = 3) readonly buffer ParamBuffer {")
    call append_line(buffer, pos, "  int N, H, W, C, K;")
    call append_line(buffer, pos, "  int kernel_size, stride, pad;")
    call append_line(buffer, pos, "  int H_out, W_out;")
    call append_line(buffer, pos, "} params;")
    call append_line(buffer, pos, "")
    
    if (config%use_lds) then
      ! Shared memory for cooperative tiling
      call append_line(buffer, pos, "// Local data share for RDNA")
      call append_line(buffer, pos, "shared float lds_input[LDS_TILE_SIZE][LDS_TILE_SIZE];")
      call append_line(buffer, pos, "shared float lds_weight[LDS_TILE_SIZE][LDS_TILE_SIZE];")
      call append_line(buffer, pos, "")
    end if
    
    ! Main function - optimized for RDNA
    call append_line(buffer, pos, "void main() {")
    call append_line(buffer, pos, "  uint idx = gl_GlobalInvocationID.x;")
    
    if (local_y > 1) then
      call append_line(buffer, pos, "  uint idy = gl_GlobalInvocationID.y;")
      call append_line(buffer, pos, "  uint total_idx = idy * gl_NumWorkGroups.x * gl_WorkGroupSize.x + idx;")
      call append_line(buffer, pos, "  if (total_idx >= uint(params.N * params.K * params.H_out * params.W_out)) return;")
      call append_line(buffer, pos, "  idx = total_idx;  // Use flattened index")
    else
      call append_line(buffer, pos, "  if (idx >= uint(params.N * params.K * params.H_out * params.W_out)) return;")
    end if
    
    call append_line(buffer, pos, "  ")
    call append_line(buffer, pos, "  // Decode output position")
    call append_line(buffer, pos, "  int n = int(idx) / (params.K * params.H_out * params.W_out);")
    call append_line(buffer, pos, "  int k = (int(idx) / (params.H_out * params.W_out)) % params.K;")
    call append_line(buffer, pos, "  int h_out = (int(idx) / params.W_out) % params.H_out;")
    call append_line(buffer, pos, "  int w_out = int(idx) % params.W_out;")
    call append_line(buffer, pos, "  ")
    
    if (config%arch%generation >= 3 .and. config%use_dual_issue) then
      ! RDNA3 can dual-issue FMA with other instructions
      call append_line(buffer, pos, "  // RDNA3: Dual-issue optimization")
      call append_line(buffer, pos, "  float sum = 0.0;")
      call append_line(buffer, pos, "  float sum2 = 0.0;  // Second accumulator for dual-issue")
      call append_line(buffer, pos, "  ")
      
      ! Unrolled convolution for dual-issue
      call append_line(buffer, pos, "  // Convolution with dual-issue FMA")
      call append_line(buffer, pos, "  for (int c = 0; c < params.C; c += 2) {")
      call append_line(buffer, pos, "    for (int kh = 0; kh < params.kernel_size; kh++) {")
      call append_line(buffer, pos, "      for (int kw = 0; kw < params.kernel_size; kw++) {")
      call append_line(buffer, pos, "        int h_in = h_out * params.stride + kh - params.pad;")
      call append_line(buffer, pos, "        int w_in = w_out * params.stride + kw - params.pad;")
      call append_line(buffer, pos, "        ")
      call append_line(buffer, pos, "        if (h_in >= 0 && h_in < params.H && w_in >= 0 && w_in < params.W) {")
      call append_line(buffer, pos, "          // Process two channels for dual-issue")
      call append_line(buffer, pos, "          if (c < params.C) {")
      call append_line(buffer, pos, "            int in_idx = ((n * params.C + c) * params.H + h_in) * " // &
                                    "params.W + w_in;")
      call append_line(buffer, pos, "            int weight_idx = ((k * params.C + c) * params.kernel_size + kh) * " // &
                                    "params.kernel_size + kw;")
      call append_line(buffer, pos, "            sum += input_buf.data[in_idx] * weight_buf.data[weight_idx];")
      call append_line(buffer, pos, "          }")
      call append_line(buffer, pos, "          if (c + 1 < params.C) {")
      call append_line(buffer, pos, "            int in_idx2 = ((n * params.C + c + 1) * params.H + h_in) * " // &
                                    "params.W + w_in;")
      call append_line(buffer, pos, "            int weight_idx2 = ((k * params.C + c + 1) * params.kernel_size + kh) * " // &
                                    "params.kernel_size + kw;")
      call append_line(buffer, pos, "            sum2 += input_buf.data[in_idx2] * weight_buf.data[weight_idx2];")
      call append_line(buffer, pos, "          }")
      call append_line(buffer, pos, "        }")
      call append_line(buffer, pos, "      }")
      call append_line(buffer, pos, "    }")
      call append_line(buffer, pos, "  }")
      call append_line(buffer, pos, "  ")
      call append_line(buffer, pos, "  output_buf.data[idx] = sum + sum2;")
    else
      ! Standard convolution (same as reference)
      call append_line(buffer, pos, "  float sum = 0.0;")
      call append_line(buffer, pos, "  ")
      call append_line(buffer, pos, "  // Convolution")
      call append_line(buffer, pos, "  for (int c = 0; c < params.C; c++) {")
      call append_line(buffer, pos, "    for (int kh = 0; kh < params.kernel_size; kh++) {")
      call append_line(buffer, pos, "      for (int kw = 0; kw < params.kernel_size; kw++) {")
      call append_line(buffer, pos, "        int h_in = h_out * params.stride + kh - params.pad;")
      call append_line(buffer, pos, "        int w_in = w_out * params.stride + kw - params.pad;")
      call append_line(buffer, pos, "        ")
      call append_line(buffer, pos, "        if (h_in >= 0 && h_in < params.H && w_in >= 0 && w_in < params.W) {")
      call append_line(buffer, pos, "          int in_idx = ((n * params.C + c) * params.H + h_in) * " // &
                                    "params.W + w_in;")
      call append_line(buffer, pos, "          int weight_idx = ((k * params.C + c) * params.kernel_size + kh) * " // &
                                    "params.kernel_size + kw;")
      call append_line(buffer, pos, "          sum += input_buf.data[in_idx] * weight_buf.data[weight_idx];")
      call append_line(buffer, pos, "        }")
      call append_line(buffer, pos, "      }")
      call append_line(buffer, pos, "    }")
      call append_line(buffer, pos, "  }")
      call append_line(buffer, pos, "  ")
      call append_line(buffer, pos, "  output_buf.data[idx] = sum;")
    end if
    
    call append_line(buffer, pos, "}")
    
    ! Allocate final string
    shader_source = trim(buffer(1:pos-1))
    
  end function generate_rdna_conv_shader
  
  ! Generate optimized GEMM shader for RDNA
  function generate_rdna_gemm_shader(config, M, N, K) result(shader_source)
    type(rdna_config), intent(in) :: config
    integer, intent(in) :: M, N, K
    character(len=:), allocatable :: shader_source
    character(len=16384) :: buffer
    integer :: pos
    
    pos = 1
    
    ! GLSL header
    call append_line(buffer, pos, "#version 450")
    call append_line(buffer, pos, "")
    
    ! Workgroup size - use wave-aligned sizes
    call append_line(buffer, pos, "// RDNA-optimized workgroup")
    call append_line(buffer, pos, "layout(local_size_x = 32, local_size_y = 8) in;")
    call append_line(buffer, pos, "")
    
    ! Constants
    call append_line(buffer, pos, "// RDNA wave size")
    call append_line(buffer, pos, "#define WAVE_SIZE 32")
    call append_line(buffer, pos, "#define TILE_M 32  // One wave per row")
    call append_line(buffer, pos, "#define TILE_N 32  // Match cache line")
    call append_line(buffer, pos, "#define TILE_K 8   // Unroll factor")
    call append_line(buffer, pos, "")
    
    ! Storage buffers
    call append_line(buffer, pos, "layout(std430, binding = 0) readonly buffer MatrixA {")
    call append_line(buffer, pos, "  float A[];")
    call append_line(buffer, pos, "};")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "layout(std430, binding = 1) readonly buffer MatrixB {")
    call append_line(buffer, pos, "  float B[];")
    call append_line(buffer, pos, "};")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "layout(std430, binding = 2) buffer MatrixC {")
    call append_line(buffer, pos, "  float C[];")
    call append_line(buffer, pos, "};")
    call append_line(buffer, pos, "")
    
    ! Shared memory for tiling
    call append_line(buffer, pos, "// Local data share for cooperative loading")
    call append_line(buffer, pos, "shared float tile_A[TILE_M][TILE_K + 1];  // +1 avoids bank conflicts")
    call append_line(buffer, pos, "shared float tile_B[TILE_K][TILE_N + 1];")
    call append_line(buffer, pos, "")
    
    ! Uniforms
    write(buffer(pos:), '(A,I0,A,I0,A,I0,A)') &
      "uniform int M = ", M, ";  // rows of A and C"
    pos = pos + len_trim(buffer(pos:)) + 1
    buffer(pos-1:pos-1) = new_line('A')
    
    write(buffer(pos:), '(A,I0,A,I0,A,I0,A)') &
      "uniform int N = ", N, ";  // cols of B and C"
    pos = pos + len_trim(buffer(pos:)) + 1
    buffer(pos-1:pos-1) = new_line('A')
    
    write(buffer(pos:), '(A,I0,A,I0,A,I0,A)') &
      "uniform int K = ", K, ";  // cols of A, rows of B"
    pos = pos + len_trim(buffer(pos:)) + 1
    buffer(pos-1:pos-1) = new_line('A')
    call append_line(buffer, pos, "")
    
    ! Main GEMM kernel
    call append_line(buffer, pos, "void main() {")
    call append_line(buffer, pos, "  int tid_x = int(gl_LocalInvocationID.x);")
    call append_line(buffer, pos, "  int tid_y = int(gl_LocalInvocationID.y);")
    call append_line(buffer, pos, "  int block_x = int(gl_WorkGroupID.x);")
    call append_line(buffer, pos, "  int block_y = int(gl_WorkGroupID.y);")
    call append_line(buffer, pos, "  ")
    call append_line(buffer, pos, "  // Global position")
    call append_line(buffer, pos, "  int global_row = block_y * TILE_M + tid_y;")
    call append_line(buffer, pos, "  int global_col = block_x * TILE_N + tid_x;")
    call append_line(buffer, pos, "  ")
    call append_line(buffer, pos, "  // Accumulator")
    call append_line(buffer, pos, "  float sum = 0.0;")
    call append_line(buffer, pos, "  ")
    call append_line(buffer, pos, "  // Loop over K dimension in tiles")
    call append_line(buffer, pos, "  for (int k_tile = 0; k_tile < K; k_tile += TILE_K) {")
    call append_line(buffer, pos, "    // Cooperative load of tiles")
    call append_line(buffer, pos, "    if (tid_y < TILE_K && global_row < M && k_tile + tid_y < K) {")
    call append_line(buffer, pos, "      tile_A[tid_x][tid_y] = A[(global_row) * K + k_tile + tid_y];")
    call append_line(buffer, pos, "    }")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    if (tid_y < TILE_K && k_tile + tid_y < K && global_col < N) {")
    call append_line(buffer, pos, "      tile_B[tid_y][tid_x] = B[(k_tile + tid_y) * N + global_col];")
    call append_line(buffer, pos, "    }")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    barrier();")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Compute using tiles")
    call append_line(buffer, pos, "    #pragma unroll")
    call append_line(buffer, pos, "    for (int k = 0; k < TILE_K; k++) {")
    call append_line(buffer, pos, "      sum += tile_A[tid_x][k] * tile_B[k][tid_x];")
    call append_line(buffer, pos, "    }")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    barrier();")
    call append_line(buffer, pos, "  }")
    call append_line(buffer, pos, "  ")
    call append_line(buffer, pos, "  // Write result")
    call append_line(buffer, pos, "  if (global_row < M && global_col < N) {")
    call append_line(buffer, pos, "    C[global_row * N + global_col] = sum;")
    call append_line(buffer, pos, "  }")
    call append_line(buffer, pos, "}")
    
    shader_source = trim(buffer(1:pos-1))
    
  end function generate_rdna_gemm_shader
  
  subroutine append_line(buffer, pos, line)
    character(len=*), intent(inout) :: buffer
    integer, intent(inout) :: pos
    character(len=*), intent(in) :: line
    integer :: line_len
    
    line_len = len_trim(line)
    buffer(pos:pos+line_len) = trim(line) // new_line('A')
    pos = pos + line_len + 1
  end subroutine append_line

end module sporkle_rdna_shader_generator