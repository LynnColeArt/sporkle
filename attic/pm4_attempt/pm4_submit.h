// PM4 Submit C Header
// ===================

#ifndef PM4_SUBMIT_H
#define PM4_SUBMIT_H

#include <stdint.h>
#include <stddef.h>
#include <sys/mman.h>

// Buffer flags
#define SP_BO_DEVICE_LOCAL  0x01  // VRAM only, no CPU access
#define SP_BO_HOST_VISIBLE  0x02  // GTT, CPU mappable

// PM4 context
typedef struct sp_pm4_ctx {
    int fd;                    // DRM file descriptor
    uint32_t gpu_ctx_id;       // GPU context ID
    uint32_t device_id;        // PCI device ID
    uint32_t num_compute_rings;
} sp_pm4_ctx;

// Buffer object
typedef struct sp_bo {
    uint32_t handle;           // GEM handle
    void* cpu_ptr;             // CPU mapping (NULL if device-local)
    size_t size;               // Size in bytes
    uint64_t gpu_va;           // GPU virtual address
    uint32_t flags;            // SP_BO_* flags
} sp_bo;

// Fence for synchronization
typedef struct sp_fence {
    uint64_t fence;            // Fence sequence number
    uint32_t ctx_id;           // Context that created it
    uint32_t ip_type;          // IP type (compute)
    uint32_t ring;             // Ring index
} sp_fence;

// Device information
typedef struct sp_device_info {
    char name[64];             // Device name
    uint32_t device_id;        // PCI device ID
    uint32_t family;           // GPU family
    uint32_t num_compute_units;// Number of CUs
    uint32_t num_shader_engines;
    uint64_t max_engine_clock; // Max GPU clock in KHz
    uint64_t max_memory_clock; // Max memory clock in KHz
    uint32_t gpu_counter_freq; // GPU counter frequency in KHz
    uint32_t vram_type;        // VRAM type (GDDR6, etc)
    uint32_t vram_bit_width;   // Memory bus width
    uint32_t ce_ram_size;      // Constant engine RAM size
    uint32_t num_tcc_blocks;   // Number of TCC blocks
    uint64_t vram_size;        // VRAM size in bytes
    uint64_t gtt_size;         // GTT size in bytes
} sp_device_info;

// PM4 packet opcodes (minimal set)
#define PM4_NOP                    0x10
#define PM4_SET_SH_REG            0x76
#define PM4_DISPATCH_DIRECT       0x15
#define PM4_WRITE_DATA            0x37
#define PM4_ACQUIRE_MEM           0x58
#define PM4_WAIT_REG_MEM          0x3C

// Register offsets
#define COMPUTE_PGM_LO            0x212
#define COMPUTE_PGM_HI            0x213
#define COMPUTE_PGM_RSRC1         0x214
#define COMPUTE_PGM_RSRC2         0x215
#define COMPUTE_NUM_THREAD_X      0x219
#define COMPUTE_NUM_THREAD_Y      0x21A
#define COMPUTE_NUM_THREAD_Z      0x21B

// API functions
sp_pm4_ctx* sp_pm4_init(const char* device_path);
void sp_pm4_cleanup(sp_pm4_ctx* ctx);
int sp_pm4_get_device_info(sp_pm4_ctx* ctx, sp_device_info* info);

sp_bo* sp_buffer_alloc(sp_pm4_ctx* ctx, size_t size, uint32_t flags);
void sp_buffer_free(sp_pm4_ctx* ctx, sp_bo* bo);

// REMOVED: sp_submit_ib and sp_submit_ib_with_bo
// Use sp_submit_ib_with_bos from src/compute/submit.h instead

// Specialized debug function for testing specific ring/instance combinations
// Note: For normal use, always use sp_submit_ib_with_bos from src/compute/submit.h
int sp_submit_ib_ring(sp_pm4_ctx* ctx, sp_bo* ib_bo, uint32_t ib_size_dw, 
                      uint32_t ip_instance, uint32_t ring, sp_fence* out_fence);

int sp_fence_wait(sp_pm4_ctx* ctx, sp_fence* fence, uint64_t timeout_ns);
int sp_fence_check(sp_pm4_ctx* ctx, sp_fence* fence);

#endif // PM4_SUBMIT_H