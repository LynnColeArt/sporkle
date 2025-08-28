module sporkle_gpu_kernels
  ! GPU kernel sources in GLSL compute shader language
  ! The Sporkle Way: Write once, run anywhere (that has OpenGL 4.3+)
  
  use kinds
  implicit none
  private
  
  public :: get_vector_add_shader, get_saxpy_shader, get_gemm_shader
  public :: get_reduction_shader, get_complex_shader
  
contains

  ! Vector addition: z = x + y
  function get_vector_add_shader() result(source)
    character(len=:), allocatable :: source
    
    source = &
      "#version 430 core" // new_line('a') // &
      "" // new_line('a') // &
      "layout(local_size_x = 256) in;" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 0) readonly buffer XBuffer {" // new_line('a') // &
      "    float x[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 1) readonly buffer YBuffer {" // new_line('a') // &
      "    float y[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 2) writeonly buffer ZBuffer {" // new_line('a') // &
      "    float z[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "uniform uint n;" // new_line('a') // &
      "" // new_line('a') // &
      "void main() {" // new_line('a') // &
      "    uint idx = gl_GlobalInvocationID.x;" // new_line('a') // &
      "    if (idx >= n) return;" // new_line('a') // &
      "    " // new_line('a') // &
      "    z[idx] = x[idx] + y[idx];" // new_line('a') // &
      "}"
    
  end function get_vector_add_shader
  
  ! SAXPY: y = alpha*x + y
  function get_saxpy_shader() result(source)
    character(len=:), allocatable :: source
    
    source = &
      "#version 430 core" // new_line('a') // &
      "" // new_line('a') // &
      "layout(local_size_x = 256) in;" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 0) readonly buffer XBuffer {" // new_line('a') // &
      "    float x[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 1) buffer YBuffer {" // new_line('a') // &
      "    float y[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "uniform uint n;" // new_line('a') // &
      "uniform float alpha;" // new_line('a') // &
      "" // new_line('a') // &
      "void main() {" // new_line('a') // &
      "    uint idx = gl_GlobalInvocationID.x;" // new_line('a') // &
      "    if (idx >= n) return;" // new_line('a') // &
      "    " // new_line('a') // &
      "    y[idx] = alpha * x[idx] + y[idx];" // new_line('a') // &
      "}"
    
  end function get_saxpy_shader
  
  ! Tiled GEMM: C = A * B
  function get_gemm_shader() result(source)
    character(len=:), allocatable :: source
    
    source = &
      "#version 430 core" // new_line('a') // &
      "" // new_line('a') // &
      "layout(local_size_x = 16, local_size_y = 16) in;" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 0) readonly buffer ABuffer {" // new_line('a') // &
      "    float A[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 1) readonly buffer BBuffer {" // new_line('a') // &
      "    float B[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 2) buffer CBuffer {" // new_line('a') // &
      "    float C[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "uniform uint M;" // new_line('a') // &
      "uniform uint N;" // new_line('a') // &
      "uniform uint K;" // new_line('a') // &
      "" // new_line('a') // &
      "shared float tileA[16][16];" // new_line('a') // &
      "shared float tileB[16][16];" // new_line('a') // &
      "" // new_line('a') // &
      "void main() {" // new_line('a') // &
      "    uint row = gl_GlobalInvocationID.y;" // new_line('a') // &
      "    uint col = gl_GlobalInvocationID.x;" // new_line('a') // &
      "    uint localRow = gl_LocalInvocationID.y;" // new_line('a') // &
      "    uint localCol = gl_LocalInvocationID.x;" // new_line('a') // &
      "    " // new_line('a') // &
      "    float sum = 0.0;" // new_line('a') // &
      "    " // new_line('a') // &
      "    // Process tiles" // new_line('a') // &
      "    for (uint t = 0; t < K; t += 16) {" // new_line('a') // &
      "        // Load tile from A" // new_line('a') // &
      "        if (row < M && (t + localCol) < K) {" // new_line('a') // &
      "            tileA[localRow][localCol] = A[row * K + t + localCol];" // new_line('a') // &
      "        } else {" // new_line('a') // &
      "            tileA[localRow][localCol] = 0.0;" // new_line('a') // &
      "        }" // new_line('a') // &
      "        " // new_line('a') // &
      "        // Load tile from B" // new_line('a') // &
      "        if ((t + localRow) < K && col < N) {" // new_line('a') // &
      "            tileB[localRow][localCol] = B[(t + localRow) * N + col];" // new_line('a') // &
      "        } else {" // new_line('a') // &
      "            tileB[localRow][localCol] = 0.0;" // new_line('a') // &
      "        }" // new_line('a') // &
      "        " // new_line('a') // &
      "        // Synchronize to ensure tile is loaded" // new_line('a') // &
      "        barrier();" // new_line('a') // &
      "        " // new_line('a') // &
      "        // Compute partial dot product" // new_line('a') // &
      "        for (uint k = 0; k < 16; k++) {" // new_line('a') // &
      "            sum += tileA[localRow][k] * tileB[k][localCol];" // new_line('a') // &
      "        }" // new_line('a') // &
      "        " // new_line('a') // &
      "        // Synchronize before loading next tile" // new_line('a') // &
      "        barrier();" // new_line('a') // &
      "    }" // new_line('a') // &
      "    " // new_line('a') // &
      "    // Write result" // new_line('a') // &
      "    if (row < M && col < N) {" // new_line('a') // &
      "        C[row * N + col] = sum;" // new_line('a') // &
      "    }" // new_line('a') // &
      "}"
    
  end function get_gemm_shader
  
  ! Parallel reduction (sum)
  function get_reduction_shader() result(source)
    character(len=:), allocatable :: source
    
    source = &
      "#version 430 core" // new_line('a') // &
      "" // new_line('a') // &
      "layout(local_size_x = 256) in;" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 0) buffer DataBuffer {" // new_line('a') // &
      "    float data[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "uniform uint n;" // new_line('a') // &
      "uniform uint stride;" // new_line('a') // &
      "" // new_line('a') // &
      "shared float sdata[256];" // new_line('a') // &
      "" // new_line('a') // &
      "void main() {" // new_line('a') // &
      "    uint tid = gl_LocalInvocationID.x;" // new_line('a') // &
      "    uint idx = gl_GlobalInvocationID.x;" // new_line('a') // &
      "    " // new_line('a') // &
      "    // Load data to shared memory" // new_line('a') // &
      "    sdata[tid] = (idx < n) ? data[idx] : 0.0;" // new_line('a') // &
      "    barrier();" // new_line('a') // &
      "    " // new_line('a') // &
      "    // Tree reduction in shared memory" // new_line('a') // &
      "    for (uint s = 128; s > 0; s >>= 1) {" // new_line('a') // &
      "        if (tid < s) {" // new_line('a') // &
      "            sdata[tid] += sdata[tid + s];" // new_line('a') // &
      "        }" // new_line('a') // &
      "        barrier();" // new_line('a') // &
      "    }" // new_line('a') // &
      "    " // new_line('a') // &
      "    // Write result" // new_line('a') // &
      "    if (tid == 0) {" // new_line('a') // &
      "        data[gl_WorkGroupID.x] = sdata[0];" // new_line('a') // &
      "    }" // new_line('a') // &
      "}"
    
  end function get_reduction_shader
  
  ! Complex computation: z = sqrt(x^2 + y^2)
  function get_complex_shader() result(source)
    character(len=:), allocatable :: source
    
    source = &
      "#version 430 core" // new_line('a') // &
      "" // new_line('a') // &
      "layout(local_size_x = 256) in;" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 0) readonly buffer XBuffer {" // new_line('a') // &
      "    float x[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 1) readonly buffer YBuffer {" // new_line('a') // &
      "    float y[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "layout(std430, binding = 2) writeonly buffer ZBuffer {" // new_line('a') // &
      "    float z[];" // new_line('a') // &
      "};" // new_line('a') // &
      "" // new_line('a') // &
      "uniform uint n;" // new_line('a') // &
      "" // new_line('a') // &
      "void main() {" // new_line('a') // &
      "    uint idx = gl_GlobalInvocationID.x;" // new_line('a') // &
      "    if (idx >= n) return;" // new_line('a') // &
      "    " // new_line('a') // &
      "    float x_val = x[idx];" // new_line('a') // &
      "    float y_val = y[idx];" // new_line('a') // &
      "    z[idx] = sqrt(x_val * x_val + y_val * y_val);" // new_line('a') // &
      "}"
    
  end function get_complex_shader

end module sporkle_gpu_kernels