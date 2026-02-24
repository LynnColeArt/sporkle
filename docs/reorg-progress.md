> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle Reorganization Progress

## Phase 1: Lean Production Core ✅

### Completed Tasks

1. **Created new directory structure** ✅
   ```
   sporkle/
   ├─ docs/adr/              ✅ Architecture decision records
   ├─ src/
   │  ├─ core/               ✅ Core types and constants
   │  ├─ pm4/                ✅ Historical PM4 archive (non-production)
   │  ├─ compute/            ✅ Submit API and selftest
   │  ├─ toolchain/          ✅ Created (empty)
   │  └─ cli/                ✅ CLI entry point
   ├─ tests/                 ✅ Moved all test files here
   ├─ kernels/               ✅ Shader sources
   └─ scripts/               ✅ Build tools
   ```

2. **Consolidated preamble logic** ✅
   - Created `src/pm4/preamble.c` with standard initialization
   - Extracted common patterns from test files
   - Using libdrm's working values

3. **Created selftest framework** ✅
  - `src/compute/selftest.c` with Stage A (DEADBEEF) and Stage B (SAXPY)
  - `src/cli/sporkle.c` with `kronos --selftest` command entrypoint
  - The command returns recovery-mode diagnostics and acts as a required smoke-test hook

4. **Moved test files** ✅
   - All `test_*.f90` files moved to `tests/`
   - Cleaned up root directory

5. **Created kernel sources** ✅
   - `kernels/deadbeef.s` - Assembly test kernel
   - `kernels/saxpy.cl` - OpenCL C kernel
   - `scripts/compile_kernel.sh` - Architecture-aware compilation

## Next Steps

### Immediate Tasks
1. **Kronos-first integration**
   - Run `make` and integration tests for current Kronos path
   - Verify dispatch wiring from production-facing interface
   - Validate failure behavior for unavailable backends

2. **Delete duplicate helpers** 📝
   - Remove old submit functions
   - Update all references to use new API

### PM4 Path Status
- PM4 code is archived and kept for historical context
- No active debug queue for PM4 execution is currently maintained
- Focus is shifted to Kronos dispatch and production-capable backends

## Key Insights from Reorganization

1. **Single submit path** prevents BO list bugs
2. **Clear selftest hook** keeps recovery diagnostics explicit
3. **Separated concerns** - production vs test code
4. **Architecture-aware** kernel compilation

## Status Summary
- ✅ Directory structure created
- ✅ Core files created (needs compilation fixes)
- ✅ Test files moved
- 🔧 Build system needs testing
- 📝 Old code needs cleanup
