> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GLSL Compute Shader Implementation Plan for Convolution-as-GEMM

## Objective

Implement our proven convolution-as-GEMM kernel as a GLSL compute shader, maintaining the same mathematical properties while leveraging GPU parallelism.

## Kernel Mathematics Recap

Our convolution-as-GEMM approach:
```
Conv(input, kernel) = GEMM(im2col(input), kernel_matrix)
```

Where:
- `im2col` transforms input patches into columns
- Convolution becomes matrix multiplication
- Optimized for cache-friendly access patterns

## GLSL Compute Shader Design

### Shader Structure

```glsl
#version 450
#extension GL_ARB_compute_shader : enable
#extension GL_ARB_shader_storage_buffer_object : enable

// Workgroup size tuned for AMDGPU
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Storage buffers
layout(std430, binding = 0) readonly buffer InputBuffer {
    float input[];
};

layout(std430, binding = 1) readonly buffer KernelBuffer {
    float kernel[];
};

layout(std430, binding = 2) writeonly buffer OutputBuffer {
    float output[];
};

// Uniforms for dimensions
uniform ivec3 input_dims;    // [height, width, channels]
uniform ivec3 kernel_dims;   // [height, width, channels]
uniform ivec3 output_dims;   // [height, width, filters]
uniform ivec2 stride;        // [stride_y, stride_x]
uniform ivec2 padding;       // [pad_y, pad_x]

// Shared memory for tile
shared float tile_input[TILE_SIZE][TILE_SIZE];
shared float tile_kernel[TILE_SIZE][TILE_SIZE];

void main() {
    // Workgroup and global indices
    ivec2 workgroup_id = ivec2(gl_WorkGroupID.xy);
    ivec2 local_id = ivec2(gl_LocalInvocationID.xy);
    ivec2 global_id = ivec2(gl_GlobalInvocationID.xy);
    
    // Output position
    int out_y = global_id.y;
    int out_x = global_id.x;
    
    if (out_y >= output_dims.y || out_x >= output_dims.x) return;
    
    // Convolution-as-GEMM accumulator
    float acc = 0.0;
    
    // Tile-based matrix multiplication
    int num_tiles = (kernel_dims.x * kernel_dims.y * kernel_dims.z + TILE_SIZE - 1) / TILE_SIZE;
    
    for (int tile = 0; tile < num_tiles; tile++) {
        // Collaborative loading into shared memory
        load_input_tile(tile, local_id);
        load_kernel_tile(tile, local_id);
        
        barrier();
        
        // Compute partial dot product
        for (int k = 0; k < TILE_SIZE; k++) {
            acc += tile_input[local_id.y][k] * tile_kernel[k][local_id.x];
        }
        
        barrier();
    }
    
    // Write result
    int out_idx = out_y * output_dims.x + out_x;
    output[out_idx] = acc;
}
```

### Memory Access Optimization

1. **Coalesced Reads**: Ensure adjacent threads read adjacent memory
2. **Shared Memory Tiling**: Reduce global memory bandwidth
3. **Bank Conflict Avoidance**: Pad shared memory arrays

### Workgroup Size Tuning

For AMDGPU:
- Wave size: 64 threads
- Optimal workgroup: Multiple of wave size
- Target occupancy: >50%

## Integration with Sparkle

### 1. Shader Generation

```fortran
function generate_conv_glsl(kernel_config) result(shader_source)
    type(convolution_config), intent(in) :: kernel_config
    character(len=:), allocatable :: shader_source
    
    ! Generate customized GLSL based on:
    ! - Kernel dimensions
    ! - Data types (fp32/fp16)
    ! - Optimization hints
    
    shader_source = glsl_header // &
                   generate_uniforms(kernel_config) // &
                   generate_shared_memory(kernel_config) // &
                   generate_compute_loop(kernel_config)
end function
```

### 2. Shader Compilation

```fortran
function compile_glsl_kernel(device, shader_source) result(kernel)
    type(amdgpu_device), intent(in) :: device
    character(len=*), intent(in) :: shader_source
    type(sporkle_kernel) :: kernel
    
    ! Use OpenGL compute shader API
    kernel%shader_id = glCreateShader(GL_COMPUTE_SHADER)
    call glShaderSource(kernel%shader_id, shader_source)
    call glCompileShader(kernel%shader_id)
    
    ! Check compilation
    call check_shader_errors(kernel%shader_id)
    
    ! Create program
    kernel%program_id = glCreateProgram()
    call glAttachShader(kernel%program_id, kernel%shader_id)
    call glLinkProgram(kernel%program_id)
end function
```

### 3. Kernel Dispatch

```fortran
subroutine dispatch_conv_glsl(kernel, input, weights, output)
    type(sporkle_kernel), intent(in) :: kernel
    type(amdgpu_buffer), intent(in) :: input, weights
    type(amdgpu_buffer), intent(inout) :: output
    
    ! Bind program
    call glUseProgram(kernel%program_id)
    
    ! Bind buffers
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, input%gl_id)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, weights%gl_id)
    call glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, output%gl_id)
    
    ! Set uniforms
    call glUniform3i(glGetUniformLocation(kernel%program_id, "input_dims"), &
                     input%height, input%width, input%channels)
    
    ! Dispatch compute
    integer :: groups_x = (output%width + 15) / 16
    integer :: groups_y = (output%height + 15) / 16
    call glDispatchCompute(groups_x, groups_y, 1)
    
    ! Ensure completion
    call glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
end subroutine
```

## Performance Optimizations

### 1. Loop Unrolling
```glsl
// Unroll inner loop for known kernel sizes
#pragma unroll
for (int ky = 0; ky < 3; ky++) {
    #pragma unroll
    for (int kx = 0; kx < 3; kx++) {
        // Convolution computation
    }
}
```

### 2. Vectorization
```glsl
// Use vec4 operations where possible
vec4 input_vec = vec4(input[idx], input[idx+1], input[idx+2], input[idx+3]);
vec4 kernel_vec = vec4(kernel[kidx], kernel[kidx+1], kernel[kidx+2], kernel[kidx+3]);
acc += dot(input_vec, kernel_vec);
```

### 3. Texture Cache Usage
Consider using texture objects for spatially-coherent access patterns

## Testing Strategy

1. **Correctness Verification**
   - Compare against CPU reference implementation
   - Test edge cases (padding, stride)
   - Validate numerical accuracy

2. **Performance Benchmarking**
   - Vary input sizes
   - Measure vs theoretical peak
   - Profile bottlenecks

3. **Stress Testing**
   - Large convolutions
   - Many small convolutions
   - Memory pressure scenarios

## Expected Performance

For AMD RX 5600M:
- Theoretical: [deferred throughput metric]
- Expected: 2-[deferred throughput metric] (40-60% efficiency)
- Target: Beat cuDNN equivalent

## Implementation Timeline

1. **Week 1**: Basic GLSL shader generation
2. **Week 2**: OpenGL integration and dispatch
3. **Week 3**: Optimization and tuning
4. **Week 4**: Benchmarking and comparison

## Success Criteria

- [ ] Numerically identical to CPU implementation
- [ ] Faster than CPU for medium/large sizes
- [ ] Clean integration with Sparkle kernel system
- [ ] No assembly code required
- [ ] Portable across AMD/NVIDIA/Intel GPUs

## Next Steps

1. Implement basic shader generator
2. Test with simple convolution
3. Add optimizations iteratively
4. Benchmark against CPU implementation
5. Document performance characteristics

This GLSL approach gives us a high-level, maintainable solution that avoids assembly while still achieving near-peak performance through careful optimization.