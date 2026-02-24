> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Persistent Mapped Buffers Research

## Executive Summary
Persistent mapped buffers are a staged mechanism for reducing CPU/GPU transfer overhead by allowing CPU and GPU to share a managed memory region.

## Background

### Traditional Buffer Management (Current)
```
1. CPU writes to system RAM
2. glBufferData() copies to GPU memory  
3. GPU processes data
4. glGetBufferSubData() copies back to CPU
5. CPU reads results from system RAM
```

**Problems:**
- 2 copies per operation in the non-mapped path (upload + download)
- Potentially elevated memory overhead (CPU + GPU copies)
- Synchronization stalls during transfers
- Transfer work can dominate runtime in some configurations

### Persistent Mapped Buffers (Target)
```
1. Create buffer accessible by both CPU and GPU
2. CPU writes directly to shared memory
3. GPU reads from same memory
4. Results immediately visible to CPU
```

**Potential benefits:**
- Reduced copy paths (or copy elimination in staged scenarios)
- Lower transfer-side memory pressure
- Asynchronous CPU/GPU access
- True streaming operations

## OpenGL Persistent Mapping

### Core Concepts

1. **Buffer Storage Flags**
   - `GL_MAP_PERSISTENT_BIT`: Buffer can remain mapped while used by GPU
   - `GL_MAP_COHERENT_BIT`: Writes are automatically visible
   - `GL_MAP_READ_BIT`: CPU can read
   - `GL_MAP_WRITE_BIT`: CPU can write

2. **Storage Immutability**
   - `glBufferStorage()` creates immutable storage
   - Size and flags cannot change after creation
   - More optimization opportunities for driver

3. **Synchronization Requirements**
   - Without `GL_MAP_COHERENT_BIT`: Manual flush/sync needed
   - With coherent: Automatic but potentially slower
   - Fences for fine-grained sync (we already have these!)

### API Usage Pattern

```c
// Create persistent mapped buffer
GLuint buffer;
glGenBuffers(1, &buffer);
glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer);

// Immutable storage with persistent mapping
GLbitfield flags = GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT;
glBufferStorage(GL_SHADER_STORAGE_BUFFER, size, NULL, flags);

// Map entire buffer persistently
void* ptr = glMapBufferRange(GL_SHADER_STORAGE_BUFFER, 0, size, flags);

// ptr remains valid for buffer lifetime!
// CPU can write anytime:
memcpy(ptr, data, size);

// GPU can read anytime after sync
glMemoryBarrier(GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT);
```

## Memory Coherency Models

### 1. Coherent Mapping (Simple but Slower)
```
Flags: GL_MAP_COHERENT_BIT | GL_MAP_PERSISTENT_BIT
Pro: Automatic visibility, no manual flush
Con: Every write goes through cache coherency protocol
Use: Small, frequent updates
```

### 2. Non-Coherent with Explicit Flush (Fast)
```
Flags: GL_MAP_PERSISTENT_BIT | GL_MAP_FLUSH_EXPLICIT_BIT
Pro: Batched updates, better performance
Con: Manual FlushMappedBufferRange() calls
Use: Large transfers, bulk updates
```

### 3. Write-Combined Memory (Fastest Writes)
```
Flags: GL_MAP_PERSISTENT_BIT | GL_MAP_WRITE_BIT
Pro: Bypasses CPU cache, fast streaming writes
Con: Terrible read performance, write-only
Use: Upload-only buffers (input data, uniforms)
```

## Platform Considerations

### AMD (Our Target)
- Strong persistent mapping support observed in staged testing
- Resizable BAR can expose VRAM to CPU in supported configurations
- Write-combined mappings are a key optimization path
- Coherent mappings are typically practical on RDNA3

### NVIDIA
- Good support with different optimization points
- Staged plans favor non-coherent with explicit flushes
- Write-combined can help in upload-heavy paths

### Intel
- Unified memory architecture
- Coherent mappings nearly free
- Less benefit but also less complexity

## Integration Strategy

### Phase 1: Simple Coherent Buffers
1. Start with coherent mappings (easier)
2. Replace glBufferData/glGetBufferSubData
3. Verify correctness
4. Measure baseline performance

### Phase 2: Optimized Non-Coherent
1. Switch to explicit flush model
2. Batch updates
3. Align to cache lines
4. Use fences for sync

### Phase 3: Specialized Buffers
1. Write-only input buffers
2. Read-only output buffers
3. Ping-pong for in-flight operations
4. Ring buffers for streaming

## Implementation Challenges

### 1. Pointer Management
- Persistent pointers must be tracked
- Cleanup on buffer destruction
- Safe wrapper abstractions needed

### 2. Synchronization
- CPU writes vs GPU reads
- Fence integration critical
- Memory barriers required

### 3. Error Handling
- Map failures (out of address space)
- Coherency violations
- Platform limitations

### 4. Performance Pitfalls
- Reading from write-combined memory
- False sharing between CPU/GPU
- Improper alignment

## Expected Performance Gains

### Memory Bandwidth Savings
- Upload: [deferred bandwidth] reduction target (1920×1080×4×60fps slice)
- Download: [deferred bandwidth] reduction target
- Total: [deferred bandwidth] target bandwidth recovery

### Latency Reduction
- glBufferData: ~0.5-[deferred latency] target reduction
- glGetBufferSubData: ~0.5-[deferred latency] target reduction
- Total: 1-[deferred latency] per frame target

### Real-World Impact
- Potential frame-time reduction after validation
- Potential memory usage reduction in transfer-heavy workloads
- Enables staged true GPU streaming
- Foundation for PM4 direct submission

## Code Architecture

```fortran
module gpu_persistent_buffers
  type :: persistent_buffer
    integer :: gl_buffer
    type(c_ptr) :: cpu_ptr
    integer(i64) :: size
    logical :: is_coherent
    logical :: is_mapped
  end type
  
  interface
    function create_persistent_buffer(size, flags) result(buffer)
    subroutine write_persistent_buffer(buffer, data, offset, size)
    subroutine read_persistent_buffer(buffer, data, offset, size)
    subroutine flush_persistent_buffer(buffer, offset, size)
    subroutine destroy_persistent_buffer(buffer)
  end interface
end module
```

## Next Steps

1. **Prototype coherent buffer** (1 day)
2. **Integration test** with simple compute (1 day)
3. **Performance comparison** vs traditional (1 day)
4. **Optimize with non-coherent** (2 days)
5. **Production implementation** (3 days)

## References

- [OpenGL 4.4 Persistent Mapping](https://www.khronos.org/opengl/wiki/Buffer_Object#Persistent_mapping)
- [AMD GPU Open: Persistent Mapped Buffers](https://gpuopen.com/learn/opengl-buffer-tips/)
- [NVIDIA: Optimizing OpenGL Buffer Transfers](https://developer.nvidia.com/content/optimizing-opengl-buffer-transfers)
- [Coherent Memory Tutorial](https://www.khronos.org/assets/uploads/developers/library/2014-gdc/Khronos-OpenGL-Persistent-Map-GDC-Mar14.pdf)
