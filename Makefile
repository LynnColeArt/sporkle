# Smart Makefile for Sporkle
# Detects platform and builds accordingly

# Base settings
FC = gfortran
CC = gcc
BASE_FFLAGS = -O3 -fopenmp -march=native -funroll-loops -ftree-vectorize -ffast-math -Wall
BASE_CFLAGS = -O2 -Wall
FFLAGS = $(BASE_FFLAGS)
CFLAGS = $(BASE_CFLAGS)

# Detect OS
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Platform-specific settings
ifeq ($(UNAME_S),Linux)
    PLATFORM = LINUX
    
    # Detect GPU vendor by checking all DRM cards
    GPU_VENDORS := $(shell for card in /sys/class/drm/card*/device/vendor; do [ -f "$$card" ] && cat "$$card" 2>/dev/null || true; done | sort -u)
    
    # Initialize GPU_TYPE as empty
    GPU_TYPE :=
    
    # Check for AMD GPU (0x1002) - highest priority for compute
    ifneq ($(filter 0x1002,$(GPU_VENDORS)),)
        GPU_TYPE = AMD
        $(info AMD GPU detected: $(filter 0x1002,$(GPU_VENDORS)))
    endif
    
    # Check for NVIDIA GPU (0x10de) - if no AMD found
    ifeq ($(GPU_TYPE),)
        ifneq ($(filter 0x10de,$(GPU_VENDORS)),)
            GPU_TYPE = NVIDIA
            $(info NVIDIA GPU detected: $(filter 0x10de,$(GPU_VENDORS)))
        endif
    endif
    
    # Check for Intel GPU (0x8086) - if no AMD or NVIDIA found  
    ifeq ($(GPU_TYPE),)
        ifneq ($(filter 0x8086,$(GPU_VENDORS)),)
            GPU_TYPE = INTEL
            $(info Intel GPU detected: $(filter 0x8086,$(GPU_VENDORS)))
        endif
    endif
    
    # Check available libraries for any GPU type
    ifneq ($(GPU_TYPE),)
        HAS_OPENGL := $(shell test -f /usr/lib/x86_64-linux-gnu/libGL.so.1 && echo yes)
        HAS_VULKAN := $(shell test -f /usr/lib/x86_64-linux-gnu/libvulkan.so.1 && echo yes)
        
        # Only proceed if we have the required libraries
        ifeq ($(HAS_OPENGL),yes)
            LDFLAGS += -lGL -lEGL -fopenmp
            CFLAGS += -DHAS_OPENGL
            GPU_BACKEND = opengl
            $(info GPU Backend: OpenGL enabled)
        else
            $(info Warning: OpenGL libraries not found, falling back to CPU)
            GPU_TYPE := CPU
        endif
        
        ifeq ($(HAS_VULKAN),yes)
            LDFLAGS += -lvulkan
            CFLAGS += -DHAS_VULKAN
            GPU_BACKEND_ALT = vulkan
            $(info Vulkan: Available for experimental use)
        endif
    else
        # No supported GPU found, use CPU configuration
        GPU_TYPE = CPU
        $(info No supported GPU detected, using CPU configuration)
    endif
endif

ifeq ($(UNAME_S),Darwin)
    PLATFORM = MACOS
    GPU_TYPE = APPLE
    LDFLAGS = -framework Metal -framework Foundation -framework CoreGraphics
    CFLAGS += -DHAS_METAL
    GPU_BACKEND = metal
endif

# Build directories
BUILD_DIR = build/$(PLATFORM)
SRC_DIR = src
EXAMPLES_DIR = examples

# Create build directory
$(shell mkdir -p $(BUILD_DIR))
$(shell mkdir -p $(BUILD_DIR)/common)
$(shell mkdir -p $(BUILD_DIR)/reference)
$(shell mkdir -p $(BUILD_DIR)/production)

# Common modules (platform-independent)
COMMON_MODULES = \
    $(SRC_DIR)/common/kinds.f90 \
    $(SRC_DIR)/common/flopcount.f90 \
    $(SRC_DIR)/sporkle_types.f90 \
    $(SRC_DIR)/sporkle_mesh_types.f90 \
    $(SRC_DIR)/sporkle_error_handling.f90 \
    $(SRC_DIR)/sporkle_config.f90 \
    $(SRC_DIR)/sporkle_memory.f90 \
    $(SRC_DIR)/sporkle_kernels.f90 \
    $(SRC_DIR)/sporkle_safe_kernels.f90 \
    $(SRC_DIR)/sporkle_platform.f90 \
    $(SRC_DIR)/gl_constants.f90 \
    $(SRC_DIR)/sporkle_gpu_kernels.f90 \
    $(SRC_DIR)/sporkle_glsl_generator.f90 \
    $(SRC_DIR)/sporkle_rdna_shader_generator.f90 \
    $(SRC_DIR)/sporkle_dynamic_shader_system.f90 \
    $(SRC_DIR)/sporkle_adaptive_kernel.f90 \
    $(SRC_DIR)/sporkle_kernel_variants.f90 \
    $(SRC_DIR)/sporkle_shader_parser.f90 \
    $(SRC_DIR)/sporkle_fortran_shaders.f90 \
    $(SRC_DIR)/sporkle_fortran_params.f90 \
    $(SRC_DIR)/sporkle_shader_parser_v2.f90 \
    $(SRC_DIR)/sporkle_fortran_shaders_v2.f90 \
    $(SRC_DIR)/production/timing_helpers.f90 \
    $(SRC_DIR)/production/gemm_simd_optimized_v2.f90 \
    $(SRC_DIR)/production/cpu_conv2d_adaptive.f90 \
    $(SRC_DIR)/production/gemm_simd_prefetch.f90 \
    $(SRC_DIR)/production/gemm_simd_streaming.f90 \
    $(SRC_DIR)/production/gemm_simd_optimized.f90 \
    $(SRC_DIR)/production/universal_memory_optimization.f90 \
    $(SRC_DIR)/cpu_device.f90 \
    $(SRC_DIR)/sporkle_discovery.f90 \
    $(SRC_DIR)/sporkle_universal_device_selector.f90 \
    $(SRC_DIR)/sporkle_hardware_profiler.f90 \
    $(SRC_DIR)/sporkle_autotuner_enhanced.f90

# Platform-specific modules
ifeq ($(PLATFORM),LINUX)
    ifeq ($(GPU_TYPE),AMD)
        PLATFORM_MODULES = \
            $(SRC_DIR)/sporkle_gpu_safe_detect.f90 \
            $(SRC_DIR)/sporkle_gpu_backend_detect.f90 \
            $(SRC_DIR)/sporkle_gpu_backend.f90 \
            $(SRC_DIR)/sporkle_amdgpu_direct.f90 \
            $(SRC_DIR)/sporkle_amdgpu_shader_binary.f90 \
            $(SRC_DIR)/sporkle_amdgpu_memory.f90 \
            $(SRC_DIR)/sporkle_amdgpu_shaders.f90 \
            $(SRC_DIR)/amdgpu_device.f90 \
            $(SRC_DIR)/sporkle_gpu_va_allocator.f90 \
            $(SRC_DIR)/sporkle_rdna3_shaders.f90 \
            $(SRC_DIR)/production/gpu_safety_guards.f90
            
        ifeq ($(HAS_OPENGL),yes)
            PLATFORM_MODULES += $(SRC_DIR)/production/gpu_opengl_interface.f90 \
                                $(SRC_DIR)/sporkle_gpu_dispatch.f90 \
                                $(SRC_DIR)/reference/cpu_conv2d_reference.f90 \
                                $(SRC_DIR)/production/gpu_fence_primitives.f90 \
                                $(SRC_DIR)/production/gpu_opengl_interface_fence.f90 \
                                $(SRC_DIR)/production/gpu_unified_buffers.f90 \
                                $(SRC_DIR)/production/gpu_opengl_zero_copy.f90 \
                                $(SRC_DIR)/production/gpu_async_executor.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_juggling.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_juggling_fence.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_auto_selector.f90 \
                                $(SRC_DIR)/production/gpu_program_cache.f90 \
                                $(SRC_DIR)/production/gpu_opengl_cached.f90 \
                                $(SRC_DIR)/production/gpu_binary_cache.f90 \
                                $(SRC_DIR)/production/gpu_program_cache_v2.f90 \
                                $(SRC_DIR)/production/gpu_program_cache_threadsafe.f90 \
                                # $(SRC_DIR)/production/gpu_dynamic_shader_cache.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_v3.f90
            PLATFORM_C_SOURCES += $(SRC_DIR)/reference/gpu_opengl_reference.c \
                                  $(SRC_DIR)/gpu_dynamic_shader_exec.c \
                                  $(SRC_DIR)/production/aligned_alloc.c \
                                  $(SRC_DIR)/production/prefetch_wrapper.c \
                                  $(SRC_DIR)/production/streaming_wrapper.c
        endif
        
        ifeq ($(HAS_VULKAN),yes)
            PLATFORM_MODULES += $(SRC_DIR)/production/gpu_vulkan_interface.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_unified.f90
            PLATFORM_C_SOURCES += $(SRC_DIR)/production/gpu_vulkan_backend.c \
                                  $(SRC_DIR)/production/glsl_to_spirv.c \
                                  $(SRC_DIR)/production/conv2d_spirv_bytecode.c \
                                  $(SRC_DIR)/production/valid_spirv_generator.c \
                                  $(SRC_DIR)/production/minimal_valid_spirv.c \
                                  $(SRC_DIR)/production/vulkan_buffer_utils.c \
                                  $(SRC_DIR)/production/vulkan_timing.c
        endif
    endif
    
    ifeq ($(GPU_TYPE),NVIDIA)
        PLATFORM_MODULES = \
            $(SRC_DIR)/sporkle_gpu_safe_detect.f90 \
            $(SRC_DIR)/sporkle_gpu_backend_detect.f90 \
            $(SRC_DIR)/sporkle_gpu_backend.f90 \
            $(SRC_DIR)/sporkle_nvidia_opengl.f90 \
            $(SRC_DIR)/sporkle_nvidia_persistent.f90 \
            $(SRC_DIR)/sporkle_nvidia_zerocopy.f90 \
            $(SRC_DIR)/sporkle_nvidia_summit.f90
            
        ifeq ($(HAS_OPENGL),yes)
            PLATFORM_MODULES += $(SRC_DIR)/production/gpu_opengl_interface.f90 \
                                $(SRC_DIR)/sporkle_gpu_dispatch.f90 \
                                $(SRC_DIR)/production/gpu_fence_primitives.f90 \
                                $(SRC_DIR)/reference/cpu_conv2d_reference.f90 \
                                $(SRC_DIR)/production/gpu_async_executor.f90 \
                                $(SRC_DIR)/production/gpu_program_cache.f90 \
                                $(SRC_DIR)/production/gpu_binary_cache.f90 \
                                $(SRC_DIR)/production/gpu_program_cache_threadsafe.f90
            PLATFORM_C_SOURCES += $(SRC_DIR)/reference/gpu_opengl_reference.c \
                                  $(SRC_DIR)/gpu_dynamic_shader_exec.c \
                                  $(SRC_DIR)/production/aligned_alloc.c \
                                  $(SRC_DIR)/production/prefetch_wrapper.c \
                                  $(SRC_DIR)/production/streaming_wrapper.c \
                                  $(SRC_DIR)/production/rdtsc_wrapper.c
        endif
        ifeq ($(HAS_VULKAN),yes)
            PLATFORM_MODULES += $(SRC_DIR)/production/gpu_vulkan_interface.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_unified.f90 \
                                $(SRC_DIR)/production/sporkle_conv2d_v2.f90
            PLATFORM_C_SOURCES += $(SRC_DIR)/production/gpu_vulkan_backend.c \
                                  $(SRC_DIR)/production/glsl_to_spirv.c \
                                  $(SRC_DIR)/production/conv2d_spirv_bytecode.c \
                                  $(SRC_DIR)/production/valid_spirv_generator.c \
                                  $(SRC_DIR)/production/minimal_valid_spirv.c \
                                  $(SRC_DIR)/production/vulkan_buffer_utils.c \
                                  $(SRC_DIR)/production/vulkan_timing.c
        endif
    endif
    
    ifeq ($(GPU_TYPE),CPU)
        # CPU-only configuration - minimal dependencies
        PLATFORM_MODULES =

        PLATFORM_C_SOURCES = \
            $(SRC_DIR)/production/aligned_alloc.c \
            $(SRC_DIR)/production/prefetch_wrapper.c \
            $(SRC_DIR)/production/streaming_wrapper.c
        
        # No GPU libraries needed for CPU-only build
        LDFLAGS += -fopenmp
        CFLAGS += -DCPU_ONLY
        GPU_BACKEND = cpu
    endif
endif

ifeq ($(PLATFORM),MACOS)
    PLATFORM_MODULES = \
        $(SRC_DIR)/sporkle_gpu_metal.f90 \
        $(SRC_DIR)/sporkle_memory_metal.f90 \
        $(SRC_DIR)/sporkle_metal_kernels.f90 \
        $(SRC_DIR)/sporkle_amx.f90 \
        $(SRC_DIR)/sporkle_neural_engine.f90 \
        $(SRC_DIR)/sporkle_apple_orchestrator.f90
        
    PLATFORM_C_SOURCES = \
        $(SRC_DIR)/metal_wrapper.m \
        $(SRC_DIR)/coreml_bridge_simple.m
endif

# All modules
MODULES = $(COMMON_MODULES) $(PLATFORM_MODULES)
OBJECTS = $(MODULES:$(SRC_DIR)/%.f90=$(BUILD_DIR)/%.o)

# Platform-specific C objects
ifeq ($(PLATFORM),MACOS)
    C_OBJECTS = $(PLATFORM_C_SOURCES:$(SRC_DIR)/%.m=$(BUILD_DIR)/%.o)
endif

ifeq ($(PLATFORM),LINUX)
    ifneq ($(strip $(PLATFORM_C_SOURCES)),)
        C_OBJECTS = $(PLATFORM_C_SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)
    endif
endif

# Info target
info:
	@echo "🌟 Sporkle Smart Build System"
	@echo "============================"
	@echo "Platform: $(PLATFORM)"
	@echo "Architecture: $(UNAME_M)"
	@echo "GPU: $(GPU_TYPE)"
	@echo "GPU Backend: $(GPU_BACKEND)"
	@echo "Build dir: $(BUILD_DIR)"
	@echo ""
	@echo "Available targets:"
	@echo "  make cpu                - Full CPU stack (AVX-512, OpenMP, adaptive tiling)"
	@echo "  make apple              - Full Apple stack (Metal, Neural Engine, AMX)"
	@echo "  make amd                - Full AMD stack (OpenGL, async pipeline)"
	@echo "  make nvidia             - Full NVIDIA stack (OpenGL, persistent kernels)"
	@echo ""
	@echo "Development targets:"
	@echo "  make info               - Show platform detection"
	@echo "  make clean              - Clean build artifacts"
	@echo ""

# Platform detection test
test_platform: $(BUILD_DIR)/test_platform
	@echo "🚀 Running platform detection..."
	@./$(BUILD_DIR)/test_platform

$(BUILD_DIR)/test_platform: $(OBJECTS) $(EXAMPLES_DIR)/test_platform.f90
	@echo "🔨 Building platform test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_platform.f90 -o $@ $(LDFLAGS)

# GPU test (platform-specific)
ifeq ($(PLATFORM),LINUX)
test_gpu: $(BUILD_DIR)/test_gpu_$(GPU_BACKEND)
	@./$(BUILD_DIR)/test_gpu_$(GPU_BACKEND)

$(BUILD_DIR)/test_gpu_opengl: $(OBJECTS) $(EXAMPLES_DIR)/test_gpu_opengl.f90
	@echo "🔨 Building OpenGL GPU test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_gpu_opengl.f90 -o $@ $(LDFLAGS)

# Direct AMDGPU test
test_amdgpu_direct: $(BUILD_DIR)/test_amdgpu_direct
	@echo "🚀 Running direct AMDGPU test..."
	@./$(BUILD_DIR)/test_amdgpu_direct

test_amdgpu_direct_integration: $(BUILD_DIR)/test_amdgpu_direct_integration
	@echo "Running AMDGPU Direct Integration Test..."
	@./$(BUILD_DIR)/test_amdgpu_direct_integration

$(BUILD_DIR)/test_amdgpu_direct_integration: $(OBJECTS) $(EXAMPLES_DIR)/test_amdgpu_direct_integration.f90
	@echo "Building AMDGPU Direct Integration Test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_amdgpu_direct_integration.f90 -o $@ $(LDFLAGS)

$(BUILD_DIR)/test_amdgpu_direct: $(OBJECTS) $(EXAMPLES_DIR)/test_amdgpu_direct.f90
	@echo "🔨 Building direct AMDGPU test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_amdgpu_direct.f90 -o $@ $(LDFLAGS)

# AMDGPU command submission test
test_amdgpu_command: $(BUILD_DIR)/test_amdgpu_command
	@echo "🚀 Running AMDGPU command submission test..."
	@./$(BUILD_DIR)/test_amdgpu_command

$(BUILD_DIR)/test_amdgpu_command: $(OBJECTS) $(EXAMPLES_DIR)/test_amdgpu_command.f90
	@echo "🔨 Building AMDGPU command submission test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_amdgpu_command.f90 -o $@ $(LDFLAGS)

# GLSL compute shader test
test_glsl_compute: $(BUILD_DIR)/test_glsl_compute
	@echo "🚀 Running GLSL compute shader test..."
	@./$(BUILD_DIR)/test_glsl_compute

$(BUILD_DIR)/test_glsl_compute: $(OBJECTS) $(EXAMPLES_DIR)/test_glsl_compute.f90
	@echo "🔨 Building GLSL compute shader test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_glsl_compute.f90 -o $@ $(LDFLAGS)

# Adaptive kernel test
test_adaptive_kernel: $(BUILD_DIR)/test_adaptive_kernel
	@echo "🚀 Running adaptive kernel test..."
	@./$(BUILD_DIR)/test_adaptive_kernel

$(BUILD_DIR)/test_adaptive_kernel: $(OBJECTS) $(EXAMPLES_DIR)/test_adaptive_kernel.f90
	@echo "🔨 Building adaptive kernel test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_adaptive_kernel.f90 -o $@ $(LDFLAGS)

# GPU async proof of concept test
test_gpu_async_poc: $(BUILD_DIR)/test_gpu_async_poc
	@echo "🚀 Running GPU async proof of concept..."
	@./$(BUILD_DIR)/test_gpu_async_poc

$(BUILD_DIR)/test_gpu_async_poc: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_gpu_async_poc.f90
	@echo "🔨 Building GPU async POC test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_gpu_async_poc.f90 -o $@ $(LDFLAGS)

# GPU async executor test
test_gpu_async_executor: $(BUILD_DIR)/test_gpu_async_executor
	@echo "🚀 Running GPU async executor test..."
	@./$(BUILD_DIR)/test_gpu_async_executor

$(BUILD_DIR)/test_gpu_async_executor: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_gpu_async_executor.f90
	@echo "🔨 Building GPU async executor test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_gpu_async_executor.f90 -o $@ $(LDFLAGS)

# AMDGPU compute shader test
test_amdgpu_compute: $(BUILD_DIR)/test_amdgpu_compute
	@echo "🚀 Running AMDGPU compute shader test..."
	@./$(BUILD_DIR)/test_amdgpu_compute

$(BUILD_DIR)/test_amdgpu_compute: $(OBJECTS) $(EXAMPLES_DIR)/test_amdgpu_compute.f90
	@echo "🔨 Building AMDGPU compute shader test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_amdgpu_compute.f90 -o $@ $(LDFLAGS)

# Simple write test
test_simple_write: $(BUILD_DIR)/test_simple_write
	@echo "🚀 Running simple GPU write/read test..."
	@./$(BUILD_DIR)/test_simple_write

$(BUILD_DIR)/test_simple_write: $(OBJECTS) $(EXAMPLES_DIR)/test_simple_write.f90
	@echo "🔨 Building simple write test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_simple_write.f90 -o $@ $(LDFLAGS)

# AMD convolution test  
test_amd_convolution: $(BUILD_DIR)/test_conv_gemm_gpu
	@echo "🚀 Running AMD GPU convolution test..."
	@./$(BUILD_DIR)/test_conv_gemm_gpu

$(BUILD_DIR)/test_conv_gemm_gpu: $(OBJECTS) $(EXAMPLES_DIR)/test_conv_gemm_gpu.f90
	@echo "🔨 Building AMD convolution test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_conv_gemm_gpu.f90 -o $@ $(LDFLAGS)

# GLSL compute test
test_glsl_compute_real: $(BUILD_DIR)/test_glsl_simple
	@echo "🚀 Running GLSL compute shader test..."
	@./$(BUILD_DIR)/test_glsl_simple

$(BUILD_DIR)/test_glsl_simple: $(EXAMPLES_DIR)/test_glsl_simple.f90
	@echo "🔨 Building GLSL compute test..."
	$(FC) $(BASE_FFLAGS) $(EXAMPLES_DIR)/test_glsl_simple.f90 -o $@ -lGL -lEGL

# ===== Safe GPU test targets =====

# Pick the device explicitly (default to iGPU render; override at CLI)
RUN_DEVICE ?= /dev/dri/renderD129  # iGPU (Raphael)
# alt: RUN_DEVICE=/dev/dri/renderD128  # dGPU (7900 XT)

BIN_GL  := $(BUILD_DIR)/test_glsl_debug

.PHONY: build_gpu run_gl

build_gpu: $(BIN_GL)

# --- SAFE RUN MODES (no auto-run during build) ---

run_gl:
	@echo ">>> RUNNING GL compute on $(RUN_DEVICE)"
	SPORKLE_DRI=$(RUN_DEVICE) $(BIN_GL) --safe --once

$(BUILD_DIR)/test_glsl_debug: $(EXAMPLES_DIR)/test_glsl_debug.f90
	@echo "🔨 Building GL debug test..."
	$(FC) $(BASE_FFLAGS) $(EXAMPLES_DIR)/test_glsl_debug.f90 -o $@ -lGL -lEGL

# Fortran shader test
test_fortran_shader: $(BUILD_DIR)/test_fortran_shader
	@echo "🚀 Running Fortran shader test..."
	@./$(BUILD_DIR)/test_fortran_shader

$(BUILD_DIR)/test_fortran_shader: $(OBJECTS) $(EXAMPLES_DIR)/test_fortran_shader.f90
	@echo "🔨 Building Fortran shader test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_fortran_shader.f90 -o $@ $(LDFLAGS)

# Universal memory optimization test
test_universal_memory_optimization: $(BUILD_DIR)/test_universal_memory_optimization
	@echo "🚀 Testing universal memory optimization patterns..."
	@./$(BUILD_DIR)/test_universal_memory_optimization

$(BUILD_DIR)/test_universal_memory_optimization: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_universal_memory_optimization.f90
	@echo "🔨 Building universal memory optimization test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_universal_memory_optimization.f90 -o $@ $(LDFLAGS)

# Intelligent device juggling test
test_intelligent_device_juggling: $(BUILD_DIR)/test_intelligent_device_juggling
	@echo "🧠 Testing intelligent device juggling system..."
	@./$(BUILD_DIR)/test_intelligent_device_juggling

$(BUILD_DIR)/test_intelligent_device_juggling: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_intelligent_device_juggling.f90
	@echo "🔨 Building intelligent device juggling test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_intelligent_device_juggling.f90 -o $@ $(LDFLAGS)

# Benchmarks
benchmark_saxpy: $(BUILD_DIR)/benchmark_saxpy
	@echo "📊 Running SAXPY benchmark..."
	@./$(BUILD_DIR)/benchmark_saxpy

$(BUILD_DIR)/benchmark_saxpy: $(OBJECTS) $(EXAMPLES_DIR)/benchmark_saxpy.f90
	@echo "🔨 Building SAXPY benchmark..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/benchmark_saxpy.f90 -o $@ $(LDFLAGS)
endif

ifeq ($(PLATFORM),MACOS)
test_gpu: $(BUILD_DIR)/test_metal_vs_mock
	@./$(BUILD_DIR)/test_metal_vs_mock
endif

# Compile rules
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.f90
	@echo "📦 Compiling $< for $(PLATFORM)..."
	$(FC) $(BASE_FFLAGS) -c $< -o $@ -J$(BUILD_DIR)

$(BUILD_DIR)/reference/%.o: $(SRC_DIR)/reference/%.f90
	@echo "📦 Compiling $< (reference) for $(PLATFORM)..."
	$(FC) $(BASE_FFLAGS) -c $< -o $@ -J$(BUILD_DIR)

$(BUILD_DIR)/common/%.o: $(SRC_DIR)/common/%.f90
	@echo "📦 Compiling $< (common) for $(PLATFORM)..."
	$(FC) $(BASE_FFLAGS) -c $< -o $@ -J$(BUILD_DIR)

$(BUILD_DIR)/production/%.o: $(SRC_DIR)/production/%.f90
	@echo "📦 Compiling $< (production) for $(PLATFORM)..."
	$(FC) $(BASE_FFLAGS) -c $< -o $@ -J$(BUILD_DIR)

$(BUILD_DIR)/reference/%.o: $(SRC_DIR)/reference/%.c
	@echo "⚙️  Compiling $< (reference C)..."
	$(CC) $(BASE_CFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.m
	@echo "🎮 Compiling $< (Objective-C)..."
	$(CC) $(BASE_CFLAGS) -fobjc-arc -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@echo "⚙️  Compiling $< (C)..."
	$(CC) $(BASE_CFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/production/%.o: $(SRC_DIR)/production/%.c
	@echo "⚙️  Compiling $< (production C)..."
	$(CC) $(BASE_CFLAGS) $(CFLAGS) -c $< -o $@

# Clean
clean:
	@echo "🧹 Cleaning $(PLATFORM) build..."
	rm -rf $(BUILD_DIR)

# Clean all platforms
clean-all:
	@echo "🧹 Cleaning all builds..."
	rm -rf build/

# Adaptive convolution test
test_adaptive_convolution: $(BUILD_DIR)/test_adaptive_convolution
	@echo "🚀 Running adaptive convolution test..."
	@./$(BUILD_DIR)/test_adaptive_convolution
$(BUILD_DIR)/test_adaptive_convolution: $(OBJECTS) $(EXAMPLES_DIR)/test_adaptive_convolution.f90
	@echo "🔨 Building adaptive convolution test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) \
		$(EXAMPLES_DIR)/test_adaptive_convolution.f90 -o $@ $(LDFLAGS)

# Convolution benchmark
benchmark_convolution: $(BUILD_DIR)/benchmark_convolution
	@echo "📊 Running convolution benchmark..."
	@./$(BUILD_DIR)/benchmark_convolution
$(BUILD_DIR)/benchmark_convolution: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/benchmark_convolution.f90
	@echo "🔨 Building convolution benchmark..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/benchmark_convolution.f90 -o $@ $(LDFLAGS)

# Production interface test
test_production_conv2d: $(BUILD_DIR)/test_production_conv2d
	@echo "🧪 Testing production conv2d interface..."
	@./$(BUILD_DIR)/test_production_conv2d
$(BUILD_DIR)/test_production_conv2d: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_production_conv2d.f90
	@echo "🔨 Building production conv2d test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_production_conv2d.f90 -o $@ $(LDFLAGS)

# Correctness test for all paths
test_correctness: $(BUILD_DIR)/test_correctness_all_paths
	@echo "🧪 Testing correctness of all execution paths..."
	@./$(BUILD_DIR)/test_correctness_all_paths
$(BUILD_DIR)/test_correctness_all_paths: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_correctness_all_paths.f90
	@echo "🔨 Building correctness test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_correctness_all_paths.f90 -o $@ $(LDFLAGS)

# Memory wall breakthrough test
test_memory_wall_breakthrough: $(BUILD_DIR)/test_memory_wall_breakthrough
	@echo "🚀 Testing memory wall breakthrough..."
	@OMP_NUM_THREADS=16 ./$(BUILD_DIR)/test_memory_wall_breakthrough

$(BUILD_DIR)/test_memory_wall_breakthrough: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_memory_wall_breakthrough.f90
	@echo "🔨 Building memory wall breakthrough test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_memory_wall_breakthrough.f90 -o $@ $(LDFLAGS)

# RDNA shader optimization test
test_rdna_shader_optimization: $(BUILD_DIR)/test_rdna_shader_optimization
	@echo "🚀 Testing RDNA shader optimization..."
	@./$(BUILD_DIR)/test_rdna_shader_optimization

$(BUILD_DIR)/test_rdna_shader_optimization: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_rdna_shader_optimization.f90
	@echo "🔨 Building RDNA shader optimization test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_rdna_shader_optimization.f90 -o $@ $(LDFLAGS)

# Dynamic shader system test
test_dynamic_shader_system: $(BUILD_DIR)/test_dynamic_shader_system
	@echo "🚀 Testing dynamic shader system..."
	@./$(BUILD_DIR)/test_dynamic_shader_system

$(BUILD_DIR)/test_dynamic_shader_system: $(BUILD_DIR)/sporkle_types.o $(BUILD_DIR)/sporkle_glsl_generator.o $(BUILD_DIR)/sporkle_rdna_shader_generator.o $(BUILD_DIR)/sporkle_dynamic_shader_system.o $(EXAMPLES_DIR)/test_dynamic_shader_system.f90
	@echo "🔨 Building dynamic shader system test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) \
		$(BUILD_DIR)/sporkle_types.o \
		$(BUILD_DIR)/sporkle_glsl_generator.o \
		$(BUILD_DIR)/sporkle_rdna_shader_generator.o \
		$(BUILD_DIR)/sporkle_dynamic_shader_system.o \
		$(EXAMPLES_DIR)/test_dynamic_shader_system.f90 -o $@

# GPU shader variants benchmark
test_gpu_shader_variants: $(BUILD_DIR)/test_gpu_shader_variants
	@echo "🚀 Testing GPU shader variants..."
	@./$(BUILD_DIR)/test_gpu_shader_variants

$(BUILD_DIR)/test_gpu_shader_variants: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_gpu_shader_variants.f90
	@echo "🔨 Building GPU shader variants test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_gpu_shader_variants.f90 -o $@ $(LDFLAGS)

# GPU dynamic shaders test
test_gpu_dynamic_shaders: $(BUILD_DIR)/test_gpu_dynamic_shaders
	@echo "🚀 Testing GPU dynamic shaders..."
	@./$(BUILD_DIR)/test_gpu_dynamic_shaders

$(BUILD_DIR)/test_gpu_dynamic_shaders: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_gpu_dynamic_shaders.f90
	@echo "🔨 Building GPU dynamic shaders test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_gpu_dynamic_shaders.f90 -o $@ $(LDFLAGS)

# Memory wall simple test
test_memory_wall_simple: $(BUILD_DIR)/test_memory_wall_simple
	@echo "🚀 Testing memory wall breakthrough (simple)..."
	@OMP_NUM_THREADS=16 ./$(BUILD_DIR)/test_memory_wall_simple

$(BUILD_DIR)/test_memory_wall_simple: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_memory_wall_simple.f90
	@echo "🔨 Building memory wall simple test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_memory_wall_simple.f90 -o $@ $(LDFLAGS)

# Test peak CPU performance
test_peak_cpu: $(BUILD_DIR)/test_peak_cpu_performance
	@echo "🚀 Testing peak CPU performance..."
	@OMP_NUM_THREADS=32 ./$(BUILD_DIR)/test_peak_cpu_performance

$(BUILD_DIR)/test_peak_cpu_performance: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_peak_cpu_performance.f90
	@echo "🔨 Building peak CPU performance test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_peak_cpu_performance.f90 -o $@ $(LDFLAGS)

# Test SIMD performance
test_simd: $(BUILD_DIR)/test_simd_performance
	@echo "🚀 Testing SIMD performance..."
	@OMP_NUM_THREADS=16 ./$(BUILD_DIR)/test_simd_performance

$(BUILD_DIR)/test_simd_performance: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_simd_performance.f90
	@echo "🔨 Building SIMD performance test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_simd_performance.f90 -o $@ $(LDFLAGS)

# Universal device selector test
test_universal_device_selector: $(BUILD_DIR)/test_universal_device_selector
	@echo "🎯 Testing universal device selector..."
	@./$(BUILD_DIR)/test_universal_device_selector

$(BUILD_DIR)/test_universal_device_selector: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_universal_device_selector.f90
	@echo "🔨 Building universal device selector test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_universal_device_selector.f90 -o $@ $(LDFLAGS)

# GPU program cache test
test_program_cache: $(BUILD_DIR)/test_program_cache
	@echo "🚀 Testing GPU program cache..."
	@./$(BUILD_DIR)/test_program_cache

$(BUILD_DIR)/test_program_cache: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_program_cache.f90
	@echo "🔨 Building GPU program cache test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_program_cache.f90 -o $@ $(LDFLAGS)

# Persistent kernel framework test
test_persistent_kernels: $(BUILD_DIR)/test_persistent_kernels
	@echo "🚀 Testing persistent kernel framework..."
	@./$(BUILD_DIR)/test_persistent_kernels

$(BUILD_DIR)/test_persistent_kernels: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_persistent_kernels.f90
	@echo "🔨 Building persistent kernel test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_persistent_kernels.f90 -o $@ $(LDFLAGS)

# Binary persistence test (Phase 2)
test_binary_persistence: $(BUILD_DIR)/test_binary_persistence
	@echo "🚀 Testing GPU binary persistence..."
	@./$(BUILD_DIR)/test_binary_persistence

$(BUILD_DIR)/test_binary_persistence: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_binary_persistence.f90
	@echo "🔨 Building binary persistence test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_binary_persistence.f90 -o $@ $(LDFLAGS)

# Thread-safe cache test
test_thread_safe_cache: $(BUILD_DIR)/test_thread_safe_cache
	@echo "🚀 Testing thread-safe GPU program cache..."
	@OMP_NUM_THREADS=4 ./$(BUILD_DIR)/test_thread_safe_cache

$(BUILD_DIR)/test_thread_safe_cache: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_thread_safe_cache.f90
	@echo "🔨 Building thread-safe cache test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_thread_safe_cache.f90 -o $@ $(LDFLAGS)

# V3 Performance benchmark
benchmark_v3: $(BUILD_DIR)/benchmark_v3_performance
	@echo "🚀 Running V3 performance benchmark..."
	@OMP_NUM_THREADS=8 ./$(BUILD_DIR)/benchmark_v3_performance

$(BUILD_DIR)/benchmark_v3_performance: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/benchmark_v3_performance.f90
	@echo "🔨 Building V3 performance benchmark..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/benchmark_v3_performance.f90 -o $@ $(LDFLAGS)

# Thread-safe performance benchmark
benchmark_thread_safe: $(BUILD_DIR)/benchmark_thread_safe_performance
	@echo "🚀 Running thread-safe cache performance benchmark..."
	@OMP_NUM_THREADS=8 ./$(BUILD_DIR)/benchmark_thread_safe_performance

$(BUILD_DIR)/benchmark_thread_safe_performance: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/benchmark_thread_safe_performance.f90
	@echo "🔨 Building thread-safe performance benchmark..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/benchmark_thread_safe_performance.f90 -o $@ $(LDFLAGS)

# Simple V3 test
test_v3_simple: $(BUILD_DIR)/test_v3_simple
	@echo "🚀 Running simple V3 test..."
	@./$(BUILD_DIR)/test_v3_simple

$(BUILD_DIR)/test_v3_simple: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_v3_simple.f90
	@echo "🔨 Building simple V3 test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_v3_simple.f90 -o $@ $(LDFLAGS)

# Fixed V3 benchmark
benchmark_v3_fixed: $(BUILD_DIR)/benchmark_v3_fixed
	@echo "🚀 Running fixed V3 performance benchmark..."
	@./$(BUILD_DIR)/benchmark_v3_fixed

$(BUILD_DIR)/benchmark_v3_fixed: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/benchmark_v3_fixed.f90
	@echo "🔨 Building fixed V3 benchmark..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/benchmark_v3_fixed.f90 -o $@ $(LDFLAGS)

# RDNA3 ISA shader test
test_rdna3_isa: $(BUILD_DIR)/test_rdna3_isa_shader
	@echo "🔧 Running RDNA3 ISA shader test..."
	@./$(BUILD_DIR)/test_rdna3_isa_shader

$(BUILD_DIR)/test_rdna3_isa_shader: $(OBJECTS) $(C_OBJECTS) test_rdna3_isa_shader.f90
	@echo "🔨 Building RDNA3 ISA shader test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_rdna3_isa_shader.f90 -o $@ $(LDFLAGS)

# Fence primitives test
test_fence: $(BUILD_DIR)/test_fence_primitives
	@echo "🧪 Running fence primitives test..."
	@./$(BUILD_DIR)/test_fence_primitives

$(BUILD_DIR)/test_fence_primitives: $(OBJECTS) $(C_OBJECTS) test_fence_primitives.f90
	@echo "🔨 Building fence primitives test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_fence_primitives.f90 -o $@ $(LDFLAGS)

# Neo Geo quality check
test_quality: $(BUILD_DIR)/test_neo_geo_quality
	@echo "🔍 Running Neo Geo quality checks..."
	@./$(BUILD_DIR)/test_neo_geo_quality

$(BUILD_DIR)/test_neo_geo_quality: $(OBJECTS) $(C_OBJECTS) test_neo_geo_quality.f90
	@echo "🔨 Building Neo Geo quality test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_neo_geo_quality.f90 -o $@ $(LDFLAGS)

# Juggler fence upgrade test
test_juggler_fence: $(BUILD_DIR)/test_juggler_fence_upgrade
	@echo "⚡ Running juggler fence upgrade test..."
	@./$(BUILD_DIR)/test_juggler_fence_upgrade

$(BUILD_DIR)/test_juggler_fence_upgrade: $(OBJECTS) $(C_OBJECTS) test_juggler_fence_upgrade.f90
	@echo "🔨 Building juggler fence upgrade test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_juggler_fence_upgrade.f90 -o $@ $(LDFLAGS)

# Comprehensive fence benchmark
test_fence_benchmark: $(BUILD_DIR)/test_fence_comprehensive_benchmark
	@echo "📊 Running comprehensive fence benchmark..."
	@./$(BUILD_DIR)/test_fence_comprehensive_benchmark

$(BUILD_DIR)/test_fence_comprehensive_benchmark: $(OBJECTS) $(C_OBJECTS) test_fence_comprehensive_benchmark.f90
	@echo "🔨 Building fence benchmark..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_fence_comprehensive_benchmark.f90 -o $@ $(LDFLAGS)

# Persistent buffer POC
test_persistent_buffer: $(BUILD_DIR)/test_persistent_buffer_poc
	@echo "🧪 Running persistent buffer POC..."
	@./$(BUILD_DIR)/test_persistent_buffer_poc

$(BUILD_DIR)/test_persistent_buffer_poc: $(OBJECTS) $(C_OBJECTS) test_persistent_buffer_poc.f90
	@echo "🔨 Building persistent buffer POC..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_persistent_buffer_poc.f90 -o $@ $(LDFLAGS)

# Unified buffers test
test_unified_buffers: $(BUILD_DIR)/test_unified_buffers
	@echo "🧪 Running unified buffers test..."
	@./$(BUILD_DIR)/test_unified_buffers

$(BUILD_DIR)/test_unified_buffers: $(OBJECTS) $(C_OBJECTS) test_unified_buffers.f90
	@echo "🔨 Building unified buffers test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_unified_buffers.f90 -o $@ $(LDFLAGS)

# Conv2D zero-copy test
test_conv2d_zero_copy: $(BUILD_DIR)/test_conv2d_zero_copy
	@echo "🏎️ Running Conv2D zero-copy test..."
	@./$(BUILD_DIR)/test_conv2d_zero_copy

$(BUILD_DIR)/test_conv2d_zero_copy: $(OBJECTS) $(C_OBJECTS) test_conv2d_zero_copy.f90
	@echo "🔨 Building Conv2D zero-copy test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_conv2d_zero_copy.f90 -o $@ $(LDFLAGS)

# Simple zero-copy test
test_zero_copy_simple: $(BUILD_DIR)/test_zero_copy_simple
	@echo "🧪 Running simple zero-copy test..."
	@./$(BUILD_DIR)/test_zero_copy_simple

$(BUILD_DIR)/test_zero_copy_simple: $(OBJECTS) $(C_OBJECTS) test_zero_copy_simple.f90
	@echo "🔨 Building simple zero-copy test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_zero_copy_simple.f90 -o $@ $(LDFLAGS)

# Standalone zero-copy test
test_zero_copy_standalone: $(BUILD_DIR)/test_zero_copy_standalone
	@echo "🚀 Running standalone zero-copy test..."
	@./$(BUILD_DIR)/test_zero_copy_standalone

$(BUILD_DIR)/test_zero_copy_standalone: $(OBJECTS) $(C_OBJECTS) test_zero_copy_standalone.f90
	@echo "🔨 Building standalone zero-copy test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_zero_copy_standalone.f90 -o $@ $(LDFLAGS)

# Parallel zero-copy test
test_zero_copy_parallel: $(BUILD_DIR)/test_zero_copy_parallel
	@echo "🚀 Running parallel zero-copy test..."
	@./$(BUILD_DIR)/test_zero_copy_parallel

$(BUILD_DIR)/test_zero_copy_parallel: $(OBJECTS) $(C_OBJECTS) test_zero_copy_parallel.f90
	@echo "🔨 Building parallel zero-copy test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_zero_copy_parallel.f90 -o $@ $(LDFLAGS)

# Large workload zero-copy test
test_zero_copy_large: $(BUILD_DIR)/test_zero_copy_large
	@echo "🚀 Running large workload zero-copy test..."
	@./$(BUILD_DIR)/test_zero_copy_large

$(BUILD_DIR)/test_zero_copy_large: $(OBJECTS) $(C_OBJECTS) test_zero_copy_large.f90
	@echo "🔨 Building large workload zero-copy test..."
	$(FC) $(BASE_FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_zero_copy_large.f90 -o $@ $(LDFLAGS)

.PHONY: info clean clean-all cpu apple amd nvidia

$(BUILD_DIR)/test_gpu_async_honest: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_gpu_async_honest.f90
	@echo "🔨 Building honest GPU async test..."
	@$(FC) $(FFLAGS) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_gpu_async_honest.f90 -o $@ $(LDFLAGS)

# =============================================================================
# MAIN PLATFORM TARGETS - Full Stack Testing
# =============================================================================

cpu: $(BUILD_DIR)/sporkle_cpu_stack
	@echo "🚀 Running full CPU stack test..."
	@./$(BUILD_DIR)/sporkle_cpu_stack

apple: $(BUILD_DIR)/sporkle_apple_stack  
	@echo "🚀 Running full Apple stack test..."
	@./$(BUILD_DIR)/sporkle_apple_stack

amd: $(BUILD_DIR)/sporkle_amd_stack
	@echo "🚀 Running full AMD stack test..."
	@./$(BUILD_DIR)/sporkle_amd_stack

nvidia: $(BUILD_DIR)/sporkle_nvidia_stack
	@echo "🚀 Running full NVIDIA stack test..."
	@./$(BUILD_DIR)/sporkle_nvidia_stack

# CPU Stack: AVX-512, OpenMP, Adaptive Tiling, Production Conv2D
$(BUILD_DIR)/sporkle_cpu_stack: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_cpu_full_stack.f90
	@echo "🔨 Building CPU full stack (AVX-512 + OpenMP + Production)..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_cpu_full_stack.f90 -o $@ $(LDFLAGS)

# Apple Stack: Metal + Neural Engine + AMX + CoreML
$(BUILD_DIR)/sporkle_apple_stack: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_apple_full_stack.f90
	@echo "🔨 Building Apple full stack (Metal + Neural Engine + AMX)..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_apple_full_stack.f90 -o $@ $(LDFLAGS)

# AMD Stack: OpenGL + Async Pipeline + Thread-Safe Cache
$(BUILD_DIR)/sporkle_amd_stack: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_amd_full_stack.f90
	@echo "🔨 Building AMD full stack (OpenGL + Async Pipeline)..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_amd_full_stack.f90 -o $@ $(LDFLAGS)

# NVIDIA Stack: OpenGL + Persistent Kernels + Zero-Copy
$(BUILD_DIR)/sporkle_nvidia_stack: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_nvidia_full_stack.f90
	@echo "🔨 Building NVIDIA full stack (OpenGL + Persistent Kernels)..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_nvidia_full_stack.f90 -o $@ $(LDFLAGS)

# Test Mini's corrections
test_mini_corrections: $(BUILD_DIR)/test_mini_corrections
	@echo "🧪 Testing Mini's RDNA3 corrections..."
	@./$(BUILD_DIR)/test_mini_corrections

$(BUILD_DIR)/test_mini_corrections: $(OBJECTS) $(C_OBJECTS) $(EXAMPLES_DIR)/test_mini_corrections.f90
	@echo "🔨 Building Mini's corrections test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		$(EXAMPLES_DIR)/test_mini_corrections.f90 -o $@ $(LDFLAGS)

# Test Vulkan breakthrough
test_vulkan_breakthrough: $(BUILD_DIR)/test_vulkan_breakthrough
	@echo "🚀 Testing Vulkan performance breakthrough..."
	@./$(BUILD_DIR)/test_vulkan_breakthrough

$(BUILD_DIR)/test_vulkan_breakthrough: $(OBJECTS) $(C_OBJECTS) test_vulkan_breakthrough.f90
	@echo "🔨 Building Vulkan breakthrough test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_vulkan_breakthrough.f90 -o $@ $(LDFLAGS)

# Test Vulkan real conv2d
test_vulkan_real: $(BUILD_DIR)/test_vulkan_real_conv2d
	@echo "🚀 Testing Vulkan real conv2d performance..."
	@./$(BUILD_DIR)/test_vulkan_real_conv2d

$(BUILD_DIR)/test_vulkan_real_conv2d: $(OBJECTS) $(C_OBJECTS) test_vulkan_real_conv2d.f90
	@echo "🔨 Building Vulkan real conv2d test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_vulkan_real_conv2d.f90 -o $@ $(LDFLAGS)

# Test Vulkan memory only
test_vulkan_memory: $(BUILD_DIR)/test_vulkan_memory_only
	@echo "💾 Testing Vulkan memory allocation..."
	@./$(BUILD_DIR)/test_vulkan_memory_only

$(BUILD_DIR)/test_vulkan_memory_only: $(OBJECTS) $(C_OBJECTS) test_vulkan_memory_only.f90
	@echo "🔨 Building Vulkan memory test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_vulkan_memory_only.f90 -o $@ $(LDFLAGS)

# Test Vulkan safe compute
test_vulkan_safe: $(BUILD_DIR)/test_vulkan_safe_compute
	@echo "🛡️  Testing Vulkan safe compute..."
	@./$(BUILD_DIR)/test_vulkan_safe_compute

$(BUILD_DIR)/test_vulkan_safe_compute: $(OBJECTS) $(C_OBJECTS) test_vulkan_safe_compute.f90
	@echo "🔨 Building Vulkan safe compute test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_vulkan_safe_compute.f90 -o $@ $(LDFLAGS)

# Test Vulkan real performance
test_vulkan_real_performance: $(BUILD_DIR)/test_vulkan_real_performance
	@echo "🎯 Testing Vulkan real performance..."
	@./$(BUILD_DIR)/test_vulkan_real_performance

$(BUILD_DIR)/test_vulkan_real_performance: $(OBJECTS) $(C_OBJECTS) test_vulkan_real_performance.f90
	@echo "🔨 Building Vulkan real performance test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		test_vulkan_real_performance.f90 -o $@ $(LDFLAGS)

# Test CPU kernel dispatch
test_cpu_dispatch: $(BUILD_DIR)/test_cpu_kernel_dispatch
	@echo "🧠 Running CPU kernel dispatch test..."
	@./$(BUILD_DIR)/test_cpu_kernel_dispatch

$(BUILD_DIR)/test_cpu_kernel_dispatch: $(OBJECTS) $(C_OBJECTS) tests/test_cpu_kernel_dispatch.f90
	@echo "🧠 Building CPU kernel dispatch test..."
	@$(FC) $(FFLAGS) -I$(BUILD_DIR) $(OBJECTS) $(C_OBJECTS) \
		tests/test_cpu_kernel_dispatch.f90 -o $@ $(LDFLAGS)
