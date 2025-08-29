/* kronos_c_bridge.c - C bridge between Kronos Rust API and Fortran
 * ================================================================
 * This bridges the gap between Rust's kronos-compute crate and our
 * Fortran code. We'll use Rust's C FFI to expose Kronos functionality.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Opaque handle types - matches Rust's opaque pointers */
typedef void* kronos_context_t;
typedef void* kronos_buffer_t;
typedef void* kronos_pipeline_t;
typedef void* kronos_fence_t;

/* Error codes */
#define KRONOS_SUCCESS 0
#define KRONOS_ERROR_INIT -1
#define KRONOS_ERROR_OOM -2
#define KRONOS_ERROR_COMPILE -3
#define KRONOS_ERROR_INVALID -4

/* Rust FFI functions from our sporkle_kronos library */
extern kronos_context_t kronos_compute_create_context(void);
extern void kronos_compute_destroy_context(kronos_context_t ctx);

extern kronos_buffer_t kronos_compute_create_buffer(kronos_context_t ctx, size_t size);
extern void kronos_compute_destroy_buffer(kronos_context_t ctx, kronos_buffer_t buffer);
extern void* kronos_compute_map_buffer(kronos_context_t ctx, kronos_buffer_t buffer);
extern void kronos_compute_unmap_buffer(kronos_context_t ctx, kronos_buffer_t buffer);

extern kronos_pipeline_t kronos_compute_create_pipeline(kronos_context_t ctx, 
                                                        const uint32_t* spirv_data, 
                                                        size_t spirv_size);
extern void kronos_compute_destroy_pipeline(kronos_context_t ctx, kronos_pipeline_t pipeline);

extern kronos_fence_t kronos_compute_dispatch(kronos_context_t ctx,
                                              kronos_pipeline_t pipeline,
                                              kronos_buffer_t* buffers,
                                              int num_buffers,
                                              size_t global_x,
                                              size_t global_y,
                                              size_t global_z);
extern int kronos_compute_wait_fence(kronos_context_t ctx, 
                                     kronos_fence_t fence, 
                                     int64_t timeout_ns);
extern void kronos_compute_destroy_fence(kronos_context_t ctx, kronos_fence_t fence);

/* C bridge functions with Fortran-friendly names */
kronos_context_t kronos_create_context(void) {
    return kronos_compute_create_context();
}

void kronos_destroy_context(kronos_context_t ctx) {
    if (ctx) {
        kronos_compute_destroy_context(ctx);
    }
}

kronos_buffer_t kronos_create_buffer(kronos_context_t ctx, size_t size) {
    if (!ctx) return NULL;
    return kronos_compute_create_buffer(ctx, size);
}

void kronos_destroy_buffer(kronos_context_t ctx, kronos_buffer_t buffer) {
    if (ctx && buffer) {
        kronos_compute_destroy_buffer(ctx, buffer);
    }
}

void* kronos_map_buffer(kronos_context_t ctx, kronos_buffer_t buffer) {
    if (!ctx || !buffer) return NULL;
    return kronos_compute_map_buffer(ctx, buffer);
}

void kronos_unmap_buffer(kronos_context_t ctx, kronos_buffer_t buffer) {
    if (ctx && buffer) {
        kronos_compute_unmap_buffer(ctx, buffer);
    }
}

kronos_pipeline_t kronos_create_pipeline(kronos_context_t ctx, 
                                        const void* spirv_data, 
                                        size_t spirv_size) {
    if (!ctx || !spirv_data || spirv_size == 0) return NULL;
    
    /* Kronos expects SPIR-V as uint32_t array */
    return kronos_compute_create_pipeline(ctx, 
                                         (const uint32_t*)spirv_data, 
                                         spirv_size / sizeof(uint32_t));
}

void kronos_destroy_pipeline(kronos_context_t ctx, kronos_pipeline_t pipeline) {
    if (ctx && pipeline) {
        kronos_compute_destroy_pipeline(ctx, pipeline);
    }
}

kronos_fence_t kronos_dispatch(kronos_context_t ctx,
                               kronos_pipeline_t pipeline,
                               void** buffers,
                               int num_buffers,
                               size_t global_x,
                               size_t global_y,
                               size_t global_z) {
    if (!ctx || !pipeline || !buffers || num_buffers <= 0) return NULL;
    
    return kronos_compute_dispatch(ctx, pipeline, 
                                  (kronos_buffer_t*)buffers, num_buffers,
                                  global_x, global_y, global_z);
}

int kronos_wait_fence(kronos_context_t ctx, kronos_fence_t fence, int64_t timeout_ns) {
    if (!ctx || !fence) return KRONOS_ERROR_INVALID;
    return kronos_compute_wait_fence(ctx, fence, timeout_ns);
}

void kronos_destroy_fence(kronos_context_t ctx, kronos_fence_t fence) {
    if (ctx && fence) {
        kronos_compute_destroy_fence(ctx, fence);
    }
}