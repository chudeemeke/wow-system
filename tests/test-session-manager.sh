#!/bin/bash
# WoW System - Session Manager Tests
# Tests for session lifecycle management
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

SESSION_MANAGER="${SCRIPT_DIR}/../src/core/session-manager.sh"
TEST_DATA_DIR=""

# ============================================================================
# Test Lifecycle
# ============================================================================

setup_all() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export WOW_HOME="${TEST_DATA_DIR}"
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_session_manager() {
    if [[ -f "${SESSION_MANAGER}" ]]; then
        source "${SESSION_MANAGER}"
        return 0
    else
        echo "Session manager not implemented yet"
        return 1
    fi
}

# ============================================================================
# Tests
# ============================================================================

test_suite "Session Manager"

# Test 1: Session manager exists
test_session_manager_exists() {
    assert_file_exists "${SESSION_MANAGER}" "Session manager should exist"
}
test_case "Session manager file exists" test_session_manager_exists

# Test 2: Start a new session
test_session_start() {
    source_session_manager || return 1
    session_start
    assert_success "Session start should succeed"
}
test_case "Start new session" test_session_start

# Test 3: Get session ID
test_session_get_id() {
    source_session_manager || return 1
    session_start

    local session_id
    session_id=$(session_get_id)

    [[ -n "${session_id}" ]] || return 1
    assert_contains "${session_id}" "session_" "Session ID should have 'session_' prefix"
}
test_case "Get session ID" test_session_get_id

# Test 4: Check session is active
test_session_is_active() {
    source_session_manager || return 1
    session_start

    session_is_active && local active="true" || local active="false"

    assert_equals "true" "${active}" "Session should be active"
}
test_case "Check session is active" test_session_is_active

# Test 5: Get session info
test_session_info() {
    source_session_manager || return 1
    session_start

    local info
    info=$(session_info)

    assert_contains "${info}" "session_id" "Should contain session_id"
    assert_contains "${info}" "started_at" "Should contain started_at"
    assert_contains "${info}" "status" "Should contain status"
}
test_case "Get session info" test_session_info

# Test 6: Track session event
test_session_track_event() {
    source_session_manager || return 1
    session_start

    session_track_event "test_event" "event_data"
    assert_success "Event tracking should succeed"
}
test_case "Track session event" test_session_track_event

# Test 7: Get session events
test_session_get_events() {
    source_session_manager || return 1
    session_start

    session_track_event "event1" "data1"
    session_track_event "event2" "data2"

    local events
    events=$(session_get_events)

    assert_contains "${events}" "event1" "Should contain event1"
    assert_contains "${events}" "event2" "Should contain event2"
}
test_case "Get session events" test_session_get_events

# Test 8: Update session metric
test_session_update_metric() {
    source_session_manager || return 1
    session_start

    session_update_metric "file_operations" "5"
    session_update_metric "bash_commands" "3"

    assert_success "Metric updates should succeed"
}
test_case "Update session metrics" test_session_update_metric

# Test 9: Get session metric
test_session_get_metric() {
    source_session_manager || return 1
    session_start

    session_update_metric "test_metric" "42"

    local value
    value=$(session_get_metric "test_metric")

    assert_equals "42" "${value}" "Should get correct metric value"
}
test_case "Get session metric" test_session_get_metric

# Test 10: Increment session counter
test_session_increment() {
    source_session_manager || return 1
    session_start

    session_increment_metric "counter"
    session_increment_metric "counter"
    session_increment_metric "counter"

    local value
    value=$(session_get_metric "counter")

    assert_equals "3" "${value}" "Counter should be 3"
}
test_case "Increment session counter" test_session_increment

# Test 11: Session duration
test_session_duration() {
    source_session_manager || return 1
    session_start

    sleep 1

    local duration
    duration=$(session_get_duration)

    [[ ${duration} -ge 1 ]] || return 1
    echo "Duration: ${duration}s"
    return 0
}
test_case "Get session duration" test_session_duration

# Test 12: Save session
test_session_save() {
    source_session_manager || return 1
    session_start

    session_update_metric "test_data" "test_value"

    session_save
    assert_success "Session save should succeed"
}
test_case "Save session" test_session_save

# Test 13: Restore session
test_session_restore() {
    source_session_manager || return 1
    session_start

    session_update_metric "persistent_data" "persistent_value"
    session_save

    # Simulate restart
    session_end

    # Restore
    session_restore
    local value
    value=$(session_get_metric "persistent_data")

    assert_equals "persistent_value" "${value}" "Should restore saved data"
}
test_case "Restore session" test_session_restore

# Test 14: End session
test_session_end() {
    source_session_manager || return 1
    session_start

    session_end
    assert_success "Session end should succeed"
}
test_case "End session" test_session_end

# Test 15: Check session not active after end
test_session_not_active_after_end() {
    source_session_manager || return 1
    session_start
    session_end

    session_is_active && local active="true" || local active="false"

    assert_equals "false" "${active}" "Session should not be active after end"
}
test_case "Session not active after end" test_session_not_active_after_end

# Test 16: Get session statistics
test_session_stats() {
    source_session_manager || return 1
    session_start

    session_update_metric "operations" "10"
    session_track_event "test1" "data1"
    session_track_event "test2" "data2"

    local stats
    stats=$(session_stats)

    assert_contains "${stats}" "metrics" "Stats should contain metrics"
    assert_contains "${stats}" "events" "Stats should contain events"
}
test_case "Get session statistics" test_session_stats

# Test 17: Session cleanup on end
test_session_cleanup() {
    source_session_manager || return 1
    session_start

    local session_id
    session_id=$(session_get_id)

    session_update_metric "temp_data" "temp_value"
    session_end

    # Start new session
    session_start

    local new_session_id
    new_session_id=$(session_get_id)

    assert_not_equals "${session_id}" "${new_session_id}" "New session should have different ID"
}
test_case "Session cleanup on end" test_session_cleanup

# Test 18: Multiple sessions
test_multiple_sessions() {
    source_session_manager || return 1

    # First session
    session_start
    local id1
    id1=$(session_get_id)
    session_update_metric "session1_data" "value1"
    session_end

    # Second session
    session_start
    local id2
    id2=$(session_get_id)
    session_update_metric "session2_data" "value2"

    assert_not_equals "${id1}" "${id2}" "Each session should have unique ID"
}
test_case "Handle multiple sessions" test_multiple_sessions

# Test 19: Session archiving
test_session_archive() {
    source_session_manager || return 1
    session_start

    session_update_metric "archived_data" "archived_value"

    session_archive
    assert_success "Session archiving should succeed"
}
test_case "Archive session" test_session_archive

# Test 20: Load configuration during session start
test_session_load_config() {
    source_session_manager || return 1

    # Create a test config file
    local config_file="${TEST_DATA_DIR}/test-config.json"
    echo '{"version": "4.1.0", "test_setting": "test_value"}' > "${config_file}"

    session_start "${config_file}"

    local session_id
    session_id=$(session_get_id)

    [[ -n "${session_id}" ]] || return 1
    assert_success "Session should start with custom config"
}
test_case "Load config during session start" test_session_load_config

# Run all tests
test_summary
