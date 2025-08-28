module sporkle_glsl_generator
  use iso_c_binding
  use sporkle_types
  implicit none
  
  private
  public :: generate_conv_glsl_shader, convolution_config
  
  ! Configuration for convolution parameters
  type :: convolution_config
    integer :: input_height, input_width, input_channels
    integer :: kernel_height, kernel_width
    integer :: output_height, output_width, output_channels
    integer :: stride_y, stride_x
    integer :: pad_y, pad_x
    integer :: tile_size
    logical :: use_fp16
  end type convolution_config
  
contains

  function generate_conv_glsl_shader(config) result(shader_source)
    type(convolution_config), intent(in) :: config
    character(len=:), allocatable :: shader_source
    character(len=8192) :: buffer
    integer :: pos
    
    ! Build shader source
    pos = 1
    
    ! Header and extensions
    call append_line(buffer, pos, "#version 450")
    call append_line(buffer, pos, "#extension GL_ARB_compute_shader : enable")
    call append_line(buffer, pos, "#extension GL_ARB_shader_storage_buffer_object : enable")
    call append_line(buffer, pos, "")
    
    ! Define tile size constant
    write(buffer(pos:), '(A,I0)') "#define TILE_SIZE ", config%tile_size
    pos = pos + len_trim(buffer(pos:)) + 1
    buffer(pos-1:pos-1) = new_line('A')
    
    ! Workgroup size - tuned for AMDGPU wave size
    call append_line(buffer, pos, "layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;")
    call append_line(buffer, pos, "")
    
    ! Storage buffers
    call append_line(buffer, pos, "// Input buffer - im2col transformed")
    call append_line(buffer, pos, "layout(std430, binding = 0) readonly buffer InputBuffer {")
    call append_line(buffer, pos, "    float input[];")
    call append_line(buffer, pos, "};")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "// Kernel weights")
    call append_line(buffer, pos, "layout(std430, binding = 1) readonly buffer KernelBuffer {")
    call append_line(buffer, pos, "    float kernel[];")
    call append_line(buffer, pos, "};")
    call append_line(buffer, pos, "")
    
    call append_line(buffer, pos, "// Output buffer")
    call append_line(buffer, pos, "layout(std430, binding = 2) writeonly buffer OutputBuffer {")
    call append_line(buffer, pos, "    float output[];")
    call append_line(buffer, pos, "};")
    call append_line(buffer, pos, "")
    
    ! Uniforms for dimensions
    call append_line(buffer, pos, "// Convolution dimensions")
    call append_line(buffer, pos, "uniform int M; // Output height * width")
    call append_line(buffer, pos, "uniform int N; // Output channels")
    call append_line(buffer, pos, "uniform int K; // Kernel height * width * input channels")
    call append_line(buffer, pos, "")
    
    ! Shared memory for tiling
    call append_line(buffer, pos, "// Shared memory tiles for cooperative loading")
    call append_line(buffer, pos, "shared float tile_A[TILE_SIZE][TILE_SIZE + 1]; // +1 to avoid bank conflicts")
    call append_line(buffer, pos, "shared float tile_B[TILE_SIZE][TILE_SIZE + 1];")
    call append_line(buffer, pos, "")
    
    ! Main function
    call append_line(buffer, pos, "void main() {")
    call append_line(buffer, pos, "    // Global thread indices")
    call append_line(buffer, pos, "    int global_row = int(gl_GlobalInvocationID.y);")
    call append_line(buffer, pos, "    int global_col = int(gl_GlobalInvocationID.x);")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Local thread indices within workgroup")
    call append_line(buffer, pos, "    int local_row = int(gl_LocalInvocationID.y);")
    call append_line(buffer, pos, "    int local_col = int(gl_LocalInvocationID.x);")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Check bounds")
    call append_line(buffer, pos, "    if (global_row >= M || global_col >= N) return;")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Accumulator for this output element")
    call append_line(buffer, pos, "    float acc = 0.0;")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Number of tiles needed")
    call append_line(buffer, pos, "    int num_tiles = (K + TILE_SIZE - 1) / TILE_SIZE;")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Tile-based matrix multiplication")
    call append_line(buffer, pos, "    for (int tile = 0; tile < num_tiles; tile++) {")
    call append_line(buffer, pos, "        // Collaborative loading of tiles")
    call append_line(buffer, pos, "        int tile_k = tile * TILE_SIZE;")
    call append_line(buffer, pos, "        ")
    call append_line(buffer, pos, "        // Load tile from input (A matrix)")
    call append_line(buffer, pos, "        int a_row = global_row;")
    call append_line(buffer, pos, "        int a_col = tile_k + local_col;")
    call append_line(buffer, pos, "        if (a_row < M && a_col < K) {")
    call append_line(buffer, pos, "            tile_A[local_row][local_col] = input[a_row * K + a_col];")
    call append_line(buffer, pos, "        } else {")
    call append_line(buffer, pos, "            tile_A[local_row][local_col] = 0.0;")
    call append_line(buffer, pos, "        }")
    call append_line(buffer, pos, "        ")
    call append_line(buffer, pos, "        // Load tile from kernel (B matrix)")
    call append_line(buffer, pos, "        int b_row = tile_k + local_row;")
    call append_line(buffer, pos, "        int b_col = global_col;")
    call append_line(buffer, pos, "        if (b_row < K && b_col < N) {")
    call append_line(buffer, pos, "            tile_B[local_row][local_col] = kernel[b_row * N + b_col];")
    call append_line(buffer, pos, "        } else {")
    call append_line(buffer, pos, "            tile_B[local_row][local_col] = 0.0;")
    call append_line(buffer, pos, "        }")
    call append_line(buffer, pos, "        ")
    call append_line(buffer, pos, "        // Synchronize to ensure all threads have loaded their data")
    call append_line(buffer, pos, "        barrier();")
    call append_line(buffer, pos, "        ")
    call append_line(buffer, pos, "        // Compute partial dot product for this tile")
    
    ! Add unrolled loop for better performance
    if (config%tile_size == 16) then
      call append_line(buffer, pos, "        // Unrolled for TILE_SIZE = 16")
      call append_line(buffer, pos, "        #pragma unroll")
      call append_line(buffer, pos, "        for (int k = 0; k < TILE_SIZE; k++) {")
      call append_line(buffer, pos, "            acc += tile_A[local_row][k] * tile_B[k][local_col];")
      call append_line(buffer, pos, "        }")
    else
      call append_line(buffer, pos, "        for (int k = 0; k < TILE_SIZE; k++) {")
      call append_line(buffer, pos, "            acc += tile_A[local_row][k] * tile_B[k][local_col];")
      call append_line(buffer, pos, "        }")
    end if
    
    call append_line(buffer, pos, "        ")
    call append_line(buffer, pos, "        // Synchronize before loading next tile")
    call append_line(buffer, pos, "        barrier();")
    call append_line(buffer, pos, "    }")
    call append_line(buffer, pos, "    ")
    call append_line(buffer, pos, "    // Write result")
    call append_line(buffer, pos, "    output[global_row * N + global_col] = acc;")
    call append_line(buffer, pos, "}")
    
    ! Allocate final string
    shader_source = trim(buffer(1:pos-1))
    
  end function generate_conv_glsl_shader
  
  subroutine append_line(buffer, pos, line)
    character(len=*), intent(inout) :: buffer
    integer, intent(inout) :: pos
    character(len=*), intent(in) :: line
    integer :: line_len
    
    line_len = len_trim(line)
    buffer(pos:pos+line_len) = trim(line) // new_line('A')
    pos = pos + line_len + 1
  end subroutine append_line

end module sporkle_glsl_generator