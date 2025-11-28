#!/bin/sh
# Test runner for raspi-config
# Executes all test suites and reports results

set -e

TESTS_DIR="$(dirname "$0")"
FAILED=0
PASSED=0

echo "Running raspi-config test suites..."
echo "===================================="
echo

for test_file in "$TESTS_DIR"/test_*.sh; do
    if [ -f "$test_file" ]; then
        test_name=$(basename "$test_file")
        echo "Running $test_name..."

        if "$test_file"; then
            PASSED=$((PASSED + 1))
            echo "✓ $test_name passed"
        else
            FAILED=$((FAILED + 1))
            echo "✗ $test_name FAILED"
        fi
        echo
    fi
done

echo "===================================="
echo "Test Results:"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "===================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All tests passed!"
exit 0
