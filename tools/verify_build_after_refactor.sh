#!/bin/bash
# Build verification script for refactoring
# =========================================
#
# This script verifies that key components build after refactoring

set -e

resolve_temp_dir() {
    local tmp_dir=""
    tmp_dir="${TMPDIR:-$TEMP}"
    if [ -z "$tmp_dir" ]; then
        tmp_dir="$TMP"
    fi
    if [ -z "$tmp_dir" ]; then
        tmp_dir="/tmp"
    fi
    if [ ! -d "$tmp_dir" ] || [ ! -w "$tmp_dir" ]; then
        tmp_dir="/tmp"
    fi
    echo "$tmp_dir"
}

TEMP_ROOT="$(mktemp -d "$(resolve_temp_dir)/sporkle-refverify-XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

echo "🔧 Build Verification for Sporkle Refactoring"
echo "============================================="
echo ""

# Function to test compilation
test_compile() {
    local file="$1"
    local desc="$2"
    local out_file="${TEMP_ROOT}/$(basename "${file}").o"
    
    echo -n "Testing $desc... "
    if gfortran -c "$file" -I src/common -J . -o "$out_file" 2>/dev/null; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Test critical modules
echo "📦 Testing core modules:"
test_compile "src/common/kinds.f90" "kinds module"
test_compile "src/common/time_utils.f90" "time_utils module"
test_compile "src/common/flopcount.f90" "flopcount module"

echo ""
echo "📦 Testing refactored modules:"
test_compile "src/sporkle_types.f90" "sporkle_types"
test_compile "src/sporkle_config.f90" "sporkle_config"

# Test a simple program
echo ""
echo "📦 Testing simple compilation:"
cat > "${TEMP_ROOT}/test_sporkle.f90" << 'EOF'
program test_sporkle
  use kinds
  implicit none
  
  real(dp) :: test_value
  integer(i64) :: test_count
  
  test_value = 3.14159_dp
  test_count = 1000000_i64
  
  print *, "Sporkle test: ", test_value * real(test_count, dp)
end program
EOF

if gfortran "${TEMP_ROOT}/test_sporkle.f90" src/common/kinds.f90 -o "${TEMP_ROOT}/test_sporkle" 2>/dev/null; then
    echo "✅ Simple program compiles"
    "${TEMP_ROOT}/test_sporkle" > /dev/null && echo "✅ Simple program runs"
else
    echo "❌ Simple program failed to compile"
fi

# Summary
echo ""
echo "🏁 Build verification complete"
echo ""
echo "Note: Full build may still have issues due to complex dependencies."
echo "This script only verifies basic refactoring was successful."

# Cleanup
rm -f *.mod
