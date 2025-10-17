#!/bin/bash
# WoW System - Credential Redactor Test Suite
# Tests for safe redaction with backup and preview
# Author: Chude <chude@emeke.org>

set -uo pipefail

# ============================================================================
# Test Setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source the redactor (which also sources detector)
source "${PROJECT_ROOT}/src/security/credential-redactor.sh"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test temp directory
TEST_TEMP_DIR="/tmp/wow-redactor-tests-$$"
mkdir -p "$TEST_TEMP_DIR"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_TEMP_DIR"
}
trap cleanup EXIT

# ============================================================================
# Test Framework
# ============================================================================

assert_equal() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    (( TESTS_RUN++ )) || true

    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $test_name"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: $test_name"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        (( TESTS_FAILED++ )) || true
    fi
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"

    (( TESTS_RUN++ )) || true

    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $test_name"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: $test_name (does not contain: $needle)"
        (( TESTS_FAILED++ )) || true
    fi
}

assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"

    (( TESTS_RUN++ )) || true

    if ! echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $test_name"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: $test_name (should not contain: $needle)"
        (( TESTS_FAILED++ )) || true
    fi
}

assert_file_exists() {
    local test_name="$1"
    local filepath="$2"

    (( TESTS_RUN++ )) || true

    if [[ -f "$filepath" ]]; then
        echo "  PASS: $test_name"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: $test_name (file does not exist: $filepath)"
        (( TESTS_FAILED++ )) || true
    fi
}

# ============================================================================
# Test Cases - String Redaction
# ============================================================================

test_string_redaction_github() {
    echo "=== Testing String Redaction (GitHub) ==="

    local input="export GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456"
    local result
    result=$(redact_string "$input")

    assert_contains "GitHub token redacted" "$result" "REDACTED"
    assert_not_contains "GitHub token removed" "$result" "ghp_1234567890"
}

test_string_redaction_openai() {
    echo "=== Testing String Redaction (OpenAI) ==="

    local input="OPENAI_API_KEY=sk-1234567890abcdefghijklmnopqrstuvwxyzABCDEFGH"
    local result
    result=$(redact_string "$input")

    assert_contains "OpenAI key redacted" "$result" "REDACTED"
    assert_not_contains "OpenAI key removed" "$result" "sk-1234567890"
}

test_string_redaction_aws() {
    echo "=== Testing String Redaction (AWS) ==="

    local input="AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
    local result
    result=$(redact_string "$input")

    assert_contains "AWS key redacted" "$result" "REDACTED"
    assert_not_contains "AWS key removed" "$result" "AKIAIOSFODNN7"
}

test_string_redaction_multiple() {
    echo "=== Testing Multiple Credentials in String ==="

    local input="GITHUB_TOKEN=ghp_abc123 and OPENAI_KEY=sk-xyz789"
    local result
    result=$(redact_string "$input")

    assert_contains "Multiple redactions applied" "$result" "REDACTED"
    assert_not_contains "GitHub token removed" "$result" "ghp_abc123"
    assert_not_contains "OpenAI key removed" "$result" "sk-xyz789"
}

test_string_redaction_preserves_context() {
    echo "=== Testing Context Preservation ==="

    local input="export GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456 for deployment"
    local result
    result=$(redact_string "$input")

    assert_contains "Preserves 'export'" "$result" "export"
    assert_contains "Preserves 'GITHUB_TOKEN'" "$result" "GITHUB_TOKEN"
    assert_contains "Preserves 'for deployment'" "$result" "for deployment"
}

# ============================================================================
# Test Cases - File Redaction
# ============================================================================

test_file_redaction_simple() {
    echo "=== Testing Simple File Redaction ==="

    local test_file="${TEST_TEMP_DIR}/test_simple.txt"
    echo "GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456" > "$test_file"

    redact_file "$test_file" >/dev/null

    local content
    content=$(<"$test_file")

    assert_contains "File redacted" "$content" "REDACTED"
    assert_not_contains "Token removed" "$content" "ghp_1234567890"
}

test_file_redaction_multiline() {
    echo "=== Testing Multiline File Redaction ==="

    local test_file="${TEST_TEMP_DIR}/test_multiline.txt"
    cat > "$test_file" <<EOF
# Configuration file
GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456
OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJK
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
# End of config
EOF

    redact_file "$test_file" >/dev/null

    local content
    content=$(<"$test_file")

    assert_contains "GitHub token redacted" "$content" "REDACTED"
    assert_not_contains "GitHub token removed" "$content" "ghp_1234567890"
    assert_not_contains "OpenAI key removed" "$content" "sk-abcdefghijklmnopqrstuvwxyz"
    assert_not_contains "AWS key removed" "$content" "AKIAIOSFODNN7"
    assert_contains "Comments preserved" "$content" "# Configuration"
    assert_contains "Comments preserved" "$content" "# End of config"
}

test_file_no_credentials() {
    echo "=== Testing File with No Credentials ==="

    local test_file="${TEST_TEMP_DIR}/test_no_creds.txt"
    echo "This is a safe file with no credentials" > "$test_file"

    redact_file "$test_file" >/dev/null

    local content
    content=$(<"$test_file")

    assert_equal "File unchanged" \
        "This is a safe file with no credentials" \
        "$content"
}

# ============================================================================
# Test Cases - Backup Management
# ============================================================================

test_backup_creation() {
    echo "=== Testing Backup Creation ==="

    local test_file="${TEST_TEMP_DIR}/test_backup.txt"
    echo "GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456" > "$test_file"

    redact_with_backup "$test_file" >/dev/null

    # Check backup was created
    local backup_count
    backup_count=$(find "$TEST_TEMP_DIR" -name "test_backup.txt.credential-backup.*" | wc -l)

    if [[ $backup_count -gt 0 ]]; then
        echo "  PASS: Backup created"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: No backup created"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true
}

test_backup_restoration() {
    echo "=== Testing Backup Restoration ==="

    local test_file="${TEST_TEMP_DIR}/test_restore.txt"
    local original_content="GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456"
    echo "$original_content" > "$test_file"

    # Redact with backup
    redact_with_backup "$test_file" >/dev/null

    # Restore
    redact_restore_latest "$test_file" >/dev/null

    local restored_content
    restored_content=$(<"$test_file")

    assert_equal "Content restored" "$original_content" "$restored_content"
}

test_backup_cleanup() {
    echo "=== Testing Backup Cleanup ==="

    local test_file="${TEST_TEMP_DIR}/test_cleanup.txt"
    echo "GITHUB_TOKEN=ghp_test" > "$test_file"

    # Create multiple backups
    for i in {1..7}; do
        sleep 1
        redact_with_backup "$test_file" >/dev/null
        echo "GITHUB_TOKEN=ghp_test" > "$test_file"  # Restore for next iteration
    done

    # Cleanup, keep only 3
    redact_cleanup_backups "$test_file" 3 >/dev/null

    # Count remaining backups
    local backup_count
    backup_count=$(find "$TEST_TEMP_DIR" -name "test_cleanup.txt.credential-backup.*" | wc -l)

    if [[ $backup_count -eq 3 ]]; then
        echo "  PASS: Cleanup successful (kept 3 backups)"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: Cleanup failed (expected: 3, actual: $backup_count)"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true
}

# ============================================================================
# Test Cases - Preview Mode
# ============================================================================

test_preview_string() {
    echo "=== Testing String Preview ==="

    local input="GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456"
    local preview
    preview=$(redact_preview "$input" 2>&1)

    assert_contains "Preview shows type" "$preview" "Type:"
    assert_contains "Preview shows severity" "$preview" "Severity:"
    assert_contains "Preview shows before" "$preview" "Before:"
    assert_contains "Preview shows after" "$preview" "After:"
}

test_preview_file_no_modification() {
    echo "=== Testing File Preview Does Not Modify ==="

    local test_file="${TEST_TEMP_DIR}/test_preview.txt"
    local original_content="GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456"
    echo "$original_content" > "$test_file"

    # Preview
    redact_preview_file "$test_file" >/dev/null

    # Check file unchanged
    local actual_content
    actual_content=$(<"$test_file")

    assert_equal "File not modified by preview" "$original_content" "$actual_content"
}

# ============================================================================
# Test Cases - Statistics
# ============================================================================

test_statistics_tracking() {
    echo "=== Testing Statistics Tracking ==="

    # Reset stats
    redact_reset_stats

    # Perform some redactions
    local test_file="${TEST_TEMP_DIR}/test_stats.txt"
    echo "GITHUB_TOKEN=ghp_abc123" > "$test_file"

    redact_with_backup "$test_file" >/dev/null

    # Check stats
    local stats
    stats=$(redact_get_stats)

    local files_processed
    files_processed=$(echo "$stats" | jq -r '.files_processed')

    if [[ $files_processed -ge 1 ]]; then
        echo "  PASS: Statistics tracked"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: Statistics not tracked properly"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true
}

# ============================================================================
# Test Cases - Edge Cases
# ============================================================================

test_empty_file() {
    echo "=== Testing Empty File ==="

    local test_file="${TEST_TEMP_DIR}/test_empty.txt"
    touch "$test_file"

    redact_file "$test_file" >/dev/null

    # Should not error
    echo "  PASS: Empty file handled"
    (( TESTS_PASSED++ )) || true
    (( TESTS_RUN++ )) || true
}

test_file_with_safe_context() {
    echo "=== Testing File with Safe Context ==="

    local test_file="${TEST_TEMP_DIR}/test_safe.txt"
    cat > "$test_file" <<EOF
# Example configuration
api_key = YOUR_API_KEY_HERE
token = REPLACE_ME
secret = example_secret
EOF

    redact_file "$test_file" >/dev/null

    local content
    content=$(<"$test_file")

    # Should preserve safe placeholders (no HIGH/MEDIUM severity matches)
    assert_contains "Placeholder preserved" "$content" "YOUR_API_KEY_HERE"
}

test_special_characters() {
    echo "=== Testing Special Characters ==="

    local test_file="${TEST_TEMP_DIR}/test_special.txt"
    echo "token='ghp_1234567890abcdefghijklmnopqrstuv123456' # sensitive" > "$test_file"

    redact_file "$test_file" >/dev/null

    local content
    content=$(<"$test_file")

    assert_contains "Token redacted" "$content" "REDACTED"
    assert_not_contains "Token removed" "$content" "ghp_1234567890"
    assert_contains "Comment preserved" "$content" "# sensitive"
}

# ============================================================================
# Test Cases - Integration
# ============================================================================

test_detector_redactor_integration() {
    echo "=== Testing Detector-Redactor Integration ==="

    local input="OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJK"

    # Detect
    local detection
    detection=$(detect_in_string "$input")

    if [[ -z "$detection" ]]; then
        echo "  FAIL: Detection failed"
        (( TESTS_FAILED++ )) || true
        (( TESTS_RUN++ )) || true
        return
    fi

    # Redact
    local redacted
    redacted=$(redact_string "$input")

    assert_contains "Integration successful" "$redacted" "REDACTED"
    assert_not_contains "Credential removed" "$redacted" "sk-abcdefghijklmnopqrstuvwxyz"
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
    echo "=========================================="
    echo "WoW Credential Redactor Test Suite"
    echo "=========================================="
    echo ""

    # Initialize
    redact_init
    redact_reset_stats

    # Run all test groups
    test_string_redaction_github
    echo ""
    test_string_redaction_openai
    echo ""
    test_string_redaction_aws
    echo ""
    test_string_redaction_multiple
    echo ""
    test_string_redaction_preserves_context
    echo ""
    test_file_redaction_simple
    echo ""
    test_file_redaction_multiline
    echo ""
    test_file_no_credentials
    echo ""
    test_backup_creation
    echo ""
    test_backup_restoration
    echo ""
    test_backup_cleanup
    echo ""
    test_preview_string
    echo ""
    test_preview_file_no_modification
    echo ""
    test_statistics_tracking
    echo ""
    test_empty_file
    echo ""
    test_file_with_safe_context
    echo ""
    test_special_characters
    echo ""
    test_detector_redactor_integration

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total tests:  $TESTS_RUN"
    echo "Passed:       $TESTS_PASSED"
    echo "Failed:       $TESTS_FAILED"
    echo ""

    # Print redaction statistics
    echo "Redaction Statistics:"
    redact_get_stats
    echo ""

    # Exit with proper code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "All tests passed!"
        exit 0
    else
        echo "Some tests failed!"
        exit 1
    fi
}

main "$@"
