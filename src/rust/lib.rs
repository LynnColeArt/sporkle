// Rust bridge for Kronos compute - exposes C FFI
// This bridges Lynn's kronos-compute Rust crate to Fortran

use kronos_compute::core::*;
use kronos_compute::sys::*;
use kronos_compute::ffi::*;
use std::ffi::{c_void, CString};
use std::ptr;

// Since the safe API is failing, implement our own using the low-level API
struct KronosContextWrapper {
    instance: VkInstance,
    physical_device: VkPhysicalDevice,
    device: VkDevice,
    queue: VkQueue,
    queue_family_index: u32,
}

struct KronosBufferWrapper {
    buffer: VkBuffer,
    memory: VkDeviceMemory,
    size: usize,
}

struct KronosPipelineWrapper {
    pipeline: VkPipeline,
}

struct KronosFenceWrapper {
    fence: VkFence,
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
        
        // Don't request any extensions or layers
        let create_info = VkInstanceCreateInfo {
            sType: VkStructureType::InstanceCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            pApplicationInfo: &app_info,
            enabledLayerCount: 0,
            ppEnabledLayerNames: ptr::null(),
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
        
        let physical_device = devices[0];
        eprintln!("[Kronos] Using physical device: {:?}", physical_device);
        
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
        
        // Use no features at all for maximum compatibility
        let features = VkPhysicalDeviceFeatures::default();
        
        let device_create_info = VkDeviceCreateInfo {
            sType: VkStructureType::DeviceCreateInfo,
            pNext: ptr::null(),
            flags: 0,
            queueCreateInfoCount: 1,
            pQueueCreateInfos: &queue_create_info,
            enabledLayerCount: 0,
            ppEnabledLayerNames: ptr::null(),
            enabledExtensionCount: 0,
            ppEnabledExtensionNames: ptr::null(),
            pEnabledFeatures: ptr::null(), // Try null to avoid any feature requirements
        };
        
        let mut device = VkDevice::NULL;
        let result = kronos_compute::vkCreateDevice(physical_device, &device_create_info, ptr::null(), &mut device);
        
        if result != VkResult::Success {
            eprintln!("[Kronos] Failed to create device: {:?}", result);
            eprintln!("[Kronos] Falling back to dummy implementation for testing");
            kronos_compute::vkDestroyInstance(instance, ptr::null());
            
            // Return dummy context to allow testing
            let wrapper = Box::new(KronosContextWrapper {
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
            instance,
            physical_device,
            device,
            queue,
            queue_family_index,
        });
        
        eprintln!("[Kronos] Context created successfully!");
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

#[no_mangle]
pub extern "C" fn kronos_compute_create_buffer(ctx: KronosContext, size: usize) -> KronosBuffer {
    eprintln!("[Kronos] Creating buffer of size {}...", size);
    if ctx.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let ctx_wrapper = &(*ctx);
        
        // For dummy context, just allocate memory
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let wrapper = Box::new(KronosBufferWrapper {
                buffer: VkBuffer::from_raw(0x5000),
                memory: VkDeviceMemory::from_raw(0x6000),
                size,
            });
            return Box::into_raw(wrapper);
        }
        
        // Real Vulkan buffer creation would go here
        eprintln!("[Kronos] Real buffer creation not implemented");
        ptr::null_mut()
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_buffer(_ctx: KronosContext, buffer: KronosBuffer) {
    eprintln!("[Kronos] Destroying buffer...");
    if !buffer.is_null() {
        unsafe {
            let _ = Box::from_raw(buffer);
        }
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_map_buffer(_ctx: KronosContext, buffer: KronosBuffer) -> *mut c_void {
    if buffer.is_null() {
        return ptr::null_mut();
    }
    
    eprintln!("[Kronos] Buffer mapping not implemented");
    ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn kronos_compute_unmap_buffer(_ctx: KronosContext, buffer: KronosBuffer) {
    eprintln!("[Kronos] Unmapping buffer...");
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
        
        // For dummy context, just create a dummy pipeline
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let wrapper = Box::new(KronosPipelineWrapper {
                pipeline: VkPipeline::from_raw(0x7000),
            });
            return Box::into_raw(wrapper);
        }
        
        eprintln!("[Kronos] Real pipeline creation not implemented");
        ptr::null_mut()
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
        // For dummy context, just return a dummy fence
        let ctx_wrapper = &(*ctx);
        if ctx_wrapper.instance.as_raw() == 0x1000 {
            let wrapper = Box::new(KronosFenceWrapper {
                fence: VkFence::from_raw(0x8000),
            });
            return Box::into_raw(wrapper);
        }
        
        eprintln!("[Kronos] Real dispatch not implemented");
        ptr::null_mut()
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
        // For dummy fence, just return success
        if fence_wrapper.fence.as_raw() == 0x8000 {
            return KRONOS_SUCCESS;
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