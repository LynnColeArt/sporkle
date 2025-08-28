// Vulkan GPU Timing with Query Pools
// ==================================
//
// Accurate GPU timing using timestamp queries

#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>

// External globals
extern VkDevice g_device;
extern VkPhysicalDevice g_physical_device;
extern VkQueue g_compute_queue;

// Query pool for timing
static VkQueryPool g_query_pool = VK_NULL_HANDLE;
static float g_timestamp_period = 1.0f;

// Initialize timing query pool
int vk_init_timing() {
    // Get timestamp period
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(g_physical_device, &props);
    g_timestamp_period = props.limits.timestampPeriod;
    
    printf("⏱️  GPU timestamp period: %.3f ns\n", g_timestamp_period);
    
    // Create query pool for timestamps
    VkQueryPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
        .queryType = VK_QUERY_TYPE_TIMESTAMP,
        .queryCount = 1000  // Support many queries
    };
    
    VkResult result = vkCreateQueryPool(g_device, &pool_info, NULL, &g_query_pool);
    if (result != VK_SUCCESS) {
        printf("❌ Failed to create query pool\n");
        return 0;
    }
    
    return 1;
}

// Cleanup timing resources
void vk_cleanup_timing() {
    if (g_query_pool != VK_NULL_HANDLE) {
        vkDestroyQueryPool(g_device, g_query_pool, NULL);
        g_query_pool = VK_NULL_HANDLE;
    }
}

// Record timestamp in command buffer
void vk_cmd_timestamp(VkCommandBuffer cmd, uint32_t query_index, VkPipelineStageFlagBits stage) {
    vkCmdWriteTimestamp(cmd, stage, g_query_pool, query_index);
}

// Get elapsed time between two queries in milliseconds
float vk_get_elapsed_ms(uint32_t start_query, uint32_t end_query) {
    uint64_t timestamps[2];
    
    // Get query results
    VkResult result = vkGetQueryPoolResults(g_device, g_query_pool, 
                                           start_query, 2, 
                                           sizeof(timestamps), timestamps,
                                           sizeof(uint64_t),
                                           VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT);
    
    if (result != VK_SUCCESS) {
        printf("❌ Failed to get query results\n");
        return -1.0f;
    }
    
    // Calculate elapsed time
    uint64_t elapsed_ns = (timestamps[1] - timestamps[0]) * g_timestamp_period;
    return elapsed_ns / 1000000.0f;  // Convert to milliseconds
}

// Reset queries before use
void vk_reset_queries(uint32_t first_query, uint32_t query_count) {
    vkResetQueryPool(g_device, g_query_pool, first_query, query_count);
}

// Timed dispatch helper
float vk_dispatch_compute_timed(VkCommandBuffer cmd_buffer, 
                               VkPipeline pipeline,
                               VkPipelineLayout layout,
                               VkDescriptorSet descriptor_set,
                               uint32_t groups_x, uint32_t groups_y, uint32_t groups_z,
                               uint32_t query_base) {
    printf("DEBUG: vk_dispatch_compute_timed called\n");
    printf("DEBUG: g_device=%p, g_query_pool=%p, g_compute_queue=%p\n", 
           (void*)g_device, (void*)g_query_pool, (void*)g_compute_queue);
    
    if (!g_device || !g_query_pool || !g_compute_queue) {
        printf("❌ Vulkan globals not initialized!\n");
        return -1.0f;
    }
    
    // Reset queries
    vk_reset_queries(query_base, 2);
    
    // Record command buffer with timestamps
    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };
    
    vkBeginCommandBuffer(cmd_buffer, &begin_info);
    
    // Start timestamp
    vk_cmd_timestamp(cmd_buffer, query_base, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT);
    
    // Bind and dispatch
    vkCmdBindPipeline(cmd_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd_buffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                           layout, 0, 1, &descriptor_set, 0, NULL);
    vkCmdDispatch(cmd_buffer, groups_x, groups_y, groups_z);
    
    // End timestamp
    vk_cmd_timestamp(cmd_buffer, query_base + 1, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
    
    vkEndCommandBuffer(cmd_buffer);
    
    // Submit
    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd_buffer
    };
    
    VkFence fence;
    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
    };
    vkCreateFence(g_device, &fence_info, NULL, &fence);
    
    if (vkQueueSubmit(g_compute_queue, 1, &submit_info, fence) != VK_SUCCESS) {
        vkDestroyFence(g_device, fence, NULL);
        return -1.0f;
    }
    
    // Wait for completion
    vkWaitForFences(g_device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkDestroyFence(g_device, fence, NULL);
    
    // Get elapsed time
    return vk_get_elapsed_ms(query_base, query_base + 1);
}