#version 450

// Optimized Conv2D for RDNA3
// ==========================
// Simple but effective shared memory usage

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Storage buffers
layout(std430, binding = 0) readonly buffer InputBuffer {
    float data[];
} input_buf;

layout(std430, binding = 1) readonly buffer WeightBuffer {
    float data[];
} weight_buf;

layout(std430, binding = 2) buffer OutputBuffer {
    float data[];
} output_buf;

// Convolution parameters
layout (constant_id = 0) const int C = 64;
layout (constant_id = 1) const int H = 224;
layout (constant_id = 2) const int W = 224;
layout (constant_id = 3) const int K = 64;
layout (constant_id = 4) const int kernel_size = 3;
layout (constant_id = 5) const int stride = 1;
layout (constant_id = 6) const int pad = 1;
layout (constant_id = 7) const int H_out = 224;
layout (constant_id = 8) const int W_out = 224;

// Shared memory for weights (most reused data)
shared float s_weights[9];  // 3x3 kernel

void main() {
    // Each thread handles one output pixel
    uint tid = gl_GlobalInvocationID.x;
    uint total_outputs = uint(H_out * W_out);
    
    if (tid >= total_outputs) return;
    
    // Output position
    int out_y = int(tid) / W_out;
    int out_x = int(tid) % W_out;
    
    // Which output channel this workgroup handles
    int out_k = int(gl_WorkGroupID.y);
    if (out_k >= K) return;
    
    float sum = 0.0;
    
    // Process all input channels
    for (int c = 0; c < C; c++) {
        // Load weights cooperatively (first 9 threads)
        if (gl_LocalInvocationID.x < 9) {
            s_weights[gl_LocalInvocationID.x] = 
                weight_buf.data[out_k * C * 9 + c * 9 + gl_LocalInvocationID.x];
        }
        barrier();
        
        // Compute convolution
        for (int ky = 0; ky < 3; ky++) {
            for (int kx = 0; kx < 3; kx++) {
                int in_y = out_y * stride - pad + ky;
                int in_x = out_x * stride - pad + kx;
                
                if (in_y >= 0 && in_y < H && in_x >= 0 && in_x < W) {
                    float input_val = input_buf.data[c * H * W + in_y * W + in_x];
                    sum += input_val * s_weights[ky * 3 + kx];
                }
            }
        }
        
        barrier();  // Before next channel
    }
    
    // Write output
    output_buf.data[out_k * H_out * W_out + tid] = sum;
}