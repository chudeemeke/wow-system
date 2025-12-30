#!/bin/bash
# WoW System - Interactive Duration Tests (TDD)
# Tests for duration confirmation and user interaction
# Author: Chude <chude@emeke.org>

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source the modules
source "${SCRIPT_DIR}/../src/core/duration-parser.sh"
source "${SCRIPT_DIR}/../src/core/interactive-duration.sh" 2>/dev/null || true

# ============================================================================
# Duration Argument Parsing Tests
# ============================================================================

test_duration_arg_provided() {
    local result
    result=$(duration_resolve_arg "2h" "bypass")
    assert_equals "7200" "${result}" "2h arg should return 7200 seconds"
}

test_duration_arg_minutes() {
    local result
    result=$(duration_resolve_arg "30m" "bypass")
    assert_equals "1800" "${result}" "30m arg should return 1800 seconds"
}

test_duration_arg_combined() {
    local result
    result=$(duration_resolve_arg "1h30m" "bypass")
    assert_equals "5400" "${result}" "1h30m arg should return 5400 seconds"
}

test_duration_arg_numeric() {
    local result
    result=$(duration_resolve_arg "60" "bypass")
    assert_equals "3600" "${result}" "60 (minutes) arg should return 3600 seconds"
}

# ============================================================================
# Default Duration Tests
# ============================================================================

test_bypass_default_duration() {
    local result
    result=$(duration_get_default "bypass")
    assert_equals "14400" "${result}" "Bypass default should be 14400s (4h)"
}

test_superadmin_default_duration() {
    local result
    result=$(duration_get_default "superadmin")
    assert_equals "1200" "${result}" "Superadmin default should be 1200s (20m)"
}

# ============================================================================
# Inactivity Timeout Ratio Tests
# ============================================================================

test_bypass_inactivity_ratio() {
    local main_duration=14400  # 4h
    local result
    result=$(duration_calculate_inactivity "${main_duration}" "bypass")
    assert_equals "1800" "${result}" "Bypass 4h should have 30m inactivity (1:8 ratio)"
}

test_bypass_inactivity_ratio_2h() {
    local main_duration=7200  # 2h
    local result
    result=$(duration_calculate_inactivity "${main_duration}" "bypass")
    assert_equals "900" "${result}" "Bypass 2h should have 15m inactivity (1:8 ratio)"
}

test_superadmin_inactivity_ratio() {
    local main_duration=1200  # 20m
    local result
    result=$(duration_calculate_inactivity "${main_duration}" "superadmin")
    assert_equals "300" "${result}" "Superadmin 20m should have 5m inactivity (1:4 ratio)"
}

test_superadmin_inactivity_ratio_1h() {
    local main_duration=3600  # 1h
    local result
    result=$(duration_calculate_inactivity "${main_duration}" "superadmin")
    assert_equals "900" "${result}" "Superadmin 1h should have 15m inactivity (1:4 ratio)"
}

# ============================================================================
# Confirmation Message Tests
# ============================================================================

test_confirmation_message_bypass() {
    local result
    result=$(duration_format_confirmation 7200 "bypass")
    assert_contains "${result}" "2h" "Confirmation should show 2h"
    assert_contains "${result}" "bypass" "Confirmation should mention bypass"
}

test_confirmation_message_superadmin() {
    local result
    result=$(duration_format_confirmation 1800 "superadmin")
    assert_contains "${result}" "30m" "Confirmation should show 30m"
    assert_contains "${result}" "superadmin" "Confirmation should mention superadmin"
}

test_confirmation_shows_inactivity() {
    local result
    result=$(duration_format_confirmation 7200 "bypass")
    # 7200s bypass = 900s (15m) inactivity
    assert_contains "${result}" "15m" "Should show inactivity timeout"
}

# ============================================================================
# User Input Validation Tests
# ============================================================================

test_validate_user_duration_valid() {
    local result
    duration_validate_user_input "2h"
    result=$?
    assert_equals "0" "${result}" "Valid input should return 0"
}

test_validate_user_duration_invalid() {
    duration_validate_user_input "abc"
    local result=$?
    assert_equals "1" "${result}" "Invalid input should return 1"
}

test_validate_user_duration_empty_ok() {
    duration_validate_user_input ""
    local result=$?
    assert_equals "0" "${result}" "Empty input (default) should be OK"
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "Interactive Duration Tests"

# Duration argument parsing
test_case "duration arg provided (2h)" test_duration_arg_provided
test_case "duration arg minutes (30m)" test_duration_arg_minutes
test_case "duration arg combined (1h30m)" test_duration_arg_combined
test_case "duration arg numeric (60)" test_duration_arg_numeric

# Default durations
test_case "bypass default duration (4h)" test_bypass_default_duration
test_case "superadmin default duration (20m)" test_superadmin_default_duration

# Inactivity ratio calculation
test_case "bypass inactivity ratio (4h->30m)" test_bypass_inactivity_ratio
test_case "bypass inactivity ratio (2h->15m)" test_bypass_inactivity_ratio_2h
test_case "superadmin inactivity ratio (20m->5m)" test_superadmin_inactivity_ratio
test_case "superadmin inactivity ratio (1h->15m)" test_superadmin_inactivity_ratio_1h

# Confirmation messages
test_case "confirmation message bypass" test_confirmation_message_bypass
test_case "confirmation message superadmin" test_confirmation_message_superadmin
test_case "confirmation shows inactivity" test_confirmation_shows_inactivity

# User input validation
test_case "validate valid user duration" test_validate_user_duration_valid
test_case "validate invalid user duration" test_validate_user_duration_invalid
test_case "validate empty input (use default)" test_validate_user_duration_empty_ok

test_summary
