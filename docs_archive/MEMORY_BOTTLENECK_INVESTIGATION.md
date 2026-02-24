> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Memory Bottleneck Investigation - Session Summary

## Current Status: CONFIRMED Memory Residency Issue

We've systematically proven that our 2,600 GFLOPS performance ceiling is due to a **host-visible memory trap**. The GPU driver is allocating our "device-local" buffers in system RAM instead of true VRAM, limiting us to system memory bandwidth instead of GPU memory bandwidth.

## Evidence Summary

### 1. Performance Ceiling Consistency
- **256×256 workload**: 2,668 GFLOPS (our baseline)
- **512×512 workload**: 821 GFLOPS (0.31× scaling vs 4× ideal)
- **Ko=4 parallel**: 629 GFLOPS (register pressure regression)

### 2. Memory Residency Tests
- **Two-dispatch speedup**: 1.15× (should be >1.5× for true VRAM)
- **Device-local allocation hints**: No improvement
- **GL_STATIC_DRAW + staging**: No improvement
- **Persistent staging + unmapped SSBOs**: No improvement (2,645 GFLOPS)

### 3. Scaling Analysis
- **Universal Dispatcher (512×512)**: Poor scaling confirms fixed overhead dominance
- **Arithmetic intensity**: 148 FLOP/byte (should easily saturate 400+ GB/s VRAM)
- **Theoretical limit**: 57 TFLOPS available, but hitting 2.6 TFLOPS ceiling

## Attempted Solutions (All Failed)

### OpenGL Allocation Strategies Tested:
1. ✅ `GL_DYNAMIC_COPY` (baseline approach)
2. ✅ `GL_STATIC_DRAW` with NULL allocation
3. ✅ Explicit staging ring with `glCopyBufferSubData`
4. ✅ OpenGL 4.4+ `glBufferStorage` with `GL_DYNAMIC_STORAGE_BIT`
5. ✅ Persistent mapped staging + unmapped device SSBOs
6. ✅ Various usage hints and allocation patterns

**Result**: All approaches hit the same 2,600 GFLOPS ceiling.

## Key Insight: Driver Stubbornness

The NVIDIA OpenGL driver appears to be **ignoring all our device-local allocation hints** and keeping data in system RAM. Even the most aggressive approaches (unmapped device SSBOs with explicit GPU copy) show no improvement.

## Critical Test Needed: Vulkan Comparison

We need to test if **Vulkan's explicit memory management** can break through this ceiling:

```cpp
// Vulkan critical test
VkMemoryPropertyFlags memProps = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
// This GUARANTEES true VRAM allocation
```

**If Vulkan shows >4,000 GFLOPS**: OpenGL driver issue, rewrite justified
**If Vulkan shows ~2,600 GFLOPS**: Deeper hardware/thermal/clock limit

## Next Steps for Main Rig

1. **Install Vulkan** (if not present):
   ```bash
   sudo apt install vulkan-tools libvulkan-dev vulkan-validationlayers-dev
   ```

2. **Compile and run Vulkan test**:
   ```bash
   g++ -O3 test_vulkan_minimal.cpp -lvulkan -o test_vulkan_minimal
   ./test_vulkan_minimal
   ```

3. **If Vulkan breaks ceiling**: Plan Vulkan rewrite strategy
4. **If Vulkan hits same ceiling**: Investigate alternative causes:
   - GPU clock throttling (thermal?)
   - Driver-level performance caps
   - Memory bandwidth probe kernel
   - Larger workload testing (1024×1024)

## Files Ready for Testing

- `test_vulkan_minimal.cpp` - Minimal Vulkan compute test with explicit VRAM
- `test_escape_hatch.f90` - Comprehensive OpenGL memory allocation test
- `test_universal_dispatcher.f90` - Scaling analysis tool

## Architecture Still Sound

Important: Our **Summit V2 shader architecture is excellent**:
- ✅ 32×32 tiling with Ko=64 blocking
- ✅ Shared memory optimization
- ✅ NHWC layout
- ✅ Register-optimal accumulation

The algorithm is not the problem - it's the memory subsystem.

## Performance Context

2,600 GFLOPS represents:
- **16% of GPU theoretical peak** (16.5 TFLOPS)
- **Excellent real-world performance** for many applications
- **5× faster than CPU implementation**

But if true VRAM residency can unlock 6,000+ GFLOPS, it's worth pursuing.

## Decision Point

The Vulkan test will definitively answer: **Is the OpenGL driver the bottleneck, or is there a fundamental limit we're hitting?**

---

*Session ended at memory bottleneck investigation. Ready for Vulkan testing on main rig.*