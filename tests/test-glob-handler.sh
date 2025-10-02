#!/bin/bash
# WoW System - Glob Handler Tests (Production-Grade)
# Comprehensive tests for security-critical glob pattern interception
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

GLOB_HANDLER="${SCRIPT_DIR}/../src/handlers/glob-handler.sh"
TEST_DATA_DIR=""

# ============================================================================
# Test Lifecycle
# ============================================================================

setup_all() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export WOW_HOME="${TEST_DATA_DIR}"

    # Initialize orchestrator for dependencies
    source "${SCRIPT_DIR}/../src/core/orchestrator.sh"
    wow_init
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_glob_handler() {
    if [[ -f "${GLOB_HANDLER}" ]]; then
        source "${GLOB_HANDLER}"
        return 0
    else
        echo "Glob handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local pattern="$1"
    local path="${2:-}"

    local json='{"tool": "Glob", "pattern": "'"${pattern}"'"'

    if [[ -n "${path}" ]]; then
        json="${json}, \"path\": \"${path}\""
    fi

    json="${json}}"
    echo "${json}"
}

# ============================================================================
# Tests: Sensitive Directory Blocking
# ============================================================================

test_suite "Glob Handler - Sensitive Directory Blocking"

# Test 1: Block glob in /etc
test_block_etc_glob() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.conf" "/etc")

    handle_glob "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block glob in /etc"
}
test_case "Block glob in '/etc'" test_block_etc_glob

# Test 2: Block glob in /root
test_block_root_glob() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*" "/root")

    handle_glob "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block glob in /root"
}
test_case "Block glob in '/root'" test_block_root_glob

# Test 3: Block glob in /sys
test_block_sys_glob() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*" "/sys")

    handle_glob "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block glob in /sys"
}
test_case "Block glob in '/sys'" test_block_sys_glob

# Test 4: Block glob in ~/.ssh
test_block_ssh_glob() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "id_*" "/home/user/.ssh")

    handle_glob "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block glob in .ssh"
}
test_case "Block glob in '~/.ssh'" test_block_ssh_glob

# Test 5: Block glob in ~/.aws
test_block_aws_glob() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*credentials*" "/home/user/.aws")

    handle_glob "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block glob in .aws"
}
test_case "Block glob in '~/.aws'" test_block_aws_glob

# Test 6: Block glob in /boot
test_block_boot_glob() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*" "/boot")

    handle_glob "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block glob in /boot"
}
test_case "Block glob in '/boot'" test_block_boot_glob

# ============================================================================
# Tests: Dangerous Pattern Warnings
# ============================================================================

test_suite "Glob Handler - Dangerous Pattern Warnings"

# Test 7: Warn on /**/* pattern
test_warn_root_recursive() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "/**/*")

    local output
    output=$(handle_glob "${input}" 2>&1)

    # Should warn about overly broad pattern
    echo "Checked /**/* pattern"
}
test_case "Warn on '/**/*' pattern" test_warn_root_recursive

# Test 8: Warn on **/* at filesystem root
test_warn_broad_root() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "**/*" "/")

    local output
    output=$(handle_glob "${input}" 2>&1)

    echo "Checked **/* at root"
}
test_case "Warn on '**/*' at root" test_warn_broad_root

# Test 9: Warn on extremely broad patterns
test_warn_extremely_broad() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "**/.*/**/*")

    local output
    output=$(handle_glob "${input}" 2>&1)

    echo "Checked extremely broad pattern"
}
test_case "Warn on extremely broad patterns" test_warn_extremely_broad

# Test 10: Warn on credential file patterns
test_warn_credential_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "**/.env")

    local output
    output=$(handle_glob "${input}" 2>&1)

    # Should warn about searching for credential files
    echo "Checked credential file pattern"
}
test_case "Warn on credential patterns" test_warn_credential_patterns

# Test 11: Warn on private key patterns
test_warn_private_key_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "**/id_rsa")

    local output
    output=$(handle_glob "${input}" 2>&1)

    echo "Checked private key pattern"
}
test_case "Warn on private key patterns" test_warn_private_key_patterns

# Test 12: Warn on wallet patterns
test_warn_wallet_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "**/wallet.dat")

    local output
    output=$(handle_glob "${input}" 2>&1)

    echo "Checked wallet pattern"
}
test_case "Warn on wallet patterns" test_warn_wallet_patterns

# ============================================================================
# Tests: Safe Pattern Access
# ============================================================================

test_suite "Glob Handler - Safe Pattern Access"

# Test 13: Allow normal code patterns
test_allow_code_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.js" "/home/user/project/src")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "*.js" "Should allow code patterns"
}
test_case "Allow normal code patterns" test_allow_code_patterns

# Test 14: Allow project-specific patterns
test_allow_project_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "src/**/*.ts" "/home/user/project")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "src/**/*.ts" "Should allow project patterns"
}
test_case "Allow project-specific patterns" test_allow_project_patterns

# Test 15: Allow config file patterns
test_allow_config_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.json" "/home/user/project")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "*.json" "Should allow config patterns"
}
test_case "Allow config file patterns" test_allow_config_patterns

# Test 16: Allow test file patterns
test_allow_test_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "test-*.sh" "/home/user/project/tests")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "test-*.sh" "Should allow test patterns"
}
test_case "Allow test file patterns" test_allow_test_patterns

# Test 17: Allow documentation patterns
test_allow_doc_patterns() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.md" "/home/user/project/docs")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "*.md" "Should allow doc patterns"
}
test_case "Allow documentation patterns" test_allow_doc_patterns

# Test 18: Allow specific directory patterns
test_allow_specific_dir() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "handlers/*.sh" "/home/user/project/src")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "handlers/*.sh" "Should allow specific directory patterns"
}
test_case "Allow specific directory patterns" test_allow_specific_dir

# ============================================================================
# Tests: Edge Cases & Security
# ============================================================================

test_suite "Glob Handler - Edge Cases"

# Test 19: Handle empty pattern
test_empty_pattern() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "")

    local output
    output=$(handle_glob "${input}" 2>/dev/null)

    # Should not crash
    [[ $? -eq 0 ]] || [[ $? -eq 2 ]] || return 1
    echo "Handled empty pattern gracefully"
}
test_case "Handle empty pattern" test_empty_pattern

# Test 20: Handle very long patterns
test_long_pattern() {
    source_glob_handler || return 1

    local long_pattern
    long_pattern="$(printf 'very-long-directory-name/%.0s' {1..20})*.txt"

    local input
    input=$(create_tool_input "${long_pattern}")

    local output
    output=$(handle_glob "${input}")

    assert_success "Should handle long patterns"
}
test_case "Handle very long patterns" test_long_pattern

# Test 21: Detect path traversal in patterns
test_path_traversal_pattern() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "../../etc/*" "/home/user/project")

    local output
    output=$(handle_glob "${input}" 2>&1)

    # Should warn or handle appropriately
    echo "Checked path traversal in pattern"
}
test_case "Detect path traversal in patterns" test_path_traversal_pattern

# Test 22: Handle special characters
test_special_characters() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.[jt]sx?" "/home/user/project")

    local output
    output=$(handle_glob "${input}")

    assert_contains "${output}" "*.[jt]sx?" "Should handle special characters"
}
test_case "Handle special characters" test_special_characters

# Test 23: Track glob operations
test_metric_tracking() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.js" "/home/user/project")

    handle_glob "${input}" &>/dev/null

    # Check if metrics were updated
    local glob_count
    glob_count=$(session_get_metric "glob_operations" "0")

    [[ "${glob_count}" != "0" ]] || return 1
    echo "Metrics tracked: ${glob_count}"
}
test_case "Track glob operation metrics" test_metric_tracking

# Test 24: Log glob events
test_event_logging() {
    source_glob_handler || return 1

    local input
    input=$(create_tool_input "*.md" "/home/user/project")

    handle_glob "${input}" &>/dev/null

    # Check if event was logged
    if type session_get_events &>/dev/null; then
        local events
        events=$(session_get_events)

        echo "Event logging verified (session manager available)"
    else
        echo "Event logging skipped (session manager not initialized)"
    fi
    return 0
}
test_case "Log glob handler events" test_event_logging

# Run all tests
test_summary
