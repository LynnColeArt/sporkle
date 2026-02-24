> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Shader Binary Attribution and Philosophy

## Our Approach

For shader compilation in Sporkle, we've made a conscious decision to leverage existing work from AMD's ROCm project rather than reinventing shader compilation from scratch.

## Why We're Using ROCm's Compiler

1. **Focus Our Innovation**: Core contributions are in:
   - Direct kernel driver access from Fortran
   - Adaptive kernel selection framework
   - Heterogeneous compute orchestration
   - Democratizing AI compute access

2. **Standing on Shoulders of Giants**: AMD has spent years perfecting:
   - Optimal instruction scheduling
   - Register allocation algorithms  
   - Architecture-specific optimizations
   - Safety and correctness objectives

3. **Pragmatic Engineering**: Sometimes the smartest move is knowing when NOT to reinvent the wheel. Shader compilation is a solved problem - our innovation lies elsewhere.

## Attribution

The shader binaries in this project are generated using:
- **AMD ROCm Compiler**: For transforming high-level kernels to GCN machine code
- **AMD GCN3 ISA Documentation**: For understanding the binary format
- **LLVM AMDGPU Backend**: The underlying compilation infrastructure

We gratefully acknowledge AMD's open-source contributions that make this possible.

## Our Contributions

While we use AMD's compiler for shader generation, our innovations include:

1. **Direct PM4 Command Submission**: Bypassing the ROCm runtime (archival path)
2. **Fortran Integration**: Fortran orchestration for kernel generation and dispatch (archival PM4 context)
3. **Adaptive Optimization**: Automatic selection of best implementation
4. **Zero-Dependency Execution**: No ROCm runtime required for the archived PM4-style execution path

## How It Works

1. **Development Time**: Use ROCm compiler to generate optimized shader binaries
2. **Compile Time**: Embed binaries directly in Fortran modules  
3. **Runtime**: Execute via direct kernel driver access. Runtime dependency posture varies by active backend and is documented in the current backend route.

## Example Workflow

```bash
# One-time: Generate shader binary using ROCm
./tools/extract_shader.sh

# This creates optimized GCN machine code
# We embed this in our Fortran module

# Runtime: Direct execution without ROCm in the archival PM4 reference path
./test_amdgpu_compute  # Historical command path; verify runtime dependencies before reuse
```

## Philosophy

We believe in:
- **Pragmatic Solutions**: Use the best tool for each job
- **Proper Attribution**: Always credit the giants whose shoulders we stand on
- **Focused Innovation**: Put our effort where we can make unique contributions
- **Open Collaboration**: Share our work as AMD shared theirs

## Future Possibilities

While we currently use pre-compiled shaders, our framework enables:
- Runtime shader generation (future feature)
- Cross-architecture shader abstractions
- The genetic shader evolution system (when we're ready!)

## License Compatibility

AMD's ROCm is released under the MIT license, making it fully compatible with our approach. We can use their compiler output while maintaining our own licensing terms for the framework.

---

*"Sometimes the most innovative thing you can do is recognize when someone else has already solved a problem well, and build something new on top of their solution."* - The Sporkle Way
