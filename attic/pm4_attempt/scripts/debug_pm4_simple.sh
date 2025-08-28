#!/bin/bash
# Simplified PM4 debug script focusing on wave execution

echo "=== Disabling GFXOFF (if supported) ==="
echo "manual" | sudo tee /sys/class/drm/card1/device/power_dpm_force_performance_level 2>/dev/null

echo -e "\n=== PRE-TEST: Checking for any waves ==="
umr -i 1 -O halt_waves --waves

echo -e "\n=== Running PM4 test in background ==="
./test_pm4_mini_final &
TEST_PID=$!

echo -e "\n=== Monitoring waves while test runs ==="
for i in {1..5}; do
    echo "Check $i:"
    umr -i 1 --waves 2>/dev/null | grep -E "(SE|SH|CU|SIMD|WAVE)" || echo "  No waves detected"
    sleep 0.1
done

echo -e "\n=== Waiting for test to complete ==="
wait $TEST_PID

echo -e "\n=== POST-TEST: Final wave check ==="
umr -i 1 -O halt_waves --waves

echo -e "\n=== Checking compute ring activity ==="
# Try different ring names for compute
for ring in compute_0.0.0 comp_1.0.0 kiq_1.0.0; do
    echo "Trying ring: $ring"
    umr -i 1 --ring-read $ring 2>/dev/null | head -5 || echo "  Ring $ring not found"
done

echo -e "\n=== Checking memory writes ==="
# If our shader was supposed to write to memory, check if it did
echo "Look for any non-zero values in output buffer (manual check needed)"