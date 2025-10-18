#!/bin/bash
# WoW System - Stress Test Framework Tests (TDD RED)
# Tests for stress-framework.sh
# Author: Chude <chude@emeke.org>

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source stress framework (under test)
source "${SCRIPT_DIR}/stress/stress-framework.sh"

# ============================================================================
# Test Suite
# ============================================================================

test_suite "Stress Test Framework"

# ============================================================================
# Test Group 1: Initialization
# ============================================================================

test_init_creates_directories() {
    # Setup
    local test_dir="/tmp/stress-test-$$"
    export STRESS_REPORT_DIR="${test_dir}/reports"

    # Execute
    stress_init

    # Assert
    assert_dir_exists "${STRESS_REPORT_DIR}"
    assert_dir_exists "${STRESS_REPORT_DIR}/metrics"
    assert_dir_exists "${STRESS_REPORT_DIR}/logs"
    assert_dir_exists "${STRESS_REPORT_DIR}/summaries"

    # Cleanup
    rm -rf "${test_dir}"
}

test_init_resets_global_state() {
    # Setup
    STRESS_OP_COUNT=999
    STRESS_ERROR_COUNT=999

    # Execute
    stress_init

    # Assert
    assert_equals 0 ${STRESS_OP_COUNT} "Operation count should be reset to 0"
    assert_equals 0 ${STRESS_ERROR_COUNT} "Error count should be reset to 0"
}

test_init_creates_metrics_file() {
    # Setup
    local test_dir="/tmp/stress-test-$$"
    export STRESS_REPORT_DIR="${test_dir}/reports"

    # Execute
    stress_init

    # Assert
    assert_file_exists "${STRESS_METRICS_FILE}"

    # Cleanup
    rm -rf "${test_dir}"
}

# ============================================================================
# Test Group 2: Metrics Collection
# ============================================================================

test_collect_metrics_returns_json() {
    # Setup
    stress_init

    # Execute
    local metrics
    metrics=$(stress_collect_metrics)

    # Assert
    assert_contains "${metrics}" "memory_rss"
    assert_contains "${metrics}" "memory_vsz"
    assert_contains "${metrics}" "cpu_usage"
    assert_contains "${metrics}" "fd_count"
}

test_collect_metrics_has_valid_values() {
    # Setup
    stress_init

    # Execute
    local metrics
    metrics=$(stress_collect_metrics)

    # Extract values
    local memory_rss=$(echo "${metrics}" | grep -oP '"memory_rss":\K\d+')
    local fd_count=$(echo "${metrics}" | grep -oP '"fd_count":\K\d+')

    # Assert (values should be positive integers)
    assert_true "[[ ${memory_rss} -gt 0 ]]" "Memory RSS should be positive"
    assert_true "[[ ${fd_count} -gt 0 ]]" "FD count should be positive"
}

# ============================================================================
# Test Group 3: Operation Recording
# ============================================================================

test_record_increments_operation_count() {
    # Setup
    stress_init

    # Execute
    stress_record "Bash" 1000000 "success"
    stress_record "Write" 2000000 "success"

    # Assert
    assert_equals 2 ${STRESS_OP_COUNT} "Should have recorded 2 operations"
}

test_record_tracks_errors() {
    # Setup
    stress_init

    # Execute
    stress_record "Bash" 1000000 "success"
    stress_record "Write" 2000000 "error"
    stress_record "Edit" 3000000 "error"

    # Assert
    assert_equals 3 ${STRESS_OP_COUNT} "Should have recorded 3 operations"
    assert_equals 2 ${STRESS_ERROR_COUNT} "Should have recorded 2 errors"
}

test_record_calculates_latency_stats() {
    # Setup
    stress_init

    # Execute (record operations with known latencies)
    stress_record "Bash" 1000000 "success"   # 1ms
    stress_record "Bash" 2000000 "success"   # 2ms
    stress_record "Bash" 3000000 "success"   # 3ms
    stress_record "Bash" 4000000 "success"   # 4ms
    stress_record "Bash" 5000000 "success"   # 5ms

    # Assert (mean should be 3ms)
    local mean=$(stress_get_mean_latency)
    assert_equals 3 ${mean} "Mean latency should be 3ms"
}

test_record_tracks_per_tool_metrics() {
    # Setup
    stress_init

    # Execute
    stress_record "Bash" 1000000 "success"
    stress_record "Bash" 2000000 "success"
    stress_record "Write" 3000000 "success"

    # Assert
    local bash_count=$(stress_get_tool_count "Bash")
    local write_count=$(stress_get_tool_count "Write")

    assert_equals 2 ${bash_count} "Bash should have 2 operations"
    assert_equals 1 ${write_count} "Write should have 1 operation"
}

# ============================================================================
# Test Group 4: Validation
# ============================================================================

test_validate_passes_when_criteria_met() {
    # Setup
    stress_init

    # Simulate successful operations
    for i in {1..100}; do
        stress_record "Bash" 1000000 "success"  # 1ms each
    done

    # Execute
    local result
    result=$(stress_validate "latency_p95" "10" "ms")

    # Assert (P95 should be well below 10ms)
    assert_equals "PASS" "${result}"
}

test_validate_fails_when_criteria_not_met() {
    # Setup
    stress_init

    # Simulate slow operations
    for i in {1..100}; do
        stress_record "Bash" 100000000 "success"  # 100ms each
    done

    # Execute
    result=$(stress_validate "latency_p95" "10" "ms")

    # Assert (P95 should be above 10ms)
    assert_equals "FAIL" "${result}"
}

test_validate_checks_error_rate() {
    # Setup
    stress_init

    # Simulate operations with errors
    for i in {1..90}; do
        stress_record "Bash" 1000000 "success"
    done
    for i in {1..10}; do
        stress_record "Bash" 1000000 "error"
    done

    # Execute (expect error rate < 5%)
    result=$(stress_validate "error_rate" "5" "percent")

    # Assert (10% error rate should fail)
    assert_equals "FAIL" "${result}"
}

test_validate_checks_memory_growth() {
    # Setup
    stress_init

    # Record baseline
    local baseline=100000  # 100MB
    STRESS_MEMORY_BASELINE=${baseline}

    # Simulate memory growth
    STRESS_MEMORY_CURRENT=150000  # 150MB (50MB growth)

    # Execute (expect < 100MB growth)
    result=$(stress_validate "memory_growth" "100" "MB")

    # Assert (50MB growth should pass)
    assert_equals "PASS" "${result}"
}

# ============================================================================
# Test Group 5: Reporting
# ============================================================================

test_report_generates_summary() {
    # Setup
    local test_dir="/tmp/stress-test-$$"
    export STRESS_REPORT_DIR="${test_dir}/reports"
    stress_init

    # Simulate operations
    for i in {1..100}; do
        stress_record "Bash" 1000000 "success"
    done

    # Execute
    stress_report "Test Report"

    # Assert
    assert_file_exists "${STRESS_REPORT_DIR}/summaries/Test_Report.txt"

    # Cleanup
    rm -rf "${test_dir}"
}

test_report_includes_key_metrics() {
    # Setup
    local test_dir="/tmp/stress-test-$$"
    export STRESS_REPORT_DIR="${test_dir}/reports"
    stress_init

    # Simulate operations
    for i in {1..100}; do
        stress_record "Bash" 1000000 "success"
    done

    # Execute
    stress_report "Test Report"

    # Read report
    local report_file="${STRESS_REPORT_DIR}/summaries/Test_Report.txt"
    local report_content
    report_content=$(cat "${report_file}")

    # Assert
    assert_contains "${report_content}" "Total Operations"
    assert_contains "${report_content}" "Success Rate"
    assert_contains "${report_content}" "Mean Latency"
    assert_contains "${report_content}" "P95 Latency"
    assert_contains "${report_content}" "P99 Latency"

    # Cleanup
    rm -rf "${test_dir}"
}

test_report_exports_json() {
    # Setup
    local test_dir="/tmp/stress-test-$$"
    export STRESS_REPORT_DIR="${test_dir}/reports"
    stress_init

    # Simulate operations
    for i in {1..100}; do
        stress_record "Bash" 1000000 "success"
    done

    # Execute
    stress_report "Test Report"

    # Assert
    local json_file="${STRESS_REPORT_DIR}/metrics/Test_Report.json"
    assert_file_exists "${json_file}"

    # Validate JSON structure
    local json_content
    json_content=$(cat "${json_file}")
    assert_contains "${json_content}" '"total_operations":'
    assert_contains "${json_content}" '"success_rate":'
    assert_contains "${json_content}" '"latency_stats":'

    # Cleanup
    rm -rf "${test_dir}"
}

# ============================================================================
# Test Group 6: Edge Cases
# ============================================================================

test_handles_zero_operations() {
    # Setup
    stress_init

    # Execute (no operations recorded)
    local result
    result=$(stress_get_mean_latency)

    # Assert
    assert_equals 0 ${result} "Mean latency should be 0 when no operations"
}

test_handles_all_errors() {
    # Setup
    stress_init

    # Execute (all operations fail)
    for i in {1..100}; do
        stress_record "Bash" 1000000 "error"
    done

    # Assert
    local error_rate=$(stress_get_error_rate)
    assert_equals 100 ${error_rate} "Error rate should be 100%"
}

test_cleanup_removes_temp_files() {
    # Setup
    local test_dir="/tmp/stress-test-$$"
    export STRESS_REPORT_DIR="${test_dir}/reports"
    stress_init

    # Execute
    stress_cleanup

    # Assert (temp files should be removed, but reports kept)
    assert_dir_exists "${STRESS_REPORT_DIR}"
    # Metrics buffer should be cleared
    assert_equals 0 ${#STRESS_LATENCIES[@]} "Latency array should be cleared"
}

# ============================================================================
# Register Tests
# ============================================================================

# Group 1: Initialization
test_case "Initialization creates directories" test_init_creates_directories
test_case "Initialization resets global state" test_init_resets_global_state
test_case "Initialization creates metrics file" test_init_creates_metrics_file

# Group 2: Metrics Collection
test_case "Metrics collection returns JSON" test_collect_metrics_returns_json
test_case "Metrics collection has valid values" test_collect_metrics_has_valid_values

# Group 3: Operation Recording
test_case "Record increments operation count" test_record_increments_operation_count
test_case "Record tracks errors" test_record_tracks_errors
test_case "Record calculates latency stats" test_record_calculates_latency_stats
test_case "Record tracks per-tool metrics" test_record_tracks_per_tool_metrics

# Group 4: Validation
test_case "Validate passes when criteria met" test_validate_passes_when_criteria_met
test_case "Validate fails when criteria not met" test_validate_fails_when_criteria_not_met
test_case "Validate checks error rate" test_validate_checks_error_rate
test_case "Validate checks memory growth" test_validate_checks_memory_growth

# Group 5: Reporting
test_case "Report generates summary" test_report_generates_summary
test_case "Report includes key metrics" test_report_includes_key_metrics
test_case "Report exports JSON" test_report_exports_json

# Group 6: Edge Cases
test_case "Handles zero operations" test_handles_zero_operations
test_case "Handles all errors" test_handles_all_errors
test_case "Cleanup removes temp files" test_cleanup_removes_temp_files

# Run tests
test_summary
