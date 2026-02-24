> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# ADR-001: Unified Submit API

## Status
Accepted

## Context
We had multiple submit helper functions scattered across the codebase:
- `sp_submit_ib` - single BO submission
- `sp_submit_ib_internal` - internal helper with different signature
- Various test-specific submit functions

This led to bugs where shader/data BOs weren't included in the submission list.

## Decision
Consolidate all submission paths into a single golden API:
```c
int sp_submit_ib_with_bos(sp_pm4_ctx* ctx, 
                          sp_bo* ib_bo, 
                          uint32_t ib_size_dw,
                          sp_bo** data_bos, 
                          uint32_t num_data_bos, 
                          sp_fence* out_fence);
```

This ensures ALL buffer objects are submitted together in one ioctl.

## Consequences
- **Good**: Eliminates split-BO bugs
- **Good**: Single code path to debug
- **Good**: Clear API contract
- **Bad**: Slightly more verbose for simple cases
- **Bad**: Need to migrate all existing code

## Implementation
1. Create new API in `src/compute/submit.c`
2. Migrate all tests to use new API
3. Delete old submit helpers
4. Update documentation