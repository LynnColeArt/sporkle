// Rust bridge for Kronos compute - exposes C FFI
use kronos_compute::{Context, Buffer, Pipeline, Fence};
use std::ffi::c_void;
use std::ptr;
use std::slice;

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
    match Context::new() {
        Ok(ctx) => Box::into_raw(Box::new(ctx)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_context(ctx: KronosContext) {
    if !ctx.is_null() {
        unsafe {
            let _ = Box::from_raw(ctx);
        }
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_create_buffer(ctx: KronosContext, size: usize) -> KronosBuffer {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    
    let context = unsafe { &*ctx };
    match Buffer::new(context, size) {
        Ok(buffer) => Box::into_raw(Box::new(buffer)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_buffer(_ctx: KronosContext, buffer: KronosBuffer) {
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
    
    let buf = unsafe { &mut *buffer };
    match buf.map() {
        Ok(ptr) => ptr as *mut c_void,
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_unmap_buffer(_ctx: KronosContext, buffer: KronosBuffer) {
    if !buffer.is_null() {
        let buf = unsafe { &mut *buffer };
        let _ = buf.unmap();
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_create_pipeline(
    ctx: KronosContext,
    spirv_data: *const u32,
    spirv_word_count: usize,
) -> KronosPipeline {
    if ctx.is_null() || spirv_data.is_null() {
        return ptr::null_mut();
    }
    
    let context = unsafe { &*ctx };
    let spirv = unsafe { slice::from_raw_parts(spirv_data, spirv_word_count) };
    
    match Pipeline::new(context, spirv) {
        Ok(pipeline) => Box::into_raw(Box::new(pipeline)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_pipeline(_ctx: KronosContext, pipeline: KronosPipeline) {
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
    if ctx.is_null() || pipeline.is_null() || buffers.is_null() || num_buffers <= 0 {
        return ptr::null_mut();
    }
    
    let context = unsafe { &*ctx };
    let pipe = unsafe { &*pipeline };
    
    // Convert buffer pointers to references
    let buffer_ptrs = unsafe { slice::from_raw_parts(buffers, num_buffers as usize) };
    let mut buffer_refs: Vec<&Buffer> = Vec::new();
    
    for &buf_ptr in buffer_ptrs {
        if buf_ptr.is_null() {
            return ptr::null_mut();
        }
        buffer_refs.push(unsafe { &*buf_ptr });
    }
    
    match pipe.dispatch(context, &buffer_refs, (global_x, global_y, global_z)) {
        Ok(fence) => Box::into_raw(Box::new(fence)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_wait_fence(
    _ctx: KronosContext,
    fence: KronosFence,
    timeout_ns: i64,
) -> i32 {
    if fence.is_null() {
        return KRONOS_ERROR_INVALID;
    }
    
    let f = unsafe { &*fence };
    match f.wait(timeout_ns as u64) {
        Ok(_) => KRONOS_SUCCESS,
        Err(_) => KRONOS_ERROR_INVALID,
    }
}

#[no_mangle]
pub extern "C" fn kronos_compute_destroy_fence(_ctx: KronosContext, fence: KronosFence) {
    if !fence.is_null() {
        unsafe {
            let _ = Box::from_raw(fence);
        }
    }
}