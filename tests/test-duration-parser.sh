#!/bin/bash
# WoW System - Duration Parser Tests (TDD)
# Tests for parsing human-friendly duration formats
# Author: Chude <chude@emeke.org>

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source the duration parser (will be created after tests)
source "${SCRIPT_DIR}/../src/core/duration-parser.sh" 2>/dev/null || true

# ============================================================================
# Duration Parsing Tests (Human-Friendly Format)
# ============================================================================

test_parse_hours_only() {
    local result
    result=$(duration_parse "1h")
    assert_equals "3600" "${result}" "1h should equal 3600 seconds"
}

test_parse_hours_multiple() {
    local result
    result=$(duration_parse "4h")
    assert_equals "14400" "${result}" "4h should equal 14400 seconds"
}

test_parse_minutes_only() {
    local result
    result=$(duration_parse "30m")
    assert_equals "1800" "${result}" "30m should equal 1800 seconds"
}

test_parse_minutes_single() {
    local result
    result=$(duration_parse "5m")
    assert_equals "300" "${result}" "5m should equal 300 seconds"
}

test_parse_combined_hm() {
    local result
    result=$(duration_parse "2h30m")
    assert_equals "9000" "${result}" "2h30m should equal 9000 seconds"
}

test_parse_combined_hm_with_space() {
    local result
    result=$(duration_parse "1h 45m")
    assert_equals "6300" "${result}" "1h 45m should equal 6300 seconds"
}

test_parse_combined_hm_alternate() {
    local result
    result=$(duration_parse "1h15m")
    assert_equals "4500" "${result}" "1h15m should equal 4500 seconds"
}

# ============================================================================
# Duration Parsing Tests (Numeric Format - Minutes)
# ============================================================================

test_parse_numeric_minutes() {
    local result
    result=$(duration_parse "60")
    assert_equals "3600" "${result}" "60 (minutes) should equal 3600 seconds"
}

test_parse_numeric_minutes_small() {
    local result
    result=$(duration_parse "30")
    assert_equals "1800" "${result}" "30 (minutes) should equal 1800 seconds"
}

test_parse_numeric_minutes_large() {
    local result
    result=$(duration_parse "240")
    assert_equals "14400" "${result}" "240 (minutes) should equal 14400 seconds"
}

test_parse_numeric_with_m_suffix() {
    local result
    result=$(duration_parse "120m")
    assert_equals "7200" "${result}" "120m should equal 7200 seconds"
}

# ============================================================================
# Edge Cases and Error Handling
# ============================================================================

test_parse_zero_duration() {
    local result
    result=$(duration_parse "0")
    assert_equals "0" "${result}" "0 should return 0 seconds"
}

test_parse_empty_returns_error() {
    local result
    duration_parse ""
    local exit_code=$?
    assert_equals "1" "${exit_code}" "Empty input should return error"
}

test_parse_invalid_format() {
    local result
    duration_parse "abc"
    local exit_code=$?
    assert_equals "1" "${exit_code}" "Invalid format should return error"
}

test_parse_negative_returns_error() {
    local result
    duration_parse "-30m"
    local exit_code=$?
    assert_equals "1" "${exit_code}" "Negative duration should return error"
}

test_parse_case_insensitive() {
    local result
    result=$(duration_parse "2H30M")
    assert_equals "9000" "${result}" "2H30M should equal 9000 seconds (case insensitive)"
}

test_parse_with_leading_zero() {
    local result
    result=$(duration_parse "01h")
    assert_equals "3600" "${result}" "01h should equal 3600 seconds"
}

# ============================================================================
# Duration Formatting Tests (Seconds to Human)
# ============================================================================

test_format_seconds_to_hours() {
    local result
    result=$(duration_format 3600)
    assert_equals "1h" "${result}" "3600 seconds should format to 1h"
}

test_format_seconds_to_minutes() {
    local result
    result=$(duration_format 1800)
    assert_equals "30m" "${result}" "1800 seconds should format to 30m"
}

test_format_seconds_to_hm() {
    local result
    result=$(duration_format 9000)
    assert_equals "2h 30m" "${result}" "9000 seconds should format to 2h 30m"
}

test_format_seconds_with_remainder() {
    local result
    result=$(duration_format 5400)
    assert_equals "1h 30m" "${result}" "5400 seconds should format to 1h 30m"
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "Duration Parser Tests"

# Human-friendly format
test_case "parse hours only (1h)" test_parse_hours_only
test_case "parse hours multiple (4h)" test_parse_hours_multiple
test_case "parse minutes only (30m)" test_parse_minutes_only
test_case "parse minutes single (5m)" test_parse_minutes_single
test_case "parse combined h+m (2h30m)" test_parse_combined_hm
test_case "parse combined with space (1h 45m)" test_parse_combined_hm_with_space
test_case "parse combined alternate (1h15m)" test_parse_combined_hm_alternate

# Numeric format (minutes)
test_case "parse numeric minutes (60)" test_parse_numeric_minutes
test_case "parse numeric small (30)" test_parse_numeric_minutes_small
test_case "parse numeric large (240)" test_parse_numeric_minutes_large
test_case "parse with m suffix (120m)" test_parse_numeric_with_m_suffix

# Edge cases
test_case "parse zero duration" test_parse_zero_duration
test_case "empty returns error" test_parse_empty_returns_error
test_case "invalid format returns error" test_parse_invalid_format
test_case "negative returns error" test_parse_negative_returns_error
test_case "case insensitive (2H30M)" test_parse_case_insensitive
test_case "leading zero (01h)" test_parse_with_leading_zero

# Formatting
test_case "format seconds to hours" test_format_seconds_to_hours
test_case "format seconds to minutes" test_format_seconds_to_minutes
test_case "format seconds to h+m" test_format_seconds_to_hm
test_case "format with remainder" test_format_seconds_with_remainder

test_summary
