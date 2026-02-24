> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Performance Regression Testing Guide

## Overview

The Sparkle performance regression testing framework ensures our optimizations remain intact across code changes. It automatically detects when performance drops below established thresholds and prevents accidental regressions from reaching production.

## Performance Baselines

Our current performance achievements that must be maintained:

| Component | Performance | Threshold (80%) | Hardware |
|-----------|-------------|-----------------|----------|
| CPU SIMD | [deferred throughput metric] | [deferred throughput metric] | AMD Ryzen 7900X (AVX-512) |
| GPU Single | [deferred throughput metric] | [deferred throughput metric] | AMD RX 7900 XT |
| GPU Async | [deferred throughput metric] | [deferred throughput metric] | AMD RX 7900 XT |
| Async Speedup | [deferred speedup] | [deferred speedup] | Triple buffering |

## Quick Start

### Running Tests Locally

```bash
# Run all performance regression tests
./run_performance_tests.sh

# Run from tests directory with make
cd tests
make test

# Run with relaxed thresholds during development
make test-dev

# Generate detailed performance report
make report
```

### Expected Output

✅ **All Tests Pass:**
```
🔍 PERFORMANCE REGRESSION TEST SUITE
===================================

Checking that our optimizations haven't regressed...

1. Testing CPU SIMD Performance...
   ✅ CPU SIMD: [deferred throughput metric] (threshold: 157.0)
2. Testing GPU Single Kernel Performance...
   ✅ GPU Single: [deferred throughput metric] (threshold: 356.0)
3. Testing GPU Async Pipeline Performance...
   ✅ GPU Async: [deferred throughput metric] (threshold: [deferred throughput metric])
   ✅ Speedup: [deferred speedup] (threshold: [deferred speedup])
4. Testing Timing Accuracy (Mini's hardening)...
   ✅ Timing accuracy: [deferred latency] for [deferred latency] sleep
5. Testing FLOP Counting Safety (Mini's hardening)...
   ✅ 64-bit FLOP counting: 151 billion FLOPs

===================================
✅ ALL PERFORMANCE TESTS PASSED!
Our optimizations are intact! 🎉
```

❌ **Performance Regression Detected:**
```
❌ GPU Single: [deferred throughput metric] (BELOW threshold: 356.0)
❌ FAILED 1 TESTS!
Performance has regressed - investigate immediately!
```

## Test Components

### 1. Core Test Suite
**File:** `tests/performance_regression_test.f90`

Tests five critical areas:
- **CPU SIMD Performance**: Ensures AVX-512 optimizations are working
- **GPU Single Kernel**: Validates single kernel dispatch performance
- **GPU Async Pipeline**: Checks triple-buffered pipeline throughput
- **Timing Accuracy**: Verifies Mini's timing hardening
- **FLOP Counting**: Ensures 64-bit safe calculations

### 2. Implementation Module
**File:** `tests/performance_regression_impl.f90`

Provides actual benchmark implementations that:
- Call production kernels with standard parameters
- Handle proper warmup (5-20 iterations)
- Average results over multiple runs
- Calculate GFLOPS using Mini's safe math

### 3. Test Runner Script
**File:** `run_performance_tests.sh`

Bash script that:
- Builds tests if needed
- Sets appropriate environment (CI vs dev)
- Provides clear pass/fail reporting
- Returns proper exit codes for automation

## Integration Points

### GitHub Actions CI/CD

The workflow (`.github/workflows/performance-tests.yml`) runs:
- On every pull request
- On pushes to main branch
- Nightly at 2 AM UTC
- Posts results as PR comments

### Git Pre-commit Hook

To enable pre-commit testing:
```bash
cp hooks/pre-commit-performance .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

This prevents commits if performance regresses. Override with:
```bash
git commit --no-verify  # Use sparingly!
```

## Customization

### Adjusting Thresholds

Edit thresholds in `tests/performance_regression_test.f90`:
```fortran
real(real64), parameter :: CPU_SIMD_THRESHOLD = [deferred throughput metric]_real64      ! 80% of deferred benchmark result
real(real64), parameter :: GPU_SINGLE_THRESHOLD = [deferred throughput metric]_real64    ! 80% of deferred benchmark result
real(real64), parameter :: GPU_ASYNC_THRESHOLD = [deferred throughput metric]_real64    ! 80% of deferred benchmark result
```

### Adding New Tests

1. Add test subroutine to `performance_regression_test.f90`
2. Implement benchmark in `performance_regression_impl.f90`
3. Call from main test sequence
4. Update documentation with new baseline

## Troubleshooting

### Common Issues

**"Performance test failed but my code should be faster"**
- Run benchmarks manually to verify: `./test_conv_cpu_vs_gpu_fixed`
- Check system load: `htop` or `nvidia-smi`
- Ensure CPU governor is set to performance mode
- Verify compiler optimizations are enabled

**"Tests pass locally but fail in CI"**
- CI environment may have different hardware
- Check GitHub Actions logs for actual performance numbers
- Consider separate CI thresholds if needed

**"64-bit FLOP counting test fails"**
- Ensure you're using Mini's `flopcount` module
- Check for manual FLOP calculations that might overflow

### Debug Mode

For detailed output during testing:
```bash
VERBOSE=1 ./run_performance_tests.sh
```

## Best Practices

1. **Run tests before committing** performance-critical changes
2. **Update baselines** when legitimate improvements are made
3. **Investigate immediately** when regressions are detected
4. **Document** any intentional performance trade-offs
5. **Monitor trends** - gradual degradation is still degradation

## Performance History

Track performance over time:
```bash
# Generate timestamped report
make -C tests report

# View historical reports
ls -la performance_report_*.txt
```

## Future Enhancements

Planned improvements:
- [ ] Graphical performance trend visualization
- [ ] Automatic bisection to find regression commits
- [ ] Hardware-specific baseline profiles
- [ ] Memory bandwidth regression tests
- [ ] Power efficiency metrics

---

Remember: **Every GFLOP counts!** Our users depend on consistent performance. This testing framework is our guardian against the forces of entropy that would slowly degrade our carefully crafted optimizations. 🛡️
