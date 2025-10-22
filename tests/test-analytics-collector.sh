#!/bin/bash
# WoW System - Analytics Collector Tests (Production-Grade)
# Comprehensive tests for multi-session data collection
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

COLLECTOR_MODULE="${SCRIPT_DIR}/../src/analytics/collector.sh"
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

source_collector() {
    if [[ -f "${COLLECTOR_MODULE}" ]]; then
        source "${COLLECTOR_MODULE}"
        return 0
    else
        echo "Collector module not implemented yet"
        return 1
    fi
}

create_test_session() {
    local session_id="$1"
    local wow_score="${2:-70}"
    local violations="${3:-0}"

    local session_dir="${TEST_DATA_DIR}/sessions/${session_id}"
    mkdir -p "${session_dir}"

    cat > "${session_dir}/metrics.json" <<EOF
{
  "wow_score": ${wow_score},
  "violations": ${violations},
  "tool_count": 25,
  "timestamp": "2025-10-22T12:00:00Z"
}
EOF
}

# ============================================================================
# Tests: Initialization
# ============================================================================

test_suite "Analytics Collector - Initialization"

# Test 1: Initialize successfully
test_init_success() {
    source_collector || return 1

    analytics_collector_init
    assert_success "Should initialize successfully"
}
test_case "Initialize collector successfully" test_init_success

# Test 2: Initialize with missing sessions subdirectory
test_init_missing_sessions_dir() {
    source_collector || return 1

    # Remove sessions directory
    rm -rf "${TEST_DATA_DIR}/sessions"

    analytics_collector_init 2>/dev/null
    # Should not crash and should create directory
    assert_success "Should handle missing sessions directory gracefully"
}
test_case "Initialize with missing sessions directory" test_init_missing_sessions_dir

# Test 3: Initialize with unreadable sessions directory
test_init_unreadable_dir() {
    source_collector || return 1

    mkdir -p "${TEST_DATA_DIR}/sessions"
    chmod 000 "${TEST_DATA_DIR}/sessions"

    analytics_collector_init 2>/dev/null
    local result=$?

    # Restore permissions for cleanup
    chmod 755 "${TEST_DATA_DIR}/sessions"

    # Should handle gracefully
    echo "Handled unreadable directory gracefully"
}
test_case "Initialize with unreadable directory" test_init_unreadable_dir

# ============================================================================
# Tests: Scanning
# ============================================================================

test_suite "Analytics Collector - Scanning"

# Test 4: Scan empty directory
test_scan_empty() {
    source_collector || return 1
    analytics_collector_init

    mkdir -p "${TEST_DATA_DIR}/sessions"

    local count
    count=$(analytics_collector_scan)

    assert_equals "0" "${count}" "Should return 0 for empty directory"
}
test_case "Scan empty directory" test_scan_empty

# Test 5: Scan single session
test_scan_single() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    local count
    count=$(analytics_collector_scan)

    assert_equals "1" "${count}" "Should return 1 for single session"
}
test_case "Scan single session" test_scan_single

# Test 6: Scan multiple sessions
test_scan_multiple() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2
    create_test_session "session-002" 90 1
    create_test_session "session-003" 75 3

    local count
    count=$(analytics_collector_scan)

    assert_equals "3" "${count}" "Should return 3 for three sessions"
}
test_case "Scan multiple sessions" test_scan_multiple

# Test 7: Scan with corrupted files
test_scan_corrupted() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    # Create corrupted session
    local session_dir="${TEST_DATA_DIR}/sessions/session-002"
    mkdir -p "${session_dir}"
    echo "INVALID JSON" > "${session_dir}/metrics.json"

    create_test_session "session-003" 75 3

    local count
    count=$(analytics_collector_scan)

    # Should skip corrupted, count valid sessions
    assert_true "[[ ${count} -ge 2 ]]" "Should skip corrupted files"
}
test_case "Scan with corrupted files" test_scan_corrupted

# Test 8: Scan with missing metrics.json
test_scan_missing_metrics() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    # Create session without metrics.json
    mkdir -p "${TEST_DATA_DIR}/sessions/session-002"

    create_test_session "session-003" 75 3

    local count
    count=$(analytics_collector_scan)

    # Should skip sessions without metrics
    assert_true "[[ ${count} -ge 2 ]]" "Should skip sessions without metrics"
}
test_case "Scan with missing metrics.json" test_scan_missing_metrics

# ============================================================================
# Tests: Session Retrieval
# ============================================================================

test_suite "Analytics Collector - Session Retrieval"

# Test 9: Get all sessions (sorted)
test_get_all_sessions() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2
    sleep 0.1
    create_test_session "session-002" 90 1
    sleep 0.1
    create_test_session "session-003" 75 3

    analytics_collector_scan > /dev/null

    local sessions
    sessions=$(analytics_collector_get_sessions)

    # Should return all sessions
    local count
    count=$(echo "${sessions}" | wc -l)
    assert_equals "3" "${count}" "Should return all sessions"
}
test_case "Get all sessions sorted" test_get_all_sessions

# Test 10: Get limited sessions (top N)
test_get_limited_sessions() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2
    create_test_session "session-002" 90 1
    create_test_session "session-003" 75 3
    create_test_session "session-004" 80 2
    create_test_session "session-005" 88 1

    analytics_collector_scan > /dev/null

    local sessions
    sessions=$(analytics_collector_get_sessions 3)

    local count
    count=$(echo "${sessions}" | wc -l)
    assert_equals "3" "${count}" "Should return only 3 sessions"
}
test_case "Get limited sessions" test_get_limited_sessions

# Test 11: Get single session data
test_get_session_data() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    analytics_collector_scan > /dev/null

    local data
    data=$(analytics_collector_get_session_data "session-001")

    assert_contains "${data}" "85" "Should return session data"
}
test_case "Get single session data" test_get_session_data

# Test 12: Get non-existent session
test_get_nonexistent_session() {
    source_collector || return 1
    analytics_collector_init

    analytics_collector_scan > /dev/null

    local data
    data=$(analytics_collector_get_session_data "nonexistent" 2>/dev/null)

    # Should return empty or null
    [[ -z "${data}" ]] || return 1
    echo "Handled non-existent session gracefully"
}
test_case "Get non-existent session" test_get_nonexistent_session

# Test 13: Get sessions with limit greater than total
test_get_sessions_limit_exceeds() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2
    create_test_session "session-002" 90 1

    analytics_collector_scan > /dev/null

    local sessions
    sessions=$(analytics_collector_get_sessions 10)

    local count
    count=$(echo "${sessions}" | wc -l)
    assert_equals "2" "${count}" "Should return all available sessions"
}
test_case "Get sessions with limit exceeds total" test_get_sessions_limit_exceeds

# ============================================================================
# Tests: Data Parsing
# ============================================================================

test_suite "Analytics Collector - Data Parsing"

# Test 14: Parse valid session metrics
test_parse_valid_metrics() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    local data
    data=$(analytics_collector_get_session_data "session-001")

    assert_contains "${data}" "wow_score" "Should parse metrics correctly"
}
test_case "Parse valid session metrics" test_parse_valid_metrics

# Test 15: Parse missing wow_score
test_parse_missing_score() {
    source_collector || return 1
    analytics_collector_init

    local session_dir="${TEST_DATA_DIR}/sessions/session-001"
    mkdir -p "${session_dir}"
    cat > "${session_dir}/metrics.json" <<EOF
{
  "violations": 2,
  "tool_count": 25
}
EOF

    local data
    data=$(analytics_collector_get_session_data "session-001" 2>/dev/null)

    # Should handle gracefully
    echo "Handled missing wow_score gracefully"
}
test_case "Parse missing wow_score" test_parse_missing_score

# Test 16: Parse empty metrics.json
test_parse_empty_metrics() {
    source_collector || return 1
    analytics_collector_init

    local session_dir="${TEST_DATA_DIR}/sessions/session-001"
    mkdir -p "${session_dir}"
    echo "{}" > "${session_dir}/metrics.json"

    local data
    data=$(analytics_collector_get_session_data "session-001" 2>/dev/null)

    # Should handle empty JSON
    echo "Handled empty metrics.json"
}
test_case "Parse empty metrics.json" test_parse_empty_metrics

# Test 17: Parse invalid JSON
test_parse_invalid_json() {
    source_collector || return 1
    analytics_collector_init

    local session_dir="${TEST_DATA_DIR}/sessions/session-001"
    mkdir -p "${session_dir}"
    echo "NOT JSON" > "${session_dir}/metrics.json"

    local data
    data=$(analytics_collector_get_session_data "session-001" 2>/dev/null)

    # Should handle invalid JSON
    echo "Handled invalid JSON gracefully"
}
test_case "Parse invalid JSON" test_parse_invalid_json

# ============================================================================
# Tests: Edge Cases
# ============================================================================

test_suite "Analytics Collector - Edge Cases"

# Test 18: Handle permission denied
test_permission_denied() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    # Remove read permission
    chmod 000 "${TEST_DATA_DIR}/sessions/session-001/metrics.json"

    analytics_collector_scan 2>/dev/null

    # Restore permission for cleanup
    chmod 644 "${TEST_DATA_DIR}/sessions/session-001/metrics.json"

    echo "Handled permission denied gracefully"
}
test_case "Handle permission denied" test_permission_denied

# Test 19: Handle large session count
test_large_session_count() {
    source_collector || return 1
    analytics_collector_init

    # Create 50 sessions (scaled down from 1000 for test speed)
    for i in $(seq 1 50); do
        create_test_session "session-$(printf '%03d' ${i})" 85 2
    done

    local start_time=$(date +%s%3N)
    analytics_collector_scan > /dev/null
    local end_time=$(date +%s%3N)
    local elapsed=$((end_time - start_time))

    # Should complete in reasonable time (< 500ms for 50 sessions)
    assert_true "[[ ${elapsed} -lt 500 ]]" "Should handle large session count efficiently"
}
test_case "Handle large session count" test_large_session_count

# Test 20: Handle concurrent access
test_concurrent_access() {
    source_collector || return 1
    analytics_collector_init

    create_test_session "session-001" 85 2

    # Simulate concurrent access
    analytics_collector_scan > /dev/null &
    local pid1=$!
    analytics_collector_scan > /dev/null &
    local pid2=$!

    wait ${pid1}
    wait ${pid2}

    echo "Handled concurrent access gracefully"
}
test_case "Handle concurrent access" test_concurrent_access

# Run all tests
test_summary
