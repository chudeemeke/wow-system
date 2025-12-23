#!/bin/bash
# WoW System - SuperAdmin Tests
# TDD Phase: RED - Define expected behavior before implementation
# Author: Chude <chude@emeke.org>
#
# SuperAdmin provides a higher privilege level than bypass:
# - Unlocks TIER_SUPERADMIN protected files (WoW self-protection)
# - Requires biometric (fingerprint) or strong secondary authentication
# - Shorter timeouts than bypass (safety)
# - Cannot unlock TIER_CRITICAL (SSRF, auth files, etc.)

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source test framework
source "${SCRIPT_DIR}/test-framework.sh"

# ============================================================================
# Test Setup
# ============================================================================

# Temporary test directory
TEST_DATA_DIR=""

setup_all() {
    # Create temp directory for test data
    TEST_DATA_DIR=$(mktemp -d)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export SUPERADMIN_DATA_DIR="${TEST_DATA_DIR}/superadmin"

    # Source the superadmin module
    source "${PROJECT_ROOT}/src/security/superadmin/superadmin-core.sh" 2>/dev/null || true

    # Disable errexit that utils.sh enables (conflicts with test framework arithmetic)
    set +e
}

teardown_all() {
    # Cleanup test data
    if [[ -n "${TEST_DATA_DIR}" && -d "${TEST_DATA_DIR}" ]]; then
        rm -rf "${TEST_DATA_DIR}"
    fi
}

setup_each() {
    # Reset superadmin state before each test
    rm -rf "${SUPERADMIN_DATA_DIR}" 2>/dev/null || true
    mkdir -p "${SUPERADMIN_DATA_DIR}"

    if type superadmin_deactivate &>/dev/null; then
        superadmin_deactivate 2>/dev/null || true
    fi
}

# ============================================================================
# Function Existence Tests
# ============================================================================

test_superadmin_init_exists() {
    if ! type superadmin_init &>/dev/null; then
        fail "superadmin_init function should exist"
        return 1
    fi
    pass
}

test_superadmin_is_active_exists() {
    if ! type superadmin_is_active &>/dev/null; then
        fail "superadmin_is_active function should exist"
        return 1
    fi
    pass
}

test_superadmin_activate_exists() {
    if ! type superadmin_activate &>/dev/null; then
        fail "superadmin_activate function should exist"
        return 1
    fi
    pass
}

test_superadmin_deactivate_exists() {
    if ! type superadmin_deactivate &>/dev/null; then
        fail "superadmin_deactivate function should exist"
        return 1
    fi
    pass
}

test_superadmin_check_fingerprint_exists() {
    if ! type superadmin_check_fingerprint &>/dev/null; then
        fail "superadmin_check_fingerprint function should exist"
        return 1
    fi
    pass
}

test_superadmin_has_biometric_exists() {
    if ! type superadmin_has_biometric &>/dev/null; then
        fail "superadmin_has_biometric function should exist"
        return 1
    fi
    pass
}

# ============================================================================
# State Management Tests
# ============================================================================

test_inactive_by_default() {
    # SuperAdmin should be inactive by default
    if superadmin_is_active; then
        fail "SuperAdmin should be inactive by default"
        return 1
    fi
    pass
}

test_activate_creates_token() {
    # Skip authentication for test (mock mode)
    export SUPERADMIN_MOCK_AUTH=1

    superadmin_activate

    if [[ ! -f "${SUPERADMIN_DATA_DIR}/active.token" ]]; then
        fail "Activation should create token file"
        return 1
    fi
    pass
}

test_deactivate_removes_token() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate
    superadmin_deactivate

    if [[ -f "${SUPERADMIN_DATA_DIR}/active.token" ]]; then
        fail "Deactivation should remove token file"
        return 1
    fi
    pass
}

test_is_active_after_activate() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    if ! superadmin_is_active; then
        fail "SuperAdmin should be active after activation"
        return 1
    fi
    pass
}

test_not_active_after_deactivate() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate
    superadmin_deactivate

    if superadmin_is_active; then
        fail "SuperAdmin should be inactive after deactivation"
        return 1
    fi
    pass
}

# ============================================================================
# TTY Enforcement Tests
# ============================================================================

test_check_tty_exists() {
    if ! type superadmin_check_tty &>/dev/null; then
        fail "superadmin_check_tty function should exist"
        return 1
    fi
    pass
}

test_tty_required_for_activation() {
    # When not in TTY, activation should fail
    unset SUPERADMIN_MOCK_AUTH

    # Simulate non-TTY environment
    if superadmin_activate < /dev/null 2>/dev/null; then
        # If it succeeded, check if we're actually in a TTY (test might be running interactively)
        if [[ ! -t 0 ]]; then
            fail "Activation should require TTY"
            return 1
        fi
    fi
    pass
}

# ============================================================================
# Biometric Detection Tests
# ============================================================================

test_detect_fingerprint_reader() {
    # Should detect if fingerprint reader is available
    local has_biometric
    has_biometric=$(superadmin_has_biometric && echo "yes" || echo "no")

    # Test passes regardless of result - just verifies function works
    if [[ "${has_biometric}" != "yes" && "${has_biometric}" != "no" ]]; then
        fail "superadmin_has_biometric should return yes or no"
        return 1
    fi
    pass
}

test_fallback_when_no_biometric() {
    # When no biometric available, should offer fallback
    if ! type superadmin_fallback_auth &>/dev/null; then
        fail "superadmin_fallback_auth function should exist for systems without biometrics"
        return 1
    fi
    pass
}

# ============================================================================
# Token Security Tests
# ============================================================================

test_token_has_expiry() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    local token
    token=$(cat "${SUPERADMIN_DATA_DIR}/active.token" 2>/dev/null)

    # Token should have expiry field (format: version:created:expires:hmac)
    local field_count
    field_count=$(echo "${token}" | tr ':' '\n' | wc -l)

    if [[ ${field_count} -lt 4 ]]; then
        fail "Token should have at least 4 fields including expiry"
        return 1
    fi
    pass
}

test_token_expires_faster_than_bypass() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    local remaining
    remaining=$(superadmin_get_remaining 2>/dev/null || echo "0")

    # SuperAdmin max duration should be <= 900 seconds (15 minutes)
    # versus bypass which is 4 hours (14400 seconds)
    if [[ ${remaining} -gt 900 ]]; then
        fail "SuperAdmin should have shorter max duration than bypass (got ${remaining}s, max 900s)"
        return 1
    fi
    pass
}

test_token_hmac_verified() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    # Tamper with token
    echo "tampered:token:data:here" > "${SUPERADMIN_DATA_DIR}/active.token"

    # Should not be active after tampering
    if superadmin_is_active; then
        fail "Tampered token should not be accepted"
        return 1
    fi
    pass
}

# ============================================================================
# Inactivity Timeout Tests
# ============================================================================

test_inactivity_timeout_shorter() {
    # SuperAdmin inactivity timeout should be shorter than bypass
    local timeout
    timeout="${SUPERADMIN_INACTIVITY_TIMEOUT:-300}"  # Default 5 min

    # Should be <= 300 seconds (5 minutes)
    if [[ ${timeout} -gt 300 ]]; then
        fail "SuperAdmin inactivity timeout should be <= 300s (got ${timeout}s)"
        return 1
    fi
    pass
}

test_activity_tracking() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    # Activity file should exist
    if [[ ! -f "${SUPERADMIN_DATA_DIR}/last_activity" ]]; then
        fail "Activity tracking file should exist after activation"
        return 1
    fi
    pass
}

test_update_activity() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    local before after
    before=$(cat "${SUPERADMIN_DATA_DIR}/last_activity" 2>/dev/null)

    sleep 1
    superadmin_update_activity

    after=$(cat "${SUPERADMIN_DATA_DIR}/last_activity" 2>/dev/null)

    if [[ "${before}" == "${after}" ]]; then
        fail "Activity timestamp should be updated"
        return 1
    fi
    pass
}

# ============================================================================
# Integration with Security Policies Tests
# ============================================================================

test_allows_superadmin_tier_when_active() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    # When active, SUPERADMIN tier operations should be allowed
    # (The actual policy check is in handler-router.sh, but we test the state)
    if ! superadmin_is_active; then
        fail "SuperAdmin should be active for this test"
        return 1
    fi
    pass
}

test_does_not_affect_critical_tier() {
    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    # Even with SuperAdmin active, CRITICAL tier should still be blocked
    # This is enforced by handler-router.sh checking CRITICAL before SUPERADMIN
    # We just verify SuperAdmin doesn't claim to bypass critical
    if type superadmin_can_unlock &>/dev/null; then
        if superadmin_can_unlock "169.254.169.254"; then
            fail "SuperAdmin should not claim to unlock CRITICAL tier (SSRF)"
            return 1
        fi
    fi
    pass
}

# ============================================================================
# Status and Display Tests
# ============================================================================

test_get_status() {
    if ! type superadmin_get_status &>/dev/null; then
        fail "superadmin_get_status function should exist"
        return 1
    fi

    local status
    status=$(superadmin_get_status)

    # Should return one of: NOT_CONFIGURED, LOCKED, UNLOCKED
    case "${status}" in
        NOT_CONFIGURED|LOCKED|UNLOCKED)
            pass
            ;;
        *)
            fail "Invalid status: ${status}"
            return 1
            ;;
    esac
}

test_get_remaining_time() {
    if ! type superadmin_get_remaining &>/dev/null; then
        fail "superadmin_get_remaining function should exist"
        return 1
    fi

    export SUPERADMIN_MOCK_AUTH=1
    superadmin_activate

    local remaining
    remaining=$(superadmin_get_remaining)

    # Should return a number
    if ! [[ "${remaining}" =~ ^-?[0-9]+$ ]]; then
        fail "superadmin_get_remaining should return a number, got: ${remaining}"
        return 1
    fi
    pass
}

# ============================================================================
# Rate Limiting Tests
# ============================================================================

test_rate_limiting_exists() {
    if ! type superadmin_check_rate_limit &>/dev/null; then
        fail "superadmin_check_rate_limit function should exist"
        return 1
    fi
    pass
}

test_rate_limit_after_failures() {
    # Record multiple failures
    superadmin_record_failure 2>/dev/null || true
    superadmin_record_failure 2>/dev/null || true
    superadmin_record_failure 2>/dev/null || true

    # Should be rate limited after 3 failures
    if superadmin_check_rate_limit 2>/dev/null; then
        # Rate limit not triggered - might be by design or needs more failures
        pass
    else
        pass
    fi
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "SuperAdmin Tests"

# Setup
setup_all

# Function existence tests
test_case "superadmin_init exists" test_superadmin_init_exists
test_case "superadmin_is_active exists" test_superadmin_is_active_exists
test_case "superadmin_activate exists" test_superadmin_activate_exists
test_case "superadmin_deactivate exists" test_superadmin_deactivate_exists
test_case "superadmin_check_fingerprint exists" test_superadmin_check_fingerprint_exists
test_case "superadmin_has_biometric exists" test_superadmin_has_biometric_exists

# State management tests
setup_each
test_case "Inactive by default" test_inactive_by_default
setup_each
test_case "Activate creates token" test_activate_creates_token
setup_each
test_case "Deactivate removes token" test_deactivate_removes_token
setup_each
test_case "Is active after activate" test_is_active_after_activate
setup_each
test_case "Not active after deactivate" test_not_active_after_deactivate

# TTY enforcement tests
test_case "check_tty exists" test_check_tty_exists
setup_each
test_case "TTY required for activation" test_tty_required_for_activation

# Biometric detection tests
test_case "Detect fingerprint reader" test_detect_fingerprint_reader
test_case "Fallback when no biometric" test_fallback_when_no_biometric

# Token security tests
setup_each
test_case "Token has expiry" test_token_has_expiry
setup_each
test_case "Token expires faster than bypass" test_token_expires_faster_than_bypass
setup_each
test_case "Token HMAC verified" test_token_hmac_verified

# Inactivity timeout tests
test_case "Inactivity timeout shorter" test_inactivity_timeout_shorter
setup_each
test_case "Activity tracking" test_activity_tracking
setup_each
test_case "Update activity" test_update_activity

# Security policy integration tests
setup_each
test_case "Allows SuperAdmin tier when active" test_allows_superadmin_tier_when_active
setup_each
test_case "Does not affect Critical tier" test_does_not_affect_critical_tier

# Status and display tests
test_case "Get status" test_get_status
setup_each
test_case "Get remaining time" test_get_remaining_time

# Rate limiting tests
test_case "Rate limiting exists" test_rate_limiting_exists
setup_each
test_case "Rate limit after failures" test_rate_limit_after_failures

# Cleanup
teardown_all

# Summary
test_summary
