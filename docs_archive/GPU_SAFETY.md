> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GPU SAFETY PROTOCOL - CRITICAL

## IMMEDIATE DANGER: PM4 Direct Command Submission

**NEVER RUN** any PM4 command submission code without proper validation. The `test_pm4_final.f90` caused a complete system freeze by submitting potentially malformed commands directly to the GPU hardware.

## What Happened
- Direct PM4 command submission via `amdgpu_submit_command_buffer()`
- Likely sent invalid shader addresses or malformed packets
- GPU hung, causing kernel panic and complete system freeze
- Required hard reset

## SAFETY RULES GOING FORWARD

### 1. NO DIRECT COMMAND SUBMISSION
```fortran
! DANGEROUS - DO NOT USE
status = amdgpu_submit_command_buffer(device, submit_cmd)
```

### 2. VALIDATION ONLY MODE
- Only test packet generation and validation
- Never actually submit to GPU hardware
- Use simulation/logging instead

### 3. MANDATORY SAFETY CHECKS
```fortran
! Check for safety mode
if (.not. gpu_safety_mode_enabled()) then
  print *, "❌ SAFETY: GPU direct submission disabled"
  return
end if

! Validate all addresses are in safe ranges
if (shader_addr < MIN_SAFE_ADDR .or. shader_addr > MAX_SAFE_ADDR) then
  print *, "❌ SAFETY: Unsafe shader address"
  return
end if
```

### 4. INCREMENTAL TESTING ONLY
- Start with OpenGL/Mesa wrappers (proven safe)
- Only attempt direct submission after extensive validation
- Always have safety timeouts and limits

## CURRENT STATUS
- PM4 packet generation: ✅ SAFE (no hardware interaction)
- VA mapping: ✅ SAFE (tested working)
- Command submission: ❌ DANGEROUS (disabled)

## RECOVERY ACTIONS
1. Removed `test_pm4_final.f90` 
2. All PM4 command submission code marked as dangerous
3. Focus on safe validation and OpenGL integration instead

**REMEMBER: We can achieve the same performance goals through safe OpenGL compute shaders rather than risking system stability with direct PM4 submission.**