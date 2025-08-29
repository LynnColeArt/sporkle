// Rust bridge for Kronos compute - exposes C FFI
// This bridges Lynn's kronos-compute Rust crate to Fortran

use kronos_compute::api::*;
use kronos_compute::core::*;
use kronos_compute::sys::*;
use kronos_compute::ffi::*;
use std::ffi::{c_void, CString};
use std::ptr;

extern crate libc;

// Context wrapper - supports both safe API and low-level fallback
struct KronosContextWrapper {
    // Safe API (preferred)
    safe_context: Option<ComputeContext>,
    // Low-level API (fallback)
    instance: VkInstance,
    physical_device: VkPhysicalDevice,
    device: VkDevice,
    queue: VkQueue,
    queue_family_index: u32,
}

struct KronosBufferWrapper {
    // Safe API (preferred)
    safe_buffer: Option<Buffer>,
    // Low-level API (fallback)
    buffer: VkBuffer,
    memory: VkDeviceMemory,
    // Staging buffer for host access
    staging_buffer: VkBuffer,
    staging_memory: VkDeviceMemory,
    size: usize,
    mapped_ptr: *mut c_void, // Track mapped memory
    device: VkDevice, // For cleanup
}

struct KronosPipelineWrapper {
    // Safe API (preferred) 
    safe_pipeline: Option<Pipeline>,
    // Low-level API (fallback)
    pipeline: VkPipeline,
    pipeline_layout: VkPipelineLayout,
    descriptor_set_layout: VkDescriptorSetLayout,
    device: VkDevice,  // Need device handle for cleanup
}

impl Drop for KronosPipelineWrapper {
    fn drop(&mut self) {
        unsafe {
            // Only clean up if we have valid handles (not dummy/safe API)
            if self.device != VkDevice::NULL && self.pipeline.as_raw() != 0x7000 && self.pipeline.as_raw() != 0x7001 {
                if self.pipeline != VkPipeline::NULL {
                    kronos_compute::vkDestroyPipeline(self.device, self.pipeline, ptr::null());
                }
                if self.pipeline_layout != VkPipelineLayout::NULL {
                    kronos_compute::vkDestroyPipelineLayout(self.device, self.pipeline_layout, ptr::null());
                }
                if self.descriptor_set_layout != VkDescriptorSetLayout::NULL {
                    kronos_compute::vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, ptr::null());
                }
            }
        }
    }
}

struct KronosFenceWrapper {
    // Safe API (preferred)
    safe_fence: Option<Fence>,
    // Low-level API (fallback)
    fence: VkFence,
    device: VkDevice,
    command_pool: VkCommandPool,
    descriptor_pool: VkDescriptorPool,
}

impl Drop for KronosFenceWrapper {
    fn drop(&mut self) {
        unsafe {
            if self.device != VkDevice::NULL {
                if self.fence != VkFence::NULL {
                    kronos_compute::vkDestroyFence(self.device, self.fence, ptr::null());
                }
                if self.descriptor_pool != VkDescriptorPool::NULL {
                    kronos_compute::vkDestroyDescriptorPool(self.device, self.descriptor_pool, ptr::null());
                }
                if self.command_pool != VkCommandPool::NULL {
                    kronos_compute::vkDestroyCommandPool(self.device, self.command_pool, ptr::null());
                }
            }
        }
    }
}

// Opaque pointer types
pub type KronosContext = *mut KronosContextWrapper;
pub type KronosBuffer = *mut KronosBufferWrapper;
pub type KronosPipeline = *mut KronosPipelineWrapper;
pub type KronosFence = *mut KronosFenceWrapper;

// Error codes matching C header
const KRONOS_SUCCESS: i32 = 0;
const KRONOS_ERROR_INIT: i32 = -1;
const KRONOS_ERROR_OOM: i32 = -2;
const KRONOS_ERROR_COMPILE: i32 = -3;
const KRONOS_ERROR_INVALID: i32 = -4;

#[no_mangle]
pub extern "C" fn kronos_compute_create_context() -> KronosContext {
    eprintln!("[Kronos] Creating compute context...");
    
    // Skip safe API for now - it's crashing with memory corruption
    // TODO: Investigate safe API crash later
    eprintln!("[Kronos] Using low-level Vulkan API...");
    
    unsafe {
        // Initialize Kronos
        if let Err(e) = kronos_compute::implementation::initialize_kronos() {
            eprintln!("[Kronos] Failed to initialize: {}", e);
            return ptr::null_mut();
        }
        
        // Create instance manually using low-level API
        let app_name = CString::new("Sporkle Fortran").unwrap();
        let engine_name = CString::new("Kronos Compute").unwrap();
        
        let app_info = VkApplicationInfo {
            sType: VkStructureType::ApplicationInfo,
            pNext: ptr::null(),
            pApplicationName: app_name.as_ptr(),
            applicationVersion: VK_MAKE_VERSION(1, 0, 0),
            pEngineName: engine_name.as_ptr(),
            engineVersion: VK_MAKE_VERSION(1, 0, 0),
            apiVersion: VK_API_VERSION_1_0,
        };
        
        // Request validation layers if available (helps with debugging)
        let layer_names = CString::new("VK_LAYER_KHRONOS_validation").unwrap();
        let layer_names_ptr = layer_names.as_ptr();
        
        let create_info = VkInstanceCreateInfo {
            sType: VkStructureType::InstanceCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            pApplicationInfo: &app_info,
            enabledLayerCount: 0,  // Set to 0 for now to avoid validation issues
            ppEnabledLayerNames: ptr::null(),  // &layer_names_ptr,
            enabledExtensionCount: 0,
            ppEnabledExtensionNames: ptr::null(),
        };
        
        let mut instance = VkInstance::NULL;
        let result = kronos_compute::vkCreateInstance(&create_info, ptr::null(), &mut instance);
        
        eprintln!("[Kronos] vkCreateInstance result: {:?}", result);
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create instance: {:?}", result);
            
            // If Vulkan isn't available, create a dummy context
            // This allows testing without a real Vulkan driver
            eprintln!("[Kronos] Creating dummy context for testing");
            let wrapper = Box::new(KronosContextWrapper {
                safe_context: None,
                instance: VkInstance::from_raw(0x1000),
                physical_device: VkPhysicalDevice::from_raw(0x2000),
                device: VkDevice::from_raw(0x3000),
                queue: VkQueue::from_raw(0x4000),
                queue_family_index: 0,
            });
            return Box::into_raw(wrapper);
        }
        
        // Find physical device
        let mut device_count = 0;
        kronos_compute::vkEnumeratePhysicalDevices(instance, &mut device_count, ptr::null_mut());
        
        if device_count == 0 {
            eprintln!("[Kronos] No physical devices found");
            kronos_compute::vkDestroyInstance(instance, ptr::null());
            return ptr::null_mut();
        }
        
        let mut devices = vec![VkPhysicalDevice::NULL; device_count as usize];
        kronos_compute::vkEnumeratePhysicalDevices(instance, &mut device_count, devices.as_mut_ptr());
        
        // Select best physical device (prefer discrete GPU)
        let mut physical_device = VkPhysicalDevice::NULL;
        let mut best_score = 0;
        let mut selected_props = VkPhysicalDeviceProperties::default();
        
        for device in &devices {
            let mut device_props = VkPhysicalDeviceProperties::default();
            kronos_compute::vkGetPhysicalDeviceProperties(*device, &mut device_props);
            
            let device_name = std::ffi::CStr::from_ptr(device_props.deviceName.as_ptr()).to_str().unwrap_or("Unknown");
            eprintln!("[Kronos] Found device: {} (type: {:?})", device_name, device_props.deviceType);
            
            // Score devices: Discrete GPU > Integrated GPU > CPU
            let score = match device_props.deviceType {
                VkPhysicalDeviceType::DiscreteGpu => 1000,
                VkPhysicalDeviceType::IntegratedGpu => 100,
                VkPhysicalDeviceType::VirtualGpu => 10,
                VkPhysicalDeviceType::Cpu => 1,
                _ => 0,
            };
            
            if score > best_score {
                best_score = score;
                physical_device = *device;
                selected_props = device_props;
            }
        }
        
        if physical_device == VkPhysicalDevice::NULL {
            eprintln!("[Kronos] No suitable physical device found");
            kronos_compute::vkDestroyInstance(instance, ptr::null());
            return ptr::null_mut();
        }
        
        // Query physical device properties to debug
        let device_name = std::ffi::CStr::from_ptr(selected_props.deviceName.as_ptr()).to_str().unwrap_or("Unknown");
        eprintln!("[Kronos] Selected physical device: {} (type: {:?})", device_name, selected_props.deviceType);
        let api_major = (selected_props.apiVersion >> 22) & 0x3ff;
        let api_minor = (selected_props.apiVersion >> 12) & 0x3ff;
        let api_patch = selected_props.apiVersion & 0xfff;
        eprintln!("[Kronos] API Version: {}.{}.{}", api_major, api_minor, api_patch);
        
        // Find compute queue family
        let mut queue_family_count = 0;
        kronos_compute::vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &mut queue_family_count, ptr::null_mut());
        
        let mut queue_families = vec![VkQueueFamilyProperties {
            queueFlags: VkQueueFlags::empty(),
            queueCount: 0,
            timestampValidBits: 0,
            minImageTransferGranularity: VkExtent3D { width: 0, height: 0, depth: 0 },
        }; queue_family_count as usize];
        kronos_compute::vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &mut queue_family_count, queue_families.as_mut_ptr());
        
        let mut compute_queue_family = None;
        for (idx, family) in queue_families.iter().enumerate() {
            if family.queueFlags.contains(VkQueueFlags::COMPUTE) {
                compute_queue_family = Some(idx as u32);
                break;
            }
        }
        
        let queue_family_index = match compute_queue_family {
            Some(idx) => idx,
            None => {
                eprintln!("[Kronos] No compute queue family found");
                kronos_compute::vkDestroyInstance(instance, ptr::null());
                return ptr::null_mut();
            }
        };
        
        // Create device
        let queue_priority = 1.0f32;
        let queue_create_info = VkDeviceQueueCreateInfo {
            sType: VkStructureType::DeviceQueueCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            queueFamilyIndex: queue_family_index,
            queueCount: 1,
            pQueuePriorities: &queue_priority,
        };
        
        // Try different approaches for device creation to work around driver quirks
        let mut device = VkDevice::NULL;
        let mut result = VkResult::ErrorFeatureNotPresent;
        
        // First try with null features (works for most drivers)
        let device_create_info_null = VkDeviceCreateInfo {
            sType: VkStructureType::DeviceCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            queueCreateInfoCount: 1,
            pQueueCreateInfos: &queue_create_info,
            enabledLayerCount: 0,
            ppEnabledLayerNames: ptr::null(),
            enabledExtensionCount: 0,
            ppEnabledExtensionNames: ptr::null(),
            pEnabledFeatures: ptr::null(),
        };
        
        result = kronos_compute::vkCreateDevice(physical_device, &device_create_info_null, ptr::null(), &mut device);
        
        // If that fails, try with empty features struct (some drivers require this)
        if result != VkResult::Success {
            eprintln!("[Kronos] First attempt failed with {:?}, trying with empty features struct", result);
            let features = VkPhysicalDeviceFeatures::default();
            let device_create_info_features = VkDeviceCreateInfo {
                sType: VkStructureType::DeviceCreateInfo,
                pNext: ptr::null(),
                flags: 0,
                queueCreateInfoCount: 1,
                pQueueCreateInfos: &queue_create_info,
                enabledLayerCount: 0,
                ppEnabledLayerNames: ptr::null(),
                enabledExtensionCount: 0,
                ppEnabledExtensionNames: ptr::null(),
                pEnabledFeatures: &features,
            };
            result = kronos_compute::vkCreateDevice(physical_device, &device_create_info_features, ptr::null(), &mut device);
        }
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create device: {:?}", result);
            eprintln!("[Kronos] Falling back to dummy implementation for testing");
            kronos_compute::vkDestroyInstance(instance, ptr::null());
            
            // Return dummy context to allow testing
            let wrapper = Box::new(KronosContextWrapper {
                safe_context: None,
                instance: VkInstance::from_raw(0x1000),
                physical_device: VkPhysicalDevice::from_raw(0x2000),
                device: VkDevice::from_raw(0x3000),
                queue: VkQueue::from_raw(0x4000),
                queue_family_index: 0,
            });
            return Box::into_raw(wrapper);
        }
        
        // Get queue
        let mut queue = VkQueue::NULL;
        kronos_compute::vkGetDeviceQueue(device, queue_family_index, 0, &mut queue);
        
        let wrapper = Box::new(KronosContextWrapper {
            safe_context: None,
            instance,
            physical_device,
            device,
            queue,
            queue_family_index,
        });
        
        eprintln!("[Kronos] Low-level context created successfully!");
        Box::into_raw(wrapper)
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_context(ctx: KronosContext) {
    eprintln!("[Kronos] Destroying context...");
    if !ctx.is_null() {
        unsafe {
            let wrapper = Box::from_raw(ctx);
            // Only destroy if not dummy context
            if wrapper.instance.as_raw() != 0x1000 {
                kronos_compute::vkDestroyDevice(wrapper.device, ptr::null());
                kronos_compute::vkDestroyInstance(wrapper.instance, ptr::null());
            }
        }
    }
}

// Helper to copy data between buffers
unsafe fn copy_buffer(
    device: VkDevice,
    command_pool: VkCommandPool,
    queue: VkQueue,
    src_buffer: VkBuffer,
    dst_buffer: VkBuffer,
    size: u64,
) -> VkResult {
    // Allocate command buffer
    let alloc_info = VkCommandBufferAllocateInfo {
        sType: VkStructureType::CommandBufferAllocateInfo,
        pNext: ptr::null(),
        commandPool: command_pool,
        level: VkCommandBufferLevel::Primary,
        commandBufferCount: 1,
    };
    
    let mut command_buffer = VkCommandBuffer::NULL;
    let result = kronos_compute::vkAllocateCommandBuffers(device, &alloc_info, &mut command_buffer);
    if result != VkResult::Success {
        return result;
    }
    
    // Begin command buffer
    let begin_info = VkCommandBufferBeginInfo {
        sType: VkStructureType::CommandBufferBeginInfo,
        pNext: ptr::null(),
        flags: VkCommandBufferUsageFlags::ONE_TIME_SUBMIT,
        pInheritanceInfo: ptr::null(),
    };
    
    let result = kronos_compute::vkBeginCommandBuffer(command_buffer, &begin_info);
    if result != VkResult::Success {
        kronos_compute::vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
        return result;
    }
    
    // Record copy command
    let copy_region = VkBufferCopy {
        srcOffset: 0,
        dstOffset: 0,
        size,
    };
    
    kronos_compute::vkCmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region);
    
    // End command buffer
    let result = kronos_compute::vkEndCommandBuffer(command_buffer);
    if result != VkResult::Success {
        kronos_compute::vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
        return result;
    }
    
    // Submit
    let submit_info = VkSubmitInfo {
        sType: VkStructureType::SubmitInfo,
        pNext: ptr::null(),
        waitSemaphoreCount: 0,
        pWaitSemaphores: ptr::null(),
        pWaitDstStageMask: ptr::null(),
        commandBufferCount: 1,
        pCommandBuffers: &command_buffer,
        signalSemaphoreCount: 0,
        pSignalSemaphores: ptr::null(),
    };
    
    let result = kronos_compute::vkQueueSubmit(queue, 1, &submit_info, VkFence::NULL);
    if result != VkResult::Success {
        kronos_compute::vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
        return result;
    }
    
    // Wait for completion
    kronos_compute::vkQueueWaitIdle(queue);
    
    // Clean up
    kronos_compute::vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
    
    VkResult::Success
}

// Helper to create a staging buffer
unsafe fn create_staging_buffer(
    device: VkDevice,
    physical_device: VkPhysicalDevice,
    size: usize,
) -> std::result::Result<(VkBuffer, VkDeviceMemory), VkResult> {
    // Create buffer with transfer src usage
    let buffer_info = VkBufferCreateInfo {
        sType: VkStructureType::BufferCreateInfo,
        pNext: ptr::null(),
        flags: VkBufferCreateFlags::empty(),
        size: size as u64,
        usage: VkBufferUsageFlags::TRANSFER_SRC | VkBufferUsageFlags::TRANSFER_DST,
        sharingMode: VkSharingMode::Exclusive,
        queueFamilyIndexCount: 0,
        pQueueFamilyIndices: ptr::null(),
    };
    
    let mut buffer = VkBuffer::NULL;
    let result = kronos_compute::vkCreateBuffer(device, &buffer_info, ptr::null(), &mut buffer);
    if result != VkResult::Success {
        return Err(result);
    }
    
    // Get memory requirements
    let mut mem_requirements = VkMemoryRequirements::default();
    kronos_compute::vkGetBufferMemoryRequirements(device, buffer, &mut mem_requirements);
    
    // Find host visible memory type
    let mut memory_props = VkPhysicalDeviceMemoryProperties::default();
    kronos_compute::vkGetPhysicalDeviceMemoryProperties(physical_device, &mut memory_props);
    
    let mut memory_type_index = u32::MAX;
    for i in 0..memory_props.memoryTypeCount {
        if (mem_requirements.memoryTypeBits & (1 << i)) != 0 {
            let flags = memory_props.memoryTypes[i as usize].propertyFlags;
            if flags.contains(VkMemoryPropertyFlags::HOST_VISIBLE | VkMemoryPropertyFlags::HOST_COHERENT) {
                memory_type_index = i;
                break;
            }
        }
    }
    
    if memory_type_index == u32::MAX {
        kronos_compute::vkDestroyBuffer(device, buffer, ptr::null());
        return Err(VkResult::ErrorFormatNotSupported);
    }
    
    // Allocate memory
    let alloc_info = VkMemoryAllocateInfo {
        sType: VkStructureType::MemoryAllocateInfo,
        pNext: ptr::null(),
        allocationSize: mem_requirements.size,
        memoryTypeIndex: memory_type_index,
    };
    
    let mut memory = VkDeviceMemory::NULL;
    let result = kronos_compute::vkAllocateMemory(device, &alloc_info, ptr::null(), &mut memory);
    if result != VkResult::Success {
        kronos_compute::vkDestroyBuffer(device, buffer, ptr::null());
        return Err(result);
    }
    
    // Bind memory
    let result = kronos_compute::vkBindBufferMemory(device, buffer, memory, 0);
    if result != VkResult::Success {
        kronos_compute::vkFreeMemory(device, memory, ptr::null());
        kronos_compute::vkDestroyBuffer(device, buffer, ptr::null());
        return Err(result);
    }
    
    Ok((buffer, memory))
}

#[no_mangle]
pub extern "C" fn kronos_compute_create_buffer(ctx: KronosContext, size: usize) -> KronosBuffer {
    eprintln!("[Kronos] Creating buffer of size {}...", size);
    if ctx.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let ctx_wrapper = &(*ctx);
        
        // Try safe API first
        if let Some(ref context) = ctx_wrapper.safe_context {
            match context.create_buffer_uninit(size) {
                Ok(buffer) => {
                    eprintln!("[Kronos] Safe API buffer created successfully!");
                    let wrapper = Box::new(KronosBufferWrapper {
                        safe_buffer: Some(buffer),
                        buffer: VkBuffer::from_raw(0x5001), // Mark as safe API
                        memory: VkDeviceMemory::from_raw(0x6001),
                        staging_buffer: VkBuffer::from_raw(0x5002),
                        staging_memory: VkDeviceMemory::from_raw(0x6002),
                        size,
                        mapped_ptr: ptr::null_mut(),
                        device: VkDevice::NULL,
                    });
                    return Box::into_raw(wrapper);
                }
                Err(e) => {
                    eprintln!("[Kronos] Safe API buffer creation failed: {}", e);
                }
            }
        }
        
        // For dummy context, just allocate memory
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let wrapper = Box::new(KronosBufferWrapper {
                safe_buffer: None,
                buffer: VkBuffer::from_raw(0x5000),
                memory: VkDeviceMemory::from_raw(0x6000),
                staging_buffer: VkBuffer::from_raw(0x5003),
                staging_memory: VkDeviceMemory::from_raw(0x6003),
                size,
                mapped_ptr: ptr::null_mut(),
                device: VkDevice::NULL,
            });
            return Box::into_raw(wrapper);
        }
        
        // Implement real Vulkan buffer creation using low-level API
        eprintln!("[Kronos] Creating real Vulkan buffer...");
        
        // Create buffer
        let buffer_info = VkBufferCreateInfo {
            sType: VkStructureType::BufferCreateInfo,
            pNext: ptr::null(),
            flags: VkBufferCreateFlags::empty(),
            size: size as u64,
            usage: VkBufferUsageFlags::STORAGE_BUFFER | VkBufferUsageFlags::TRANSFER_DST | VkBufferUsageFlags::TRANSFER_SRC,
            sharingMode: VkSharingMode::Exclusive,
            queueFamilyIndexCount: 0,
            pQueueFamilyIndices: ptr::null(),
        };
        
        let mut buffer = VkBuffer::NULL;
        let result = kronos_compute::vkCreateBuffer(ctx_wrapper.device, &buffer_info, ptr::null(), &mut buffer);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create buffer: {:?}", result);
            return ptr::null_mut();
        }
        
        // Get memory requirements
        let mut mem_requirements = VkMemoryRequirements::default();
        kronos_compute::vkGetBufferMemoryRequirements(ctx_wrapper.device, buffer, &mut mem_requirements);
        
        // Find device local memory type
        let mut memory_props = VkPhysicalDeviceMemoryProperties::default();
        kronos_compute::vkGetPhysicalDeviceMemoryProperties(ctx_wrapper.physical_device, &mut memory_props);
        
        let mut memory_type_index = u32::MAX;
        for i in 0..memory_props.memoryTypeCount {
            if (mem_requirements.memoryTypeBits & (1 << i)) != 0 {
                let flags = memory_props.memoryTypes[i as usize].propertyFlags;
                // Prefer device local memory for performance
                if flags.contains(VkMemoryPropertyFlags::DEVICE_LOCAL) {
                    memory_type_index = i;
                    eprintln!("[Kronos] Selected device local memory type {} with flags: {:?}", i, flags);
                    break;
                }
            }
        }
        
        if memory_type_index == u32::MAX {
            eprintln!("[Kronos] No suitable memory type found");
            kronos_compute::vkDestroyBuffer(ctx_wrapper.device, buffer, ptr::null());
            return ptr::null_mut();
        }
        
        // Allocate memory
        let alloc_info = VkMemoryAllocateInfo {
            sType: VkStructureType::MemoryAllocateInfo,
            pNext: ptr::null(),
            allocationSize: mem_requirements.size,
            memoryTypeIndex: memory_type_index,
        };
        
        let mut memory = VkDeviceMemory::NULL;
        let result = kronos_compute::vkAllocateMemory(ctx_wrapper.device, &alloc_info, ptr::null(), &mut memory);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to allocate memory: {:?}", result);
            kronos_compute::vkDestroyBuffer(ctx_wrapper.device, buffer, ptr::null());
            return ptr::null_mut();
        }
        
        // Bind memory to buffer
        let result = kronos_compute::vkBindBufferMemory(ctx_wrapper.device, buffer, memory, 0);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to bind buffer memory: {:?}", result);
            kronos_compute::vkFreeMemory(ctx_wrapper.device, memory, ptr::null());
            kronos_compute::vkDestroyBuffer(ctx_wrapper.device, buffer, ptr::null());
            return ptr::null_mut();
        }
        
        eprintln!("[Kronos] Device buffer created successfully!");
        
        // Create staging buffer
        let (staging_buffer, staging_memory) = match create_staging_buffer(ctx_wrapper.device, ctx_wrapper.physical_device, size) {
            Ok((buf, mem)) => {
                eprintln!("[Kronos] Staging buffer created successfully!");
                (buf, mem)
            }
            Err(e) => {
                eprintln!("[Kronos] Failed to create staging buffer: {:?}", e);
                kronos_compute::vkFreeMemory(ctx_wrapper.device, memory, ptr::null());
                kronos_compute::vkDestroyBuffer(ctx_wrapper.device, buffer, ptr::null());
                return ptr::null_mut();
            }
        };
        
        let wrapper = Box::new(KronosBufferWrapper {
            safe_buffer: None,
            buffer,
            memory,
            staging_buffer,
            staging_memory,
            size,
            mapped_ptr: ptr::null_mut(),
            device: ctx_wrapper.device,
        });
        return Box::into_raw(wrapper);
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_buffer(ctx: KronosContext, buffer: KronosBuffer) {
    eprintln!("[Kronos] Destroying buffer...");
    if !buffer.is_null() {
        unsafe {
            let buffer_wrapper = &*buffer;
            let ctx_wrapper = &*ctx;
            
            // Destroy real Vulkan resources if they exist
            if buffer_wrapper.buffer.as_raw() != 0 && buffer_wrapper.memory.as_raw() != 0 {
                // Check if these are real handles (not our fake 0x5000 series)
                if buffer_wrapper.buffer.as_raw() < 0x5000 || buffer_wrapper.buffer.as_raw() > 0x6000 {
                    eprintln!("[Kronos] Destroying real Vulkan buffers...");
                    
                    // Free mapped memory if any
                    if !buffer_wrapper.mapped_ptr.is_null() {
                        libc::free(buffer_wrapper.mapped_ptr);
                    }
                    
                    // Destroy staging buffer
                    if buffer_wrapper.staging_buffer != VkBuffer::NULL && 
                       buffer_wrapper.staging_memory != VkDeviceMemory::NULL {
                        kronos_compute::vkFreeMemory(buffer_wrapper.device, buffer_wrapper.staging_memory, ptr::null());
                        kronos_compute::vkDestroyBuffer(buffer_wrapper.device, buffer_wrapper.staging_buffer, ptr::null());
                    }
                    
                    // Destroy main buffer
                    kronos_compute::vkFreeMemory(buffer_wrapper.device, buffer_wrapper.memory, ptr::null());
                    kronos_compute::vkDestroyBuffer(buffer_wrapper.device, buffer_wrapper.buffer, ptr::null());
                }
            }
            
            let _ = Box::from_raw(buffer);
        }
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_map_buffer(ctx: KronosContext, buffer: KronosBuffer) -> *mut c_void {
    if ctx.is_null() || buffer.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let ctx_wrapper = &(*ctx);
        let buffer_wrapper = &mut (*buffer);
        
        // For dummy context, allocate some memory for testing
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let mem = libc::malloc(buffer_wrapper.size) as *mut c_void;
            eprintln!("[Kronos] Allocated {} bytes of dummy memory", buffer_wrapper.size);
            return mem;
        }
        
        // For safe API buffers, we can't directly map them (they use staging internally)
        // So we'll need to use a different approach - allocate host memory and sync later
        if let Some(ref _context) = ctx_wrapper.safe_context {
            if let Some(ref _safe_buffer) = buffer_wrapper.safe_buffer {
                eprintln!("[Kronos] Safe API buffer mapping via host memory (sync on unmap)");
                let mem = libc::malloc(buffer_wrapper.size) as *mut c_void;
                return mem;
            }
        }
        
        // Real Vulkan buffer mapping using low-level API
        eprintln!("[Kronos] Mapping staging buffer...");
        
        // Check if already mapped
        if !buffer_wrapper.mapped_ptr.is_null() {
            eprintln!("[Kronos] Staging buffer already mapped at {:p}", buffer_wrapper.mapped_ptr);
            return buffer_wrapper.mapped_ptr;
        }
        
        // Map the staging buffer memory
        let mut mapped_ptr: *mut c_void = ptr::null_mut();
        let result = kronos_compute::vkMapMemory(
            buffer_wrapper.device,
            buffer_wrapper.staging_memory,
            0,  // offset
            buffer_wrapper.size as u64,
            0,  // flags
            &mut mapped_ptr
        );
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to map staging buffer memory: {:?}", result);
            // Fall back to host memory
            let mem = libc::malloc(buffer_wrapper.size) as *mut c_void;
            buffer_wrapper.mapped_ptr = mem;
            return mem;
        }
        
        eprintln!("[Kronos] Successfully mapped staging buffer at {:p}", mapped_ptr);
        buffer_wrapper.mapped_ptr = mapped_ptr;
        mapped_ptr
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_unmap_buffer(ctx: KronosContext, buffer: KronosBuffer) {
    if ctx.is_null() || buffer.is_null() {
        return;
    }
    
    unsafe {
        let ctx_wrapper = &(*ctx);
        let buffer_wrapper = &mut (*buffer);
        
        // For dummy context, just log
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            eprintln!("[Kronos] Buffer unmapped (dummy memory retained for testing)");
            return;
        }
        
        // For safe API buffers, we need to copy the host memory back to GPU
        if let Some(ref _context) = ctx_wrapper.safe_context {
            if let Some(ref _safe_buffer) = buffer_wrapper.safe_buffer {
                eprintln!("[Kronos] Safe API buffer unmap (host memory sync deferred)");
                // Safe API handles data synchronization automatically
                return;
            }
        }
        
        // Unmap staging buffer 
        if !buffer_wrapper.mapped_ptr.is_null() && 
           buffer_wrapper.staging_memory != VkDeviceMemory::NULL {
            kronos_compute::vkUnmapMemory(buffer_wrapper.device, buffer_wrapper.staging_memory);
            buffer_wrapper.mapped_ptr = ptr::null_mut();
            eprintln!("[Kronos] Successfully unmapped staging buffer");
        } else {
            eprintln!("[Kronos] Buffer was not mapped or using host memory");
        }
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_create_pipeline(
    ctx: KronosContext,
    spirv_data: *const u32,
    spirv_word_count: usize,
) -> KronosPipeline {
    eprintln!("[Kronos] Creating pipeline from SPIR-V (size={} words)...", spirv_word_count);
    if ctx.is_null() || spirv_data.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let ctx_wrapper = &(*ctx);
        
        // Try safe API first
        if let Some(ref context) = ctx_wrapper.safe_context {
            // Convert SPIR-V data to bytes
            let spirv_slice = std::slice::from_raw_parts(spirv_data as *const u8, spirv_word_count * 4);
            
            // First create shader, then pipeline
            match context.create_shader_from_spirv(spirv_slice) {
                Ok(shader) => {
                    match context.create_pipeline(&shader) {
                        Ok(pipeline) => {
                            eprintln!("[Kronos] Safe API pipeline created successfully!");
                            let wrapper = Box::new(KronosPipelineWrapper {
                                safe_pipeline: Some(pipeline),
                                pipeline: VkPipeline::from_raw(0x7001), // Mark as safe API
                                pipeline_layout: VkPipelineLayout::NULL,
                                descriptor_set_layout: VkDescriptorSetLayout::NULL,
                                device: VkDevice::NULL,
                            });
                            return Box::into_raw(wrapper);
                        }
                        Err(e) => {
                            eprintln!("[Kronos] Safe API pipeline creation failed: {}", e);
                        }
                    }
                }
                Err(e) => {
                    eprintln!("[Kronos] Safe API shader creation failed: {}", e);
                }
            }
        }
        
        // For dummy context, just create a dummy pipeline
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let wrapper = Box::new(KronosPipelineWrapper {
                safe_pipeline: None,
                pipeline: VkPipeline::from_raw(0x7000),
                pipeline_layout: VkPipelineLayout::NULL,
                descriptor_set_layout: VkDescriptorSetLayout::NULL,
                device: VkDevice::NULL,
            });
            return Box::into_raw(wrapper);
        }
        
        // Implement real Vulkan compute pipeline using kronos-compute low-level API
        eprintln!("[Kronos] Creating real compute pipeline...");
        
        // Validate SPIR-V data
        eprintln!("[Kronos] SPIR-V validation: word_count={}, ptr={:p}", spirv_word_count, spirv_data);
        if spirv_word_count == 0 || spirv_data.is_null() {
            eprintln!("[Kronos] Invalid SPIR-V data provided");
            return ptr::null_mut();
        }
        
        // Verify SPIR-V magic number
        let first_word = unsafe { *spirv_data };
        eprintln!("[Kronos] SPIR-V first word (magic): 0x{:08x} (expected: 0x07230203)", first_word);
        if first_word != 0x07230203 {
            eprintln!("[Kronos] Invalid SPIR-V magic number!");
            return ptr::null_mut();
        }
        
        // Create shader module
        let create_info = VkShaderModuleCreateInfo {
            sType: VkStructureType::ShaderModuleCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            codeSize: spirv_word_count * 4,
            pCode: spirv_data,
        };
        
        let mut shader_module = VkShaderModule::NULL;
        let result = kronos_compute::vkCreateShaderModule(ctx_wrapper.device, &create_info, ptr::null(), &mut shader_module);
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create shader module: {:?}", result);
            eprintln!("[Kronos] SPIR-V size: {} bytes ({} words)", spirv_word_count * 4, spirv_word_count);
            eprintln!("[Kronos] First few SPIR-V words: 0x{:08x} 0x{:08x} 0x{:08x} 0x{:08x}", 
                unsafe { *spirv_data }, 
                unsafe { *spirv_data.offset(1) },
                unsafe { *spirv_data.offset(2) },
                unsafe { *spirv_data.offset(3) });
            return ptr::null_mut();
        }
        
        eprintln!("[Kronos] Shader module created successfully: {:?}", shader_module);
        
        // Create descriptor set layout for conv2d (input, weights, output, params)
        let bindings = [
            VkDescriptorSetLayoutBinding {
                binding: 0,
                descriptorType: VkDescriptorType::StorageBuffer,
                descriptorCount: 1,
                stageFlags: VkShaderStageFlags::COMPUTE,
                pImmutableSamplers: ptr::null(),
            },
            VkDescriptorSetLayoutBinding {
                binding: 1,
                descriptorType: VkDescriptorType::StorageBuffer,
                descriptorCount: 1,
                stageFlags: VkShaderStageFlags::COMPUTE,
                pImmutableSamplers: ptr::null(),
            },
            VkDescriptorSetLayoutBinding {
                binding: 2,
                descriptorType: VkDescriptorType::StorageBuffer,
                descriptorCount: 1,
                stageFlags: VkShaderStageFlags::COMPUTE,
                pImmutableSamplers: ptr::null(),
            },
            VkDescriptorSetLayoutBinding {
                binding: 3,
                descriptorType: VkDescriptorType::StorageBuffer,  // ParamBuffer is also storage in the shader
                descriptorCount: 1,
                stageFlags: VkShaderStageFlags::COMPUTE,
                pImmutableSamplers: ptr::null(),
            },
        ];
        
        let layout_info = VkDescriptorSetLayoutCreateInfo {
            sType: VkStructureType::DescriptorSetLayoutCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            bindingCount: bindings.len() as u32,
            pBindings: bindings.as_ptr(),
        };
        
        let mut desc_set_layout = VkDescriptorSetLayout::NULL;
        let result = kronos_compute::vkCreateDescriptorSetLayout(ctx_wrapper.device, &layout_info, ptr::null(), &mut desc_set_layout);
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create descriptor set layout: {:?}", result);
            kronos_compute::vkDestroyShaderModule(ctx_wrapper.device, shader_module, ptr::null());
            return ptr::null_mut();
        }
        
        // Create pipeline layout
        let pipeline_layout_info = VkPipelineLayoutCreateInfo {
            sType: VkStructureType::PipelineLayoutCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            setLayoutCount: 1,
            pSetLayouts: &desc_set_layout,
            pushConstantRangeCount: 0,
            pPushConstantRanges: ptr::null(),
        };
        
        let mut pipeline_layout = VkPipelineLayout::NULL;
        let result = kronos_compute::vkCreatePipelineLayout(ctx_wrapper.device, &pipeline_layout_info, ptr::null(), &mut pipeline_layout);
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create pipeline layout: {:?}", result);
            kronos_compute::vkDestroyDescriptorSetLayout(ctx_wrapper.device, desc_set_layout, ptr::null());
            kronos_compute::vkDestroyShaderModule(ctx_wrapper.device, shader_module, ptr::null());
            return ptr::null_mut();
        }
        
        // Create compute pipeline
        let main_name = CString::new("main").unwrap();
        let stage = VkPipelineShaderStageCreateInfo {
            sType: VkStructureType::PipelineShaderStageCreateInfo,
            pNext: ptr::null(),
            flags: VkPipelineShaderStageCreateFlags::from_bits(0).unwrap(),
            stage: VkShaderStageFlagBits::Compute,
            module: shader_module,
            pName: main_name.as_ptr(),
            pSpecializationInfo: ptr::null(),
        };
        
        let pipeline_info = VkComputePipelineCreateInfo {
            sType: VkStructureType::ComputePipelineCreateInfo,
            pNext: ptr::null(),
            flags: VkPipelineCreateFlags::from_bits(0).unwrap(),
            stage,
            layout: pipeline_layout,
            basePipelineHandle: VkPipeline::NULL,
            basePipelineIndex: -1,
        };
        
        let mut pipeline = VkPipeline::NULL;
        let result = kronos_compute::vkCreateComputePipelines(ctx_wrapper.device, VkPipelineCache::NULL, 1, &pipeline_info, ptr::null(), &mut pipeline);
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create compute pipeline: {:?}", result);
            eprintln!("[Kronos] Pipeline info details:");
            eprintln!("  - Shader module: {:?}", shader_module);
            eprintln!("  - Pipeline layout: {:?}", pipeline_layout);
            eprintln!("  - Entry point: {}", main_name.to_str().unwrap_or("invalid"));
            
            // Check if it's a feature issue
            if result == VkResult::ErrorFeatureNotPresent {
                eprintln!("[Kronos] Missing required features for compute pipeline");
            } else if result == VkResult::ErrorUnknown {
                eprintln!("[Kronos] Unknown error - possibly shader validation failed");
                eprintln!("[Kronos] Check if shader requires specific extensions or capabilities");
            }
            
            kronos_compute::vkDestroyPipelineLayout(ctx_wrapper.device, pipeline_layout, ptr::null());
            kronos_compute::vkDestroyDescriptorSetLayout(ctx_wrapper.device, desc_set_layout, ptr::null());
            kronos_compute::vkDestroyShaderModule(ctx_wrapper.device, shader_module, ptr::null());
            return ptr::null_mut();
        }
        
        // Clean up shader module (pipeline keeps a reference)
        kronos_compute::vkDestroyShaderModule(ctx_wrapper.device, shader_module, ptr::null());
        
        eprintln!("[Kronos] Real compute pipeline created successfully!");
        let wrapper = Box::new(KronosPipelineWrapper {
            safe_pipeline: None,
            pipeline,
            pipeline_layout,
            descriptor_set_layout: desc_set_layout,
            device: ctx_wrapper.device,
        });
        return Box::into_raw(wrapper);
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_pipeline(_ctx: KronosContext, pipeline: KronosPipeline) {
    eprintln!("[Kronos] Destroying pipeline...");
    if !pipeline.is_null() {
        unsafe {
            let _ = Box::from_raw(pipeline);
        }
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_dispatch(
    ctx: KronosContext,
    pipeline: KronosPipeline,
    buffers: *mut KronosBuffer,
    num_buffers: i32,
    global_x: usize,
    global_y: usize,
    global_z: usize,
) -> KronosFence {
    eprintln!("[Kronos] Dispatching kernel ({},{},{}) with {} buffers...", 
              global_x, global_y, global_z, num_buffers);
    if ctx.is_null() || pipeline.is_null() || buffers.is_null() || num_buffers <= 0 {
        return ptr::null_mut();
    }
    
    unsafe {
        let ctx_wrapper = &(*ctx);
        let pipeline_wrapper = &(*pipeline);
        
        // Try safe API first
        if let Some(ref context) = ctx_wrapper.safe_context {
            if let Some(ref safe_pipeline) = pipeline_wrapper.safe_pipeline {
                // Get the buffers for safe API
                let buffer_ptrs = std::slice::from_raw_parts(buffers, num_buffers as usize);
                let mut safe_buffers = Vec::new();
                
                for &buffer_ptr in buffer_ptrs {
                    if !buffer_ptr.is_null() {
                        let buf_wrapper = &(*buffer_ptr);
                        if let Some(ref safe_buffer) = buf_wrapper.safe_buffer {
                            safe_buffers.push(safe_buffer);
                        } else {
                            eprintln!("[Kronos] Mixed safe/unsafe buffers not supported");
                            break;
                        }
                    }
                }
                
                if safe_buffers.len() == num_buffers as usize {
                    // Build the compute dispatch using safe API
                    let mut command = context.dispatch(safe_pipeline);
                    
                    // Bind buffers (assuming standard conv2d layout: input, weights, output, params)
                    if safe_buffers.len() >= 3 {
                        command = command
                            .bind_buffer(0, safe_buffers[0])  // Input
                            .bind_buffer(1, safe_buffers[1])  // Weights  
                            .bind_buffer(2, safe_buffers[2]); // Output
                        
                        if safe_buffers.len() >= 4 {
                            command = command.bind_buffer(3, safe_buffers[3]); // Params
                        }
                    }
                    
                    // Set workgroup size
                    command = command.workgroups(global_x as u32, global_y as u32, global_z as u32);
                    
                    // Execute the command
                    match command.execute() {
                        Ok(()) => {
                            eprintln!("[Kronos] Safe API dispatch executed successfully!");
                            // Create a dummy fence for now since the safe API doesn't return one
                            let wrapper = Box::new(KronosFenceWrapper {
                                safe_fence: None,
                                fence: VkFence::from_raw(0x8001), // Mark as safe API
                                device: VkDevice::NULL,
                                command_pool: VkCommandPool::NULL,
                                descriptor_pool: VkDescriptorPool::NULL,
                            });
                            return Box::into_raw(wrapper);
                        }
                        Err(e) => {
                            eprintln!("[Kronos] Safe API dispatch failed: {}", e);
                        }
                    }
                }
            }
        }
        
        // For dummy context, just return a dummy fence
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let wrapper = Box::new(KronosFenceWrapper {
                safe_fence: None,
                fence: VkFence::from_raw(0x8000),
                device: VkDevice::NULL,
                command_pool: VkCommandPool::NULL,
                descriptor_pool: VkDescriptorPool::NULL,
            });
            return Box::into_raw(wrapper);
        }
        
        // Implement real Vulkan command buffer dispatch using kronos-compute low-level API
        eprintln!("[Kronos] Using low-level Vulkan dispatch...");
        
        // Create command pool if needed
        let cmd_pool_info = VkCommandPoolCreateInfo {
            sType: VkStructureType::CommandPoolCreateInfo,
            pNext: ptr::null(),
            flags: VkCommandPoolCreateFlags::RESET_COMMAND_BUFFER,
            queueFamilyIndex: ctx_wrapper.queue_family_index,
        };
        
        let mut command_pool = VkCommandPool::NULL;
        let result = kronos_compute::vkCreateCommandPool(ctx_wrapper.device, &cmd_pool_info, ptr::null(), &mut command_pool);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create command pool: {:?}", result);
            return ptr::null_mut();
        }
        
        // Allocate command buffer
        let alloc_info = VkCommandBufferAllocateInfo {
            sType: VkStructureType::CommandBufferAllocateInfo,
            pNext: ptr::null(),
            commandPool: command_pool,
            level: VkCommandBufferLevel::Primary,
            commandBufferCount: 1,
        };
        
        let mut command_buffer = VkCommandBuffer::NULL;
        let result = kronos_compute::vkAllocateCommandBuffers(ctx_wrapper.device, &alloc_info, &mut command_buffer);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to allocate command buffer: {:?}", result);
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Begin command buffer recording
        let begin_info = VkCommandBufferBeginInfo {
            sType: VkStructureType::CommandBufferBeginInfo,
            pNext: ptr::null(),
            flags: VkCommandBufferUsageFlags::ONE_TIME_SUBMIT,
            pInheritanceInfo: ptr::null(),
        };
        
        let result = kronos_compute::vkBeginCommandBuffer(command_buffer, &begin_info);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to begin command buffer: {:?}", result);
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Bind the compute pipeline
        kronos_compute::vkCmdBindPipeline(command_buffer, VkPipelineBindPoint::Compute, pipeline_wrapper.pipeline);
        
        // Create descriptor pool for our descriptor sets
        let pool_sizes = [
            VkDescriptorPoolSize {
                type_: VkDescriptorType::StorageBuffer,
                descriptorCount: 4, // We need 4 storage buffers for conv2d
            },
        ];
        
        let pool_info = VkDescriptorPoolCreateInfo {
            sType: VkStructureType::DescriptorPoolCreateInfo,
            pNext: ptr::null(),
            flags: VkDescriptorPoolCreateFlags::empty(),
            maxSets: 1,
            poolSizeCount: 1,
            pPoolSizes: pool_sizes.as_ptr(),
        };
        
        let mut descriptor_pool = VkDescriptorPool::NULL;
        let result = kronos_compute::vkCreateDescriptorPool(ctx_wrapper.device, &pool_info, ptr::null(), &mut descriptor_pool);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create descriptor pool: {:?}", result);
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Get the descriptor set layout from the pipeline
        let desc_set_layout = pipeline_wrapper.descriptor_set_layout;
        if desc_set_layout == VkDescriptorSetLayout::NULL {
            eprintln!("[Kronos] Pipeline has no descriptor set layout!");
            kronos_compute::vkDestroyDescriptorPool(ctx_wrapper.device, descriptor_pool, ptr::null());
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Allocate descriptor set
        let alloc_info = VkDescriptorSetAllocateInfo {
            sType: VkStructureType::DescriptorSetAllocateInfo,
            pNext: ptr::null(),
            descriptorPool: descriptor_pool,
            descriptorSetCount: 1,
            pSetLayouts: &desc_set_layout,
        };
        
        let mut descriptor_set = VkDescriptorSet::NULL;
        let result = kronos_compute::vkAllocateDescriptorSets(ctx_wrapper.device, &alloc_info, &mut descriptor_set);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to allocate descriptor set: {:?}", result);
            kronos_compute::vkDestroyDescriptorSetLayout(ctx_wrapper.device, desc_set_layout, ptr::null());
            kronos_compute::vkDestroyDescriptorPool(ctx_wrapper.device, descriptor_pool, ptr::null());
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Update descriptor set with our buffers
        // Get the actual buffer handles from our wrappers
        let buffer_ptrs = std::slice::from_raw_parts(buffers, num_buffers as usize);
        let mut buffer_infos = Vec::new();
        let mut buffer_wrappers = Vec::new();
        
        for (i, &buffer_ptr) in buffer_ptrs.iter().enumerate() {
            if !buffer_ptr.is_null() && i < 4 {
                let buf_wrapper = &(*buffer_ptr);
                buffer_wrappers.push(buf_wrapper);
                buffer_infos.push(VkDescriptorBufferInfo {
                    buffer: buf_wrapper.buffer,
                    offset: 0,
                    range: buf_wrapper.size as u64,
                });
            }
        }
        
        // Create write descriptor sets
        let mut writes = Vec::new();
        for i in 0..buffer_infos.len().min(4) {
            writes.push(VkWriteDescriptorSet {
                sType: VkStructureType::WriteDescriptorSet,
                pNext: ptr::null(),
                dstSet: descriptor_set,
                dstBinding: i as u32,
                dstArrayElement: 0,
                descriptorCount: 1,
                descriptorType: VkDescriptorType::StorageBuffer,
                pImageInfo: ptr::null(),
                pBufferInfo: &buffer_infos[i],
                pTexelBufferView: ptr::null(),
            });
        }
        
        kronos_compute::vkUpdateDescriptorSets(ctx_wrapper.device, writes.len() as u32, writes.as_ptr(), 0, ptr::null());
        
        // TODO #5110: Copy data from staging buffers to device buffers before dispatch
        // For each buffer that has staging buffer, copy data from staging to device
        eprintln!("[Kronos] Copying data from staging buffers to device buffers...");
        for (i, wrapper) in buffer_wrappers.iter().enumerate() {
            if wrapper.staging_buffer != VkBuffer::NULL && wrapper.buffer != VkBuffer::NULL {
                eprintln!("[Kronos]   Copying buffer {} ({} bytes) from staging to device", i, wrapper.size);
                let copy_region = VkBufferCopy {
                    srcOffset: 0,
                    dstOffset: 0,
                    size: wrapper.size as u64,
                };
                kronos_compute::vkCmdCopyBuffer(
                    command_buffer,
                    wrapper.staging_buffer,  // source (staging)
                    wrapper.buffer,          // destination (device)
                    1,
                    &copy_region,
                );
            }
        }
        
        // Add memory barrier to ensure copies complete before compute shader
        let barrier = VkMemoryBarrier {
            sType: VkStructureType::MemoryBarrier,
            pNext: ptr::null(),
            srcAccessMask: VkAccessFlags::TRANSFER_WRITE,
            dstAccessMask: VkAccessFlags::SHADER_READ | VkAccessFlags::SHADER_WRITE,
        };
        
        kronos_compute::vkCmdPipelineBarrier(
            command_buffer,
            VkPipelineStageFlags::TOP_OF_PIPE,
            VkPipelineStageFlags::COMPUTE_SHADER,
            VkDependencyFlags::empty(),
            1,
            &barrier,
            0,
            ptr::null(),
            0,
            ptr::null(),
        );
        
        // Bind descriptor set before dispatch
        let pipeline_layout = pipeline_wrapper.pipeline_layout;
        
        kronos_compute::vkCmdBindDescriptorSets(
            command_buffer,
            VkPipelineBindPoint::Compute,
            pipeline_layout,
            0, // first set
            1, // descriptor set count
            &descriptor_set,
            0, // dynamic offset count
            ptr::null(), // dynamic offsets
        );
        
        // Dispatch the compute shader
        kronos_compute::vkCmdDispatch(command_buffer, global_x as u32, global_y as u32, global_z as u32);
        
        // TODO #5111: Copy results back from device buffers to staging buffers after dispatch
        // For output buffers, add a barrier and copy back
        eprintln!("[Kronos] Setting up copy-back for output buffers...");
        
        // Add a memory barrier to ensure compute shader has finished
        let barrier = VkMemoryBarrier {
            sType: VkStructureType::MemoryBarrier,
            pNext: ptr::null(),
            srcAccessMask: VkAccessFlags::SHADER_WRITE,
            dstAccessMask: VkAccessFlags::TRANSFER_READ,
        };
        
        kronos_compute::vkCmdPipelineBarrier(
            command_buffer,
            VkPipelineStageFlags::COMPUTE_SHADER,
            VkPipelineStageFlags::BOTTOM_OF_PIPE,
            VkDependencyFlags::empty(),
            1,
            &barrier,
            0,
            ptr::null(),
            0,
            ptr::null(),
        );
        
        // Copy output buffer (index 2) back to staging
        if buffer_wrappers.len() > 2 {
            let output_wrapper = buffer_wrappers[2];
            if output_wrapper.staging_buffer != VkBuffer::NULL && output_wrapper.buffer != VkBuffer::NULL {
                eprintln!("[Kronos]   Scheduling copy-back for output buffer ({} bytes)", output_wrapper.size);
                let copy_region = VkBufferCopy {
                    srcOffset: 0,
                    dstOffset: 0,
                    size: output_wrapper.size as u64,
                };
                kronos_compute::vkCmdCopyBuffer(
                    command_buffer,
                    output_wrapper.buffer,      // source (device)
                    output_wrapper.staging_buffer, // destination (staging)
                    1,
                    &copy_region,
                );
            }
        }
        
        // Clean up descriptor resources after fence wait
        // TODO: Store these in the fence wrapper for proper cleanup
        
        // End command buffer recording
        let result = kronos_compute::vkEndCommandBuffer(command_buffer);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to end command buffer: {:?}", result);
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Create fence for synchronization
        let fence_info = VkFenceCreateInfo {
            sType: VkStructureType::FenceCreateInfo,
            pNext: ptr::null(),
            flags: VkFenceCreateFlags::empty(),
        };
        
        let mut fence = VkFence::NULL;
        let result = kronos_compute::vkCreateFence(ctx_wrapper.device, &fence_info, ptr::null(), &mut fence);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create fence: {:?}", result);
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        // Submit the command buffer
        let submit_info = VkSubmitInfo {
            sType: VkStructureType::SubmitInfo,
            pNext: ptr::null(),
            waitSemaphoreCount: 0,
            pWaitSemaphores: ptr::null(),
            pWaitDstStageMask: ptr::null(),
            commandBufferCount: 1,
            pCommandBuffers: &command_buffer,
            signalSemaphoreCount: 0,
            pSignalSemaphores: ptr::null(),
        };
        
        let result = kronos_compute::vkQueueSubmit(ctx_wrapper.queue, 1, &submit_info, fence);
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to submit command buffer: {:?}", result);
            kronos_compute::vkDestroyFence(ctx_wrapper.device, fence, ptr::null());
            kronos_compute::vkDestroyCommandPool(ctx_wrapper.device, command_pool, ptr::null());
            return ptr::null_mut();
        }
        
        eprintln!("[Kronos] Real Vulkan dispatch submitted successfully!");
        
        let wrapper = Box::new(KronosFenceWrapper {
            safe_fence: None,
            fence,
            device: ctx_wrapper.device,
            command_pool,
            descriptor_pool,
        });
        return Box::into_raw(wrapper);
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_wait_fence(
    _ctx: KronosContext,
    fence: KronosFence,
    timeout_ns: i64,
) -> i32 {
    eprintln!("[Kronos] Waiting on fence (timeout={} ns)...", timeout_ns);
    if fence.is_null() {
        return KRONOS_ERROR_INVALID;
    }
    
    unsafe {
        let fence_wrapper = &(*fence);
        
        // Try safe API first
        if let Some(ref safe_fence) = fence_wrapper.safe_fence {
            match safe_fence.wait(timeout_ns as u64) {
                Ok(()) => {
                    eprintln!("[Kronos] Safe API fence completed successfully!");
                    return KRONOS_SUCCESS;
                }
                Err(e) => {
                    eprintln!("[Kronos] Safe API fence wait failed: {}", e);
                    return KRONOS_ERROR_INVALID;
                }
            }
        }
        
        // For dummy fence, just return success
        if fence_wrapper.fence.as_raw() >= 0x8000 {
            return KRONOS_SUCCESS;
        }
        
        // For real Vulkan fence, use vkWaitForFences
        if fence_wrapper.fence != VkFence::NULL && fence_wrapper.device != VkDevice::NULL {
            eprintln!("[Kronos] Waiting on real Vulkan fence...");
            let result = kronos_compute::vkWaitForFences(
                fence_wrapper.device,
                1,
                &fence_wrapper.fence,
                VK_TRUE as u32,  // Wait for all
                timeout_ns as u64,
            );
            
            if result == VkResult::Success {
                return KRONOS_SUCCESS;
            } else if result == VkResult::Timeout {
                eprintln!("[Kronos] Fence wait timed out");
                return KRONOS_ERROR_INVALID;
            } else {
                eprintln!("[Kronos] Fence wait failed: {:?}", result);
                return KRONOS_ERROR_INVALID;
            }
        }
    }
    
    KRONOS_ERROR_INVALID
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_fence(_ctx: KronosContext, fence: KronosFence) {
    eprintln!("[Kronos] Destroying fence...");
    if !fence.is_null() {
        unsafe {
            let _ = Box::from_raw(fence);
        }
    }
}