// Streaming (non-temporal) store wrappers for Fortran
// Portable fallback implementation to keep symbol coverage in all toolchains.

#include <stdint.h>
#include <string.h>

void mm512_stream_ps_wrapper(float* addr, const float* data) {
    memcpy(addr, data, 16 * sizeof(float));
}

void mm256_stream_ps_wrapper(float* addr, const float* data) {
    memcpy(addr, data, 8 * sizeof(float));
}

void mm128_stream_ps_wrapper(float* addr, const float* data) {
    memcpy(addr, data, 4 * sizeof(float));
}

void sfence_wrapper(void) {
    __asm__ __volatile__("sfence" : : : "memory");
}

void prefetchnta_wrapper(const void* addr) {
    __builtin_prefetch(addr, 0, 0);
}

// Utility: Check if address is aligned for streaming stores
int is_aligned_for_streaming(const void* addr, size_t alignment) {
    return ((uintptr_t)addr % alignment) == 0;
}
