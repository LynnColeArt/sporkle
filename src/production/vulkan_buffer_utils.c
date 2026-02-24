// Vulkan Buffer Utilities
// ======================
//
// Helper functions for buffer management including staging buffers
// for proper GPU memory initialization

#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// External globals from main backend
extern VkDevice g_device;
extern VkPhysicalDevice g_physical_device;
extern VkQueue g_compute_queue;
extern VkCommandPool g_command_pool;

// Buffer structure with staging support
typedef struct {
    VkBuffer buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;
    void* mapped_ptr;
    VkBuffer staging_buffer;
    VkDeviceMemory staging_memory;
    void* staging_ptr;
} vulkan_buffer_full_t;

// Find memory type with desired properties
uint32_t find_memory_type_util(uint32_t type_filter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties mem_props;
    vkGetPhysicalDeviceMemoryProperties(g_physical_device, &mem_props);

    // If looking for DEVICE_LOCAL, prefer pure DEVICE_LOCAL (not HOST_VISIBLE)
    if (properties & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
        // First pass: Look for pure DEVICE_LOCAL
        for (uint32_t i = 0; i < mem_props.memoryTypeCount; i++) {
            if ((type_filter & (1 << i)) &&
                (mem_props.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) &&
                !(mem_props.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
                VkDeviceSize heap_size = mem_props.memoryHeaps[mem_props.memoryTypes[i].heapIndex].size;
                printf("✅ Selected pure DEVICE_LOCAL memory type %d (Heap %d: %.1f GB VRAM)\n",
                       i, mem_props.memoryTypes[i].heapIndex, heap_size / (1024.0 * 1024.0 * 1024.0));
                return i;
            }
        }
    }

    // Second pass: Accept any matching properties
    for (uint32_t i = 0; i < mem_props.memoryTypeCount; i++) {
        if ((type_filter & (1 << i)) &&
            (mem_props.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }

    return UINT32_MAX;
}

// Create buffer with memory
static VkResult create_buffer(VkDeviceSize size, VkBufferUsageFlags usage,
                             VkMemoryPropertyFlags properties, VkBuffer* buffer,
                             VkDeviceMemory* memory) {
    // Create buffer
    VkBufferCreateInfo buffer_info = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE
    };

    VkResult result = vkCreateBuffer(g_device, &buffer_info, NULL, buffer);
    if (result != VK_SUCCESS) return result;

    // Get memory requirements
    VkMemoryRequirements mem_reqs;
    vkGetBufferMemoryRequirements(g_device, *buffer, &mem_reqs);

    // Allocate memory
    uint32_t memory_type = find_memory_type_util(mem_reqs.memoryTypeBits, properties);
    if (memory_type == UINT32_MAX) {
        vkDestroyBuffer(g_device, *buffer, NULL);
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }

    VkMemoryAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_reqs.size,
        .memoryTypeIndex = memory_type
    };

    result = vkAllocateMemory(g_device, &alloc_info, NULL, memory);
    if (result != VK_SUCCESS) {
        vkDestroyBuffer(g_device, *buffer, NULL);
        return result;
    }

    // Bind buffer to memory
    result = vkBindBufferMemory(g_device, *buffer, *memory, 0);
    if (result != VK_SUCCESS) {
        vkDestroyBuffer(g_device, *buffer, NULL);
        vkFreeMemory(g_device, *memory, NULL);
        return result;
    }

    return VK_SUCCESS;
}

// Copy buffer using command buffer
static VkResult copy_buffer(VkBuffer src, VkBuffer dst, VkDeviceSize size) {
    // Allocate command buffer
    VkCommandBufferAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = g_command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1
    };

    VkCommandBuffer cmd_buffer;
    VkResult result = vkAllocateCommandBuffers(g_device, &alloc_info, &cmd_buffer);
    if (result != VK_SUCCESS) {
        return result;
    }

    // Record copy command
    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };

    result = vkBeginCommandBuffer(cmd_buffer, &begin_info);
    if (result != VK_SUCCESS) {
        vkFreeCommandBuffers(g_device, g_command_pool, 1, &cmd_buffer);
        return result;
    }

    VkBufferCopy copy_region = {
        .size = size
    };
    vkCmdCopyBuffer(cmd_buffer, src, dst, 1, &copy_region);

    result = vkEndCommandBuffer(cmd_buffer);
    if (result != VK_SUCCESS) {
        vkFreeCommandBuffers(g_device, g_command_pool, 1, &cmd_buffer);
        return result;
    }

    // Submit and wait
    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd_buffer
    };

    VkFence fence;
    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
    };

    result = vkCreateFence(g_device, &fence_info, NULL, &fence);
    if (result != VK_SUCCESS) {
        vkFreeCommandBuffers(g_device, g_command_pool, 1, &cmd_buffer);
        return result;
    }

    result = vkQueueSubmit(g_compute_queue, 1, &submit_info, fence);
    if (result != VK_SUCCESS) {
        vkDestroyFence(g_device, fence, NULL);
        vkFreeCommandBuffers(g_device, g_command_pool, 1, &cmd_buffer);
        return result;
    }

    result = vkWaitForFences(g_device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkDestroyFence(g_device, fence, NULL);
    if (result != VK_SUCCESS) {
        vkFreeCommandBuffers(g_device, g_command_pool, 1, &cmd_buffer);
        return result;
    }

    vkFreeCommandBuffers(g_device, g_command_pool, 1, &cmd_buffer);
    return VK_SUCCESS;
}

// Allocate buffer with staging support
void* vk_allocate_buffer_with_staging(size_t size_bytes, int device_local) {
    vulkan_buffer_full_t* buf = calloc(1, sizeof(vulkan_buffer_full_t));
    buf->size = size_bytes;

    if (device_local) {
        // Create staging buffer
        VkResult result = create_buffer(size_bytes,
            VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &buf->staging_buffer, &buf->staging_memory);

        if (result != VK_SUCCESS) {
            free(buf);
            return NULL;
        }

        // Map staging buffer
        result = vkMapMemory(g_device, buf->staging_memory, 0, size_bytes, 0, &buf->staging_ptr);
        if (result != VK_SUCCESS) {
            vkDestroyBuffer(g_device, buf->staging_buffer, NULL);
            vkFreeMemory(g_device, buf->staging_memory, NULL);
            free(buf);
            return NULL;
        }

        // Create device local buffer
        result = create_buffer(size_bytes,
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &buf->buffer, &buf->memory);

        if (result != VK_SUCCESS) {
            vkUnmapMemory(g_device, buf->staging_memory);
            vkDestroyBuffer(g_device, buf->staging_buffer, NULL);
            vkFreeMemory(g_device, buf->staging_memory, NULL);
            free(buf);
            return NULL;
        }
    } else {
        // Create host visible buffer
        result = create_buffer(size_bytes,
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &buf->buffer, &buf->memory);

        if (result != VK_SUCCESS) {
            free(buf);
            return NULL;
        }

        // Map the buffer
        result = vkMapMemory(g_device, buf->memory, 0, size_bytes, 0, &buf->mapped_ptr);
        if (result != VK_SUCCESS) {
            vkDestroyBuffer(g_device, buf->buffer, NULL);
            vkFreeMemory(g_device, buf->memory, NULL);
            free(buf);
            return NULL;
        }
    }

    return buf;
}

// Upload data to GPU buffer
void vk_upload_buffer_data(void* buffer, const void* data, size_t size) {
    vulkan_buffer_full_t* buf = (vulkan_buffer_full_t*)buffer;
    if (!buf || !buffer || !data || size == 0 || size > buf->size) {
        return;
    }

    if (buf->staging_ptr) {
        // Device local buffer - copy to staging then to device
        memcpy(buf->staging_ptr, data, size);
        VkResult result = copy_buffer(buf->staging_buffer, buf->buffer, size);
        if (result != VK_SUCCESS) {
            printf("❌ Failed to copy staged data into device-local buffer: %d\n", result);
        }
    } else if (buf->mapped_ptr) {
        // Host visible buffer - direct copy
        memcpy(buf->mapped_ptr, data, size);
    }
}

// Initialize buffer with zeros
void vk_clear_buffer(void* buffer) {
    vulkan_buffer_full_t* buf = (vulkan_buffer_full_t*)buffer;
    if (!buf) return;

    if (buf->staging_ptr) {
        // Clear staging buffer and copy
        memset(buf->staging_ptr, 0, buf->size);
        VkResult result = copy_buffer(buf->staging_buffer, buf->buffer, buf->size);
        if (result != VK_SUCCESS) {
            printf("❌ Failed to copy clear data into device-local buffer: %d\n", result);
        }
    } else if (buf->mapped_ptr) {
        // Direct clear
        memset(buf->mapped_ptr, 0, buf->size);
    }
}

// Get actual VkBuffer handle
VkBuffer vk_get_buffer_handle(void* buffer) {
    vulkan_buffer_full_t* buf = (vulkan_buffer_full_t*)buffer;
    return buf->buffer;
}

// Free buffer with staging
void vk_free_buffer_full(void* buffer) {
    if (!buffer) return;

    vulkan_buffer_full_t* buf = (vulkan_buffer_full_t*)buffer;

    if (buf->staging_buffer) {
        vkUnmapMemory(g_device, buf->staging_memory);
        vkDestroyBuffer(g_device, buf->staging_buffer, NULL);
        vkFreeMemory(g_device, buf->staging_memory, NULL);
    }

    if (buf->mapped_ptr) {
        vkUnmapMemory(g_device, buf->memory);
    }

    vkDestroyBuffer(g_device, buf->buffer, NULL);
    vkFreeMemory(g_device, buf->memory, NULL);
    free(buf);
}
