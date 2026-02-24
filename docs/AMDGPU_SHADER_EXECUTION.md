> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# AMDGPU Shader Execution Strategy

## Overview

This document outlines our approach to executing compute shaders on AMD GPUs using direct PM4 command submission, without relying on ROCm or any vendor SDK.

## Shader Binary Format

AMD GPUs use the GCN (Graphics Core Next) or RDNA ISA (Instruction Set Architecture). Shaders must be compiled to this binary format.

### Options for Obtaining Shader Binaries:

1. **Pre-compiled Binaries**
   - Compile shaders offline using LLVM/AMDGPU backend
   - Embed binaries in Fortran as data arrays
   - Pros: Simple, no runtime compilation needed
   - Cons: Fixed to specific GPU architectures

2. **Runtime Assembly**
   - Write GCN assembly directly
   - Assemble at runtime using our own assembler
   - Pros: Full control, can adapt to GPU
   - Cons: Complex to implement

3. **LLVM Integration**
   - Link with LLVM's AMDGPU backend
   - Compile from LLVM IR at runtime
   - Pros: Flexible, supports optimization
   - Cons: Large dependency

## PM4 Packet Structure for Compute Dispatch

```
1. Set shader program address (COMPUTE_PGM_LO/HI)
2. Configure shader resources (COMPUTE_PGM_RSRC1/2)
3. Set workgroup dimensions (COMPUTE_NUM_THREAD_X/Y/Z)
4. Set kernel arguments (user SGPRs)
5. Dispatch compute grid (DISPATCH_DIRECT)
6. Memory fence (ACQUIRE_MEM)
```

## Implementation Progress

### ✅ Completed:
- PM4 packet generation functions
- Shader structure definitions
- Compute dispatch framework
- Register definitions for GFX9

### 🔨 In Progress:
- Actual shader binary (currently placeholder)
- Memory copy operations (DMA)
- Kernel argument passing

### 📋 TODO:
- Implement real vector_add shader binary
- Add DMA operations for memory transfers
- Test on actual hardware
- Add safety checks for GPU generation

## Example: Vector Addition Kernel

### High-level code:
```c
void vector_add(float* a, float* b, float* c, int n) {
    int tid = get_global_id(0);
    if (tid < n) {
        c[tid] = a[tid] + b[tid];
    }
}
```

### GCN Assembly (simplified):
```asm
; Load kernel arguments from SGPRs
s_load_dwordx4 s[0:3], s[4:5], 0x00  ; Load a, b pointers
s_load_dwordx2 s[8:9], s[4:5], 0x10  ; Load c pointer
s_load_dword s10, s[4:5], 0x18        ; Load n

; Calculate global thread ID
v_lshlrev_b32 v0, 2, v0              ; tid *= 4 (sizeof(float))

; Load values
v_add_u32 v1, s0, v0                 ; address = a + offset
v_add_u32 v2, s2, v0                 ; address = b + offset
flat_load_dword v3, v[1:2]           ; load a[tid]
flat_load_dword v4, v[2:3]           ; load b[tid]

; Add
v_add_f32 v5, v3, v4                 ; c = a + b

; Store result
v_add_u32 v6, s8, v0                 ; address = c + offset
flat_store_dword v[6:7], v5          ; store c[tid]
```

## Memory Management

### Buffer Setup:
1. Allocate buffers using GEM_CREATE
2. Map to GPU VA space using GEM_VA
3. Pass GPU addresses to shader via kernel args

### Data Transfer Options:
1. **CPU Mapping**: Map GPU buffer to CPU space, memcpy data
2. **SDMA**: Use DMA engine for async transfers
3. **Compute Shader**: Use copy kernel

## Testing Strategy

1. Start with simple vector operations
2. Verify using CPU readback
3. Progress to complex kernels (GEMM)
4. Benchmark against CPU baseline

## Safety Considerations

- Always check GPU generation before dispatch
- Validate shader binary size
- Use timeout mechanisms
- Verify completion before reading results

## Next Steps

1. Implement real GCN shader binary for vector_add
2. Add SDMA support for memory transfers
3. Test on hardware
4. Extend to GEMM kernel
5. Integrate with adaptive framework

## References

- AMD GCN3 ISA Manual
- AMD PM4 Packet Reference
- Linux AMDGPU Driver Source