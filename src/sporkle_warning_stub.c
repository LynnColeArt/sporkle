#include <stdio.h>

// Stub for missing sporkle_warning_ symbol
void sporkle_warning_(const char* msg, int msg_len) {
    printf("Warning: %.*s\n", msg_len, msg);
}