# Sporkle Documentation Credibility Recovery Status

**Date:** 2026-02-24  
**Scope:** Sporkle docs only (Kronos docs remain in separate recovery posture)

## Credibility posture

This repository is in a Kronos-first recovery state. The active production path is:

- AMD/NVIDIA execution through Kronos
- Apple Neural Engine support as planned/refresh-needed
- PM4, OpenGL, and other direct-driver paths retained as historical reference

During recovery:

- Historical performance claims are not treated as current production facts.
- New claims in active docs must be tagged with evidence state (`[implemented]`, `[experimental]`, `[planned]`).
- Benchmark claims are intentionally deferred until the active runtime is stable and benchmarks are re-run.

## What changed in this cleanup pass

- `docs/reorg-progress.md`
  - Reoriented PM4 status to archival-only.
  - Replaced PM4 build/debug priorities with Kronos-first integration tasks.
- `docs/AMDGPU_DIRECT_INTEGRATION.md`
  - Reframed direct AMDGPU as historical reference.
  - Removed direct submission performance uplift language as active evidence.
- `docs/MILESTONE_AMDGPU_DIRECT.md`
  - Updated thesis and milestones to archival context.
  - Reframed next-steps toward Kronos-backed orchestration.
- `docs/PENDING_INTEGRATIONS.md`
  - Archived PM4 item as non-production.
  - Replaced PM4 integration readiness with Kronos-native NVIDIA work.
- `docs/UNIVERSAL_DEVICE_SELECTOR_DESIGN.md`
- `docs/AUTOMATIC_DEVICE_SELECTION.md`
- `docs/PERSISTENT_KERNEL_IMPLEMENTATION.md`
- `docs/PERFORMANCE.md`
- `docs/PERFORMANCE_TESTING.md`
  - Removed hard claims on validated speedups and benchmark thresholds.
  - Emphasized placeholders and deferred enforcement.
- `docs/DISCUSSION_MEMORY_CEILING_BREAKTHROUGH.md`
- `docs/PROPOSAL_UNIFIED_FORTRAN_DSL.md`
- `docs/GITHUB_ISSUE_UNIFIED_DSL.md`
- `docs/FORTRAN_SHADER_MVP.md`
- `docs/persistent_mapped_buffers_research.md`
- `docs/GLSL_KERNEL_IMPLEMENTATION_PLAN.md`
- `docs/GLSL_IMPLEMENTATION_STATUS.md`
- `docs/GPU_CACHE_COMPRESSION.md`
  - Staged language applied to historical performance statements and migration claims.
- `docs/GPU_ARCHITECTURE.md`
  - Relaxed cross-vendor language to staged capability intent.
- `docs/ADAPTIVE_KERNEL_STRATEGY.md`
  - Reframed cross-vendor statements as staged validation targets.
- `docs/GPU_ASYNC_REALITY_CHECK.md`
  - Softened concluding production statements and marked as staged validation only.
- `docs/GPU_ASYNC_BREAKTHROUGH.md`
  - Converted concrete utilization/speedup percentages to deferred placeholders.
- `docs/PERSISTENT_KERNEL_DESIGN.md`
  - Reworded staged performance/error-handling claims away from production-ready assertions.
- `docs/GPU_CACHE_COMPRESSION.md`
  - Removed raw "faster" net-effect assertions in favor of staged comparison language.

## Outstanding risks to monitor

- Some historic "breakthrough" and "achievement" narratives remain in older design notes.
  - They are now uniformly prefixed by the repository recovery note, but any external-facing references should still verify freshness.
- Kronos runtime stability and NVIDIA capability verification are still the highest-priority blockers for reintroducing production performance numbers.

## Planned follow-ups

1. Keep claims in active docs limited to observed, reproducible telemetry.
2. Re-run benchmark corpus after Kronos execution and dispatch telemetry are stable.
3. Re-enable explicit threshold gates only after post-recovery threshold baselines are produced.
4. Continue removing PM4 from operational paths; keep only archival references for research.

## Notes

- Benchmark claims will return once `make`/validation and telemetry baselines are stable under the active Kronos path.
- Hard-fail behavior remains preferred over silent fallback behavior where routing or hardware assumptions are unverified.
