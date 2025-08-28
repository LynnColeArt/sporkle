// PM4 Real Submission Implementation
// ==================================
// Replace stub with actual ioctl-based GPU command submission
// This is pm4_submit_impl.c (renamed to avoid conflict with pm4_submit.f90)

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <pthread.h>
#include <drm/drm.h>
#include <drm/amdgpu_drm.h>

#include "pm4_submit.h"

// Logging levels
enum {
    SP_LOG_TRACE = 0,
    SP_LOG_INFO  = 1,
    SP_LOG_WARN  = 2,
    SP_LOG_ERROR = 3
};

static int g_log_level = SP_LOG_INFO;

// VA allocator structures
typedef struct va_range {
    uint64_t start;
    uint64_t size;
    struct va_range* next;
} va_range;

typedef struct va_allocator {
    va_range* free_list;
    uint64_t base_addr;
    uint64_t total_size;
    pthread_mutex_t lock;
} va_allocator;

static va_allocator g_va_alloc = {0};

// Simple logger (no emojis!)
static void sp_log(int level, const char* fmt, ...) {
    if (level < g_log_level) return;
    
    const char* prefix[] = {"[TRACE]", "[INFO]", "[WARN]", "[ERROR]"};
    fprintf(stderr, "%s ", prefix[level]);
    
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
}

// Initialize VA allocator
static int va_allocator_init(uint64_t base, uint64_t size) {
    pthread_mutex_init(&g_va_alloc.lock, NULL);
    g_va_alloc.base_addr = base;
    g_va_alloc.total_size = size;
    
    // Create initial free range covering entire VA space
    g_va_alloc.free_list = malloc(sizeof(va_range));
    if (!g_va_alloc.free_list) return -ENOMEM;
    
    g_va_alloc.free_list->start = base;
    g_va_alloc.free_list->size = size;
    g_va_alloc.free_list->next = NULL;
    
    sp_log(SP_LOG_TRACE, "VA allocator initialized: base=0x%lx, size=0x%lx", base, size);
    return 0;
}

// Cleanup VA allocator
static void va_allocator_cleanup(void) {
    pthread_mutex_lock(&g_va_alloc.lock);
    
    va_range* current = g_va_alloc.free_list;
    while (current) {
        va_range* next = current->next;
        free(current);
        current = next;
    }
    g_va_alloc.free_list = NULL;
    
    pthread_mutex_unlock(&g_va_alloc.lock);
    pthread_mutex_destroy(&g_va_alloc.lock);
}

// Allocate VA space
static uint64_t va_alloc(uint64_t size) {
    // Align to 64KB
    size = (size + 0xFFFF) & ~0xFFFF;
    
    pthread_mutex_lock(&g_va_alloc.lock);
    
    va_range* prev = NULL;
    va_range* current = g_va_alloc.free_list;
    
    while (current) {
        if (current->size >= size) {
            // Found a suitable range
            uint64_t addr = current->start;
            
            if (current->size == size) {
                // Exact match - remove this range
                if (prev) {
                    prev->next = current->next;
                } else {
                    g_va_alloc.free_list = current->next;
                }
                free(current);
            } else {
                // Split the range
                current->start += size;
                current->size -= size;
            }
            
            pthread_mutex_unlock(&g_va_alloc.lock);
            sp_log(SP_LOG_TRACE, "VA allocated: addr=0x%lx, size=0x%lx", addr, size);
            return addr;
        }
        prev = current;
        current = current->next;
    }
    
    pthread_mutex_unlock(&g_va_alloc.lock);
    sp_log(SP_LOG_ERROR, "VA allocation failed: no space for size 0x%lx", size);
    return 0;
}

// Free VA space
static void va_free(uint64_t addr, uint64_t size) {
    // Align to 64KB
    size = (size + 0xFFFF) & ~0xFFFF;
    
    pthread_mutex_lock(&g_va_alloc.lock);
    
    // Create new free range
    va_range* new_range = malloc(sizeof(va_range));
    if (!new_range) {
        pthread_mutex_unlock(&g_va_alloc.lock);
        sp_log(SP_LOG_ERROR, "Failed to allocate free range");
        return;
    }
    
    new_range->start = addr;
    new_range->size = size;
    
    // Insert into free list (sorted by address for coalescing)
    va_range* prev = NULL;
    va_range* current = g_va_alloc.free_list;
    
    while (current && current->start < addr) {
        prev = current;
        current = current->next;
    }
    
    // Check if we can coalesce with previous range
    if (prev && prev->start + prev->size == addr) {
        prev->size += size;
        free(new_range);
        new_range = prev;
    } else {
        new_range->next = current;
        if (prev) {
            prev->next = new_range;
        } else {
            g_va_alloc.free_list = new_range;
        }
    }
    
    // Check if we can coalesce with next range
    if (current && new_range->start + new_range->size == current->start) {
        new_range->size += current->size;
        new_range->next = current->next;
        free(current);
    }
    
    pthread_mutex_unlock(&g_va_alloc.lock);
    sp_log(SP_LOG_TRACE, "VA freed: addr=0x%lx, size=0x%lx", addr, size);
}

// Initialize PM4 context
sp_pm4_ctx* sp_pm4_init(const char* device_path) {
    sp_pm4_ctx* ctx = calloc(1, sizeof(sp_pm4_ctx));
    if (!ctx) {
        sp_log(SP_LOG_ERROR, "Failed to allocate PM4 context");
        return NULL;
    }
    
    // Open render node (default to renderD129 for iGPU)
    ctx->fd = open(device_path ? device_path : "/dev/dri/renderD129", O_RDWR);
    if (ctx->fd < 0) {
        sp_log(SP_LOG_ERROR, "Failed to open device: %s", strerror(errno));
        free(ctx);
        return NULL;
    }
    
    // Verify this is amdgpu driver
    struct drm_version version = {0};
    char name[64] = {0};
    version.name = name;
    version.name_len = sizeof(name);
    
    if (ioctl(ctx->fd, DRM_IOCTL_VERSION, &version) == 0) {
        sp_log(SP_LOG_TRACE, "DRM driver: %s", name);
        if (strcmp(name, "amdgpu") != 0) {
            sp_log(SP_LOG_ERROR, "Not an amdgpu device: %s", name);
            close(ctx->fd);
            free(ctx);
            return NULL;
        }
    }
    
    // Get device info
    struct drm_amdgpu_info request = {0};
    struct drm_amdgpu_info_device dev_info = {0};
    
    request.return_pointer = (uintptr_t)&dev_info;
    request.return_size = sizeof(dev_info);
    request.query = AMDGPU_INFO_DEV_INFO;
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_INFO, &request) < 0) {
        sp_log(SP_LOG_ERROR, "Failed to get device info: %s", strerror(errno));
        close(ctx->fd);
        free(ctx);
        return NULL;
    }
    
    ctx->device_id = dev_info.device_id;
    
    // Query actual compute ring count
    struct drm_amdgpu_info_hw_ip hw_ip_info = {0};
    request.return_pointer = (uintptr_t)&hw_ip_info;
    request.return_size = sizeof(hw_ip_info);
    request.query = AMDGPU_INFO_HW_IP_INFO;
    request.query_hw_ip.type = AMDGPU_HW_IP_COMPUTE;
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_INFO, &request) == 0) {
        ctx->num_compute_rings = hw_ip_info.available_rings;
    } else {
        sp_log(SP_LOG_WARN, "Failed to query compute rings, defaulting to 1");
        ctx->num_compute_rings = 1;
    }
    
    sp_log(SP_LOG_INFO, "PM4 context initialized on device 0x%04x", ctx->device_id);
    sp_log(SP_LOG_INFO, "Compute rings available: %d", ctx->num_compute_rings);
    sp_log(SP_LOG_TRACE, "Device fd: %d", ctx->fd);
    
    // Create GPU context
    union drm_amdgpu_ctx ctx_args = {0};
    ctx_args.in.op = AMDGPU_CTX_OP_ALLOC_CTX;
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_CTX, &ctx_args) < 0) {
        sp_log(SP_LOG_ERROR, "Failed to create GPU context: %s", strerror(errno));
        close(ctx->fd);
        free(ctx);
        return NULL;
    }
    
    ctx->gpu_ctx_id = ctx_args.out.alloc.ctx_id;
    sp_log(SP_LOG_TRACE, "GPU context created: %u", ctx->gpu_ctx_id);
    
    // Initialize VA allocator on first context creation
    static int va_init_done = 0;
    if (!va_init_done) {
        // VA space from 32GB to 1TB
        if (va_allocator_init(0x800000000ULL, 0xF800000000ULL) < 0) {
            sp_log(SP_LOG_ERROR, "Failed to initialize VA allocator");
            // Cleanup and fail
            union drm_amdgpu_ctx cleanup_args = {0};
            cleanup_args.in.op = AMDGPU_CTX_OP_FREE_CTX;
            cleanup_args.in.ctx_id = ctx->gpu_ctx_id;
            ioctl(ctx->fd, DRM_IOCTL_AMDGPU_CTX, &cleanup_args);
            close(ctx->fd);
            free(ctx);
            return NULL;
        }
        va_init_done = 1;
    }
    
    return ctx;
}

// Cleanup PM4 context
void sp_pm4_cleanup(sp_pm4_ctx* ctx) {
    if (!ctx) return;
    
    // Destroy GPU context
    if (ctx->gpu_ctx_id) {
        union drm_amdgpu_ctx ctx_args = {0};
        ctx_args.in.op = AMDGPU_CTX_OP_FREE_CTX;
        ctx_args.in.ctx_id = ctx->gpu_ctx_id;
        ioctl(ctx->fd, DRM_IOCTL_AMDGPU_CTX, &ctx_args);
    }
    
    if (ctx->fd >= 0) {
        close(ctx->fd);
    }
    
    sp_log(SP_LOG_TRACE, "PM4 context cleaned up");
    free(ctx);
}

// Get device info from PM4 context
int sp_pm4_get_device_info(sp_pm4_ctx* ctx, sp_device_info* info) {
    if (!ctx || !info) {
        sp_log(SP_LOG_ERROR, "NULL context or info passed to sp_pm4_get_device_info");
        return -1;
    }
    
    struct drm_amdgpu_info request = {0};
    struct drm_amdgpu_info_device dev_info = {0};
    
    request.return_pointer = (uintptr_t)&dev_info;
    request.return_size = sizeof(dev_info);
    request.query = AMDGPU_INFO_DEV_INFO;
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_INFO, &request) < 0) {
        sp_log(SP_LOG_ERROR, "Failed to get device info: %s", strerror(errno));
        return -1;
    }
    
    // Fill in device info
    info->device_id = dev_info.device_id;
    info->family = dev_info.family;
    info->num_compute_units = dev_info.cu_active_number;
    info->num_shader_engines = dev_info.num_shader_engines;
    info->max_engine_clock = dev_info.max_engine_clock;
    info->max_memory_clock = dev_info.max_memory_clock;
    info->gpu_counter_freq = dev_info.gpu_counter_freq;
    info->vram_type = dev_info.vram_type;
    info->vram_bit_width = dev_info.vram_bit_width;
    info->ce_ram_size = dev_info.ce_ram_size;
    info->num_tcc_blocks = dev_info.num_tcc_blocks;
    
    // Get memory info
    request.query = AMDGPU_INFO_VRAM_GTT;
    struct drm_amdgpu_info_vram_gtt vram_gtt = {0};
    request.return_pointer = (uintptr_t)&vram_gtt;
    request.return_size = sizeof(vram_gtt);
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_INFO, &request) == 0) {
        info->vram_size = vram_gtt.vram_size;
        info->gtt_size = vram_gtt.gtt_size;
    }
    
    // Determine device name based on device ID
    switch (info->device_id) {
        case 0x164e: snprintf(info->name, sizeof(info->name), "AMD Raphael (iGPU)"); break;
        case 0x744c: snprintf(info->name, sizeof(info->name), "AMD Radeon RX 7900 XT"); break;
        default: snprintf(info->name, sizeof(info->name), "AMD GPU 0x%04x", info->device_id); break;
    }
    
    return 0;
}

// Allocate GPU buffer
sp_bo* sp_buffer_alloc(sp_pm4_ctx* ctx, size_t size, uint32_t flags) {
    if (!ctx) {
        sp_log(SP_LOG_ERROR, "NULL context passed to sp_buffer_alloc");
        return NULL;
    }
    
    sp_log(SP_LOG_TRACE, "sp_buffer_alloc called: size=%zu, flags=0x%x, fd=%d", 
           size, flags, ctx->fd);
    
    sp_bo* bo = calloc(1, sizeof(sp_bo));
    if (!bo) return NULL;
    
    // Align size to page
    size = (size + 4095) & ~4095;
    bo->size = size;
    bo->flags = flags;
    
    // GEM allocation
    union drm_amdgpu_gem_create gem_args = {0};
    gem_args.in.bo_size = size;
    gem_args.in.alignment = 4096;
    
    // For now, use GTT for all allocations (works on both APU and dGPU)
    gem_args.in.domains = AMDGPU_GEM_DOMAIN_GTT;
    if (!(flags & SP_BO_DEVICE_LOCAL)) {
        gem_args.in.domain_flags = AMDGPU_GEM_CREATE_CPU_ACCESS_REQUIRED;
    } else {
        gem_args.in.domain_flags = 0;
    }
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_CREATE, &gem_args) < 0) {
        sp_log(SP_LOG_ERROR, "GEM_CREATE failed: %s (domains=0x%x, size=%zu)", 
               strerror(errno), gem_args.in.domains, size);
        free(bo);
        return NULL;
    }
    
    bo->handle = gem_args.out.handle;
    
    // Allocate VA space using proper allocator
    bo->gpu_va = va_alloc(size);
    if (!bo->gpu_va) {
        sp_log(SP_LOG_ERROR, "Failed to allocate VA space for size %zu", size);
        struct drm_gem_close close_args = {0};
        close_args.handle = bo->handle;
        ioctl(ctx->fd, DRM_IOCTL_GEM_CLOSE, &close_args);
        free(bo);
        return NULL;
    }
    
    // Map buffer to GPU VA
    struct drm_amdgpu_gem_va va_args = {0};
    va_args.handle = bo->handle;
    va_args.operation = AMDGPU_VA_OP_MAP;
    
    // Set flags based on buffer type
    if (flags & SP_BO_HOST_VISIBLE) {
        // Host visible buffers need read/write for data, executable for shaders
        va_args.flags = AMDGPU_VM_PAGE_READABLE | AMDGPU_VM_PAGE_WRITEABLE | AMDGPU_VM_PAGE_EXECUTABLE;
    } else {
        // Device local buffers need read/write
        va_args.flags = AMDGPU_VM_PAGE_READABLE | AMDGPU_VM_PAGE_WRITEABLE;
    }
    
    va_args.va_address = bo->gpu_va;
    va_args.offset_in_bo = 0;
    va_args.map_size = size;
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_VA, &va_args) < 0) {
        sp_log(SP_LOG_ERROR, "Failed to map VA: %s (va=0x%lx, size=%zu)", 
               strerror(errno), bo->gpu_va, size);
        // Don't free here - causes double free
        struct drm_gem_close close_args = {0};
        close_args.handle = bo->handle;
        ioctl(ctx->fd, DRM_IOCTL_GEM_CLOSE, &close_args);
        free(bo);
        return NULL;
    }
    
    // VA already set above
    
    // CPU map if host visible
    if (!(flags & SP_BO_DEVICE_LOCAL)) {
        union drm_amdgpu_gem_mmap mmap_args = {0};
        mmap_args.in.handle = bo->handle;
        
        if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_MMAP, &mmap_args) == 0) {
            bo->cpu_ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, 
                              MAP_SHARED, ctx->fd, mmap_args.out.addr_ptr);
            if (bo->cpu_ptr == MAP_FAILED) {
                bo->cpu_ptr = NULL;
            } else {
                sp_log(SP_LOG_TRACE, "Mapped buffer: mmap_offset=0x%lx", 
                       mmap_args.out.addr_ptr);
            }
        }
    }
    
    sp_log(SP_LOG_TRACE, "Allocated buffer: size=%zu, gpu_va=0x%lx, flags=0x%x", 
           size, bo->gpu_va, flags);
    
    return bo;
}

// Free GPU buffer
void sp_buffer_free(sp_pm4_ctx* ctx, sp_bo* bo) {
    if (!ctx || !bo) return;
    
    // Unmap CPU
    if (bo->cpu_ptr) {
        munmap(bo->cpu_ptr, bo->size);
    }
    
    // Unmap GPU VA
    if (bo->gpu_va) {
        struct drm_amdgpu_gem_va va_args = {0};
        va_args.handle = bo->handle;
        va_args.operation = AMDGPU_VA_OP_UNMAP;
        va_args.va_address = bo->gpu_va;
        va_args.map_size = bo->size;
        ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_VA, &va_args);
        
        // Return VA space to allocator
        va_free(bo->gpu_va, bo->size);
    }
    
    // Free GEM object
    if (bo->handle) {
        struct drm_gem_close close_args = {0};
        close_args.handle = bo->handle;
        ioctl(ctx->fd, DRM_IOCTL_GEM_CLOSE, &close_args);
    }
    
    sp_log(SP_LOG_TRACE, "Freed buffer: gpu_va=0x%lx", bo->gpu_va);
    free(bo);
}

// REMOVED: sp_submit_ib_with_bo - use sp_submit_ib_with_bos instead
// This function was replaced to ensure all BOs are submitted together
#if 0
int sp_submit_ib_with_bo(sp_pm4_ctx* ctx, sp_bo* ib_bo, uint32_t ib_size_dw, 
                         sp_bo* data_bo, sp_fence* out_fence) {
    if (!ctx || !ib_bo || !out_fence) return -EINVAL;
    
    // Validate IB buffer size
    uint32_t ib_size_bytes = ib_size_dw * 4;
    sp_log(SP_LOG_TRACE, "IB validation: requested=%u bytes, buffer_size=%zu bytes", 
           ib_size_bytes, ib_bo->size);
    if (ib_size_bytes > ib_bo->size) {
        sp_log(SP_LOG_ERROR, "IB size overflow: %u bytes requested, buffer is %zu bytes",
               ib_size_bytes, ib_bo->size);
        return -EINVAL;
    }
    
    // Validate GPU VA alignment (must be 4-byte aligned for IB)
    if (ib_bo->gpu_va & 0x3) {
        sp_log(SP_LOG_ERROR, "IB GPU VA not aligned: 0x%lx (must be 4-byte aligned)",
               ib_bo->gpu_va);
        return -EINVAL;
    }
    
    // Validate data buffer if provided
    if (data_bo) {
        if (data_bo->gpu_va == 0) {
            sp_log(SP_LOG_ERROR, "Data buffer has no GPU VA mapping");
            return -EINVAL;
        }
        // Check for VA range overlap
        uint64_t ib_end = ib_bo->gpu_va + ib_bo->size;
        uint64_t data_start = data_bo->gpu_va;
        uint64_t data_end = data_bo->gpu_va + data_bo->size;
        if ((ib_bo->gpu_va < data_end) && (ib_end > data_start)) {
            sp_log(SP_LOG_ERROR, "Buffer VA overlap: IB [0x%lx-0x%lx], Data [0x%lx-0x%lx]",
                   ib_bo->gpu_va, ib_end, data_start, data_end);
            return -EINVAL;
        }
    }
    
    sp_log(SP_LOG_TRACE, "sp_submit_ib_with_bo: ctx=%p, ib_bo=%p, size_dw=%u, data_bo=%p", 
           ctx, ib_bo, ib_size_dw, data_bo);
    
    // Create BO list with IB and data buffer
    uint32_t bo_list_handle = 0;
    union drm_amdgpu_bo_list bo_list_args = {0};
    
    // Include both IB and data buffer in BO list
    int num_bos = data_bo ? 2 : 1;
    struct drm_amdgpu_bo_list_entry bo_info[2] = {0};
    
    bo_info[0].bo_handle = ib_bo->handle;
    bo_info[0].bo_priority = 0;
    
    if (data_bo) {
        bo_info[1].bo_handle = data_bo->handle;
        bo_info[1].bo_priority = 0;
    }
    
    bo_list_args.in.operation = AMDGPU_BO_LIST_OP_CREATE;
    bo_list_args.in.bo_number = num_bos;
    bo_list_args.in.bo_info_size = sizeof(struct drm_amdgpu_bo_list_entry);
    bo_list_args.in.bo_info_ptr = (uintptr_t)bo_info;
    
    sp_log(SP_LOG_TRACE, "Creating BO list with %d buffers: IB=%u, data=%u", 
           num_bos, ib_bo->handle, data_bo ? data_bo->handle : 0);
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_BO_LIST, &bo_list_args) < 0) {
        sp_log(SP_LOG_WARN, "Failed to create BO list: %s. Trying without...", 
               strerror(errno));
        bo_list_handle = 0;
    } else {
        bo_list_handle = bo_list_args.out.list_handle;
        sp_log(SP_LOG_TRACE, "Created BO list: handle=%u", bo_list_handle);
    }
    
    // Build CS submission - allocate on heap per Mini's suggestion
    struct drm_amdgpu_cs_chunk *chunks = calloc(1, sizeof(struct drm_amdgpu_cs_chunk));
    struct drm_amdgpu_cs_chunk_ib *ib_data = calloc(1, sizeof(struct drm_amdgpu_cs_chunk_ib));
    uint64_t *chunk_ptrs = calloc(1, sizeof(uint64_t));  // CRITICAL: Array of pointers!
    
    if (!chunks || !ib_data || !chunk_ptrs) {
        sp_log(SP_LOG_ERROR, "Failed to allocate CS structures");
        if (bo_list_handle > 0) {
            bo_list_args.in.operation = AMDGPU_BO_LIST_OP_DESTROY;
            bo_list_args.in.list_handle = bo_list_handle;
            ioctl(ctx->fd, DRM_IOCTL_AMDGPU_BO_LIST, &bo_list_args);
        }
        free(chunks);
        free(ib_data);
        free(chunk_ptrs);
        return -ENOMEM;
    }
    
    // Fill IB info
    ib_data->_pad = 0;  // Explicit padding field
    ib_data->flags = 0;
    ib_data->va_start = ib_bo->gpu_va;
    ib_data->ib_bytes = ib_size_dw * 4;  // Size in BYTES, not dwords
    ib_data->ip_type = AMDGPU_HW_IP_COMPUTE;  // Use COMPUTE ring as Mini suggests
    ib_data->ip_instance = 0;
    ib_data->ring = 0;
    
    // CRITICAL: length_dw is the size of the STRUCT, not the IB!
    chunks[0].chunk_id = AMDGPU_CHUNK_ID_IB;
    chunks[0].length_dw = sizeof(struct drm_amdgpu_cs_chunk_ib) / 4;
    chunks[0].chunk_data = (uint64_t)(uintptr_t)ib_data;
    
    // CRITICAL FIX: Create array of pointers to chunks!
    chunk_ptrs[0] = (uint64_t)(uintptr_t)&chunks[0];
    
    sp_log(SP_LOG_TRACE, "Chunk setup: struct_size=%zu, length_dw=%u", 
           sizeof(struct drm_amdgpu_cs_chunk_ib), chunks[0].length_dw);
    
    union drm_amdgpu_cs cs_args = {0};
    cs_args.in.ctx_id = ctx->gpu_ctx_id;
    cs_args.in.bo_list_handle = bo_list_handle;
    cs_args.in.num_chunks = 1;
    cs_args.in.chunks = (uint64_t)(uintptr_t)chunk_ptrs;  // Pass pointer array!
    
    sp_log(SP_LOG_TRACE, "CS submit: ctx=%u, bo_list=%u, chunks=%u, ib_va=0x%lx, ib_bytes=%u",
           ctx->gpu_ctx_id, bo_list_handle, cs_args.in.num_chunks, 
           ib_data->va_start, ib_data->ib_bytes);
    sp_log(SP_LOG_TRACE, "  chunks ptr: %p, chunk[0] ptr: %p", 
           (void*)cs_args.in.chunks, chunks);
    sp_log(SP_LOG_TRACE, "  ib_data ptr: %p, chunk_ptrs[0]: 0x%lx", ib_data, chunk_ptrs[0]);
    sp_log(SP_LOG_TRACE, "  IP type: %u, instance: %u, ring: %u", 
           ib_data->ip_type, ib_data->ip_instance, ib_data->ring);
    
    int ret = ioctl(ctx->fd, DRM_IOCTL_AMDGPU_CS, &cs_args);
    
    // Cleanup BO list if we created one
    if (bo_list_handle > 0) {
        bo_list_args.in.operation = AMDGPU_BO_LIST_OP_DESTROY;
        bo_list_args.in.list_handle = bo_list_handle;
        ioctl(ctx->fd, DRM_IOCTL_AMDGPU_BO_LIST, &bo_list_args);
    }
    
    if (ret < 0) {
        sp_log(SP_LOG_ERROR, "CS submit failed: %s", strerror(errno));
        free(chunks);
        free(ib_data);
        free(chunk_ptrs);
        return -errno;
    }
    
    // Return fence info
    out_fence->ctx_id = ctx->gpu_ctx_id;
    out_fence->ip_type = AMDGPU_HW_IP_COMPUTE;  // Match the submission type
    out_fence->ring = 0;
    out_fence->fence = cs_args.out.handle;
    
    sp_log(SP_LOG_TRACE, "Submitted IB: %u dwords, fence=%lu", ib_size_dw, out_fence->fence);
    
    free(chunks);
    free(ib_data);
    free(chunk_ptrs);
    return 0;
}
#endif

// REMOVED: sp_submit_ib - use sp_submit_ib_with_bos instead

// Submit IB with multiple buffer objects
int sp_submit_ib_with_bos(sp_pm4_ctx* ctx, sp_bo* ib_bo, uint32_t ib_size_dw,
                          sp_bo** data_bos, uint32_t num_data_bos, sp_fence* out_fence) {
    sp_log(SP_LOG_INFO, "sp_submit_ib_with_bos: ctx=%p, ib_bo=%p, data_bos=%p, num=%u", 
           ctx, ib_bo, data_bos, num_data_bos);
    
    if (!ctx || !ib_bo || !out_fence) return -EINVAL;
    
    // Validate IB buffer
    uint32_t ib_size_bytes = ib_size_dw * 4;
    if (ib_size_bytes > ib_bo->size) {
        sp_log(SP_LOG_ERROR, "IB size overflow: %u bytes requested, buffer is %zu bytes",
               ib_size_bytes, ib_bo->size);
        return -EINVAL;
    }
    
    // Create BO list with all buffers
    uint32_t bo_list_handle = 0;
    union drm_amdgpu_bo_list bo_list_args = {0};
    
    int total_bos = 1 + num_data_bos;
    struct drm_amdgpu_bo_list_entry* bo_info = calloc(total_bos, sizeof(struct drm_amdgpu_bo_list_entry));
    if (!bo_info) return -ENOMEM;
    
    // Add IB buffer
    bo_info[0].bo_handle = ib_bo->handle;
    bo_info[0].bo_priority = 0;
    
    // Add data buffers
    for (uint32_t i = 0; i < num_data_bos; i++) {
        if (!data_bos[i]) {
            free(bo_info);
            return -EINVAL;
        }
        bo_info[i + 1].bo_handle = data_bos[i]->handle;
        bo_info[i + 1].bo_priority = 0;
    }
    
    bo_list_args.in.operation = AMDGPU_BO_LIST_OP_CREATE;
    bo_list_args.in.bo_number = total_bos;
    bo_list_args.in.bo_info_size = sizeof(struct drm_amdgpu_bo_list_entry);
    bo_list_args.in.bo_info_ptr = (uintptr_t)bo_info;
    
    sp_log(SP_LOG_TRACE, "Creating BO list with %d buffers (IB + %d data)", total_bos, num_data_bos);
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_BO_LIST, &bo_list_args) < 0) {
        sp_log(SP_LOG_ERROR, "Failed to create BO list: %s", strerror(errno));
        free(bo_info);
        return -errno;
    }
    
    free(bo_info);
    bo_list_handle = bo_list_args.out.list_handle;
    
    // Build CS submission
    struct drm_amdgpu_cs_chunk *chunks = calloc(1, sizeof(struct drm_amdgpu_cs_chunk));
    struct drm_amdgpu_cs_chunk_ib *ib_data = calloc(1, sizeof(struct drm_amdgpu_cs_chunk_ib));
    uint64_t *chunk_ptrs = calloc(1, sizeof(uint64_t));
    
    if (!chunks || !ib_data || !chunk_ptrs) {
        sp_log(SP_LOG_ERROR, "Failed to allocate CS structures");
        // Clean up BO list
        bo_list_args.in.operation = AMDGPU_BO_LIST_OP_DESTROY;
        bo_list_args.in.list_handle = bo_list_handle;
        ioctl(ctx->fd, DRM_IOCTL_AMDGPU_BO_LIST, &bo_list_args);
        free(chunks);
        free(ib_data);
        free(chunk_ptrs);
        return -ENOMEM;
    }
    
    // Fill IB info
    ib_data->_pad = 0;
    ib_data->flags = 0;
    ib_data->va_start = ib_bo->gpu_va;
    ib_data->ib_bytes = ib_size_bytes;
    ib_data->ip_type = AMDGPU_HW_IP_COMPUTE;
    ib_data->ip_instance = 0;
    ib_data->ring = 0;
    
    chunks[0].chunk_id = AMDGPU_CHUNK_ID_IB;
    chunks[0].length_dw = sizeof(struct drm_amdgpu_cs_chunk_ib) / 4;
    chunks[0].chunk_data = (uint64_t)(uintptr_t)ib_data;
    
    chunk_ptrs[0] = (uint64_t)(uintptr_t)&chunks[0];
    
    union drm_amdgpu_cs cs_args = {0};
    cs_args.in.ctx_id = ctx->gpu_ctx_id;
    cs_args.in.bo_list_handle = bo_list_handle;
    cs_args.in.num_chunks = 1;
    cs_args.in.chunks = (uint64_t)(uintptr_t)chunk_ptrs;
    
    sp_log(SP_LOG_TRACE, "CS submit with %d BOs: ctx=%u, bo_list=%u, ib_va=0x%lx, ib_bytes=%u",
           total_bos, ctx->gpu_ctx_id, bo_list_handle, ib_data->va_start, ib_data->ib_bytes);
    
    int ret = ioctl(ctx->fd, DRM_IOCTL_AMDGPU_CS, &cs_args);
    
    // Clean up BO list
    bo_list_args.in.operation = AMDGPU_BO_LIST_OP_DESTROY;
    bo_list_args.in.list_handle = bo_list_handle;
    ioctl(ctx->fd, DRM_IOCTL_AMDGPU_BO_LIST, &bo_list_args);
    
    if (ret < 0) {
        sp_log(SP_LOG_ERROR, "CS submit failed: %s", strerror(errno));
        free(chunks);
        free(ib_data);
        free(chunk_ptrs);
        return -errno;
    }
    
    // Return fence info
    out_fence->ctx_id = ctx->gpu_ctx_id;
    out_fence->ip_type = AMDGPU_HW_IP_COMPUTE;
    out_fence->ring = 0;
    out_fence->fence = cs_args.out.handle;
    
    sp_log(SP_LOG_TRACE, "Submitted IB with %d BOs: fence=%lu", total_bos, out_fence->fence);
    
    free(chunks);
    free(ib_data);
    free(chunk_ptrs);
    return 0;
}

// Submit IB with specific ring/instance selection
int sp_submit_ib_ring(sp_pm4_ctx* ctx, sp_bo* ib_bo, uint32_t ib_size_dw, 
                      uint32_t ip_instance, uint32_t ring, sp_fence* out_fence) {
    sp_log(SP_LOG_TRACE, "Submitting IB with instance=%u, ring=%u", ip_instance, ring);
    
    struct drm_amdgpu_cs_chunk chunks[1] = {0};
    struct drm_amdgpu_cs_chunk_ib* ib_data = calloc(1, sizeof(struct drm_amdgpu_cs_chunk_ib));
    if (!ib_data) return -ENOMEM;
    
    // Set up IB data
    ib_data->va_start = ib_bo->gpu_va;
    ib_data->ib_bytes = ib_size_dw * 4;
    ib_data->ip_type = AMDGPU_HW_IP_COMPUTE;
    ib_data->ip_instance = ip_instance;
    ib_data->ring = ring;
    
    chunks[0].chunk_id = AMDGPU_CHUNK_ID_IB;
    chunks[0].length_dw = sizeof(struct drm_amdgpu_cs_chunk_ib) / 4;
    chunks[0].chunk_data = (uintptr_t)ib_data;
    
    // Submit
    union drm_amdgpu_cs cs_args = {0};
    cs_args.in.ctx_id = ctx->gpu_ctx_id;
    cs_args.in.bo_list_handle = 0;
    cs_args.in.num_chunks = 1;
    cs_args.in.chunks = (uintptr_t)chunks;
    
    int ret = ioctl(ctx->fd, DRM_IOCTL_AMDGPU_CS, &cs_args);
    if (ret < 0) {
        sp_log(SP_LOG_ERROR, "CS ioctl failed: %s", strerror(errno));
        free(ib_data);
        return ret;
    }
    
    // Fill fence info
    out_fence->ctx_id = ctx->gpu_ctx_id;
    out_fence->ip_type = AMDGPU_HW_IP_COMPUTE;
    out_fence->ring = ring;
    out_fence->fence = cs_args.out.handle;
    
    free(ib_data);
    return 0;
}

// Wait for fence (blocking)
int sp_fence_wait(sp_pm4_ctx* ctx, sp_fence* fence, uint64_t timeout_ns) {
    union drm_amdgpu_wait_cs wait_args = {0};
    wait_args.in.handle = fence->fence;
    wait_args.in.ip_type = fence->ip_type;
    wait_args.in.ctx_id = fence->ctx_id;
    wait_args.in.timeout = timeout_ns;
    
    if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_WAIT_CS, &wait_args) < 0) {
        if (errno == ETIME) {
            return -ETIME;  // Timeout
        }
        sp_log(SP_LOG_ERROR, "Fence wait failed: %s", strerror(errno));
        return -errno;
    }
    
    return 0;
}

// Check fence status (non-blocking)
int sp_fence_check(sp_pm4_ctx* ctx, sp_fence* fence) {
    return sp_fence_wait(ctx, fence, 0);  // 0 timeout = poll
}

// Initialize logging from environment
__attribute__((constructor))
static void sp_init_logging(void) {
    const char* level = getenv("SPORKLE_LOG_LEVEL");
    if (level) {
        if (strcmp(level, "TRACE") == 0) g_log_level = SP_LOG_TRACE;
        else if (strcmp(level, "INFO") == 0) g_log_level = SP_LOG_INFO;
        else if (strcmp(level, "WARN") == 0) g_log_level = SP_LOG_WARN;
        else if (strcmp(level, "ERROR") == 0) g_log_level = SP_LOG_ERROR;
    }
}