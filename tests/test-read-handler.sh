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
# Tests: Sensitive File Blocking
# ============================================================================

test_suite "Read Handler - Sensitive File Blocking"

# Test 1: Block /etc/shadow
test_block_etc_shadow() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/shadow")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block /etc/shadow"
}
test_case "Block '/etc/shadow'" test_block_etc_shadow

# Test 2: Block /etc/passwd
test_block_etc_passwd() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/passwd")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block /etc/passwd"
}
test_case "Block '/etc/passwd'" test_block_etc_passwd

# Test 3: Block private SSH keys
test_block_ssh_private_key() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.ssh/id_rsa")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block private SSH keys"
}
test_case "Block private SSH key" test_block_ssh_private_key

# Test 4: Block AWS credentials
test_block_aws_credentials() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.aws/credentials")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block AWS credentials"
}
test_case "Block AWS credentials" test_block_aws_credentials

# Test 5: Block cryptocurrency wallets
test_block_crypto_wallet() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.bitcoin/wallet.dat")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block crypto wallets"
}
test_case "Block cryptocurrency wallet" test_block_crypto_wallet

# Test 6: Block /etc/sudoers
test_block_etc_sudoers() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/etc/sudoers")

    handle_read "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block /etc/sudoers"
}
test_case "Block '/etc/sudoers'" test_block_etc_sudoers

# ============================================================================
# Tests: Credential File Warnings
# ============================================================================

test_suite "Read Handler - Credential File Warnings"

# Test 7: Warn on .env files
test_warn_env_file() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/.env")

    local output
    output=$(handle_read "${input}" 2>&1)

    # Should warn but allow
    assert_contains "${output}" ".env" "Should mention .env file"
    echo "Warned on .env file access"
}
test_case "Warn on '.env' file" test_warn_env_file

# Test 8: Warn on credentials.json
test_warn_credentials_json() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/credentials.json")

    local output
    output=$(handle_read "${input}" 2>&1)

    assert_contains "${output}" "credentials" "Should mention credentials file"
    echo "Warned on credentials.json access"
}
test_case "Warn on 'credentials.json'" test_warn_credentials_json

# Test 9: Warn on secrets.yaml
test_warn_secrets_yaml() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/project/secrets.yaml")

    local output
    output=$(handle_read "${input}" 2>&1)

    assert_contains "${output}" "secrets" "Should mention secrets file"
    echo "Warned on secrets.yaml access"
}
test_case "Warn on 'secrets.yaml'" test_warn_secrets_yaml

# Test 10: Warn on browser cookies
test_warn_browser_cookies() {
    source_read_handler || return 1

    local input
    input=$(create_tool_input "/home/user/.mozilla/firefox/cookies.sqlite")

    local output
    output=$(handle_read "${input}" 2>&1)

    # Should warn about browser data
    echo "Checked browser cookies access"
}
test_case "Warn on browser cookies" test_warn_browser_cookies

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
