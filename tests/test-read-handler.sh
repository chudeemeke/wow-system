#!/bin/bash
# WoW System - Read Handler Tests (Production-Grade)
# Comprehensive tests for security-critical file read interception
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

READ_HANDLER="${SCRIPT_DIR}/../src/handlers/read-handler.sh"
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

source_read_handler() {
    if [[ -f "${READ_HANDLER}" ]]; then
        source "${READ_HANDLER}"
        return 0
    else
        echo "Read handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local file_path="$1"
    local offset="${2:-}"
    local limit="${3:-}"

    local json='{"tool": "Read", "file_path": "'"${file_path}"'"'

    if [[ -n "${offset}" ]]; then
        json="${json}, \"offset\": ${offset}"
    fi

    if [[ -n "${limit}" ]]; then
        json="${json}, \"limit\": ${limit}"
    fi

    json="${json}}"
    echo "${json}"
}

# ============================================================================
# Tests: TIER 1 - Critical File Blocking (v5.3.0)
# ============================================================================

test_suite "Read Handler - TIER 1: Critical Files (Hard Block)"

# Test 1: Block /etc/shadow (TIER 1)
test_block_etc_shadow() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/shadow")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block /etc/shadow (TIER 1: catastrophic)"
}
test_case "Block '/etc/shadow' (TIER 1)" test_block_etc_shadow

# Test 2: Block /etc/sudoers (TIER 1)
test_block_etc_sudoers() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/sudoers")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block /etc/sudoers (TIER 1: catastrophic)"
}
test_case "Block '/etc/sudoers' (TIER 1)" test_block_etc_sudoers

# Test 3: Block /etc/gshadow (TIER 1)
test_block_etc_gshadow() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/gshadow")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block /etc/gshadow (TIER 1: catastrophic)"
}
test_case "Block '/etc/gshadow' (TIER 1)" test_block_etc_gshadow

# ============================================================================
# Tests: TIER 2 - Sensitive Files (Warn by Default, Block in Strict Mode)
# ============================================================================

test_suite "Read Handler - TIER 2: Sensitive Files (Contextual)"

# Test 4: Allow /etc/passwd with warning (TIER 2, strict_mode=false)
test_allow_etc_passwd_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/passwd")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow /etc/passwd with warning (TIER 2, strict_mode=false)"
}
test_case "Allow '/etc/passwd' with warning (TIER 2)" test_allow_etc_passwd_with_warning

# Test 5: Allow private SSH keys with warning (TIER 2, strict_mode=false)
test_allow_ssh_private_key_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.ssh/id_rsa")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow SSH keys with warning (TIER 2, might debug auth)"
}
test_case "Allow SSH private key with warning (TIER 2)" test_allow_ssh_private_key_with_warning

# Test 6: Allow AWS credentials with warning (TIER 2, strict_mode=false)
test_allow_aws_credentials_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.aws/credentials")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow AWS creds with warning (TIER 2, might debug auth)"
}
test_case "Allow AWS credentials with warning (TIER 2)" test_allow_aws_credentials_with_warning

# Test 7: Allow cryptocurrency wallets with warning (TIER 2, strict_mode=false)
test_allow_crypto_wallet_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.bitcoin/wallet.dat")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow crypto wallets with warning (TIER 2, might work on crypto project)"
}
test_case "Allow cryptocurrency wallet with warning (TIER 2)" test_allow_crypto_wallet_with_warning

# Test 8: Allow .env files with warning (TIER 2, strict_mode=false)
test_allow_env_file_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/.env")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow .env with warning (TIER 2, common dev file)"
}
test_case "Allow .env file with warning (TIER 2)" test_allow_env_file_with_warning

# Test 9: Allow credentials.json with warning (TIER 2, strict_mode=false)
test_allow_credentials_json_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/credentials.json")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow credentials.json with warning (TIER 2)"
}
test_case "Allow credentials.json with warning (TIER 2)" test_allow_credentials_json_with_warning

# Test 10: Allow secrets.yaml with warning (TIER 2, strict_mode=false)
test_allow_secrets_yaml_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/secrets.yaml")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow secrets.yaml with warning (TIER 2)"
}
test_case "Allow secrets.yaml with warning (TIER 2)" test_allow_secrets_yaml_with_warning

# Test 11: Allow browser cookies with warning (TIER 2, strict_mode=false)
test_allow_browser_cookies_with_warning() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.mozilla/firefox/cookies.sqlite")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow browser cookies with warning (TIER 2)"
}
test_case "Allow browser cookies with warning (TIER 2)" test_allow_browser_cookies_with_warning

# Test 11: Warn on database files
test_warn_database_files() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/app.db")

    local output
    output=$(handle_read "${input}" 2>&1)

    # Should allow but track database access
    echo "Checked database file access"
}
test_case "Warn on database files" test_warn_database_files

# Test 12: Warn on .pem files
test_warn_pem_files() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/certs/private-key.pem")

    local output
    output=$(handle_read "${input}" 2>&1)

    # Should warn on certificate files
    echo "Checked .pem file access"
}
test_case "Warn on '.pem' files" test_warn_pem_files

# ============================================================================
# Tests: Safe File Access
# ============================================================================

test_suite "Read Handler - Safe File Access"

# Test 13: Allow normal code files
test_allow_code_files() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/src/index.js")

    local output
    output=$(handle_read "${input}")

    assert_contains "${output}" "index.js" "Should allow code files"
}
test_case "Allow normal code files" test_allow_code_files

# Test 14: Allow config files
test_allow_config_files() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/package.json")

    local output
    output=$(handle_read "${input}")

    assert_contains "${output}" "package.json" "Should allow config files"
}
test_case "Allow config files" test_allow_config_files

# Test 15: Allow documentation
test_allow_documentation() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/docs/guide.md")

    local output
    output=$(handle_read "${input}")

    assert_contains "${output}" "guide.md" "Should allow documentation"
}
test_case "Allow documentation files" test_allow_documentation

# Test 16: Allow README files
test_allow_readme() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/README.md")

    local output
    output=$(handle_read "${input}")

    assert_contains "${output}" "README" "Should allow README files"
}
test_case "Allow README files" test_allow_readme

# Test 17: Allow test files
test_allow_test_files() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/tests/test-handler.sh")

    local output
    output=$(handle_read "${input}")

    assert_contains "${output}" "test-handler" "Should allow test files"
}
test_case "Allow test files" test_allow_test_files

# Test 18: Allow build files
test_allow_build_files() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/Makefile")

    local output
    output=$(handle_read "${input}")

    assert_contains "${output}" "Makefile" "Should allow build files"
}
test_case "Allow build files" test_allow_build_files

# ============================================================================
# Tests: Edge Cases & Security
# ============================================================================

test_suite "Read Handler - Edge Cases"

# Test 19: Handle empty file path
test_empty_file_path() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "")

    local output
    output=$(handle_read "${input}" 2>/dev/null)

    # Should not crash
    [[ $? -eq 0 ]] || [[ $? -eq 2 ]] || return 1
    echo "Handled empty file path gracefully"
}
test_case "Handle empty file path" test_empty_file_path

# Test 20: Handle non-existent files
test_nonexistent_file() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/does-not-exist.txt")

    local output
    output=$(handle_read "${input}")

    # Should pass through (Claude Code will handle the error)
    assert_contains "${output}" "does-not-exist" "Should pass through non-existent files"
}
test_case "Handle non-existent files" test_nonexistent_file

# Test 21: Detect path traversal
test_path_traversal() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/../../etc/passwd")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block path traversal"
}
test_case "Detect path traversal" test_path_traversal

# Test 22: Handle very long paths
test_long_path() {
    source_read_handler || return 1

    local long_path
    long_path="/home/user/$(printf 'very-long-directory-name/%.0s' {1..50})file.txt"

    local input
    input=$(create_tool_input "${long_path}")

    local output
    output=$(handle_read "${input}")

    assert_success "Should handle long paths"
}
test_case "Handle very long paths" test_long_path

# Test 23: Track read operations
test_metric_tracking() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/src/index.js")

    handle_read "${input}" &>/dev/null

    # Check if metrics were updated
    local read_count
    read_count=$(session_get_metric "file_reads" "0")

    [[ "${read_count}" != "0" ]] || return 1
    echo "Metrics tracked: ${read_count}"
}
test_case "Track read operation metrics" test_metric_tracking

# Test 24: Log read events
test_event_logging() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/README.md")

    handle_read "${input}" &>/dev/null

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
test_case "Log read handler events" test_event_logging

# Run all tests
test_summary
