> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# AMDGPU Direct Integration

## Overview

**Status:** historical reference only (PM4/direct driver path is archived).
The AMDGPU direct driver interface was used for kernel-path experiments and is now outside the active Kronos-first production route.

## Architecture

```
┌─────────────────────────────────────┐
│     Sparkle Device Interface        │
│    (compute_device abstract)        │
└─────────────┬───────────────────────┘
              │
┌─────────────┴───────────────────────┐
│    amdgpu_compute_device            │
│  (extends compute_device)           │
│                                     │
│  - Implements allocate/deallocate   │
│  - Implements memcpy/execute/sync   │
│  - Tracks GPU buffers               │
└─────────────┬───────────────────────┘
              │
┌─────────────┴───────────────────────┐
│    sporkle_amdgpu_direct            │
│  (Direct kernel ioctl interface)    │
│                                     │
│  - Opens /dev/dri/cardN             │
│  - GEM buffer management            │
│  - PM4 packet submission            │
└─────────────────────────────────────┘
              │
┌─────────────┴───────────────────────┐
│      Linux Kernel AMDGPU Driver     │
└─────────────────────────────────────┘
```

## Implementation Status

### ✅ Completed
- Created `amdgpu_device_mod` module that extends `compute_device`
- Implemented required abstract methods during historical exploration
- Connected to existing AMDGPU direct implementation
- Test program compiles and runs in historical mode

### ⚠️ Limitations
- Buffer allocation depends on host permissions and device state
- PM4 shader execution remains unimplemented in active paths
- Fence-based synchronization was incomplete for production handoff
- Buffer tracking simplified (max 100 buffers)

## Key Design Decisions

1. **Naming**: Used `amdgpu_compute_device` to avoid conflicts with existing `amdgpu_device` type

2. **Context Management**: Simplified context creation (would need proper ioctl in production)

3. **Buffer Tracking**: Added array to track allocated GPU buffers for cleanup

4. **Memory Mapping**: All GPU buffers are mapped to CPU for access (coherent memory model)

## Usage Example

```fortran
! Create device for discrete GPU (card1)
device = create_amdgpu_device(1)

! Check if initialized
if (device%is_available) then
  ! Allocate GPU memory
  buffer = device%allocate(size_bytes)
  
  ! Execute kernel
  status = device%execute("kernel_name", args, grid, block)
  
  ! Cleanup
  call device%cleanup()
end if
```

## Integration Points

The AMDGPU direct device is useful for:

1. **Standalone**: Direct low-level investigation and troubleshooting
2. **Benchmarking references** for low-level behavior
3. **Experimental**: Cross-check dispatch assumptions against Kronos logs

## Future Work

1. **PM4 Compute Dispatch**: Maintain this as a documented reference only
2. **Fence Synchronization**: Preserve notes for future diagnostic tooling
3. **Multi-GPU**: Support both iGPU (card0) and dGPU (card1) simultaneously in Kronos runtime
4. **Memory Domains**: Prioritize Kronos runtime pathway compatibility

## Performance Potential

Performance uplift in this document is historical and not active evidence.

## Testing

```bash
# Build test
make test_amdgpu_direct_integration

# Run (requires video group membership or root)
./build/test_amdgpu_direct_integration
```

Current output shows the historical device interface behavior; archive artifacts are for reference only.
