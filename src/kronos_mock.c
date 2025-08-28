/* kronos_mock.c - Mock implementation for testing without real Kronos
 * ==================================================================
 * This provides stub implementations so we can test the Fortran bindings
 * before building the full Rust integration.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int initialized;
    int device_id;
} mock_context;

typedef struct {
    size_t size;
    void* data;
} mock_buffer;

void* kronos_create_context(void) {
    printf("[MOCK] Creating Kronos context...\n");
    mock_context* ctx = malloc(sizeof(mock_context));
    if (ctx) {
        ctx->initialized = 1;
        ctx->device_id = 0;
    }
    return ctx;
}

void kronos_destroy_context(void* ctx) {
    printf("[MOCK] Destroying Kronos context...\n");
    if (ctx) {
        free(ctx);
    }
}

void* kronos_create_buffer(void* ctx, size_t size) {
    printf("[MOCK] Creating buffer of size %zu...\n", size);
    if (!ctx) return NULL;
    
    mock_buffer* buf = malloc(sizeof(mock_buffer));
    if (buf) {
        buf->size = size;
        buf->data = malloc(size);
        memset(buf->data, 0, size);
    }
    return buf;
}

void kronos_destroy_buffer(void* ctx, void* buffer) {
    printf("[MOCK] Destroying buffer...\n");
    if (buffer) {
        mock_buffer* buf = (mock_buffer*)buffer;
        if (buf->data) free(buf->data);
        free(buf);
    }
}

void* kronos_map_buffer(void* ctx, void* buffer) {
    if (!buffer) return NULL;
    mock_buffer* buf = (mock_buffer*)buffer;
    printf("[MOCK] Mapping buffer (size=%zu)...\n", buf->size);
    return buf->data;
}

void kronos_unmap_buffer(void* ctx, void* buffer) {
    printf("[MOCK] Unmapping buffer...\n");
}

void* kronos_create_pipeline(void* ctx, const void* spirv_data, size_t spirv_size) {
    printf("[MOCK] Creating pipeline from SPIR-V (size=%zu)...\n", spirv_size);
    // Just return a dummy pointer for now
    return ctx ? (void*)0xDEADBEEF : NULL;
}

void kronos_destroy_pipeline(void* ctx, void* pipeline) {
    printf("[MOCK] Destroying pipeline...\n");
}

void* kronos_dispatch(void* ctx, void* pipeline, void** buffers, 
                     int num_buffers, size_t gx, size_t gy, size_t gz) {
    printf("[MOCK] Dispatching kernel (%zu,%zu,%zu) with %d buffers...\n", 
           gx, gy, gz, num_buffers);
    // Return dummy fence
    return ctx ? (void*)0xFE4CE : NULL;
}

int kronos_wait_fence(void* ctx, void* fence, long long timeout_ns) {
    printf("[MOCK] Waiting on fence (timeout=%lld ns)...\n", timeout_ns);
    return 0; // SUCCESS
}

void kronos_destroy_fence(void* ctx, void* fence) {
    printf("[MOCK] Destroying fence...\n");
}