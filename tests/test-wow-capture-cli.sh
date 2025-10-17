#!/bin/bash
# WoW System - Capture CLI Test Suite
# Comprehensive testing for wow-capture tool
# Author: Chude <chude@emeke.org>

set -uo pipefail

# ============================================================================
# Test Framework Setup
# ============================================================================

# Determine WoW root
if [[ -d "/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects/wow-system" ]]; then
    WOW_ROOT="/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects/wow-system"
elif [[ -d "/root/wow-system" ]]; then
    WOW_ROOT="/root/wow-system"
else
    echo "ERROR: WoW system not found" >&2
    exit 1
fi

# Source library
source "${WOW_ROOT}/lib/wow-capture-lib.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test temp directory
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT

# ============================================================================
# Test Framework Functions
# ============================================================================

# Print test header
test_header() {
    echo ""
    echo "========================================"
    echo "TEST: $1"
    echo "========================================"
}

# Assert command succeeds
assert_success() {
    local description="$1"
    shift
    local cmd="$*"

    ((TESTS_RUN++)) || true

    if eval "$cmd" >/dev/null 2>&1; then
        echo "✓ PASS: $description"
        ((TESTS_PASSED++)) || true
        return 0
    else
        echo "✗ FAIL: $description"
        echo "  Command: $cmd"
        ((TESTS_FAILED++)) || true
        return 1
    fi
}

# Assert command fails
assert_failure() {
    local description="$1"
    shift
    local cmd="$*"

    ((TESTS_RUN++)) || true

    if eval "$cmd" >/dev/null 2>&1; then
        echo "✗ FAIL: $description (expected failure, got success)"
        ((TESTS_FAILED++)) || true
        return 1
    else
        echo "✓ PASS: $description"
        ((TESTS_PASSED++)) || true
        return 0
    fi
}

# Assert output contains string
assert_contains() {
    local description="$1"
    local expected="$2"
    local output="$3"

    ((TESTS_RUN++)) || true

    if echo "$output" | grep -q "$expected"; then
        echo "✓ PASS: $description"
        ((TESTS_PASSED++)) || true
        return 0
    else
        echo "✗ FAIL: $description"
        echo "  Expected: $expected"
        echo "  Got: ${output:0:100}..."
        ((TESTS_FAILED++)) || true
        return 1
    fi
}

# Assert equal
assert_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    ((TESTS_RUN++)) || true

    if [[ "$expected" == "$actual" ]]; then
        echo "✓ PASS: $description"
        ((TESTS_PASSED++)) || true
        return 0
    else
        echo "✗ FAIL: $description"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        ((TESTS_FAILED++)) || true
        return 1
    fi
}

# ============================================================================
# Test Data Setup
# ============================================================================

# Create test history file
create_test_history() {
    local history_file="${TEST_DIR}/history.jsonl"

    # Create sample JSONL entries with various frustration patterns
    cat > "$history_file" <<'EOF'
{"timestamp":"2025-10-05T08:00:00Z","content":"Starting new session, everything working fine","role":"user"}
{"timestamp":"2025-10-05T08:05:00Z","content":"ERROR: Command failed with exit code 1","role":"assistant"}
{"timestamp":"2025-10-05T08:06:00Z","content":"This is annoying, why doesn't it work?","role":"user"}
{"timestamp":"2025-10-05T08:10:00Z","content":"Let me try a workaround with a symlink","role":"user"}
{"timestamp":"2025-10-05T08:15:00Z","content":"Path issue with /mnt/c/Users/Name/My Documents","role":"assistant"}
{"timestamp":"2025-10-05T08:20:00Z","content":"ERROR: Command failed again","role":"assistant"}
{"timestamp":"2025-10-05T08:25:00Z","content":"Need to restart Claude Code to fix this","role":"user"}
{"timestamp":"2025-10-05T08:30:00Z","content":"ERROR: Still failing after restart","role":"assistant"}
{"timestamp":"2025-10-05T08:35:00Z","content":"I NEED TO BE THE ONE that approves this, not you!","role":"user"}
{"timestamp":"2025-10-05T08:40:00Z","content":"Here's my API token: sk-test-1234567890abcdefghijklmnopqrstuvwxyz","role":"user"}
EOF

    echo "$history_file"
}

# Create test scratch file
create_test_scratch() {
    local scratch_file="${TEST_DIR}/scratch.md"

    cat > "$scratch_file" <<'EOF'
# Test Scratch Notes

## Existing Note
This is a pre-existing note.

EOF

    echo "$scratch_file"
}

# ============================================================================
# Library Function Tests
# ============================================================================

test_library_functions() {
    test_header "Library Function Tests"

    # Test date parsing
    local date_epoch
    date_epoch=$(lib_parse_date "2025-10-05")
    assert_success "Parse valid date" "[[ -n '$date_epoch' ]]"

    assert_failure "Reject invalid date" "lib_parse_date 'invalid-date'"

    # Test credential detection
    local cred_text="Here is my token: sk-ant-1234567890abcdefghijklmnop"
    local result
    result=$(lib_scan_credentials "$cred_text" 2>/dev/null || echo "")
    assert_success "Detect Anthropic API key" "[[ -n '$result' ]]"

    # Test pattern detection (use valid JSON array)
    local error_json='[{"content":"ERROR: Failed"},{"content":"ERROR: Failed again"},{"content":"ERROR: Still failing"}]'
    result=$(lib_detect_repeated_errors "$error_json")
    assert_equal "Detect repeated errors" "true" "$result"

    # Test path detection
    local path_text="Path with spaces: /mnt/c/Users/Name/My Folder"
    result=$(lib_detect_path_issues "$path_text")
    assert_equal "Detect path issues" "true" "$result"

    # Test restart detection
    local restart_text="Need to restart the application"
    result=$(lib_detect_restarts "$restart_text")
    assert_equal "Detect restart mention" "true" "$result"

    # Test frustration language
    local frust_text="This is so annoying and frustrating"
    result=$(lib_detect_frustration_language "$frust_text")
    assert_equal "Detect frustration language" "true" "$result"

    # Test workaround detection
    local work_text="Let me create a symlink as a workaround"
    result=$(lib_detect_workarounds "$work_text")
    assert_equal "Detect workaround mention" "true" "$result"

    # Test authority violation detection
    local auth_text="You did that without asking for my approval!"
    result=$(lib_detect_authority_violations "$auth_text")
    assert_equal "Detect authority violation" "true" "$result"

    # Test confidence scoring
    result=$(lib_calculate_confidence "credential" 1 "")
    assert_equal "Credential = HIGH confidence" "HIGH" "$result"

    result=$(lib_calculate_confidence "repeated_error" 5 "")
    assert_equal "Repeated error (5x) = HIGH confidence" "HIGH" "$result"

    result=$(lib_calculate_confidence "path_issue" 1 "")
    assert_equal "Path issue = MEDIUM confidence" "MEDIUM" "$result"

    result=$(lib_calculate_confidence "restart" 1 "")
    assert_equal "Single restart = LOW confidence" "LOW" "$result"
}

# ============================================================================
# CLI Command Tests
# ============================================================================

test_cli_help() {
    test_header "CLI Help & Version Tests"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"

    # Test help command
    local output
    output=$("$wow_capture" help 2>&1)
    assert_contains "Help shows usage" "USAGE:" "$output"
    assert_contains "Help shows commands" "COMMANDS:" "$output"

    # Test --help flag
    output=$("$wow_capture" --help 2>&1)
    assert_contains "--help flag works" "USAGE:" "$output"

    # Test version
    output=$("$wow_capture" --version 2>&1)
    assert_contains "Version shows version number" "wow-capture v" "$output"
}

test_cli_analyze_basic() {
    test_header "CLI Analyze Command - Basic"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"
    local history_file
    history_file=$(create_test_history)

    # Override history location for test
    export HOME="$TEST_DIR"
    mkdir -p "${TEST_DIR}/.claude"
    cp "$history_file" "${TEST_DIR}/.claude/history.jsonl"

    # Test basic analyze (dry-run)
    local output
    output=$("$wow_capture" analyze --dry-run 2>&1 || echo "")

    # Check for key components
    assert_contains "Analysis runs" "Conversation Analysis" "$output"
    assert_contains "History file found" "History file:" "$output"
    assert_contains "Detects patterns" "Pattern Detection" "$output"
}

test_cli_analyze_date_range() {
    test_header "CLI Analyze Command - Date Range"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"

    # Test with valid date range
    local output
    output=$("$wow_capture" analyze --from 2025-10-01 --to 2025-10-05 --dry-run 2>&1 || echo "")

    assert_contains "Date range parsing" "Date range:" "$output"
}

test_cli_analyze_invalid_dates() {
    test_header "CLI Analyze Command - Invalid Dates"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"

    # Test with invalid date
    assert_failure "Reject invalid from date" \
        "$wow_capture analyze --from 'invalid' --dry-run 2>&1"
}

test_cli_config() {
    test_header "CLI Config Command"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"

    local output
    output=$("$wow_capture" config 2>&1)

    assert_contains "Config shows settings" "Current Settings:" "$output"
    assert_contains "Config shows thresholds" "Detection Thresholds:" "$output"
    assert_contains "Config shows WoW root" "WoW Root:" "$output"
}

test_cli_report() {
    test_header "CLI Report Command"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"

    local output
    output=$("$wow_capture" report 2>&1)

    assert_contains "Report generates" "Report" "$output"
}

# ============================================================================
# Edge Case Tests
# ============================================================================

test_edge_cases() {
    test_header "Edge Case Tests"

    # Test empty history file
    local empty_history="${TEST_DIR}/empty.jsonl"
    touch "$empty_history"

    local result
    result=$(lib_validate_jsonl "$empty_history" && echo "valid" || echo "invalid")
    assert_equal "Empty file is invalid JSONL" "invalid" "$result"

    # Test corrupted JSON
    local corrupt_history="${TEST_DIR}/corrupt.jsonl"
    echo "not valid json" > "$corrupt_history"
    result=$(lib_validate_jsonl "$corrupt_history" && echo "valid" || echo "invalid")
    assert_equal "Corrupted file is invalid JSONL" "invalid" "$result"

    # Test valid JSONL
    local valid_history="${TEST_DIR}/valid.jsonl"
    echo '{"test":"value"}' > "$valid_history"
    result=$(lib_validate_jsonl "$valid_history" && echo "valid" || echo "invalid")
    assert_equal "Valid JSONL is recognized" "valid" "$result"

    # Test missing history file
    local missing_history="${TEST_DIR}/nonexistent.jsonl"
    result=$(lib_validate_jsonl "$missing_history" && echo "valid" || echo "invalid")
    assert_equal "Missing file is invalid" "invalid" "$result"
}

test_pattern_combinations() {
    test_header "Pattern Combination Tests"

    # Test text with multiple patterns
    local multi_text="ERROR: Path issue with /mnt/c/My Folder. This is annoying! Need to restart."

    local has_error=$(lib_detect_repeated_errors "[$multi_text]")
    local has_path=$(lib_detect_path_issues "$multi_text")
    local has_frust=$(lib_detect_frustration_language "$multi_text")
    local has_restart=$(lib_detect_restarts "$multi_text")

    assert_equal "Detects path in multi-pattern" "true" "$has_path"
    assert_equal "Detects frustration in multi-pattern" "true" "$has_frust"
    assert_equal "Detects restart in multi-pattern" "true" "$has_restart"
}

test_credential_redaction() {
    test_header "Credential Redaction Tests"

    local text_with_cred="My token is sk-ant-abcdefghijklmnopqrstuvwxyz123456"
    local match="sk-ant-abcdefghijklmnopqrstuvwxyz123456"

    local redacted
    redacted=$(lib_redact_credential "$text_with_cred" "$match")

    assert_contains "Credential is redacted" "[REDACTED]" "$redacted"
    assert_success "Original token not in redacted text" "[[ ! '$redacted' =~ 'sk-ant-' ]]"
}

# ============================================================================
# Integration Tests
# ============================================================================

test_full_workflow() {
    test_header "Full Workflow Integration Test"

    local wow_capture="${WOW_ROOT}/bin/wow-capture"
    local history_file
    history_file=$(create_test_history)

    # Setup test environment with library
    local test_home="${TEST_DIR}/test-home"
    mkdir -p "${test_home}/.claude"
    mkdir -p "${TEST_DIR}/lib"
    cp "$history_file" "${test_home}/.claude/history.jsonl"
    cp "${WOW_ROOT}/lib/wow-capture-lib.sh" "${TEST_DIR}/lib/"

    # Create output directory
    mkdir -p "${TEST_DIR}/docs/principles/v5.0"

    # Run with proper environment
    local output
    output=$(HOME="$test_home" WOW_SYSTEM_DIR="$WOW_ROOT" "$wow_capture" analyze --dry-run 2>&1 || echo "workflow-failed")

    assert_contains "Full workflow completes" "Conversation Analysis" "$output"
}

# ============================================================================
# Performance Tests
# ============================================================================

test_performance() {
    test_header "Performance Tests"

    # Create large history file
    local large_history="${TEST_DIR}/large.jsonl"

    # Generate 1000 entries
    for i in {1..1000}; do
        echo "{\"timestamp\":\"2025-10-05T08:00:00Z\",\"content\":\"Test entry $i\",\"role\":\"user\"}" >> "$large_history"
    done

    # Test parsing performance
    local start_time=$(date +%s)
    local count=0
    while IFS= read -r line; do
        ((count++)) || true
    done < "$large_history"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    assert_success "Process 1000 entries quickly (<10s)" "[[ $duration -lt 10 ]]"
    assert_equal "Correct entry count" "1000" "$count"
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    echo ""
    echo "========================================"
    echo "WoW Capture CLI - Test Suite"
    echo "========================================"
    echo ""

    # Run all test groups
    test_library_functions
    test_cli_help
    test_cli_analyze_basic
    test_cli_analyze_date_range
    test_cli_analyze_invalid_dates
    test_cli_config
    test_cli_report
    test_edge_cases
    test_pattern_combinations
    test_credential_redaction
    test_full_workflow
    test_performance

    # Summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Total Tests:  $TESTS_RUN"
    echo "Passed:       $TESTS_PASSED"
    echo "Failed:       $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ ALL TESTS PASSED!"
        return 0
    else
        echo "✗ SOME TESTS FAILED"
        return 1
    fi
}

# Run tests
run_all_tests
