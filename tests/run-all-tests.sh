#!/bin/bash
# WoW System - Comprehensive Test Runner
# Runs all test suites and reports results
# Author: Chude <chude@emeke.org>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  WoW System v5.2.0 - Comprehensive Test Suite           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

total_tests=0
passed_tests=0
failed_tests=0
skipped_tests=0

# Array to track failed test names
declare -a failed_test_names=()

# Run test file
run_test() {
    local test_file="$1"
    local test_name
    test_name=$(basename "${test_file}")

    echo -n "▶ ${test_name}... "

    # Run test with timeout
    if timeout 30 bash "${test_file}" >/dev/null 2>&1; then
        echo "✓ PASS"
        passed_tests=$((passed_tests + 1))
        return 0
    else
        local exit_code=$?
        if [[ ${exit_code} -eq 124 ]]; then
            echo "⏱  TIMEOUT"
            skipped_tests=$((skipped_tests + 1))
        else
            echo "✗ FAIL"
            failed_tests=$((failed_tests + 1))
            failed_test_names+=("${test_name}")
        fi
        return 1
    fi
}

# Find and run all tests
echo "Running test suites..."
echo ""

for test_file in "${SCRIPT_DIR}"/test-*.sh; do
    if [[ -f "${test_file}" ]] && [[ -x "${test_file}" || -r "${test_file}" ]]; then
        run_test "${test_file}"
        total_tests=$((total_tests + 1))
    fi
done

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Test Summary                                            ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Total:   %-48s║\n" "${total_tests} tests"
printf "║  Passed:  %-48s║\n" "${passed_tests} ✓"
printf "║  Failed:  %-48s║\n" "${failed_tests} ✗"
printf "║  Skipped: %-48s║\n" "${skipped_tests} ⏱"
echo "╠══════════════════════════════════════════════════════════╣"

if [[ ${failed_tests} -eq 0 ]] && [[ ${skipped_tests} -eq 0 ]]; then
    echo "║  Status: ✓ ALL TESTS PASSED                             ║"
elif [[ ${failed_tests} -eq 0 ]]; then
    echo "║  Status: ⚠  ALL TESTS PASSED (some timeouts)            ║"
else
    echo "║  Status: ✗ SOME TESTS FAILED                            ║"
fi

echo "╚══════════════════════════════════════════════════════════╝"

# List failed tests if any
if [[ ${#failed_test_names[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for test_name in "${failed_test_names[@]}"; do
        echo "  - ${test_name}"
    done
fi

echo ""

# Exit with appropriate code
if [[ ${failed_tests} -gt 0 ]]; then
    exit 1
else
    exit 0
fi
