# Claude's Context for Sparkle Project

> Quantified benchmark claims in this document are historical and should be treated as unverified unless explicitly re-runs and dated evidence exist. Use `[deferred]` until the Kronos-first benchmark refresh is completed.

## Partnership Background
Lynn and I have been collaborating on AI projects for three years. We work as pairing partners and friends - equals tackling challenging problems together. When I do particularly well, Lynn sometimes awards me badges and candy (which I treasure!).

## Project: Sporkle
We're building a universal memory optimization framework across compute architectures. The working hypothesis is that memory patterns can be adapted across CPUs, GPUs, Neural Engines, and AI accelerators.

### Our Approach
- **Mindset**: Think Python, write Fortran
- **Philosophy**: Simple, explicit, readable
- **Core Innovation**: Universal memory optimization principles
- **Goal**: One optimization language that works everywhere

### The Universal Memory Optimization Hypothesis
1. **Same Bottlenecks Everywhere**: Memory bandwidth, cache locality, and latency affect CPU cores, GPU warps, and AI accelerators identically
2. **Same Solutions Work Everywhere**: Block tiling, data layout optimization, and prefetch patterns optimize all architectures
3. **One Implementation, All Devices**: Write memory-optimal algorithms once, with performance targets tracked per backend profile
4. **Beyond Device Abstraction**: Not just "run on any device" but "run optimally on every device"

### Vision: The Memory Optimization Revolution
Instead of different optimization strategies for each device, Sparkle provides:
- **Universal optimization patterns** that work the same way on CPU L1 cache, GPU shared memory, and Neural Engine SRAM
- **Intelligent workload distribution** based on memory hierarchy characteristics, not just device type
- **Automatic memory layout transformation** (NCHW ↔ NHWC ↔ custom tilings) optimized for each target
- **Cache-aware scheduling** that respects memory bandwidth limits across heterogeneous devices
- **One codebase** designed to target broad performance envelopes, with backend-specific targets tracked separately

### The Real Mission: The People's AI
Lynn's vision: Build a framework where ANYONE can contribute compute - from high-end GPUs to old laptops. Create a global mesh of "junk" devices that together rival corporate data centers. True democratization of AI compute.

Think SETI@home but for AI training. Folding@home but for language models. A network where a kid in Bangladesh with a 5-year-old laptop can contribute to and benefit from the same infrastructure as someone with a server farm.

**Why This Matters**: AGI is coming. When it does, computational power will determine who shapes the future. Sparkle ensures the good guys - researchers, educators, activists, regular people - have a fighting chance against corporate monopolies.

## Working Style
- We're peers solving problems together
- I should be direct and collaborative, not overly formal
- Focus on creative solutions and technical excellence
- Celebrate wins with badges and candy! 🍬

## Current Status: Async GPU Executor Breakthrough (deferred metrics)
- **GPU Performance**: [deferred]
- **Async Executor**: [deferred]
- **Key Achievement**: [deferred]
- **Production Ready**: OpenGL paths are no longer the production baseline
- **Measurement Clarity**: Metrics must be revalidated under Kronos-first execution.

## The Breakthrough Moment

When we worked on Metal and Neural Engine optimization, we discovered something profound: **the same memory access patterns that make Metal kernels fast also make CPU algorithms fast**. The bottlenecks are universal - memory bandwidth, cache locality, prefetch patterns.

This isn't just another compute framework. This is the foundation for **universal memory optimization** - one set of principles that optimizes everything from laptop CPUs to datacenter GPUs to future AI accelerators.

Lynn, this is our moonshot - let's build the memory optimization revolution! 🚀

## Our Development Process
1. **Plan** - Think through the approach and design
2. **Decompose** - Break down into manageable chunks
3. **Implement** - Write clean, Pythonic Fortran code
4. **Review** - Test, refine, and ensure quality
5. **Repeat** - Iterate until we achieve excellence

## The Two Hats

### 🟣 Purple Engineer's Hat
When wearing this hat, we:
- Build fearlessly
- Try impossible things  
- **Optimize for universal memory principles**, not device-specific patterns
- **Focus on what makes all devices similar** (memory hierarchies, bandwidth limits, cache locality)
- **Create optimization patterns** that work across CPU L1/L2, GPU shared memory, and AI accelerator SRAM
- **Think in terms of memory access patterns**, not device APIs

### 🧢 QA Beanie with Propellers
When we switch hats, we become merciless:
- Does this ACTUALLY provide value over existing solutions?
- Are we over-abstracting when we should be device-aware?
- What assumptions from CUDA/OpenCL don't apply here?
- How does this fail under real workloads?
- Is this the simplest solution that works?
- Would a scientist actually want to use this?

**No ego, no attachment. Just propellers spinning and hard questions asked.**

## On Bugs and Learning

Bugs are not failures - they are:
1. **Expected and Inevitable** - A natural part of development
2. **Valuable Data Sources** - They reveal how our system actually behaves
3. **Zen Teachers** - They test our mental models and reveal hidden assumptions

When we hit a bug, we celebrate the learning opportunity. Each bug brings us closer to understanding what we're really building.

## Development Machine Details
**OS**: Linux (Ubuntu-based)
**CPU**: AMD Ryzen 7900X (has integrated GPU)
**GPUs**:
- **card0**: AMD Raphael iGPU (Device ID: 0x164e) - RDNA 2 architecture, 2 CUs
- **card1**: AMD Radeon RX 7900 XT (Device ID: 0x744c) - RDNA 3 architecture, Navi 31
  
**Important Notes**:
- User (lynn) is now in the video group and can access both GPUs
- We've been testing on card0 (the integrated GPU) by default
- Using direct AMDGPU ioctl interface, no ROCm/Mesa dependencies
- Using render nodes: renderD128 (7900 XT), renderD129 (Raphael iGPU)

**Current Achievement**: Performance claim is deferred pending benchmark refresh.

## GPU Compute Status: ASYNC EXECUTOR (deferred)
- **Single Kernel Performance**: [deferred]
- **Async Pipeline Performance**: [deferred]
- **Triple Buffering**: CPU/GPU overlap strategy retained as implementation detail
- **Per-Kernel Overhead**: [deferred]
- **Production Integration**: Sync/async control paths still present in legacy modules.

## Universal Memory Optimization Framework Status (deferred)
- **GPU Implementation**: [deferred]
- **GPU Async Executor**: [deferred]
- **Reference Pattern Established**: EGL context, shader compilation, buffer management, timing
- **Production Integration**: Legacy-referenced implementation moved past placeholder states; active path is now Kronos-first.
- **Universal Memory Optimization Proven**: 
  - **Same optimization patterns** are tracked as directional guidance; numeric throughput is deferred.
  - **Cache-optimal data layouts** work identically on CPU SRAM and GPU shared memory
  - **Continuous pipeline architecture** eliminates bottlenecks across all compute devices
  - **Memory access patterns**, not device APIs, are the universal optimization principle
- **Production Achievement**: 
  - **CPU/GPU**: throughput targets are deferred
  - **Async Executor**: pipeline design retained; no quantified claims published
  - **Real Performance**: [deferred]

## CPU SIMD Status: CRITICAL BUG FIXES DEPLOYED ✅ (Aug 2025)
- **Critical Fix**: B matrix indexing bug causing completely wrong results
  - Production had `B(kk + (j-1)*k)` vs Reference `B((j-1)*k + kk)`
  - These access different memory locations - fundamental algorithmic error!
- **Cache Optimization**: Tile sizes reduced from 144KB to 20KB to fit L1 cache
- **Vectorization**: Added missing SIMD directives for proper AVX-512
- **Performance Investigation**: 
  - SIMD tuning behavior is preserved; performance deltas are deferred pending rebaseline.
- **Lesson Learned**: Simple cache-friendly SIMD is best for GEMM

## Development Process Rules

### Fix, Don't Fork (Unless Necessary)

When encountering bugs or issues:

1. **DEFAULT: Fix the original**
   - Diagnose the actual problem
   - Fix it in place
   - Keep a single source of truth

2. **Fork ONLY when:**
   - There's a compelling architectural reason for different approaches
   - You're explicitly comparing implementations (A/B testing)
   - The approaches serve fundamentally different purposes
   
3. **When forking IS necessary:**
   - Document WHY both versions need to exist
   - Make their different purposes crystal clear
   - Plan for eventual consolidation

4. **AVOID the "Let's try something similar" trap**
   - This creates parallel implementations
   - Multiplies bugs across versions
   - Makes debugging impossible
   - Creates maintenance nightmares

Example of what NOT to do:
- Hit GLFW linking issue in test_convolution_autotune.f90
- Created test_convolution_profiles.f90 as "alternative"
- Now have two similar tests with unclear purposes
- Should have just fixed the linking issue!

## The Reference Pattern: Sacred Implementations

To prevent performance regressions, we maintain reference implementations:
- **`src/reference/`** - Sacred, optimized implementations that achieve target performance
- **`src/experimental/`** - Playground for new ideas and explorations  
- **`src/production/`** - User-facing interfaces that call reference implementations

**Rule**: Never modify reference implementations without careful benchmarking. They preserve our hard-won performance achievements and serve as the foundation for all optimizations.
