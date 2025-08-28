// GPU Device Discovery
// ====================
// Automatically discover available GPU render nodes

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#define MAX_GPU_DEVICES 8

// Check if a path is a valid render node
static int is_render_node(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    
    // Check if it's a character device
    if (!S_ISCHR(st.st_mode)) return 0;
    
    // Try to open it to verify it's accessible
    int fd = open(path, O_RDWR);
    if (fd < 0) {
        // Try read-only as fallback
        fd = open(path, O_RDONLY);
        if (fd < 0) return 0;
    }
    close(fd);
    
    return 1;
}

// Discover GPU render nodes
// Returns number of devices found, fills paths array
int sp_discover_gpu_devices(char paths[][256], int max_devices) {
    DIR* dir;
    struct dirent* entry;
    int count = 0;
    
    // Open /dev/dri directory
    dir = opendir("/dev/dri");
    if (!dir) {
        fprintf(stderr, "Failed to open /dev/dri: %s\n", strerror(errno));
        return 0;
    }
    
    // Scan for renderD* nodes
    while ((entry = readdir(dir)) != NULL && count < max_devices) {
        if (strncmp(entry->d_name, "renderD", 7) == 0) {
            char full_path[256];
            snprintf(full_path, sizeof(full_path), "/dev/dri/%s", entry->d_name);
            
            if (is_render_node(full_path)) {
                strcpy(paths[count], full_path);
                count++;
            }
        }
    }
    
    closedir(dir);
    return count;
}

// Get default GPU device path
// Returns first available render node or NULL
const char* sp_get_default_gpu_device(void) {
    static char default_path[256];
    char paths[MAX_GPU_DEVICES][256];
    
    int count = sp_discover_gpu_devices(paths, MAX_GPU_DEVICES);
    if (count > 0) {
        strcpy(default_path, paths[0]);
        return default_path;
    }
    
    // Fallback to common paths
    if (is_render_node("/dev/dri/renderD128")) {
        return "/dev/dri/renderD128";
    }
    if (is_render_node("/dev/dri/renderD129")) {
        return "/dev/dri/renderD129";
    }
    
    return NULL;
}

// Get GPU device path from environment or auto-discover
const char* sp_get_gpu_device_path(void) {
    // Check environment variable first
    const char* env_path = getenv("SPORKLE_GPU_DEVICE");
    if (env_path && is_render_node(env_path)) {
        return env_path;
    }
    
    // Auto-discover
    return sp_get_default_gpu_device();
}