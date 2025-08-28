#version 450

// Simple compute shader that copies input to output
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// Storage buffers
layout(std430, binding = 0) readonly buffer InputBuffer {
    float data[];
} input_buf;

layout(std430, binding = 1) writeonly buffer OutputBuffer {
    float data[];
} output_buf;

void main() {
    uint idx = gl_GlobalInvocationID.x;
    
    // Simple copy operation
    output_buf.data[idx] = input_buf.data[idx] * 2.0;
}