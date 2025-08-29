fn main() {
    // The Rust library provides the C FFI directly,
    // so we don't need to build the C bridge
    
    // Tell cargo to link against Vulkan
    println!("cargo:rustc-link-lib=vulkan");
}