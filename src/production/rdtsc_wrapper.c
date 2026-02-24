#include <stdint.h>

uint64_t rdtsc_wrapper() {
    unsigned int lo, hi;
    __asm__ __volatile__ ("rdtsc" : "=a" (lo), "=d" (hi));
    return ((uint64_t)hi << 32) | lo;
}

uint64_t rdtscp_wrapper() {
    unsigned int lo, hi, aux;
    __asm__ __volatile__ ("rdtscp" : "=a" (lo), "=d" (hi), "=c" (aux));
    return ((uint64_t)hi << 32) | lo;
}

uint64_t rdtsc_fenced() {
    unsigned int lo, hi;
    __asm__ __volatile__ ("mfence");
    __asm__ __volatile__ ("rdtsc" : "=a" (lo), "=d" (hi));
    return ((uint64_t)hi << 32) | lo;
}
