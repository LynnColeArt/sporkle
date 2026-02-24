> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Naming TODO: Sparkle → Sporkle Transition

## Background
We discovered a naming conflict with SparkleAI in the community, so we've decided to rename the project to "Sporkle". This document tracks what needs to be updated.

## Transition Strategy
For now, we're keeping the internal code names as "sporkle_*" to avoid disrupting active development. The rename will be done in a future refactoring phase.

## What Needs to be Renamed

### 1. Module Names (All `sporkle_*` → `sporkle_*`)
- sporkle_types
- sporkle_memory
- sporkle_kernels
- sporkle_safe_kernels
- sporkle_platform
- sporkle_config
- sporkle_error_handling
- sporkle_mesh_types
- sporkle_gpu_*
- sporkle_amdgpu_direct
- sporkle_glsl_*
- sporkle_adaptive_kernel
- etc. (all 50+ modules)

### 2. Type Names
- sporkle_buffer → sporkle_buffer
- sporkle_context → sporkle_context
- sporkle_array → sporkle_array
- sporkle_kernel → sporkle_kernel
- sporkle_config_type → sporkle_config_type
- etc.

### 3. Constants and Parameters
- SPARKLE_SUCCESS → SPORKLE_SUCCESS
- SPARKLE_ERROR → SPORKLE_ERROR
- SPARKLE_DEBUG → SPORKLE_DEBUG
- SPARKLE_MAX_* → SPORKLE_MAX_*
- etc.

### 4. Environment Variables
- SPARKLE_MAX_CPU_THREADS → SPORKLE_MAX_CPU_THREADS
- SPARKLE_CHECK_BOUNDS → SPORKLE_CHECK_BOUNDS
- SPARKLE_DEBUG → SPORKLE_DEBUG
- etc.

### 5. Documentation
- Update project name in all docs
- "The Sporkle Way" → "The Sporkle Way"
- SPARKLE_PROPOSAL.md → SPORKLE_PROPOSAL.md
- All references in CLAUDE.md
- README files
- Philosophy documents
- etc.

### 6. Build System
- Project name in Makefile
- CMakeLists.txt project declaration
- Any sparkle-specific targets

### 7. Comments and Strings
- All comments mentioning "Sparkle"
- Print statements in examples
- Error messages
- Documentation strings

## Files Affected
- 106+ files contain "Sparkle" references
- Virtually every source file needs module name updates
- All documentation files
- All example programs
- All test programs

## Recommended Approach
1. Create a git branch specifically for the rename
2. Use automated tools (sed/awk) for bulk replacements
3. Manual review of edge cases
4. Comprehensive testing after rename
5. Update all documentation

## Priority
LOW - Current focus is on implementation and benchmarking. This can be done as a cleanup task once core functionality is stable.

## Notes
- The name "Sporkle" is fun and memorable (like a spork - versatile and practical!)
- Internal consistency is more important than external naming for now
- This rename should be done in one comprehensive pass to avoid confusion