/*
 * DRM GPU Interface for Sparkle
 * 
 * This is The Sparkle Way - talk directly to the kernel, not vendor SDKs.
 * Uses Direct Rendering Manager (DRM) ioctls for GPU access.
 * 
 * No CUDA. No ROCm. No vendor lock-in. Just kernel interfaces.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <stdint.h>

// DRM headers - these are kernel headers, not vendor SDK
#include <drm/drm.h>
#include <drm/amdgpu_drm.h>

// Sparkle GPU context
typedef struct {
    int fd;                  // DRM device file descriptor
    uint32_t gpu_id;         // GPU ID from kernel
    uint64_t vram_size;      // VRAM size in bytes
    uint64_t gart_size;      // GTT/GART size in bytes
    char name[64];           // GPU name
    int is_amd;              // Is this an AMD GPU?
    int is_intel;            // Is this an Intel GPU?
} sparkle_gpu_context;

// Initialize GPU via DRM
sparkle_gpu_context* sparkle_gpu_init(const char* device_path) {
    sparkle_gpu_context* ctx = calloc(1, sizeof(sparkle_gpu_context));
    if (!ctx) return NULL;
    
    // Open the DRM device
    ctx->fd = open(device_path, O_RDWR);
    if (ctx->fd < 0) {
        fprintf(stderr, "Failed to open %s: %s\n", device_path, strerror(errno));
        free(ctx);
        return NULL;
    }
    
    // Get basic device info
    struct drm_version version = {0};
    if (ioctl(ctx->fd, DRM_IOCTL_VERSION, &version) == 0) {
        version.name = malloc(version.name_len);
        version.date = malloc(version.date_len);
        version.desc = malloc(version.desc_len);
        
        if (ioctl(ctx->fd, DRM_IOCTL_VERSION, &version) == 0) {
            strncpy(ctx->name, version.name, sizeof(ctx->name) - 1);
            
            // Detect GPU type
            if (strcmp(version.name, "amdgpu") == 0) {
                ctx->is_amd = 1;
            } else if (strcmp(version.name, "i915") == 0) {
                ctx->is_intel = 1;
            }
            
            printf("DRM Device: %s (%s)\n", version.name, version.desc);
        }
        
        free(version.name);
        free(version.date);
        free(version.desc);
    }
    
    // Get GPU memory info (AMD specific for now)
    if (ctx->is_amd) {
        struct drm_amdgpu_info request = {0};
        struct drm_amdgpu_memory_info mem_info = {0};
        
        request.query = AMDGPU_INFO_MEMORY;
        request.return_pointer = (uint64_t)&mem_info;
        request.return_size = sizeof(mem_info);
        
        if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_INFO, &request) == 0) {
            ctx->vram_size = mem_info.vram.total_heap_size;
            ctx->gart_size = mem_info.gtt.total_heap_size;
            
            printf("VRAM: %lu MB, GTT: %lu MB\n", 
                   ctx->vram_size / (1024*1024),
                   ctx->gart_size / (1024*1024));
        }
    }
    
    return ctx;
}

// Allocate GPU memory
typedef struct {
    uint64_t gpu_addr;       // GPU virtual address
    uint32_t handle;         // GEM handle
    void* cpu_ptr;           // CPU mapping (if mapped)
    size_t size;
} sparkle_gpu_buffer;

sparkle_gpu_buffer* sparkle_gpu_alloc(sparkle_gpu_context* ctx, size_t size) {
    if (!ctx || size == 0) return NULL;
    
    sparkle_gpu_buffer* buf = calloc(1, sizeof(sparkle_gpu_buffer));
    if (!buf) return NULL;
    
    buf->size = size;
    
    if (ctx->is_amd) {
        // AMD GPU allocation via GEM
        union drm_amdgpu_gem_create args = {0};
        args.in.bo_size = size;
        args.in.alignment = 4096;  // Page aligned
        args.in.domains = AMDGPU_GEM_DOMAIN_VRAM;
        args.in.domain_flags = AMDGPU_GEM_CREATE_CPU_ACCESS_REQUIRED;
        
        if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_CREATE, &args) == 0) {
            buf->handle = args.out.handle;
            
            // Get GPU address
            struct drm_amdgpu_gem_va va_args = {0};
            va_args.handle = buf->handle;
            va_args.operation = AMDGPU_VA_OP_MAP;
            va_args.flags = AMDGPU_VM_PAGE_READABLE | AMDGPU_VM_PAGE_WRITEABLE;
            va_args.va_address = 0;  // Let kernel choose
            va_args.offset_in_bo = 0;
            va_args.map_size = size;
            
            if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_VA, &va_args) == 0) {
                buf->gpu_addr = va_args.va_address;
                return buf;
            }
        }
    }
    
    // Fallback or other GPU types would go here
    free(buf);
    return NULL;
}

// Map GPU buffer to CPU
void* sparkle_gpu_map(sparkle_gpu_context* ctx, sparkle_gpu_buffer* buf) {
    if (!ctx || !buf || buf->cpu_ptr) return buf->cpu_ptr;
    
    if (ctx->is_amd) {
        struct drm_amdgpu_gem_mmap args = {0};
        args.handle = buf->handle;
        
        if (ioctl(ctx->fd, DRM_IOCTL_AMDGPU_GEM_MMAP, &args) == 0) {
            buf->cpu_ptr = mmap(NULL, buf->size, PROT_READ | PROT_WRITE,
                                MAP_SHARED, ctx->fd, args.out.addr_ptr);
            if (buf->cpu_ptr != MAP_FAILED) {
                return buf->cpu_ptr;
            }
        }
    }
    
    return NULL;
}

// Free GPU buffer
void sparkle_gpu_free(sparkle_gpu_context* ctx, sparkle_gpu_buffer* buf) {
    if (!ctx || !buf) return;
    
    if (buf->cpu_ptr && buf->cpu_ptr != MAP_FAILED) {
        munmap(buf->cpu_ptr, buf->size);
    }
    
    if (ctx->is_amd && buf->handle) {
        struct drm_gem_close args = {0};
        args.handle = buf->handle;
        ioctl(ctx->fd, DRM_IOCTL_GEM_CLOSE, &args);
    }
    
    free(buf);
}

// Cleanup
void sparkle_gpu_cleanup(sparkle_gpu_context* ctx) {
    if (!ctx) return;
    
    if (ctx->fd >= 0) {
        close(ctx->fd);
    }
    
    free(ctx);
}

// Simple test function
void sparkle_gpu_test() {
    printf("=== Sparkle GPU Direct Test ===\n");
    
    // Try to open the first AMD GPU
    sparkle_gpu_context* ctx = sparkle_gpu_init("/dev/dri/card1");
    if (!ctx) {
        printf("Failed to initialize GPU\n");
        return;
    }
    
    // Allocate 1MB of GPU memory
    size_t test_size = 1024 * 1024;
    sparkle_gpu_buffer* buf = sparkle_gpu_alloc(ctx, test_size);
    if (buf) {
        printf("Allocated %zu bytes at GPU address 0x%lx\n", 
               test_size, buf->gpu_addr);
        
        // Map and write some data
        float* data = (float*)sparkle_gpu_map(ctx, buf);
        if (data) {
            for (int i = 0; i < 256; i++) {
                data[i] = i * 3.14159f;
            }
            printf("Wrote test data to GPU memory\n");
        }
        
        sparkle_gpu_free(ctx, buf);
    }
    
    sparkle_gpu_cleanup(ctx);
    printf("Test complete!\n");
}