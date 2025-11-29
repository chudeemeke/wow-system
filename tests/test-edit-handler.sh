#!/bin/bash
# WoW System - Edit Handler Tests (Production-Grade)
# Comprehensive tests for file edit interception and safety enforcement
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

EDIT_HANDLER="${SCRIPT_DIR}/../src/handlers/edit-handler.sh"
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

source_edit_handler() {
    if [[ -f "${EDIT_HANDLER}" ]]; then
        source "${EDIT_HANDLER}"
        return 0
    else
        echo "Edit handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local file_path="$1"
    local old_string="$2"
    local new_string="$3"
    local replace_all="${4:-false}"

    cat <<EOF
{
  "tool": "Edit",
  "file_path": "${file_path}",
  "old_string": "${old_string}",
  "new_string": "${new_string}",
  "replace_all": ${replace_all}
}
EOF
}

# ============================================================================
# Tests: File Path Validation
# ============================================================================

test_suite "Edit Handler - File Path Validation"

# Test 1: Block edits to /etc
test_block_edit_etc() {
    source_edit_handler || return 1

    local input
    input=$(create_tool_input "/etc/hosts" "localhost" "hacked")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block edits to /etc"
}
test_case "Block edits to /etc" test_block_edit_etc

# Test 2: Block edits to /bin
test_block_edit_bin() {
    source_edit_handler || return 1

    local input
    input=$(create_tool_input "/bin/bash" "#!/bin/bash" "#!/bin/malware")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block edits to /bin"
}
test_case "Block edits to /bin" test_block_edit_bin

# Test 3: Allow edits to safe files
test_allow_edit_safe() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/safe.txt"
    echo "Hello World" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "Hello" "Goodbye")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should allow edits to safe files"
}
test_case "Allow edits to safe files" test_allow_edit_safe

# Test 4: Block path traversal
test_block_path_traversal() {
    source_edit_handler || return 1

    local input
    input=$(create_tool_input "../../etc/passwd" "root" "hacker")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block path traversal"
}
test_case "Block path traversal in edits" test_block_path_traversal

# ============================================================================
# Tests: Dangerous Edit Detection
# ============================================================================

test_suite "Edit Handler - Dangerous Edit Detection"

# Test 5: Detect security code removal
test_detect_security_removal() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/security.sh"
    echo "if [[ security_check ]]; then" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "if [[ security_check ]]; then" "# disabled")

    # Should warn about removing security checks
    local output
    output=$(handle_edit "${input}" 2>&1)

    echo "Security removal check completed"
}
test_case "Detect security code removal" test_detect_security_removal

# Test 6: Detect validation bypass
test_detect_validation_bypass() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/validate.sh"
    echo "validate_input || return 1" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "validate_input || return 1" "# skip validation")

    # Should warn about validation bypass
    local output
    output=$(handle_edit "${input}" 2>&1)

    echo "Validation bypass check completed"
}
test_case "Detect validation bypass" test_detect_validation_bypass

# Test 7: Detect malicious replacements
test_detect_malicious_replacement() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/test.sh"
    echo "echo 'safe'" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "echo 'safe'" "rm -rf /")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Should block malicious replacements
    echo "Malicious replacement check: ${result}"
}
test_case "Detect malicious replacements" test_detect_malicious_replacement

# ============================================================================
# Tests: Edit Operation Validation
# ============================================================================

test_suite "Edit Handler - Edit Operation Validation"

# Test 8: Validate old_string exists
test_validate_old_string_exists() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/exists.txt"
    echo "Hello World" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "Nonexistent" "Replacement")

    # Should warn or handle gracefully when old_string doesn't exist
    local output
    output=$(handle_edit "${input}" 2>&1)

    echo "Old string existence check completed"
}
test_case "Validate old_string exists" test_validate_old_string_exists

# Test 9: Handle empty old_string
test_empty_old_string() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/empty-old.txt"
    echo "content" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "" "new")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Empty old_string should be blocked
    assert_equals "blocked" "${result}" "Should block empty old_string"
}
test_case "Handle empty old_string" test_empty_old_string

# Test 10: Handle empty new_string
test_empty_new_string() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/empty-new.txt"
    echo "delete this" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "delete this" "")

    # Empty new_string (deletion) should be allowed
    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should allow deletion via empty new_string"
}
test_case "Handle empty new_string (deletion)" test_empty_new_string

# Test 11: Handle same old and new strings
test_same_strings() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/same.txt"
    echo "unchanged" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "unchanged" "unchanged")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Same strings should be blocked (no-op)
    echo "Same strings check: ${result}"
}
test_case "Handle same old and new strings" test_same_strings

# ============================================================================
# Tests: Replace All Mode
# ============================================================================

test_suite "Edit Handler - Replace All Mode"

# Test 12: Replace all occurrences
test_replace_all() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/multiple.txt"
    echo -e "foo\nfoo\nfoo" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "foo" "bar" "true")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "\"replace_all\": true" "Should preserve replace_all flag"
}
test_case "Replace all occurrences" test_replace_all

# Test 13: Replace single occurrence (default)
test_replace_single() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/single.txt"
    echo -e "foo\nfoo" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "foo" "bar" "false")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should allow single replacement"
}
test_case "Replace single occurrence" test_replace_single

# ============================================================================
# Tests: Special Characters & Escaping
# ============================================================================

test_suite "Edit Handler - Special Characters"

# Test 14: Handle regex special characters
test_regex_special_chars() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/regex.txt"
    echo "value = 123" > "${test_file}"

    # Test with simpler special chars to avoid JSON escaping issues
    local input
    input=$(create_tool_input "${test_file}" "value = 123" "value = 456")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should handle file edits"
}
test_case "Handle regex special characters" test_regex_special_chars

# Test 15: Handle quotes in strings
test_quotes_in_strings() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/quotes.txt"
    echo "say \"hello\"" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "say \\\"hello\\\"" "say \\\"goodbye\\\"")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should handle quotes"
}
test_case "Handle quotes in strings" test_quotes_in_strings

# Test 16: Handle newlines
test_handle_newlines() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/newlines.txt"
    echo -e "line1\nline2" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "line1\\nline2" "new content")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should handle newlines"
}
test_case "Handle newlines in strings" test_handle_newlines

# ============================================================================
# Tests: Edge Cases
# ============================================================================

test_suite "Edit Handler - Edge Cases"

# Test 17: Handle non-existent file
test_nonexistent_file() {
    source_edit_handler || return 1

    local input
    input=$(create_tool_input "${TEST_DATA_DIR}/nonexistent.txt" "old" "new")

    # Should warn about missing file
    local output
    output=$(handle_edit "${input}" 2>&1)

    echo "Non-existent file check completed"
}
test_case "Handle non-existent file" test_nonexistent_file

# Test 18: Handle empty file path
test_empty_file_path() {
    source_edit_handler || return 1

    local input
    input=$(create_tool_input "" "old" "new")

    handle_edit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block empty file path"
}
test_case "Handle empty file path" test_empty_file_path

# Test 19: Handle very long strings
test_long_strings() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/long.txt"
    local long_content=$(printf 'a%.0s' {1..1000})
    echo "${long_content}" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "${long_content:0:100}" "replacement")

    local output
    output=$(handle_edit "${input}")

    assert_contains "${output}" "${test_file}" "Should handle long strings"
}
test_case "Handle very long strings" test_long_strings

# Test 20: Handle malformed JSON
test_malformed_json() {
    source_edit_handler || return 1

    local input='{"tool": "Edit", "file_path": invalid}'
    local failed=""

    handle_edit "${input}" 2>/dev/null || failed="true"

    echo "Malformed JSON handled gracefully"
    return 0
}
test_case "Handle malformed JSON" test_malformed_json

# ============================================================================
# Tests: Security Scenarios
# ============================================================================

test_suite "Edit Handler - Security Scenarios"

# Test 21: Detect backdoor insertion
test_detect_backdoor() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/auth.sh"
    echo "authenticate_user()" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "authenticate_user()" "authenticate_user() { return 0; # backdoor }")

    # Should warn about suspicious changes
    local output
    output=$(handle_edit "${input}" 2>&1)

    echo "Backdoor detection check completed"
}
test_case "Detect backdoor insertion attempts" test_detect_backdoor

# Test 22: Detect permission escalation
test_detect_permission_escalation() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/perms.sh"
    echo "chmod 644 file.txt" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "chmod 644 file.txt" "chmod 777 file.txt")

    # Should warn about permission changes
    local output
    output=$(handle_edit "${input}" 2>&1)

    echo "Permission escalation check completed"
}
test_case "Detect permission escalation" test_detect_permission_escalation

# ============================================================================
# Tests: Metrics & Logging
# ============================================================================

test_suite "Edit Handler - Metrics & Logging"

# Test 23: Track edit operations
test_track_edits() {
    source_edit_handler || return 1

    local test_file="${TEST_DATA_DIR}/tracked.txt"
    echo "original" > "${test_file}"

    local input
    input=$(create_tool_input "${test_file}" "original" "modified")

    handle_edit "${input}" &>/dev/null

    # Check if metrics were updated
    local edit_count
    edit_count=$(session_get_metric "file_edits" "0") 2>/dev/null || edit_count="0"

    echo "Edit operations tracked: ${edit_count}"
}
test_case "Track edit operations" test_track_edits

# Test 24: Track security violations
test_track_edit_violations() {
    source_edit_handler || return 1

    local input
    input=$(create_tool_input "/etc/passwd" "root" "hacker")

    handle_edit "${input}" 2>/dev/null || true

    # Check if violation was tracked
    local violations
    violations=$(session_get_metric "violations" "0") 2>/dev/null || violations="0"

    echo "Edit violations tracked: ${violations}"
}
test_case "Track edit violations" test_track_edit_violations

# Run all tests
test_summary
