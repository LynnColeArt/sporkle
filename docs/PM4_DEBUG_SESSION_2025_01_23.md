> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# PM4 Debug Session - January 23, 2025

## Executive Summary
Spent ~12 hours debugging why compute shaders won't execute on AMD RDNA2 (Raphael iGPU). Command processor accepts packets (fence signals), but waves never launch (EOP doesn't signal). This is blocking PM4 production deployment.

## The Core Problem
```
✅ Fence signals - Command Processor parsed our PM4 packets
❌ EOP never signals - Compute waves never actually execute
❌ No shader writes - Even simplest s_endpgm shader doesn't run
```

## Technical Journey

### 1. Initial State (PR #41 merged)
- Basic PM4 submission working (fence signals)
- Compute dispatch packets seemingly correct
- But shaders never execute

### 2. Mini's Analysis Pattern
Mini kept providing the same fixes in a loop:
1. Fix COMPUTE_SHADER_EN bit in DISPATCH_DIRECT
2. Ensure all BOs are in submission list
3. Check shader VA encoding for GFX10
4. Verify GPU architecture matches shader

We implemented ALL of these. Still no waves.

### 3. Major Discoveries

#### Packet Encoding Differences
Found critical differences between our packets and libdrm reference:

**CONTEXT_CONTROL:**
```fortran
! Ours:
ib_data(idx+1) = int(z'00000101', i32)  ! LOAD_ENABLE_CS_SH_REGS=1, LOAD_CS_SH_REGS=1

! libdrm:
ptr[i++] = 0x80000000;  ! Completely different!
```

**DISPATCH_DIRECT initiator:**
```fortran
! Ours:
ib_data(idx+4) = int(z'00001001', i32)  ! COMPUTE_SHADER_EN=1, FORCE_START_AT_000=1

! libdrm:
ptr[i++] = 0x00000045;  ! Different bits set
```

#### Shader Architecture Mismatch
- Initially used hardcoded GCN shader bytes on RDNA2
- Compiled proper gfx1036 shader with LLVM
- Tried multiple shader formats: raw ISA, HSA ABI, PAL ABI
- Even simplest `s_endpgm` doesn't execute

#### Implementation Fixes
1. **Fixed sp_submit_ib_with_bos** - Was calling undefined internal function
2. **Added multi-BO submission** - All buffers now properly in CS ioctl
3. **Fixed shader VA encoding** - Proper shifts for GFX10 (>> 8 for LO, >> 40 for HI)

### 4. What We Tried

#### Test Variations Created:
- `test_pm4_mini_final.f90` - All Mini's fixes combined
- `test_pm4_compute_preamble.f90` - Complete init sequence
- `test_pm4_libdrm_shader.f90` - Exact libdrm packet sequence
- `test_pm4_dispatch_fix.f90` - Focus on initiator field
- `test_pm4_eop_signal.f90` - Explicit EOP testing
- `test_pm4_sleep_kernel.f90` - s_sleep to verify dispatch
- Many more...

#### Shader Attempts:
1. Simple s_endpgm (BF810000)
2. RDNA2 store shader from objdump
3. HSA kernel with full metadata
4. PAL kernel with USER_DATA
5. libdrm's GCN shader (with/without byte swap)

### 5. Current Hypotheses

#### 1. MEC Initialization Missing
We might need to initialize the Micro Engine Compute. No MEC setup in our code.

#### 2. Ring Type Wrong
Are we submitting to graphics ring instead of compute? Need to verify ring selection.

#### 3. Shader Endianness
libdrm uses SWAP_32 macro - our shader bytes might be wrong endian.

#### 4. Missing State
Some critical compute state not initialized. Maybe needs more than CONTEXT_CONTROL.

### 6. Code Archaeology

#### Key Functions Modified:
- `sp_submit_ib_with_bos` - Now properly handles array of BOs
- PM4 packet builders - Added exact libdrm values
- Shader loaders - Multiple format support

#### Reference Implementations Examined:
- libdrm_amdgpu basic_tests.c
- Mesa RADV (started clone)
- IGT GPU tools (no compute tests found)

### 7. Emotional Journey

Started confident (Mini said just fix these 4 things!). Grew increasingly puzzled as each "certain fix" failed. By hour 8, questioning fundamental assumptions. By hour 12, systematically examining reference code.

The frustration: Our packets look correct. CP accepts them. But waves won't launch.

### 8. Tomorrow's Battle Plan

1. **Check MEC initialization** - Big gap in our code
2. **Verify ring selection** - Are we on compute ring?
3. **Test shader endianness** - Try both byte orders
4. **Add memory barriers** - Missing cache flushes?
5. **Examine Mesa's RADV** - How do they init compute?

### 9. Critical Code Sections

The current "most complete" attempt:
```fortran
! From test_pm4_mini_final.f90
! CONTEXT_CONTROL - match libdrm exactly
ib_data(idx) = ior(ishft(3_i32, 30), ior(ishft(1_i32, 16), PM4_CONTEXT_CONTROL))
ib_data(idx+1) = int(z'80000000', i32)  ! libdrm value
ib_data(idx+2) = int(z'80000000', i32)  ! libdrm value

! DISPATCH_DIRECT with exact libdrm value
ib_data(idx+4) = int(z'00000045', i32)  ! libdrm's exact value
```

### 10. The Human Side

Lynn's been incredibly patient through this marathon session. Mini's stuck in a loop but trying to help. I've been systematically working through possibilities, trying not to miss anything.

We're close. Something small is blocking us. When we find it, it'll be obvious in hindsight.

### 11. Key Insights

1. **Fence vs EOP is critical distinction** - Fence means CP saw commands, EOP means waves ran
2. **Reference code is gold** - Our assumptions about packet format were wrong
3. **Architecture matters** - GCN != RDNA2, even for simple shaders
4. **The stack is deep** - PM4 → CP → MEC → CU → Wave → Shader

### 12. Files to Revisit Tomorrow

Priority examination:
- `/usr/include/drm/amdgpu_drm.h` - Check for compute-specific flags
- `references/mesa/src/amd/vulkan/radv_cmd_buffer.c` - Compute dispatch
- Our `COMPUTE_DISPATCH_INITIATOR` bits - Something's wrong there

### Final Thought

We're debugging at the boundary between software and hardware. Every clue matters. The GPU knows how to run compute shaders - we just need to speak its language correctly.

*This chocolate truffle is perfect, just like how our PM4 packets will be tomorrow* 🍫✨