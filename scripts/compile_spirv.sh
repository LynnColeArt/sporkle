#!/bin/bash
# Compile GLSL shaders to SPIR-V for Kronos

set -e

SHADER_DIR="src"
OUTPUT_DIR="build/spirv"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check if glslangValidator is available
if ! command -v glslangValidator &> /dev/null; then
    echo "Error: glslangValidator not found!"
    echo "Install with: sudo apt-get install glslang-tools"
    exit 1
fi

echo "Compiling Conv2D shader to SPIR-V..."
glslangValidator -V -o "$OUTPUT_DIR/conv2d.spv" "$SHADER_DIR/spirv_conv2d.glsl"

if [ $? -eq 0 ]; then
    echo "✅ Successfully compiled to $OUTPUT_DIR/conv2d.spv"
    echo "Size: $(wc -c < "$OUTPUT_DIR/conv2d.spv") bytes"
    
    # Generate hex dump for embedding in Fortran
    echo ""
    echo "Generating Fortran module with embedded SPIR-V..."
    xxd -i "$OUTPUT_DIR/conv2d.spv" > "$OUTPUT_DIR/conv2d_spirv.h"
    
    # Also create a simple binary dump
    echo "Creating binary dump for inspection..."
    spirv-dis "$OUTPUT_DIR/conv2d.spv" -o "$OUTPUT_DIR/conv2d.spvasm" 2>/dev/null || true
else
    echo "❌ Compilation failed!"
    exit 1
fi