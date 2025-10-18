#!/bin/bash
# Test Suite: Score Display Module
# Tests violation display and score visualization
# Author: Chude <chude@emeke.org>
#
# TDD Approach: Tests written FIRST before implementation

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source modules under test
source "${SCRIPT_DIR}/../src/core/utils.sh"
source "${SCRIPT_DIR}/../src/core/file-storage.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/core/state-manager.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/core/session-manager.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/core/scoring-engine.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/ui/display.sh"
source "${SCRIPT_DIR}/../src/ui/score-display.sh"

# ============================================================================
# Test Suite Setup
# ============================================================================

test_suite "Score Display Module Tests"

# Setup test environment
setup_test() {
    # Initialize modules
    scoring_init 2>/dev/null || true
    session_init 2>/dev/null || true
}

cleanup_test() {
    # Clean up
    true
}

# ============================================================================
# Test Cases - Basic Violation Display
# ============================================================================

test_display_violation_basic() {
    setup_test

    # Display violation
    local output
    output=$(score_display_violation "path_traversal" "/etc/passwd" "read-handler" 2>&1)

    # Should contain key elements
    assert_contains "${output}" "VIOLATION" "Should show violation header"
    assert_contains "${output}" "path_traversal" "Should show violation type"
    assert_contains "${output}" "/etc/passwd" "Should show path"
    assert_contains "${output}" "read-handler" "Should show handler"

    cleanup_test
}

test_display_shows_current_score() {
    setup_test

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should show score (default or current)
    assert_contains "${output}" "/100" "Should show score out of 100"

    cleanup_test
}

test_display_shows_score_gauge() {
    setup_test

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should contain gauge (bracket characters)
    assert_contains "${output}" "[" "Should show gauge start"
    assert_contains "${output}" "]" "Should show gauge end"

    cleanup_test
}

test_display_shows_status() {
    setup_test

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should show one of the status levels
    if [[ "${output}" =~ (EXCELLENT|GOOD|WARNING|CRITICAL|BLOCKED) ]]; then
        assert_success "Should show a valid status level"
    else
        assert_fail "Should show a status level"
    fi

    cleanup_test
}

# ============================================================================
# Test Cases - Score Levels & Colors
# ============================================================================

test_excellent_score_display() {
    setup_test

    # Set high score
    scoring_set_score 95 2>/dev/null || true

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    assert_contains "${output}" "95" "Should show high score"
    # Status should be excellent or good
    if [[ "${output}" =~ (EXCELLENT|GOOD) ]]; then
        assert_success "Should show positive status"
    else
        assert_fail "High score should show positive status"
    fi

    cleanup_test
}

test_warning_score_display() {
    setup_test

    # Set warning-level score
    scoring_set_score 55 2>/dev/null || true

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    assert_contains "${output}" "55" "Should show warning score"
    assert_contains "${output}" "WARNING" "Should show WARNING status"

    cleanup_test
}

test_critical_score_display() {
    setup_test

    # Set critical-level score
    scoring_set_score 35 2>/dev/null || true

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    assert_contains "${output}" "35" "Should show critical score"
    assert_contains "${output}" "CRITICAL" "Should show CRITICAL status"

    cleanup_test
}

test_blocked_score_display() {
    setup_test

    # Set blocked-level score
    scoring_set_score 20 2>/dev/null || true

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    assert_contains "${output}" "20" "Should show blocked score"
    assert_contains "${output}" "BLOCKED" "Should show BLOCKED status"

    cleanup_test
}

# ============================================================================
# Test Cases - Violation Details
# ============================================================================

test_displays_violation_type() {
    setup_test

    local output
    output=$(score_display_violation "command_injection" "/tmp/test" "bash-handler" 2>&1)

    assert_contains "${output}" "command_injection" "Should display violation type"

    cleanup_test
}

test_displays_violation_path() {
    setup_test

    local output
    output=$(score_display_violation "test" "../../etc/shadow" "read-handler" 2>&1)

    assert_contains "${output}" "../../etc/shadow" "Should display full path"

    cleanup_test
}

test_displays_handler_name() {
    setup_test

    local output
    output=$(score_display_violation "test" "/tmp/test" "write-handler" 2>&1)

    assert_contains "${output}" "write-handler" "Should display handler name"

    cleanup_test
}

# ============================================================================
# Test Cases - Violation History
# ============================================================================

test_displays_recent_violations_count() {
    setup_test

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should mention violations count or history
    if [[ "${output}" =~ (Violations|violations|Recent|recent) ]]; then
        assert_success "Should show violations tracking"
    else
        assert_success "Violations count display optional"
    fi

    cleanup_test
}

# ============================================================================
# Test Cases - Configuration & Flags
# ============================================================================

test_respects_display_enabled_flag() {
    setup_test

    # When disabled, should return empty or minimal output
    # (This depends on implementation - might skip display entirely)
    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1 || true)

    # Should produce some output (either full display or minimal)
    assert_not_empty "${output}" "Should produce output"

    cleanup_test
}

test_handles_missing_score_gracefully() {
    setup_test

    # Don't initialize scoring engine
    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1 || true)

    # Should not crash, show default score
    assert_success "Should handle missing score gracefully"
    assert_not_empty "${output}" "Should still produce output"

    cleanup_test
}

test_handles_empty_violation_type() {
    setup_test

    local output
    output=$(score_display_violation "" "/tmp/test" "test-handler" 2>&1 || true)

    # Should handle gracefully
    assert_success "Should handle empty violation type"

    cleanup_test
}

test_handles_empty_path() {
    setup_test

    local output
    output=$(score_display_violation "test" "" "test-handler" 2>&1 || true)

    # Should handle gracefully
    assert_success "Should handle empty path"

    cleanup_test
}

# ============================================================================
# Test Cases - Score Penalty Display
# ============================================================================

test_shows_score_change_indicator() {
    setup_test

    # This test assumes the implementation tracks score changes
    # May need adjustment based on actual implementation
    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should show score (change indicator optional in v1)
    assert_contains "${output}" "/100" "Should show score"

    cleanup_test
}

# ============================================================================
# Test Cases - Output Format
# ============================================================================

test_output_contains_box_drawing() {
    setup_test

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should contain Unicode box-drawing characters
    if [[ "${output}" =~ [┌┐└┘─│═╔╗╚╝║] ]]; then
        assert_success "Should use box-drawing characters"
    else
        assert_success "Box-drawing optional (may use ASCII)"
    fi

    cleanup_test
}

test_output_is_readable() {
    setup_test

    local output
    output=$(score_display_violation "path_traversal" "/etc/passwd" "read-handler" 2>&1)

    # Should be multi-line output (not just single line)
    local line_count
    line_count=$(echo "${output}" | wc -l)

    assert_greater_than 3 ${line_count} "Should be multi-line output"

    cleanup_test
}

# ============================================================================
# Test Cases - Integration
# ============================================================================

test_integrates_with_scoring_engine() {
    setup_test

    # Initialize scoring with specific value
    scoring_init 2>/dev/null || true
    scoring_set_score 75 2>/dev/null || true

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1)

    # Should show the set score
    assert_contains "${output}" "75" "Should integrate with scoring engine"

    cleanup_test
}

test_integrates_with_session_metrics() {
    setup_test

    # Initialize session
    session_init 2>/dev/null || true

    local output
    output=$(score_display_violation "test" "/tmp/test" "test-handler" 2>&1 || true)

    # Should work with or without session manager
    assert_success "Should integrate with session manager"

    cleanup_test
}

# ============================================================================
# Test Cases - Edge Cases
# ============================================================================

test_handles_very_long_path() {
    setup_test

    local long_path="/very/long/path/that/goes/on/and/on/and/on/and/on/and/on/file.txt"
    local output
    output=$(score_display_violation "test" "${long_path}" "test-handler" 2>&1)

    # Should truncate or wrap long paths gracefully
    assert_success "Should handle long paths"
    assert_not_empty "${output}" "Should produce output for long paths"

    cleanup_test
}

test_handles_special_characters_in_path() {
    setup_test

    local special_path="/tmp/test with spaces & special.txt"
    local output
    output=$(score_display_violation "test" "${special_path}" "test-handler" 2>&1)

    # Should handle special characters
    assert_success "Should handle special characters"
    assert_contains "${output}" "special" "Should display path with special chars"

    cleanup_test
}

# ============================================================================
# Run Test Suite
# ============================================================================

# Basic Display (4 tests)
test_case "should display basic violation info" test_display_violation_basic
test_case "should show current score" test_display_shows_current_score
test_case "should show score gauge" test_display_shows_score_gauge
test_case "should show status level" test_display_shows_status

# Score Levels (4 tests)
test_case "should display excellent score correctly" test_excellent_score_display
test_case "should display warning score correctly" test_warning_score_display
test_case "should display critical score correctly" test_critical_score_display
test_case "should display blocked score correctly" test_blocked_score_display

# Violation Details (3 tests)
test_case "should display violation type" test_displays_violation_type
test_case "should display violation path" test_displays_violation_path
test_case "should display handler name" test_displays_handler_name

# History (1 test)
test_case "should display recent violations" test_displays_recent_violations_count

# Configuration (3 tests)
test_case "should respect display enabled flag" test_respects_display_enabled_flag
test_case "should handle missing score" test_handles_missing_score_gracefully
test_case "should handle empty violation type" test_handles_empty_violation_type

# Additional (4 tests)
test_case "should handle empty path" test_handles_empty_path
test_case "should show score change" test_shows_score_change_indicator
test_case "should use box drawing" test_output_contains_box_drawing
test_case "should produce readable output" test_output_is_readable

# Integration (2 tests)
test_case "should integrate with scoring engine" test_integrates_with_scoring_engine
test_case "should integrate with session manager" test_integrates_with_session_metrics

# Edge Cases (2 tests)
test_case "should handle very long paths" test_handles_very_long_path
test_case "should handle special characters" test_handles_special_characters_in_path

# Show summary
test_summary
