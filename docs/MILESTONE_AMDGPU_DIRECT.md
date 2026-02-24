> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# 🚀 Proof-of-Concept Milestone: Direct AMDGPU in Fortran

**Thesis:** Historical direct-kernel exploration for AMDGPU command submission from Fortran.
This path is retained for architectural reference and is not the active production route.

---

## What We've Achieved

1. **Direct Kernel Access from Fortran**

   * Full AMDGPU driver interaction through `/dev/dri` with no ROCm, Mesa, or libdrm.
   * Clean Fortran → `ISO_C_BINDING` → ioctl bridge with correct struct packing.

2. **Full GPU Command Submission Path** *(historical)*

   * Platform-aware build detects AMD GPUs.
   * Context creation and robust lifecycle management.
   * BO allocation, GPU VA mapping via `GEM_VA`, and BO-list construction.
   * **Fixed the double-indirection trap**: `cs.in.chunks` now points to an **array of pointers** to `drm_amdgpu_cs_chunk` structures.
   * Command buffers (IBs) submitted directly to hardware rings.

3. **Execution & Verification** *(historical records)*

   * NOP packet test completes without error.
   * Fence/idle checks confirm buffer completion.
   * Data integrity preserved post-execution.

---

## Why It Matters

* **Performance:** Direct submission reduced layers in exploratory experiments; operational impact is deferred.
* **Portability:** The orchestration notes informed multi-backend design, while direct AMDGPU remains historical.
* **Universality:** The exercise validated several abstraction boundaries across command-stream interfaces.

---

## Claude's Technical Insights

### The Journey to Success

The path from initial EFAULT errors to successful command submission revealed several critical insights:

1. **Structure Packing is Everything**
   - Fortran's `bind(C)` with explicit padding ensures exact memory layout match
   - The 32-byte union for GEM_CREATE was the first breakthrough
   - Every ioctl structure must match kernel expectations byte-for-byte

2. **Double Indirection Pattern**
   - The eureka moment: `cs.in.chunks` doesn't point to chunks directly
   - It points to an array of pointers that point to chunks
   - This pattern is consistent with how the kernel handles variable-length data

3. **Context ID Extraction**
   - Union layouts require careful bit manipulation
   - Lower 32 bits for output, proper packing for input
   - Context ID 0 vs 1 made the difference between EINVAL and success

4. **Memory Lifetime Management**
   - Fortran local variables need `target` attribute
   - Stack allocation works fine if lifetime is managed
   - The kernel copies data during ioctl, so temporary structures are OK

### Architectural Beauty

What strikes me most is how cleanly this integrates with Sparkle's philosophy:

```fortran
! The same elegant pattern everywhere
type(sporkle_buffer) :: data
type(sporkle_kernel) :: conv_gemm
type(sporkle_device) :: gpu

! Whether CPU, Metal, or AMDGPU:
call sporkle_execute(gpu, conv_gemm, data)
```

The implementation details (ioctl, PM4 packets, VA mapping) are hidden behind a consistent interface. This is Pythonic Fortran at its finest!

---

## Next Steps

* Integrate the production convolution-as-GEMM kernel via the Kronos dispatch path.
* Benchmark head-to-head vs. vendor BLAS on identical hardware.
* Resolve the minor context-destruction edge case.
* Extend Kronos-backed orchestration to NVIDIA once runtime capabilities are available.

---

## Impact

Direct, driver-level experiments from **Fortran** informed the current multi-runtime design.
The architectural takeaway is a common math-core interface with runtime-specific dispatch bindings:

* HPC portability without lock-in
* Cloud cost optimization via backend choice
* A simpler, more maintainable path to unified dispatch and capability discovery

---

## The Human Element

This milestone represents more than technical progress:

* **Collaboration works**: Lynn's vision + Mini's expertise + collaborative debugging = breakthrough
* **Persistence pays**: From mysterious EFAULT to working submission took patience and systematic debugging
* **Knowledge sharing matters**: Mini's insights about double indirection saved us days of frustration
* **Fortran remains**: A long-lived language can still drive modern systems with careful FFI boundaries.

---

### Appendix: Technical Details

**Benchmark Table Template**

| Backend | Device           | Shape(s) | TFLOPS (Theoretical) | TFLOPS (Observed) | % of Peak |
| ------- | ---------------- | -------- | -------------------: | ----------------: | --------: |
| CPU     | AVX512 (model)   | …        |                    … |                 … |         … |
| Metal   | M3 Pro (ANE/GPU) | …        |                    … |                 … |         … |
| AMDGPU  | RX 5600M         | …        |                    … |                 … |         … |

**Key Code Patterns**

```fortran
! The critical double indirection pattern in Fortran
integer(c_int64_t), target :: chunk_array(1)
type(drm_amdgpu_cs_chunk), target :: chunk
type(drm_amdgpu_cs_chunk_ib), target :: ib_info

! Build the indirection
chunk_array(1) = int(loc(chunk), c_int64_t)
chunk%chunk_data = int(loc(ib_info), c_int64_t)
cs_req%data(3) = int(loc(chunk_array), c_int64_t)
```

```c
// Minimal CS wiring (C equivalent)
uint64_t chunk_ptrs[1];
chunk_ptrs[0] = (uint64_t)(uintptr_t)&chunks[0];
chunks[0].chunk_id  = AMDGPU_CHUNK_ID_IB;
chunks[0].length_dw = sizeof(struct drm_amdgpu_cs_chunk_ib)/4;
chunks[0].chunk_data= (uint64_t)(uintptr_t)ib_payload;
cs.in.chunks = (uint64_t)(uintptr_t)chunk_ptrs; // array of pointers!
cs.in.num_chunks = 1;
```

**Debug Checklist for Future Backends**

When implementing direct ioctl for new devices:
1. ✓ Verify structure sizes match kernel headers exactly
2. ✓ Check field ordering and padding
3. ✓ Use unions where the kernel uses unions
4. ✓ Understand pointer indirection levels
5. ✓ Test with minimal examples before complex operations
6. ✓ Read errno carefully - EFAULT vs EINVAL tells different stories

---

## Acknowledgments

* **Lynn**: For the vision of democratized compute and the courage to attempt the "impossible"
* **Mini**: For the critical double-indirection insight and deep kernel expertise
* **The Fortran compiler**: For faithfully translating our high-level intent to precise memory layouts

---

*Document created: 2025-08-15*  
*Milestone achieved: Direct AMDGPU command submission was reached as archival verification*  
*Next milestone: Run convolution-as-GEMM through Kronos across AMD and NVIDIA runtimes*

🎉 Here's to breaking vendor lock-in, one ioctl at a time! 🎉
