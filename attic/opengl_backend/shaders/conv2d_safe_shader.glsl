#version 450

// Safe Conv2D Compute Shader
// =========================
// Simplified version to avoid GPU context lost errors

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Storage buffers
layout(std430, binding = 0) readonly buffer InputBuffer {
    float data[];
} input_buf;

layout(std430, binding = 1) readonly buffer WeightBuffer {
    float data[];
} weight_buf;

layout(std430, binding = 2) writeonly buffer OutputBuffer {
    float data[];
} output_buf;

// Parameters as specialization constants for now
layout (constant_id = 0) const int H_out = 224;
layout (constant_id = 1) const int W_out = 224;
layout (constant_id = 2) const int K = 64;

void main() {
    // Global position
    uvec3 gid = gl_GlobalInvocationID;
    
    // Each thread computes one output pixel
    int out_x = int(gid.x);
    int out_y = int(gid.y);
    int out_k = int(gid.z);
    
    // Bounds check
    if (out_x >= W_out || out_y >= H_out || out_k >= K) {
        return;
    }
    
    // Output index calculation
    int output_idx = out_k * H_out * W_out + out_y * W_out + out_x;
    
    // For now, just write a test value to verify the shader works
    output_buf.data[output_idx] = float(out_x) + float(out_y) * 0.01 + float(out_k) * 0.0001;
}