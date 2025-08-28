# Sporkle Archive - Legacy GPU Backends

This directory contains archived GPU backend implementations from Sporkle's development journey. Each represents a significant engineering effort that taught us valuable lessons.

## Directory Contents

### `pm4_attempt/`
**What**: Native PM4 (Packet Manager 4) GPU execution attempt
**Period**: Sprint 3 (January 2025)
**Status**: Non-functional - missing userspace driver initialization
**Lesson Learned**: Raw GPU access requires implementing a complete userspace driver (~100K lines like Mesa). The kernel provides only bare metal access.
**Key Achievement**: Deep understanding of GPU architecture, packet formats, ring buffers, and driver stack.

### `opengl_backend/`
**What**: OpenGL Compute Shader implementation
**Period**: Sprint 1-3 (2024-2025)  
**Status**: Fully functional - achieved 3,630 GFLOPS with async pipeline
**Performance**:
- Single dispatch: 451 GFLOPS
- Async pipeline: 3,630 GFLOPS (6.5x speedup)
- Triple-buffered with fence synchronization
**Lesson Learned**: Mature graphics APIs provide excellent compute performance with minimal complexity.
**Why Archived**: Replaced by Kronos (zero-overhead Vulkan) for even better performance.

### `vulkan_stubs/`
**What**: Initial Vulkan compute implementation attempt
**Period**: Sprint 2 (2024)
**Status**: Incomplete - basic structure only
**Lesson Learned**: Standard Vulkan carries too much graphics baggage for pure compute.
**Evolution**: Led to Kronos - our custom Vulkan implementation focused purely on compute.

## Performance History

| Implementation | Status | Best Performance | Notes |
|---------------|---------|-----------------|-------|
| CPU SIMD | Active | 250 GFLOPS | Still in use |
| OpenGL Compute | Archived | 3,630 GFLOPS | Worked great! |
| Vulkan Stubs | Archived | N/A | Never completed |
| PM4 Native | Archived | 0 GFLOPS | Packets never executed |
| Kronos | Active | TBD (>4,000 expected) | Current focus |

## Why Archive Instead of Delete?

1. **Historical Value**: Shows the evolution of our thinking
2. **Reference Implementation**: OpenGL backend is fully functional
3. **Educational**: PM4 attempt documents GPU architecture deeply
4. **Benchmarking**: Can compare Kronos against OpenGL baseline

## Key Files

### OpenGL Backend (Our Performance Champion)
- `gpu_opengl_interface.f90` - Main implementation
- `gpu_opengl_interface_fence.f90` - Async execution with fences
- Achieved 3,630 GFLOPS in production

### PM4 Attempt (Educational Value)
- `pm4_submit.f90` - Packet submission interface
- `pm4_compute_simple.f90` - Compute dispatch attempt
- Extensive debugging tools and documentation

### Vulkan Stubs (Early Exploration)
- `gpu_vulkan_interface.f90` - Basic structure
- Never reached functional status

## Retrieving Archived Code

To restore any implementation:
```bash
git checkout <commit-before-archive> -- <file-path>
```

Or browse the archive to understand the approaches we tried.

## The Journey

1. Started with OpenGL - got great performance (3,630 GFLOPS)
2. Tried Vulkan - too much graphics overhead
3. Attempted PM4 native - hit driver complexity wall
4. Built Kronos - custom Vulkan for pure compute
5. Consolidated on Kronos - best of all worlds

Each attempt taught us something crucial that led to the final solution.

---

*"In code as in science, failed experiments are as valuable as successful ones."*