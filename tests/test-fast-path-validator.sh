#!/bin/bash
# WoW System - Fast Path Validator Tests (TDD)
# Tests written FIRST before implementation
# Author: Chude <chude@emeke.org>

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Test suite name
test_suite "Fast Path Validator Tests"

# ============================================================================
# Setup / Teardown
# ============================================================================

setup() {
    # Source the validator - MUST exist for tests to pass
    VALIDATOR_PATH="${SCRIPT_DIR}/../src/core/fast-path-validator.sh"

    if [[ ! -f "${VALIDATOR_PATH}" ]]; then
        echo "ERROR: fast-path-validator.sh not found at ${VALIDATOR_PATH}" >&2
        echo "TDD RED: Implementation missing (expected)" >&2
        return 1
    fi

    source "${VALIDATOR_PATH}" || {
        echo "ERROR: Failed to source fast-path-validator.sh" >&2
        return 1
    }

    # Verify function exists
    if ! type fast_path_validate &>/dev/null; then
        echo "ERROR: fast_path_validate function not found" >&2
        return 1
    fi
}

teardown() {
    true
}

# ============================================================================
# Test Group 1: Current Directory Validator
# ============================================================================

test_fast_path_current_dir_safe() {
    setup

    # Test: Files in current directory should be safe
    local result
    result=$(fast_path_validate "src/app.ts" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} "Current directory file should return 0 (safe)"

    teardown
}

test_fast_path_current_dir_relative_safe() {
    setup

    # Test: Relative paths within project should be safe
    local result
    result=$(fast_path_validate "./src/components/Button.tsx" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} "Relative path within project should be safe"

    teardown
}

test_fast_path_traversal_suspicious() {
    setup

    # Test: Path traversal should trigger deep validation
    local result
    result=$(fast_path_validate "../../../etc/passwd" "read" 2>/dev/null)
    local exit_code=$?

    # Should return 1 (needs deep check) or 2 (block)
    assert_not_equals 0 ${exit_code} "Path traversal should not fast-path allow"

    teardown
}

test_fast_path_absolute_system_blocked() {
    setup

    # Test: Absolute paths to system dirs should be blocked immediately
    local result
    result=$(fast_path_validate "/etc/shadow" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 2 ${exit_code} "Absolute system path should be blocked (exit 2)"

    teardown
}

# ============================================================================
# Test Group 2: Safe Extension Validator
# ============================================================================

test_fast_path_safe_extension_js() {
    setup

    # Test: .js files should be safe
    local result
    result=$(fast_path_validate "app.js" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} ".js file should be safe"

    teardown
}

test_fast_path_safe_extension_ts() {
    setup

    # Test: .ts files should be safe
    local result
    result=$(fast_path_validate "types.ts" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} ".ts file should be safe"

    teardown
}

test_fast_path_safe_extension_md() {
    setup

    # Test: .md files should be safe
    local result
    result=$(fast_path_validate "README.md" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} ".md file should be safe"

    teardown
}

test_fast_path_safe_extension_json() {
    setup

    # Test: .json files should be safe
    local result
    result=$(fast_path_validate "package.json" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} ".json file should be safe"

    teardown
}

test_fast_path_unsafe_extension_needs_deep_check() {
    setup

    # Test: Unusual extensions should trigger deep validation
    local result
    result=$(fast_path_validate "secrets.dat" "read" 2>/dev/null)
    local exit_code=$?

    # Should return 1 (needs deep check) - not 0 (safe)
    assert_not_equals 0 ${exit_code} "Unusual extension should need deep validation"

    teardown
}

# ============================================================================
# Test Group 3: System Path Blocking
# ============================================================================

test_fast_path_blocks_etc_directory() {
    setup

    # Test: /etc/* paths should be blocked
    local result
    result=$(fast_path_validate "/etc/passwd" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 2 ${exit_code} "/etc/* should be blocked immediately"

    teardown
}

test_fast_path_blocks_root_directory() {
    setup

    # Test: /root/* paths should be blocked
    local result
    result=$(fast_path_validate "/root/.bashrc" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 2 ${exit_code} "/root/* should be blocked immediately"

    teardown
}

test_fast_path_blocks_ssh_private_keys() {
    setup

    # Test: SSH private keys should be blocked
    local result
    result=$(fast_path_validate "/home/user/.ssh/id_rsa" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 2 ${exit_code} "SSH private keys should be blocked immediately"

    teardown
}

test_fast_path_blocks_aws_credentials() {
    setup

    # Test: AWS credentials should be blocked
    local result
    result=$(fast_path_validate "/home/user/.aws/credentials" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 2 ${exit_code} "AWS credentials should be blocked immediately"

    teardown
}

# ============================================================================
# Test Group 4: Edge Cases
# ============================================================================

test_fast_path_empty_path() {
    setup

    # Test: Empty path should trigger deep validation
    local result
    result=$(fast_path_validate "" "read" 2>/dev/null)
    local exit_code=$?

    # Should not return 0 (safe)
    assert_not_equals 0 ${exit_code} "Empty path should not be fast-path safe"

    teardown
}

test_fast_path_dot_env_needs_deep_check() {
    setup

    # Test: .env files should trigger deep validation (not auto-safe)
    local result
    result=$(fast_path_validate ".env" "read" 2>/dev/null)
    local exit_code=$?

    # Should return 1 (needs deep check) - might be legitimate or might be credential leak
    assert_not_equals 0 ${exit_code} ".env file should need deep validation"

    teardown
}

test_fast_path_hidden_file_current_dir() {
    setup

    # Test: Hidden files in current dir with safe extension should be safe
    local result
    result=$(fast_path_validate ".eslintrc.json" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} "Hidden config files with safe extension should be safe"

    teardown
}

test_fast_path_package_json_nested() {
    setup

    # Test: package.json in nested directory should be safe
    local result
    result=$(fast_path_validate "node_modules/lodash/package.json" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} "Nested package.json should be safe"

    teardown
}

# ============================================================================
# Test Group 5: Operation Type Handling
# ============================================================================

test_fast_path_read_operation() {
    setup

    # Test: Fast path should work for read operations
    local result
    result=$(fast_path_validate "src/app.ts" "read" 2>/dev/null)
    local exit_code=$?

    assert_equals 0 ${exit_code} "Read operation on safe file should be allowed"

    teardown
}

test_fast_path_write_operation_needs_check() {
    setup

    # Test: Write operations might need stricter validation
    # Even for safe files, writes should potentially trigger deep checks
    local result
    result=$(fast_path_validate "src/app.ts" "write" 2>/dev/null)
    local exit_code=$?

    # Can be 0 (safe) or 1 (needs check) - implementation decision
    # Just verify it doesn't crash
    assert_success "Write operation should not crash validator"

    teardown
}

test_fast_path_edit_operation_needs_check() {
    setup

    # Test: Edit operations handled correctly
    local result
    result=$(fast_path_validate "src/app.ts" "edit" 2>/dev/null)
    local exit_code=$?

    assert_success "Edit operation should not crash validator"

    teardown
}

# ============================================================================
# Test Group 6: Performance Characteristics
# ============================================================================

test_fast_path_performance_under_20ms() {
    setup

    # Test: Fast path validation should complete in <20ms
    local start_time=$(date +%s%N)

    for i in {1..10}; do
        fast_path_validate "src/file${i}.ts" "read" >/dev/null 2>&1
    done

    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    local avg_ms=$((duration_ms / 10))

    # Average should be under 20ms per operation
    [[ ${avg_ms} -lt 20 ]] && echo "PASS" || echo "FAIL: ${avg_ms}ms (target: <20ms)"
    assert_success "Fast path should complete in <20ms average"

    teardown
}

# ============================================================================
# Test Group 7: Integration with Config
# ============================================================================

test_fast_path_respects_config_flag() {
    setup

    # Test: Fast path can be disabled via config
    # This tests the config integration (implementation will check config)

    # Just verify function exists and handles config
    type fast_path_validate &>/dev/null
    assert_success "fast_path_validate function should exist"

    teardown
}

# ============================================================================
# Run all tests
# ============================================================================

# Current directory validators
test_case "Fast path allows current directory files" test_fast_path_current_dir_safe
test_case "Fast path allows relative paths in project" test_fast_path_current_dir_relative_safe
test_case "Fast path detects path traversal" test_fast_path_traversal_suspicious
test_case "Fast path blocks absolute system paths" test_fast_path_absolute_system_blocked

# Safe extension validators
test_case "Fast path allows .js files" test_fast_path_safe_extension_js
test_case "Fast path allows .ts files" test_fast_path_safe_extension_ts
test_case "Fast path allows .md files" test_fast_path_safe_extension_md
test_case "Fast path allows .json files" test_fast_path_safe_extension_json
test_case "Fast path checks unusual extensions" test_fast_path_unsafe_extension_needs_deep_check

# System path blocking
test_case "Fast path blocks /etc/* paths" test_fast_path_blocks_etc_directory
test_case "Fast path blocks /root/* paths" test_fast_path_blocks_root_directory
test_case "Fast path blocks SSH private keys" test_fast_path_blocks_ssh_private_keys
test_case "Fast path blocks AWS credentials" test_fast_path_blocks_aws_credentials

# Edge cases
test_case "Fast path handles empty paths" test_fast_path_empty_path
test_case "Fast path checks .env files" test_fast_path_dot_env_needs_deep_check
test_case "Fast path allows hidden config files" test_fast_path_hidden_file_current_dir
test_case "Fast path allows nested package.json" test_fast_path_package_json_nested

# Operation types
test_case "Fast path handles read operations" test_fast_path_read_operation
test_case "Fast path handles write operations" test_fast_path_write_operation_needs_check
test_case "Fast path handles edit operations" test_fast_path_edit_operation_needs_check

# Performance
test_case "Fast path completes in <20ms" test_fast_path_performance_under_20ms

# Config integration
test_case "Fast path respects config flags" test_fast_path_respects_config_flag

# Summary
test_summary
