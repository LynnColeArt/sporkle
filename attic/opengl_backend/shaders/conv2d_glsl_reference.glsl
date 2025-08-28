// REFERENCE IMPLEMENTATION - DO NOT MODIFY WITHOUT DISCUSSION
// 
// Performance achieved:
//   - 493 GFLOPS on AMD Radeon RX 7900 XTX
//   - 451 GFLOPS typical runtime performance
//
// Key features:
//   - Direct convolution with boundary checking
//   - Parameter buffer for flexible sizes
//   - Coalesced memory access pattern
//   - Local work size: 64
//
// Last verified: 2024-12-20
// Original source: test_conv_cpu_vs_gpu.c
//
// DO NOT MODIFY THIS FILE DIRECTLY

#version 430 core
layout(local_size_x = 64) in;

layout(std430, binding = 0) readonly buffer InputBuffer {
  float data[];
} input_buf;

layout(std430, binding = 1) readonly buffer WeightBuffer {
  float data[];
} weight_buf;

layout(std430, binding = 2) writeonly buffer OutputBuffer {
  float data[];
} output_buf;

layout(std430, binding = 3) readonly buffer ParamBuffer {
  int N, H, W, C, K;
  int kernel_size, stride, pad;
  int H_out, W_out;
} params;

void main() {
  uint idx = gl_GlobalInvocationID.x;
  if (idx >= uint(params.N * params.K * params.H_out * params.W_out)) return;
  
  // Decode output position
  int n = int(idx) / (params.K * params.H_out * params.W_out);
  int k = (int(idx) / (params.H_out * params.W_out)) % params.K;
  int h_out = (int(idx) / params.W_out) % params.H_out;
  int w_out = int(idx) % params.W_out;
  
  float sum = 0.0;
  
  // Convolution with proper padding handling
  for (int c = 0; c < params.C; c++) {
    for (int kh = 0; kh < params.kernel_size; kh++) {
      for (int kw = 0; kw < params.kernel_size; kw++) {
        int h_in = h_out * params.stride + kh - params.pad;
        int w_in = w_out * params.stride + kw - params.pad;
        
        if (h_in >= 0 && h_in < params.H && w_in >= 0 && w_in < params.W) {
          int in_idx = ((n * params.C + c) * params.H + h_in) * params.W + w_in;
          int weight_idx = ((k * params.C + c) * params.kernel_size + kh) * params.kernel_size + kw;
          sum += input_buf.data[in_idx] * weight_buf.data[weight_idx];
        }
      }
    }
  }
  
  output_buf.data[idx] = sum;
}