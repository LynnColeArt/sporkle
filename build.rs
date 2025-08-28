use cc::Build;

fn main() {
    // Build the C bridge
    Build::new()
        .file("src/kronos_c_bridge.c")
        .include("src")
        .compile("kronos_c_bridge");
    
    // Tell cargo to link against Vulkan
    println!("cargo:rustc-link-lib=vulkan");
}