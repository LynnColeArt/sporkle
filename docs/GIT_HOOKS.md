> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Mini's Integrity Checking Git Hooks

## Overview

Automated pre-commit hooks that catch common Fortran bugs before they enter the codebase. Based on Mini's code review findings.

## Setup

```bash
./setup_git_hooks.sh
```

This configures git to use the `.githooks/` directory for hooks.

## What Gets Checked

### 1. Mixed-Kind Arithmetic 🔢
Detects numeric literals without kind suffixes in arithmetic operations.
- **Bad**: `x = y * 2.0`
- **Good**: `x = y * 2.0_dp`

### 2. Raw system_clock Usage ⏰
Ensures proper time measurement using time_utils module.
- **Bad**: `call system_clock(t1)`
- **Good**: `use time_utils; call tic(t1)`

### 3. Manual FLOP Calculations 🧮
Detects manual FLOP counting that might overflow.
- **Bad**: `flops = n * m * k * 2`
- **Good**: `use flopcount; flops = gemm_flops(n, m, k)`

### 4. Direct iso_fortran_env Usage 📦
Enforces use of kinds module for portability.
- **Bad**: `use iso_fortran_env, only: real64`
- **Good**: `use kinds`

### 5. c_f_pointer Shape Issues 🔧
Warns about literals in shape arguments.
- **Bad**: `call c_f_pointer(ptr, array, [100])`
- **Good**: `call c_f_pointer(ptr, array, [100_c_int])`

### 6. GFLOPS Precision Errors 📊
Catches single-precision literals in performance calculations.
- **Bad**: `gflops = flops / 1.0e6`
- **Good**: `gflops = flops / 1.0d6`

### 7. Error Handling 🛡️
Warns about missing error checking.
- **Bad**: `allocate(array(n))`
- **Good**: `allocate(array(n), stat=ierr)`

## Usage

The hooks run automatically on `git commit`. If issues are found:

```
❌ Found 4 critical issues that should be fixed.

To bypass this check (not recommended):
  git commit --no-verify
```

## Advanced: Compilation Checking

For thorough checking, enable compilation tests:

```bash
export SPORKLE_COMPILE_CHECK=1
git commit -m "..."
```

This will attempt to compile staged files (slower but catches more issues).

## Disabling

To temporarily disable:
```bash
git commit --no-verify -m "Emergency fix"
```

To permanently disable:
```bash
git config --unset core.hooksPath
```

## Philosophy

"An ounce of prevention is worth a pound of debugging" - Mini

These hooks catch issues that:
- Cause subtle numerical errors
- Lead to platform-specific bugs  
- Create performance regressions
- Result in memory issues

By catching them at commit time, we maintain code quality and save debugging time.