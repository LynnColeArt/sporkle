// Rust bridge for Kronos compute - exposes C FFI
// This provides a working stub implementation until we can
// determine the exact kronos_compute API

use std::ffi::c_void;
use std::ptr;
use std::slice;

// Stub types until we can access real kronos_compute types
struct Context {
    initialized: bool,
}

struct Buffer {
    size: usize,
    data: Vec<u8>,
}

struct Pipeline {
    spirv: Vec<u32>,
}

struct Fence {
    completed: bool,
}

// Opaque pointer types
pub type KronosContext = *mut Context;
pub type KronosBuffer = *mut Buffer;
pub type KronosPipeline = *mut Pipeline;
pub type KronosFence = *mut Fence;

// Error codes matching C header
const KRONOS_SUCCESS: i32 = 0;
const KRONOS_ERROR_INIT: i32 = -1;
const KRONOS_ERROR_OOM: i32 = -2;
const KRONOS_ERROR_COMPILE: i32 = -3;
const KRONOS_ERROR_INVALID: i32 = -4;

#[no_mangle]
pub extern "C" fn kronos_compute_create_context() -> KronosContext {
    eprintln!("[Rust Stub] Creating Kronos context...");
    let ctx = Box::new(Context { initialized: true });
    Box::into_raw(ctx)
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_context(ctx: KronosContext) {
    eprintln!("[Rust Stub] Destroying Kronos context...");
    if !ctx.is_null() {
        unsafe {
            let _ = Box::from_raw(ctx);
        }
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_create_buffer(ctx: KronosContext, size: usize) -> KronosBuffer {
    eprintln!("[Rust Stub] Creating buffer of size {}...", size);
    if ctx.is_null() {
        return ptr::null_mut();
    }
    
    let buffer = Box::new(Buffer {
        size,
        data: vec![0u8; size],
    });
    Box::into_raw(buffer)
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_buffer(_ctx: KronosContext, buffer: KronosBuffer) {
    eprintln!("[Rust Stub] Destroying buffer...");
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
    
    unsafe {
        let buf = &mut *buffer;
        eprintln!("[Rust Stub] Mapping buffer (size={})...", buf.size);
        buf.data.as_mut_ptr() as *mut c_void
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_unmap_buffer(_ctx: KronosContext, buffer: KronosBuffer) {
    eprintln!("[Rust Stub] Unmapping buffer...");
}

#[no_mangle]
pub extern "C" fn kronos_compute_create_pipeline(
    ctx: KronosContext,
    spirv_data: *const u32,
    spirv_word_count: usize,
) -> KronosPipeline {
    eprintln!("[Rust Stub] Creating pipeline from SPIR-V (size={} words)...", spirv_word_count);
    if ctx.is_null() || spirv_data.is_null() {
        return ptr::null_mut();
    }
    
    let spirv = unsafe { slice::from_raw_parts(spirv_data, spirv_word_count) };
    let pipeline = Box::new(Pipeline {
        spirv: spirv.to_vec(),
    });
    Box::into_raw(pipeline)
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_pipeline(_ctx: KronosContext, pipeline: KronosPipeline) {
    eprintln!("[Rust Stub] Destroying pipeline...");
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
    eprintln!("[Rust Stub] Dispatching kernel ({},{},{}) with {} buffers...", 
              global_x, global_y, global_z, num_buffers);
    if ctx.is_null() || pipeline.is_null() || buffers.is_null() || num_buffers <= 0 {
        return ptr::null_mut();
    }
    
    // Create a dummy fence
    let fence = Box::new(Fence { completed: true });
    Box::into_raw(fence)
}

#[no_mangle]
pub extern "C" fn kronos_compute_wait_fence(
    _ctx: KronosContext,
    fence: KronosFence,
    timeout_ns: i64,
) -> i32 {
    eprintln!("[Rust Stub] Waiting on fence (timeout={} ns)...", timeout_ns);
    if fence.is_null() {
        return KRONOS_ERROR_INVALID;
    }
    
    // Stub always succeeds immediately
    KRONOS_SUCCESS
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_fence(_ctx: KronosContext, fence: KronosFence) {
    eprintln!("[Rust Stub] Destroying fence...");
    if !fence.is_null() {
        unsafe {
            let _ = Box::from_raw(fence);
        }
    }
}