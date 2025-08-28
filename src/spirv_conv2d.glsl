#version 450

// Conv2D compute shader for Kronos (Vulkan)
// ========================================
// Adapted from OpenGL version for SPIR-V

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Storage buffers - using std430 for Vulkan compatibility
layout(std430, set = 0, binding = 0) readonly buffer InputBuffer {
    float data[];
} input_buf;

layout(std430, set = 0, binding = 1) readonly buffer WeightBuffer {
    float data[];
} weight_buf;

layout(std430, set = 0, binding = 2) buffer OutputBuffer {
    float data[];
} output_buf;

// Push constants for parameters (more efficient than specialization constants)
layout(push_constant) uniform Parameters {
    int C;          // Input channels
    int H;          // Input height
    int W;          // Input width
    int K;          // Output channels
    int kernel_size;
    int stride;
    int pad;
    int H_out;      // Output height
    int W_out;      // Output width
} params;

// Shared memory for weight caching
shared float s_weights[9];  // 3x3 kernel

void main() {
    // Each thread handles one output pixel
    uint tid = gl_GlobalInvocationID.x;
    uint total_outputs = uint(params.H_out * params.W_out);
    
    if (tid >= total_outputs) return;
    
    // Output position
    int out_y = int(tid) / params.W_out;
    int out_x = int(tid) % params.W_out;
    
    // Which output channel this workgroup handles
    int out_k = int(gl_WorkGroupID.y);
    if (out_k >= params.K) return;
    
    float sum = 0.0;
    
    // Process all input channels
    for (int c = 0; c < params.C; c++) {
        // Load weights cooperatively (first 9 threads)
        if (gl_LocalInvocationID.x < 9) {
            s_weights[gl_LocalInvocationID.x] = 
                weight_buf.data[out_k * params.C * 9 + c * 9 + gl_LocalInvocationID.x];
        }
        barrier();
        
        // Compute convolution
        for (int ky = 0; ky < 3; ky++) {
            for (int kx = 0; kx < 3; kx++) {
                int in_y = out_y * params.stride - params.pad + ky;
                int in_x = out_x * params.stride - params.pad + kx;
                
                if (in_y >= 0 && in_y < params.H && in_x >= 0 && in_x < params.W) {
                    float input_val = input_buf.data[c * params.H * params.W + in_y * params.W + in_x];
                    sum += input_val * s_weights[ky * 3 + kx];
                }
            }
        }
        
        barrier();  // Before next channel
    }
    
    // Write output
    output_buf.data[out_k * params.H_out * params.W_out + tid] = sum;
}