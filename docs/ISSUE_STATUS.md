> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Issue Status Tracking

## Completed Issues ✅

1. **Platform-aware build system** 
   - Status: COMPLETE
   - Evidence: Makefile.smart detects Linux/AMD and builds accordingly

2. **Direct AMDGPU driver access**
   - Status: COMPLETE  
   - Evidence: Successfully submitting command buffers via ioctl

3. **Fix AMDGPU mmap for buffer allocation**
   - Status: COMPLETE
   - Evidence: 32-byte union fix resolved the issue

4. **AMDGPU command submission** 
   - Status: COMPLETE
   - Evidence: NOP packets executing successfully

5. **Fix double indirection for CS submission**
   - Status: COMPLETE
   - Evidence: cs.in.chunks properly points to array of pointers

6. **GLSL compute shader generation**
   - Status: COMPLETE
   - Evidence: sporkle_glsl_generator.f90 creates valid GLSL

7. **Adaptive kernel framework**
   - Status: COMPLETE
   - Evidence: Framework selecting optimal variants based on profiling

## In Progress Issues 🔨

1. **Integrate convolution-as-GEMM kernel for AMDGPU**
   - Next step: Implement actual compute shader
   - Blocked by: Need shader compiler integration

2. **Create EGL context for headless compute**
   - Next step: Initialize EGL for OpenGL compute
   - Priority: HIGH

## Pending Issues 📋

1. **AMDGPU shader compilation**
   - Approach: Start with pre-compiled binary, then add runtime compilation

2. **Run real benchmarks**
   - Waiting for: Actual kernel implementation

3. **GL/AMDGPU buffer interop**
   - Needed for: GLSL compute path

4. **Rename Sparkle to Sporkle**
   - Status: DEFERRED
   - Priority: LOW
   - Reason: Focus on functionality first

## Future Features 🚀

1. **Dynamic Shader Generation with Genetic Algorithms**
   - Status: PROPOSED
   - Timeline: After core functionality complete
   - Potential: Revolutionary but requires solid foundation

2. **SPIR-V variant implementation**
   - Part of adaptive kernel strategy

3. **Direct PM4 shader execution**
   - Most "metal" approach

4. **Extend to NVIDIA via direct ioctl**
   - After AMD implementation is solid

## Closed Non-Issues 🎉

1. **Basic memory safety** - Resolved with error handling module
2. **GPU detection command injection** - Fixed with safe detection
3. **Memory leaks in tests** - Cleaned up
4. **Compilation warnings** - Addressed

## Priority Order

1. Get ONE kernel actually computing on GPU
2. Measure real performance
3. Implement remaining variants
4. Benchmark everything honestly
5. THEN consider advanced features like genetic optimization