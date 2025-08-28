# Sprint 4: The Great Consolidation
## Kronos-Sporkle Integration & Legacy Cleanup

### 🎯 Epic Overview

After hitting the PM4 wall in Sprint 3, we pivoted to building Kronos - a zero-overhead Vulkan compute runtime in Rust. Now it's time to integrate this powerful engine into Sporkle and clean house.

### 📊 Current State

**What We Have:**
- ✅ Sporkle: 3,630 GFLOPS via OpenGL (working but messy)
- ✅ Kronos: Zero-overhead Vulkan compute (RC1, published to crates.io)
- ✅ Unified sporkle_conv2d API with fence-based async
- ❌ Three different GPU backends (OpenGL, legacy Vulkan stubs, PM4 attempts)
- ❌ Fragmented codebase with multiple abandoned approaches

**Performance Baseline:**
- CPU SIMD: 250 GFLOPS
- GPU (OpenGL): 3,630 GFLOPS
- Target (Kronos): 4,000+ GFLOPS

### 🚀 Sprint Goals

#### 1. **HAL Layer Introduction** 
Create `sporkle-hal` with clean trait abstractions:
```rust
pub trait Device {
    type Buffer: Buffer;
    type Pipeline: Pipeline;
    type Queue: Queue;
}
```

#### 2. **Kronos Integration**
- Implement HAL traits for Kronos
- Create Fortran FFI bindings
- Port conv2d shaders to SPIR-V
- Replace gpu_opengl_interface.f90

#### 3. **Legacy Cleanup**
Move to `/attic`:
- `src/sporkle_gpu_opengl.f90` (replaced by Kronos)
- `src/production/gpu_opengl_*.f90`
- `src/production/gpu_vulkan_*.f90` (stubs)
- All PM4 implementation attempts
- GLSL shader generators

#### 4. **Communication Architecture v2**

**In-Process Mode (Default):**
- Direct Rust→Rust calls
- Zero serialization overhead
- Perfect for single-node compute

**Daemon Mode (Optional):**
- `sporkled` daemon process
- FlatBuffers control plane
- Shared memory data rings
- Enables distributed compute vision

#### 5. **Developer Experience**
- `SPORKLE_TRACE=1`: Full execution tracing
- `SPORKLE_VALIDATION=1`: Resource/state checking
- `.spkl` crash dumps for debugging
- Record/replay infrastructure

### 📋 Task Breakdown

#### Phase 1: HAL Design (Week 1)
- [ ] Define core HAL traits in Rust
- [ ] Document trait semantics
- [ ] Create mock implementation for testing

#### Phase 2: Kronos Integration (Week 2-3)
- [ ] Implement HAL traits for Kronos
- [ ] Create C FFI layer for Fortran
- [ ] Port conv2d GLSL → SPIR-V
- [ ] Wire up sporkle_conv2d → Kronos

#### Phase 3: Legacy Cleanup (Week 4)
- [x] Archive OpenGL implementation (achieved 3,630 GFLOPS)
- [x] Archive PM4 attempts (educational value preserved)
- [x] Remove unused Vulkan stubs
- [x] Update build system (smart Makefile preserves detection logic)

#### Phase 4: Communication Layer (Week 5-6)
- [ ] Design FlatBuffers schema
- [ ] Implement sporkled daemon
- [ ] Shared memory ring buffers
- [ ] Client library

#### Phase 5: Testing & Polish (Week 7-8)
- [ ] Performance benchmarks
- [ ] Record/replay tests
- [ ] CI matrix setup
- [ ] Documentation

### 🎯 Success Metrics

1. **Performance**: Beat 3,630 GFLOPS baseline
2. **Simplicity**: Single GPU backend (Kronos)
3. **Stability**: 100% deterministic replay
4. **Developer Joy**: Clean traces, fast iteration

### 💡 Key Insights

**From Mini's outline:**
- Don't reinvent drivers - adapt and optimize
- Rust provides the safety and performance we need
- Clean separation: Kronos (compute) vs Sporkle (orchestration)

**Additional thoughts:**
- HAL layer enables future backends (Metal, DirectML)
- Daemon mode unlocks the "People's AI" distributed vision
- Record/replay is crucial for debugging async compute

### 🔮 Beyond Sprint 4

With this foundation:
- **Sprint 5**: Multi-device orchestration
- **Sprint 6**: Network distribution
- **Sprint 7**: Auto-tuning and load balancing
- **Sprint 8**: Production deployment

The dream of democratized compute becomes real when anyone can:
```rust
let cluster = Sporkle::connect("mesh://global")?;
let result = cluster.compute(&my_model)?;
```

### 📝 Notes

- Keep Fortran API stable during transition
- Benchmark at each integration step
- Document migration path for users

### 🎉 Progress Update (Jan 28, 2025)

**Phase 3 Complete!** 

We've successfully cleaned up the legacy GPU backends:

1. **Archived Implementations**:
   - `/attic/pm4_attempt/` - PM4 native GPU packets (non-functional but educational)
   - `/attic/opengl_backend/` - Our performance champion (3,630 GFLOPS)
   - `/attic/vulkan_stubs/` - Early Vulkan exploration

2. **Smart Makefile Updates**:
   - Preserved ALL platform detection logic (AMD/NVIDIA/Intel/Apple)
   - GPU backends temporarily disabled with helpful messages
   - Forces CPU-only mode until Kronos integration
   - Added AVX-512 support for C code
   - Fixed module dependencies and build order

3. **Documentation**:
   - Created comprehensive `/attic/README.md`
   - Preserved performance history and lessons learned
   - Clear path for retrieving archived code if needed

**Key Achievement**: The smart Makefile still detects GPUs and libraries but gracefully falls back to CPU mode. When Kronos is ready, we can simply re-enable the GPU paths without losing any detection capabilities.

**Next Steps**: Ready for Phase 2 - Kronos Integration!

---

*"We're not just consolidating code - we're consolidating our vision into reality."* - Mini & Claude