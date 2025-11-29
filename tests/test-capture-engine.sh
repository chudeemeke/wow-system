#!/bin/bash
# WoW System - Capture Engine Tests (TDD - Tests First)
# Comprehensive test suite for frustration capture engine
# Author: Chude <chude@emeke.org>

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source test framework
source "${SCRIPT_DIR}/test-framework.sh"

# Source dependencies
source "${PROJECT_ROOT}/src/core/utils.sh"
source "${PROJECT_ROOT}/src/core/state-manager.sh"
source "${PROJECT_ROOT}/src/core/session-manager.sh"
source "${PROJECT_ROOT}/src/patterns/event-bus.sh"

# Source the capture engine (will be implemented)
source "${PROJECT_ROOT}/src/engines/capture-engine.sh"

# ============================================================================
# Test Setup & Teardown
# ============================================================================

TEST_TEMP_DIR=""

setup_all() {
    TEST_TEMP_DIR=$(test_temp_dir)
    export WOW_STATE_DIR="${TEST_TEMP_DIR}/.wow"
    mkdir -p "${WOW_STATE_DIR}"
}

teardown_all() {
    if [[ -n "${TEST_TEMP_DIR}" ]] && [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

setup() {
    # Clean state before each test
    state_init 2>/dev/null
    session_start 2>/dev/null >/dev/null
    event_bus_init 2>/dev/null
    capture_engine_init 2>/dev/null
}

teardown() {
    # Clean up after each test
    capture_engine_reset 2>/dev/null || true
    event_bus_clear_all
}

# ============================================================================
# Test Cases - Initialization
# ============================================================================

test_capture_init_succeeds() {
    capture_engine_init
    assert_equals "0" "$?" "Capture engine initialization should succeed"
}

test_capture_init_is_idempotent() {
    capture_engine_init
    capture_engine_init
    capture_engine_init
    assert_equals "0" "$?" "Multiple inits should not cause errors"
}

test_capture_init_subscribes_to_events() {
    capture_engine_init

    local events_list
    events_list=$(event_bus_list_events)

    # Should subscribe to handler events
    assert_contains "${events_list}" "handler.blocked" "Should subscribe to handler.blocked"
    assert_contains "${events_list}" "handler.error" "Should subscribe to handler.error"
}

test_capture_init_creates_session_state() {
    capture_engine_init

    local frustration_count
    frustration_count=$(session_get_metric "frustration_count" "")

    assert_equals "0" "${frustration_count}" "Should initialize frustration count to 0"
}

# ============================================================================
# Test Cases - Event Detection
# ============================================================================

test_detect_handler_blocked_event() {
    local result
    result=$(capture_detect_event "handler.blocked" "Bash" "dangerous_operation")

    assert_equals "0" "$?" "Detection should succeed"
    assert_not_equals "" "${result}" "Should return frustration ID"
}

test_detect_handler_error_event() {
    local result
    result=$(capture_detect_event "handler.error" "Write" "permission_denied")

    assert_equals "0" "$?" "Detection should succeed"
    assert_not_equals "" "${result}" "Should return frustration ID"
}

test_detect_handler_retry_event() {
    local result
    result=$(capture_detect_event "handler.retry" "Edit" "file_locked")

    assert_equals "0" "$?" "Detection should succeed"
}

test_detect_path_issue_event() {
    local result
    result=$(capture_detect_event "path.issue" "/path with spaces/file.txt" "space_in_path")

    assert_equals "0" "$?" "Detection should succeed"
    assert_not_equals "" "${result}" "Should detect path issue"
}

test_detect_credential_exposure_event() {
    local result
    result=$(capture_detect_event "security.credential" "API_KEY=secret123" "env_var_exposed")

    assert_equals "0" "$?" "Detection should succeed"
    assert_not_equals "" "${result}" "Should detect credential exposure"
}

test_detect_workaround_event() {
    local result
    result=$(capture_detect_event "workaround.detected" "symlink_created" "manual_fix")

    assert_equals "0" "$?" "Detection should succeed"
}

test_detect_increments_frustration_count() {
    capture_detect_event "handler.blocked" "Bash" "dangerous_op"

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_equals "1" "${count}" "Should increment frustration count"
}

test_detect_stores_frustration_details() {
    local frust_id
    frust_id=$(capture_detect_event "handler.error" "Write" "permission_denied")

    local details
    details=$(capture_get_frustration "${frust_id}")

    assert_contains "${details}" "handler.error" "Should store event type"
    assert_contains "${details}" "Write" "Should store context"
}

# ============================================================================
# Test Cases - Pattern Analysis
# ============================================================================

test_analyze_pattern_detects_repeated_errors() {
    # Simulate 3 repeated errors
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"

    local pattern
    pattern=$(capture_analyze_pattern)

    assert_contains "${pattern}" "repeated_error" "Should detect repeated error pattern"
}

test_analyze_pattern_detects_rapid_fire_events() {
    # Simulate rapid-fire events
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.blocked" "Bash" "op2"
    capture_detect_event "handler.blocked" "Bash" "op3"
    capture_detect_event "handler.blocked" "Bash" "op4"

    local pattern
    pattern=$(capture_analyze_pattern)

    assert_contains "${pattern}" "rapid_fire" "Should detect rapid-fire pattern"
}

test_analyze_pattern_detects_workaround_sequence() {
    # User blocks -> tries workaround -> blocks again
    capture_detect_event "handler.blocked" "Bash" "operation"
    capture_detect_event "workaround.detected" "symlink" "manual_fix"
    capture_detect_event "handler.blocked" "Bash" "operation"

    local pattern
    pattern=$(capture_analyze_pattern)

    assert_contains "${pattern}" "workaround_attempt" "Should detect workaround pattern"
}

test_analyze_pattern_detects_path_issues_pattern() {
    # Multiple path issues
    capture_detect_event "path.issue" "/path with spaces/file1.txt" "space"
    capture_detect_event "path.issue" "/another path/file2.txt" "space"

    local pattern
    pattern=$(capture_analyze_pattern)

    assert_contains "${pattern}" "path_pattern" "Should detect path pattern"
}

test_analyze_pattern_returns_none_for_single_event() {
    capture_detect_event "handler.error" "Bash" "single_error"

    local pattern
    pattern=$(capture_analyze_pattern)

    assert_equals "none" "${pattern}" "Single event should not form pattern"
}

test_analyze_pattern_ignores_old_events() {
    # Events older than threshold should be ignored
    capture_detect_event "handler.error" "Bash" "old_error"

    # Simulate time passage by updating timestamp manually
    session_update_metric "last_frustration_at" "$(($(date +%s) - 400))"

    local pattern
    pattern=$(capture_analyze_pattern)

    assert_equals "none" "${pattern}" "Old events should not affect pattern"
}

# ============================================================================
# Test Cases - Prompting Decision
# ============================================================================

test_should_prompt_after_threshold_met() {
    # Create multiple frustrations to meet threshold
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"
    capture_detect_event "handler.blocked" "Bash" "op2"

    local should_prompt
    should_prompt=$(capture_should_prompt)

    assert_equals "true" "${should_prompt}" "Should prompt after threshold met"
}

test_should_not_prompt_below_threshold() {
    # Single event below threshold
    capture_detect_event "handler.error" "Bash" "single_error"

    local should_prompt
    should_prompt=$(capture_should_prompt)

    assert_equals "false" "${should_prompt}" "Should not prompt below threshold"
}

test_should_prompt_for_critical_pattern() {
    # Critical patterns should prompt immediately
    capture_detect_event "security.credential" "API_KEY=secret" "exposed"

    local should_prompt
    should_prompt=$(capture_should_prompt)

    assert_equals "true" "${should_prompt}" "Should prompt for critical security issue"
}

test_should_not_prompt_if_recently_prompted() {
    # Simulate recent prompt
    session_update_metric "last_prompt_at" "$(date +%s)"

    # Add multiple frustrations
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"
    capture_detect_event "handler.blocked" "Bash" "op2"

    local should_prompt
    should_prompt=$(capture_should_prompt)

    assert_equals "false" "${should_prompt}" "Should not prompt if recently prompted"
}

test_should_prompt_resets_after_cooldown() {
    # Set prompt time in the past (beyond cooldown)
    session_update_metric "last_prompt_at" "$(($(date +%s) - 400))"

    # Add frustrations
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"
    capture_detect_event "handler.blocked" "Bash" "op2"

    local should_prompt
    should_prompt=$(capture_should_prompt)

    assert_equals "true" "${should_prompt}" "Should prompt after cooldown period"
}

# ============================================================================
# Test Cases - Confidence Scoring
# ============================================================================

test_confidence_high_for_repeated_pattern() {
    # Create clear repeated pattern
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"

    local confidence
    confidence=$(capture_get_confidence)

    assert_equals "HIGH" "${confidence}" "Should have high confidence for repeated pattern"
}

test_confidence_medium_for_multiple_events() {
    # Multiple different events
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"
    capture_detect_event "path.issue" "/path/file" "issue1"

    local confidence
    confidence=$(capture_get_confidence)

    assert_equals "MEDIUM" "${confidence}" "Should have medium confidence for multiple events"
}

test_confidence_low_for_single_event() {
    # Single event
    capture_detect_event "handler.error" "Bash" "single_error"

    local confidence
    confidence=$(capture_get_confidence)

    assert_equals "LOW" "${confidence}" "Should have low confidence for single event"
}

test_confidence_critical_for_security_issues() {
    # Security-related frustration
    capture_detect_event "security.credential" "PASSWORD=secret" "exposed"

    local confidence
    confidence=$(capture_get_confidence)

    assert_equals "CRITICAL" "${confidence}" "Should have critical confidence for security issue"
}

test_confidence_considers_recency() {
    # Recent events should have higher confidence
    capture_detect_event "handler.blocked" "Bash" "recent1"
    capture_detect_event "handler.blocked" "Bash" "recent2"

    local confidence
    confidence=$(capture_get_confidence)

    assert_not_equals "LOW" "${confidence}" "Recent events should boost confidence"
}

# ============================================================================
# Test Cases - Integration with Event Bus
# ============================================================================

test_event_bus_integration_handler_blocked() {
    # Publish event through event bus
    event_bus_publish "handler.blocked" "handler=Bash|operation=rm_rf|path=/data"

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_not_equals "0" "${count}" "Event bus should trigger detection"
}

test_event_bus_integration_handler_error() {
    # Publish error event
    event_bus_publish "handler.error" "handler=Write|error=EACCES|path=/etc/test"

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_not_equals "0" "${count}" "Error event should be captured"
}

test_event_bus_integration_multiple_events() {
    # Publish multiple events
    event_bus_publish "handler.blocked" "operation=dangerous"
    event_bus_publish "handler.error" "error=permission_denied"
    event_bus_publish "handler.blocked" "operation=dangerous"

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_not_equals "0" "${count}" "Multiple events should accumulate"
}

# ============================================================================
# Test Cases - Frustration Storage & Retrieval
# ============================================================================

test_get_frustration_returns_details() {
    local frust_id
    frust_id=$(capture_detect_event "handler.error" "Write" "permission_denied")

    local details
    details=$(capture_get_frustration "${frust_id}")

    assert_not_equals "" "${details}" "Should return frustration details"
    assert_contains "${details}" "Write" "Should contain context"
}

test_get_all_frustrations() {
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"
    capture_detect_event "handler.blocked" "Edit" "op2"

    local all_frustrations
    all_frustrations=$(capture_get_all_frustrations)

    assert_contains "${all_frustrations}" "handler.blocked" "Should contain blocked events"
    assert_contains "${all_frustrations}" "handler.error" "Should contain error events"
}

test_clear_frustrations() {
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"

    capture_clear_frustrations

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_equals "0" "${count}" "Should clear frustration count"
}

# ============================================================================
# Test Cases - Edge Cases
# ============================================================================

test_duplicate_event_detection_prevented() {
    # Detect same event twice in quick succession
    local id1
    id1=$(capture_detect_event "handler.blocked" "Bash" "same_op")
    local id2
    id2=$(capture_detect_event "handler.blocked" "Bash" "same_op")

    # Should create separate entries (not duplicate prevention in detection)
    assert_not_equals "${id1}" "${id2}" "Should create separate frustration entries"
}

test_handles_empty_context() {
    local result
    result=$(capture_detect_event "handler.error" "" "no_context")

    assert_equals "0" "$?" "Should handle empty context gracefully"
}

test_handles_empty_details() {
    local result
    result=$(capture_detect_event "handler.blocked" "Bash" "")

    assert_equals "0" "$?" "Should handle empty details gracefully"
}

test_session_boundary_handling() {
    # Detect event in first session
    capture_detect_event "handler.error" "Bash" "error1"

    # End and start new session
    session_end
    session_start
    capture_engine_init

    # New session should have clean state
    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_equals "0" "${count}" "New session should start with clean state"
}

test_concurrent_event_handling() {
    # Rapidly fire events (simulating concurrent operations)
    for i in {1..5}; do
        capture_detect_event "handler.blocked" "Bash" "op${i}"
    done

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_equals "5" "${count}" "Should handle all events"
}

# ============================================================================
# Test Cases - Reporting & Summary
# ============================================================================

test_generate_summary_report() {
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"
    capture_detect_event "handler.blocked" "Edit" "op2"

    local summary
    summary=$(capture_summary)

    assert_not_equals "" "${summary}" "Should generate summary"
    assert_contains "${summary}" "frustration" "Summary should mention frustrations"
}

test_summary_includes_pattern_analysis() {
    # Create pattern
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"
    capture_detect_event "handler.error" "Bash" "same_error"

    local summary
    summary=$(capture_summary)

    assert_contains "${summary}" "pattern" "Summary should include pattern analysis"
}

test_summary_includes_confidence_level() {
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"

    local summary
    summary=$(capture_summary)

    assert_contains "${summary}" "confidence" "Summary should include confidence level"
}

# ============================================================================
# Test Cases - Reset & Cleanup
# ============================================================================

test_reset_clears_all_state() {
    capture_detect_event "handler.blocked" "Bash" "op1"
    capture_detect_event "handler.error" "Write" "error1"

    capture_engine_reset

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_equals "0" "${count}" "Reset should clear state"
}

test_reset_unsubscribes_from_events() {
    capture_engine_reset

    # After reset, events should not be captured
    event_bus_publish "handler.blocked" "test"

    local count
    count=$(session_get_metric "frustration_count" "0")

    assert_equals "0" "${count}" "Should not capture events after reset"
}

# ============================================================================
# Test Runner
# ============================================================================

main() {
    setup_all

    test_suite "Capture Engine - Frustration Detection & Analysis"

    echo ""
    echo "Testing Initialization..."
    setup; test_case "Capture init succeeds" test_capture_init_succeeds
    setup; test_case "Capture init is idempotent" test_capture_init_is_idempotent
    setup; test_case "Init subscribes to events" test_capture_init_subscribes_to_events
    setup; test_case "Init creates session state" test_capture_init_creates_session_state

    echo ""
    echo "Testing Event Detection..."
    setup; test_case "Detect handler.blocked event" test_detect_handler_blocked_event
    setup; test_case "Detect handler.error event" test_detect_handler_error_event
    setup; test_case "Detect handler.retry event" test_detect_handler_retry_event
    setup; test_case "Detect path.issue event" test_detect_path_issue_event
    setup; test_case "Detect credential exposure" test_detect_credential_exposure_event
    setup; test_case "Detect workaround event" test_detect_workaround_event
    setup; test_case "Detection increments count" test_detect_increments_frustration_count
    setup; test_case "Detection stores details" test_detect_stores_frustration_details

    echo ""
    echo "Testing Pattern Analysis..."
    setup; test_case "Analyze detects repeated errors" test_analyze_pattern_detects_repeated_errors
    setup; test_case "Analyze detects rapid-fire events" test_analyze_pattern_detects_rapid_fire_events
    setup; test_case "Analyze detects workaround sequence" test_analyze_pattern_detects_workaround_sequence
    setup; test_case "Analyze detects path issues" test_analyze_pattern_detects_path_issues_pattern
    setup; test_case "Returns none for single event" test_analyze_pattern_returns_none_for_single_event
    setup; test_case "Ignores old events" test_analyze_pattern_ignores_old_events

    echo ""
    echo "Testing Prompting Decision..."
    setup; test_case "Should prompt after threshold" test_should_prompt_after_threshold_met
    setup; test_case "Should not prompt below threshold" test_should_not_prompt_below_threshold
    setup; test_case "Should prompt for critical pattern" test_should_prompt_for_critical_pattern
    setup; test_case "Should not prompt if recently prompted" test_should_not_prompt_if_recently_prompted
    setup; test_case "Should prompt after cooldown" test_should_prompt_resets_after_cooldown

    echo ""
    echo "Testing Confidence Scoring..."
    setup; test_case "High confidence for repeated pattern" test_confidence_high_for_repeated_pattern
    setup; test_case "Medium confidence for multiple events" test_confidence_medium_for_multiple_events
    setup; test_case "Low confidence for single event" test_confidence_low_for_single_event
    setup; test_case "Critical confidence for security" test_confidence_critical_for_security_issues
    setup; test_case "Confidence considers recency" test_confidence_considers_recency

    echo ""
    echo "Testing Event Bus Integration..."
    setup; test_case "Event bus handler.blocked integration" test_event_bus_integration_handler_blocked
    setup; test_case "Event bus handler.error integration" test_event_bus_integration_handler_error
    setup; test_case "Event bus multiple events" test_event_bus_integration_multiple_events

    echo ""
    echo "Testing Frustration Storage..."
    setup; test_case "Get frustration returns details" test_get_frustration_returns_details
    setup; test_case "Get all frustrations" test_get_all_frustrations
    setup; test_case "Clear frustrations" test_clear_frustrations

    echo ""
    echo "Testing Edge Cases..."
    setup; test_case "Duplicate event detection" test_duplicate_event_detection_prevented
    setup; test_case "Handles empty context" test_handles_empty_context
    setup; test_case "Handles empty details" test_handles_empty_details
    setup; test_case "Session boundary handling" test_session_boundary_handling
    setup; test_case "Concurrent event handling" test_concurrent_event_handling

    echo ""
    echo "Testing Reporting..."
    setup; test_case "Generate summary report" test_generate_summary_report
    setup; test_case "Summary includes pattern analysis" test_summary_includes_pattern_analysis
    setup; test_case "Summary includes confidence" test_summary_includes_confidence_level

    echo ""
    echo "Testing Reset & Cleanup..."
    setup; test_case "Reset clears all state" test_reset_clears_all_state
    setup; test_case "Reset unsubscribes from events" test_reset_unsubscribes_from_events

    teardown_all

    test_summary
}

# Run all tests
main
