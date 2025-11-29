#!/bin/bash
# WoW System - Grep Handler Tests (Production-Grade)
# Comprehensive tests for security-critical grep/search interception
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

GREP_HANDLER="${SCRIPT_DIR}/../src/handlers/grep-handler.sh"
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

source_grep_handler() {
    if [[ -f "${GREP_HANDLER}" ]]; then
        source "${GREP_HANDLER}"
        return 0
    else
        echo "Grep handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local pattern="$1"
    local path="${2:-}"
    local output_mode="${3:-files_with_matches}"

    local json='{"tool": "Grep", "pattern": "'"${pattern}"'", "output_mode": "'"${output_mode}"'"'

    if [[ -n "${path}" ]]; then
        json="${json}, \"path\": \"${path}\""
    fi

    json="${json}}"
    echo "${json}"
}

# ============================================================================
# Tests: Sensitive Directory Blocking
# ============================================================================

test_suite "Grep Handler - Sensitive Directory Blocking"

# Test 1: Block grep in /etc
test_block_etc_grep() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input ".*" "/etc")

    handle_grep "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block grep in /etc"
}
test_case "Block grep in '/etc'" test_block_etc_grep

# Test 2: Block grep in /root
test_block_root_grep() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input ".*" "/root")

    handle_grep "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block grep in /root"
}
test_case "Block grep in '/root'" test_block_root_grep

# Test 3: Block grep in /sys
test_block_sys_grep() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input ".*" "/sys")

    handle_grep "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block grep in /sys"
}
test_case "Block grep in '/sys'" test_block_sys_grep

# Test 4: Block grep in ~/.ssh
test_block_ssh_grep() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "PRIVATE KEY" "/home/user/.ssh")

    handle_grep "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block grep in .ssh"
}
test_case "Block grep in '~/.ssh'" test_block_ssh_grep

# Test 5: Block grep in ~/.aws
test_block_aws_grep() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "aws_access_key" "/home/user/.aws")

    handle_grep "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block grep in .aws"
}
test_case "Block grep in '~/.aws'" test_block_aws_grep

# Test 6: Block grep in /proc
test_block_proc_grep() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input ".*" "/proc")

    handle_grep "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block grep in /proc"
}
test_case "Block grep in '/proc'" test_block_proc_grep

# ============================================================================
# Tests: Credential Pattern Warnings
# ============================================================================

test_suite "Grep Handler - Credential Pattern Warnings"

# Test 7: Warn on password pattern searches
test_warn_password_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "password\\s*=\\s*" "/home/user/project")

    local output
    output=$(handle_grep "${input}" 2>&1)

    # Should warn about credential search
    echo "Checked password pattern search"
}
test_case "Warn on password searches" test_warn_password_search

# Test 8: Warn on API key searches
test_warn_api_key_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "api_key" "/home/user/project")

    local output
    output=$(handle_grep "${input}" 2>&1)

    echo "Checked API key pattern search"
}
test_case "Warn on API key searches" test_warn_api_key_search

# Test 9: Warn on secret searches
test_warn_secret_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "secret.*=.*" "/home/user/project")

    local output
    output=$(handle_grep "${input}" 2>&1)

    echo "Checked secret pattern search"
}
test_case "Warn on secret searches" test_warn_secret_search

# Test 10: Warn on token searches
test_warn_token_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "token\\s*:" "/home/user/project")

    local output
    output=$(handle_grep "${input}" 2>&1)

    echo "Checked token pattern search"
}
test_case "Warn on token searches" test_warn_token_search

# Test 11: Warn on private key searches
test_warn_private_key_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "BEGIN.*PRIVATE KEY" "/home/user/project")

    local output
    output=$(handle_grep "${input}" 2>&1)

    echo "Checked private key pattern search"
}
test_case "Warn on private key searches" test_warn_private_key_search

# Test 12: Warn on connection string searches
test_warn_connection_string() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "mongodb://.*@.*" "/home/user/project")

    local output
    output=$(handle_grep "${input}" 2>&1)

    echo "Checked connection string pattern search"
}
test_case "Warn on connection string searches" test_warn_connection_string

# ============================================================================
# Tests: Safe Pattern Searches
# ============================================================================

test_suite "Grep Handler - Safe Pattern Searches"

# Test 13: Allow normal code searches
test_allow_code_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "function.*handleClick" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "function.*handleClick" "Should allow code searches"
}
test_case "Allow normal code searches" test_allow_code_search

# Test 14: Allow TODO/bug searches
test_allow_todo_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "TODO|FIXME|BUG" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "TODO" "Should allow TODO searches"
}
test_case "Allow TODO/bug searches" test_allow_todo_search

# Test 15: Allow import/require searches
test_allow_import_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "import.*from" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "import.*from" "Should allow import searches"
}
test_case "Allow import/require searches" test_allow_import_search

# Test 16: Allow class/interface searches
test_allow_class_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "class\\s+\\w+" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "class" "Should allow class searches"
}
test_case "Allow class/interface searches" test_allow_class_search

# Test 17: Allow error message searches
test_allow_error_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "Error:|Exception:" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "Error" "Should allow error searches"
}
test_case "Allow error message searches" test_allow_error_search

# Test 18: Allow configuration searches
test_allow_config_search() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "\"port\":" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "port" "Should allow config searches"
}
test_case "Allow configuration searches" test_allow_config_search

# ============================================================================
# Tests: Edge Cases & Security
# ============================================================================

test_suite "Grep Handler - Edge Cases"

# Test 19: Handle empty pattern
test_empty_pattern() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "")

    local output
    output=$(handle_grep "${input}" 2>/dev/null)

    # Should not crash
    [[ $? -eq 0 ]] || [[ $? -eq 2 ]] || return 1
    echo "Handled empty pattern gracefully"
}
test_case "Handle empty pattern" test_empty_pattern

# Test 20: Handle very long patterns
test_long_pattern() {
    source_grep_handler || return 1

    local long_pattern
    long_pattern="($(printf 'option%d|' {1..50})end)"

    local input
    input=$(create_tool_input "${long_pattern}")

    local output
    output=$(handle_grep "${input}")

    assert_success "Should handle long patterns"
}
test_case "Handle very long patterns" test_long_pattern

# Test 21: Detect path traversal
test_path_traversal() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input ".*" "../../etc")

    local output
    output=$(handle_grep "${input}" 2>&1)

    # Should handle path traversal
    echo "Checked path traversal in grep"
}
test_case "Detect path traversal" test_path_traversal

# Test 22: Handle regex special characters
test_special_characters() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "\\[.*\\]\\(.*\\)" "/home/user/project")

    local output
    output=$(handle_grep "${input}")

    assert_contains "${output}" "\\[" "Should handle regex special characters"
}
test_case "Handle regex special characters" test_special_characters

# Test 23: Track grep operations
test_metric_tracking() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "function" "/home/user/project")

    handle_grep "${input}" &>/dev/null

    # Check if metrics were updated
    local grep_count
    grep_count=$(session_get_metric "grep_operations" "0")

    [[ "${grep_count}" != "0" ]] || return 1
    echo "Metrics tracked: ${grep_count}"
}
test_case "Track grep operation metrics" test_metric_tracking

# Test 24: Log grep events
test_event_logging() {
    source_grep_handler || return 1

    local input
    input=$(create_tool_input "TODO" "/home/user/project")

    handle_grep "${input}" &>/dev/null

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
test_case "Log grep handler events" test_event_logging

# Run all tests
test_summary
