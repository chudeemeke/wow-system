#!/bin/bash
# WoW System - Test Framework
# Simple bash testing framework with assertions and test runners
# Author: Chude <chude@emeke.org>

set -uo pipefail

# ============================================================================
# Test Framework State
# ============================================================================

TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0
CURRENT_TEST=""
TEST_START_TIME=0

# Color codes
if [[ -t 1 ]]; then
    readonly T_RED='\033[0;31m'
    readonly T_GREEN='\033[0;32m'
    readonly T_YELLOW='\033[1;33m'
    readonly T_BLUE='\033[0;34m'
    readonly T_RESET='\033[0m'
    readonly T_BOLD='\033[1m'
else
    readonly T_RED=''
    readonly T_GREEN=''
    readonly T_YELLOW=''
    readonly T_BLUE=''
    readonly T_RESET=''
    readonly T_BOLD=''
fi

# ============================================================================
# Test Organization
# ============================================================================

# Start a test suite
test_suite() {
    local suite_name="$1"
    echo -e "${T_BOLD}${T_BLUE}▶ Test Suite: ${suite_name}${T_RESET}"
    echo ""
}

# Define a test case
test_case() {
    local test_name="$1"
    shift
    local test_cmd="$@"

    CURRENT_TEST="${test_name}"
    TEST_START_TIME=$(date +%s%N)
    ((TEST_COUNT++))

    # Run the test
    local output
    local exit_code=0

    output=$("$@" 2>&1) && exit_code=0 || exit_code=$?

    if [[ ${exit_code} -eq 0 ]]; then
        ((TEST_PASSED++))
        local duration=$(($(date +%s%N) - TEST_START_TIME))
        duration=$((duration / 1000000))  # Convert to ms
        echo -e "  ${T_GREEN}✓${T_RESET} ${test_name} ${T_BLUE}(${duration}ms)${T_RESET}"
        return 0
    else
        ((TEST_FAILED++))
        echo -e "  ${T_RED}✗${T_RESET} ${test_name}"
        if [[ -n "${output}" ]]; then
            echo "${output}" | sed 's/^/    /'
        fi
        return 1
    fi
}

# Skip a test
test_skip() {
    local test_name="$1"
    local reason="${2:-No reason provided}"

    CURRENT_TEST="${test_name}"
    ((TEST_COUNT++))
    ((TEST_SKIPPED++))

    echo -e "  ${T_YELLOW}⊘${T_RESET} ${test_name} ${T_YELLOW}(skipped: ${reason})${T_RESET}"
}

# ============================================================================
# Assertions
# ============================================================================

# Assert that two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "${expected}" == "${actual}" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Expected: '${expected}'"
        echo "      Actual:   '${actual}'"
        return 1
    fi
}

# Assert that two values are not equal
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "${not_expected}" != "${actual}" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Should not equal: '${not_expected}'"
        echo "      But got:          '${actual}'"
        return 1
    fi
}

# Assert that a value is true
assert_true() {
    local condition="$1"
    local message="${2:-Expected true}"

    if [[ "${condition}" == "true" ]] || [[ "${condition}" == "0" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Expected: true"
        echo "      Got:      ${condition}"
        return 1
    fi
}

# Assert that a value is false
assert_false() {
    local condition="$1"
    local message="${2:-Expected false}"

    if [[ "${condition}" == "false" ]] || [[ "${condition}" != "0" && "${condition}" != "true" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Expected: false"
        echo "      Got:      ${condition}"
        return 1
    fi
}

# Assert that a string contains a substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String does not contain expected substring}"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Haystack: '${haystack}'"
        echo "      Needle:   '${needle}'"
        return 1
    fi
}

# Assert that a command succeeds
assert_success() {
    local message="${1:-Command should succeed}"

    if [[ $? -eq 0 ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Expected: exit code 0"
        echo "      Got:      exit code $?"
        return 1
    fi
}

# Assert that a command fails
assert_failure() {
    local message="${1:-Command should fail}"

    if [[ $? -ne 0 ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Expected: non-zero exit code"
        echo "      Got:      exit code 0"
        return 1
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"

    if [[ -f "${file_path}" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      File: ${file_path}"
        return 1
    fi
}

# Assert that a file does not exist
assert_file_not_exists() {
    local file_path="$1"
    local message="${2:-File should not exist}"

    if [[ ! -f "${file_path}" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      File: ${file_path}"
        return 1
    fi
}

# Assert that a directory exists
assert_dir_exists() {
    local dir_path="$1"
    local message="${2:-Directory should exist}"

    if [[ -d "${dir_path}" ]]; then
        return 0
    else
        echo -e "    ${T_RED}${message}${T_RESET}"
        echo "      Directory: ${dir_path}"
        return 1
    fi
}

# ============================================================================
# Test Helpers
# ============================================================================

# Pass test with optional message
pass() {
    local message="${1:-Test passed}"
    return 0
}

# Fail test with message
fail() {
    local message="${1:-Test failed}"
    echo -e "    ${T_RED}${message}${T_RESET}"
    return 1
}

# Skip test (note: this is different from test_skip, used within test functions)
skip() {
    local message="${1:-Test skipped}"
    echo -e "    ${T_YELLOW}${message}${T_RESET}"
    return 0
}

# ============================================================================
# Test Lifecycle
# ============================================================================

# Setup function (override in test files)
setup() {
    :  # No-op by default
}

# Teardown function (override in test files)
teardown() {
    :  # No-op by default
}

# Setup before all tests
setup_all() {
    :  # No-op by default
}

# Teardown after all tests
teardown_all() {
    :  # No-op by default
}

# ============================================================================
# Test Runner
# ============================================================================

# Print test summary
test_summary() {
    echo ""
    echo -e "${T_BOLD}═══════════════════════════════════════════${T_RESET}"
    echo -e "${T_BOLD}Test Summary${T_RESET}"
    echo -e "${T_BOLD}═══════════════════════════════════════════${T_RESET}"
    echo ""
    echo "  Total:   ${TEST_COUNT}"
    echo -e "  ${T_GREEN}Passed:${T_RESET}  ${TEST_PASSED}"
    echo -e "  ${T_RED}Failed:${T_RESET}  ${TEST_FAILED}"
    echo -e "  ${T_YELLOW}Skipped:${T_RESET} ${TEST_SKIPPED}"
    echo ""

    if [[ ${TEST_FAILED} -eq 0 ]]; then
        echo -e "${T_GREEN}${T_BOLD}✓ All tests passed!${T_RESET}"
        return 0
    else
        echo -e "${T_RED}${T_BOLD}✗ Some tests failed${T_RESET}"
        return 1
    fi
}

# Run all tests and exit with status
test_run() {
    # Call setup_all if defined
    if declare -f setup_all >/dev/null; then
        setup_all
    fi

    # Run tests here (tests will call test_case)

    # Call teardown_all if defined
    if declare -f teardown_all >/dev/null; then
        teardown_all
    fi

    # Print summary and exit
    test_summary
    exit $?
}

# ============================================================================
# Utilities
# ============================================================================

# Create a temporary directory for test data
test_temp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d -t wow-test-XXXXXXXXXX)
    echo "${temp_dir}"
}

# Clean up temporary directory
test_cleanup_temp() {
    local temp_dir="$1"
    rm -rf "${temp_dir}"
}

# Mock a command
mock_command() {
    local cmd_name="$1"
    local mock_script="$2"

    # Create mock function
    eval "${cmd_name}() { ${mock_script}; }"
    export -f "${cmd_name}"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_suite "Test Framework Self-Test"

    # Define test helper functions first
    test_temp_dir_creation() {
        local temp=$(test_temp_dir)
        assert_dir_exists "${temp}"
        test_cleanup_temp "${temp}"
        return 0
    }

    # Test assertions
    test_case "assert_equals works" assert_equals 'hello' 'hello'
    test_case "assert_contains works" assert_contains 'hello world' 'world'
    test_case "assert_file_exists works" assert_file_exists "${BASH_SOURCE[0]}"

    # Test temp directory
    test_case "test_temp_dir creates directory" test_temp_dir_creation

    test_summary
fi
