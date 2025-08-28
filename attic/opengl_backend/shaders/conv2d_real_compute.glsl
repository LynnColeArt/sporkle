#version 450

// Conv2D with CPU-style Memory Optimization for GPU
// =================================================
// Apply the same tiling patterns that made CPU fast

// Wave32 optimal for RDNA3
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(std430, binding = 0) readonly buffer InputBuffer {
    float data[];
} input_buf;

layout(std430, binding = 1) readonly buffer WeightBuffer {
    float data[];
} weight_buf;

layout(std430, binding = 2) buffer OutputBuffer {
    float data[];
} output_buf;

// Parameters
layout (constant_id = 0) const int C = 64;
layout (constant_id = 1) const int H = 224;
layout (constant_id = 2) const int W = 224;
layout (constant_id = 3) const int K = 64;
layout (constant_id = 4) const int kernel_size = 3;
layout (constant_id = 5) const int stride = 1;
layout (constant_id = 6) const int pad = 1;
layout (constant_id = 7) const int H_out = 224;
layout (constant_id = 8) const int W_out = 224;

// Apply CPU memory optimization principles:
// 1. Process multiple outputs per thread (like CPU register blocking)
// 2. Tile both inputs AND outputs (like CPU cache blocking)
// 3. Sequential memory access (like CPU prefetching)

// Shared memory = GPU's L1 cache
shared float tile_input[4][36];  // 4 input channels × 36 pixels (6×6 with padding)
shared float tile_weights[4][64][9]; // 4 input channels × 64 output channels × 9 weights

void main() {
    const int TILE_H = 4;  // Output tile height
    const int TILE_W = 8;  // Output tile width (32 threads = 4×8)
    const int CHAN_BLOCK = 4; // Process 4 channels at a time (like CPU vectorization)
    
    int tid = int(gl_LocalInvocationID.x);
    int wg_id = int(gl_WorkGroupID.x);
    
    // Each workgroup handles TILE_H × TILE_W outputs
    int tile_row = wg_id / ((W_out + TILE_W - 1) / TILE_W);
    int tile_col = wg_id % ((W_out + TILE_W - 1) / TILE_W);
    
    int base_out_y = tile_row * TILE_H;
    int base_out_x = tile_col * TILE_W;
    
    // Each thread computes one output
    int local_y = tid / TILE_W;
    int local_x = tid % TILE_W;
    int out_y = base_out_y + local_y;
    int out_x = base_out_x + local_x;
    
    if (out_y >= H_out || out_x >= W_out) return;
    
    // Process all output channels
    for (int ko = 0; ko < K; ko += 16) {  // Output channel blocking
        // Accumulator for 16 output channels
        float sum[16];
        for (int i = 0; i < 16; i++) sum[i] = 0.0;
        
        // Process input channels in blocks
        for (int ci = 0; ci < C; ci += CHAN_BLOCK) {
            // Collaborative load input tile (6×6 for 4×8 outputs with 3×3 kernel)
            if (tid < 36) {
                for (int c = 0; c < CHAN_BLOCK; c++) {
                    if (ci + c < C) {
                        int py = tid / 6;
                        int px = tid % 6;
                        int in_y = base_out_y + py - pad;
                        int in_x = base_out_x + px - pad;
                        
                        if (in_y >= 0 && in_y < H && in_x >= 0 && in_x < W) {
                            tile_input[c][tid] = input_buf.data[(ci + c) * H * W + in_y * W + in_x];
                        } else {
                            tile_input[c][tid] = 0.0;
                        }
                    }
                }
            }
            
            // Load weights for current block (each thread loads some)
            // 32 threads load 4×16×9 = 576 values
            int weights_per_thread = (CHAN_BLOCK * 16 * 9 + 31) / 32;
            int weight_base = tid * weights_per_thread;
            
            for (int w = 0; w < weights_per_thread; w++) {
                int idx = weight_base + w;
                if (idx < CHAN_BLOCK * 16 * 9) {
                    int c = idx / (16 * 9);
                    int k = (idx / 9) % 16;
                    int kyx = idx % 9;
                    
                    if (ci + c < C && ko + k < K) {
                        tile_weights[c][k][kyx] = 
                            weight_buf.data[(ko + k) * C * 9 + (ci + c) * 9 + kyx];
                    }
                }
            }
            
            barrier();
            
            // Compute convolution for this channel block
            for (int c = 0; c < CHAN_BLOCK; c++) {
                if (ci + c < C) {
                    // Input position for this thread's output
                    int in_base_y = local_y;
                    int in_base_x = local_x;
                    
                    // Convolve with all 16 output channels
                    for (int k = 0; k < 16; k++) {
                        if (ko + k < K) {
                            // 3x3 convolution
                            for (int ky = 0; ky < 3; ky++) {
                                for (int kx = 0; kx < 3; kx++) {
                                    int idx = (in_base_y + ky) * 6 + (in_base_x + kx);
                                    sum[k] += tile_input[c][idx] * tile_weights[c][k][ky * 3 + kx];
                                }
                            }
                        }
                    }
                }
            }
            
            barrier();
        }
        
        // Write outputs
        for (int k = 0; k < 16; k++) {
            if (ko + k < K) {
                output_buf.data[(ko + k) * H_out * W_out + out_y * W_out + out_x] = sum[k];
            }
        }
    }
}