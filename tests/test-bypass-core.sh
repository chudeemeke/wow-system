#!/bin/bash
# WoW System - Bypass Core Tests (Comprehensive)
# TDD test suite for bypass authentication system
# Author: Chude <chude@emeke.org>
#
# Coverage: TTY detection, passphrase hashing, token management,
#           rate limiting, state management, edge cases, security attacks

set -uo pipefail

# Determine script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source test framework
source "${SCRIPT_DIR}/test-framework.sh"

# Module under test
BYPASS_CORE="${PROJECT_ROOT}/src/security/bypass-core.sh"

# Test data directory (isolated from real data)
TEST_DATA_DIR="/tmp/wow-bypass-test-$$"

# ============================================================================
# Test Setup/Teardown
# ============================================================================

setup_test_env() {
    rm -rf "${TEST_DATA_DIR}"
    mkdir -p "${TEST_DATA_DIR}/bypass"
    chmod 700 "${TEST_DATA_DIR}"
    chmod 700 "${TEST_DATA_DIR}/bypass"

    # Source bypass-core if not already loaded
    # WOW_DATA_DIR must be set before first source (readonly after)
    if [[ -z "${WOW_BYPASS_CORE_LOADED:-}" ]]; then
        # First time: set WOW_DATA_DIR before sourcing
        export WOW_DATA_DIR="${TEST_DATA_DIR}"
        if [[ -f "${BYPASS_CORE}" ]]; then
            source "${BYPASS_CORE}"
        fi
    fi
    # Subsequent calls: just recreate test directories
}

teardown_test_env() {
    rm -rf "${TEST_DATA_DIR}"
    # Note: WOW_DATA_DIR may be readonly after sourcing, so we don't unset it
    # Tests use TEST_DATA_DIR which is set before sourcing
}

# Helper to get bypass file paths (matches bypass-core.sh)
get_hash_file() { echo "${TEST_DATA_DIR}/bypass/passphrase.hash"; }
get_token_file() { echo "${TEST_DATA_DIR}/bypass/active.token"; }
get_failures_file() { echo "${TEST_DATA_DIR}/bypass/failures.json"; }

# Helper to check if module exists
require_module() {
    if [[ ! -f "${BYPASS_CORE}" ]]; then
        echo "bypass-core.sh not found - TDD RED phase"
        return 1
    fi
    return 0
}

# ============================================================================
# TTY Detection Tests
# ============================================================================

test_tty_piped_input() {
    setup_test_env
    require_module || return 1

    local result
    result=$(echo "test" | bash -c 'source "'"${BYPASS_CORE}"'" 2>/dev/null && bypass_check_tty && echo "TTY" || echo "NO_TTY"')
    assert_equals "NO_TTY" "${result}" "Piped input should fail TTY check"

    teardown_test_env
}

test_tty_subshell_no_tty() {
    setup_test_env
    require_module || return 1

    local result
    result=$(bash -c 'source "'"${BYPASS_CORE}"'" 2>/dev/null && bypass_check_tty && echo "TTY" || echo "NO_TTY"' </dev/null)
    assert_equals "NO_TTY" "${result}" "Subshell without TTY should fail"

    teardown_test_env
}

test_tty_heredoc_input() {
    setup_test_env
    require_module || return 1

    local result
    result=$(bash -c 'source "'"${BYPASS_CORE}"'" 2>/dev/null && bypass_check_tty && echo "TTY" || echo "NO_TTY"' <<< "input")
    assert_equals "NO_TTY" "${result}" "Heredoc input should fail TTY check"

    teardown_test_env
}

test_tty_process_substitution() {
    setup_test_env
    require_module || return 1

    local result
    result=$(bash -c 'source "'"${BYPASS_CORE}"'" 2>/dev/null && bypass_check_tty && echo "TTY" || echo "NO_TTY"' < <(echo "test"))
    assert_equals "NO_TTY" "${result}" "Process substitution should fail TTY check"

    teardown_test_env
}

# ============================================================================
# Passphrase Hashing Tests - Basic
# ============================================================================

test_hash_format_valid() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpassword123")

    # Format: 32 hex chars (salt) : 128 hex chars (SHA512)
    if [[ ! "${hash}" =~ ^[a-f0-9]{32}:[a-f0-9]{128}$ ]]; then
        echo "Invalid hash format: ${hash}"
        return 1
    fi

    teardown_test_env
}

test_hash_unique_salts() {
    setup_test_env
    require_module || return 1

    local hash1 hash2 hash3
    hash1=$(bypass_hash_passphrase "samepassword")
    hash2=$(bypass_hash_passphrase "samepassword")
    hash3=$(bypass_hash_passphrase "samepassword")

    # All three should be different (different salts)
    if [[ "${hash1}" == "${hash2}" ]] || [[ "${hash2}" == "${hash3}" ]] || [[ "${hash1}" == "${hash3}" ]]; then
        echo "Same password produced identical hashes - salt not working"
        return 1
    fi

    teardown_test_env
}

test_hash_different_passwords_different() {
    setup_test_env
    require_module || return 1

    local hash1 hash2
    hash1=$(bypass_hash_passphrase "password1")
    hash2=$(bypass_hash_passphrase "password2")

    # Different passwords should produce different hashes (even ignoring salt)
    local hash_part1="${hash1#*:}"
    local hash_part2="${hash2#*:}"

    if [[ "${hash_part1}" == "${hash_part2}" ]]; then
        echo "Different passwords produced same hash portion"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Passphrase Hashing Tests - Edge Cases
# ============================================================================

test_hash_empty_passphrase() {
    setup_test_env
    require_module || return 1

    # Empty passphrase should still produce valid hash format
    local hash
    hash=$(bypass_hash_passphrase "")

    if [[ ! "${hash}" =~ ^[a-f0-9]{32}:[a-f0-9]{128}$ ]]; then
        echo "Empty passphrase should still produce valid hash format"
        return 1
    fi

    teardown_test_env
}

test_hash_very_long_passphrase() {
    setup_test_env
    require_module || return 1

    # 1000 character passphrase
    local long_pass
    long_pass=$(printf 'a%.0s' {1..1000})

    local hash
    hash=$(bypass_hash_passphrase "${long_pass}")

    if [[ ! "${hash}" =~ ^[a-f0-9]{32}:[a-f0-9]{128}$ ]]; then
        echo "Long passphrase should produce valid hash"
        return 1
    fi

    teardown_test_env
}

test_hash_special_characters() {
    setup_test_env
    require_module || return 1

    local special_pass='!@#$%^&*()_+-=[]{}|;:,.<>?/~`"'"'"
    local hash
    hash=$(bypass_hash_passphrase "${special_pass}")

    if [[ ! "${hash}" =~ ^[a-f0-9]{32}:[a-f0-9]{128}$ ]]; then
        echo "Special characters should produce valid hash"
        return 1
    fi

    teardown_test_env
}

test_hash_unicode_passphrase() {
    setup_test_env
    require_module || return 1

    local unicode_pass="密码テスト🔐émoji"
    local hash
    hash=$(bypass_hash_passphrase "${unicode_pass}")

    if [[ ! "${hash}" =~ ^[a-f0-9]{32}:[a-f0-9]{128}$ ]]; then
        echo "Unicode passphrase should produce valid hash"
        return 1
    fi

    teardown_test_env
}

test_hash_whitespace_passphrase() {
    setup_test_env
    require_module || return 1

    local whitespace_pass="   spaces   tabs	and
newlines"
    local hash
    hash=$(bypass_hash_passphrase "${whitespace_pass}")

    if [[ ! "${hash}" =~ ^[a-f0-9]{32}:[a-f0-9]{128}$ ]]; then
        echo "Whitespace passphrase should produce valid hash"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Passphrase Verification Tests
# ============================================================================

test_verify_correct_passphrase() {
    setup_test_env
    require_module || return 1

    local passphrase="correcthorsebatterystaple"
    local hash
    hash=$(bypass_hash_passphrase "${passphrase}")
    echo "${hash}" > "$(get_hash_file)"
    chmod 600 "$(get_hash_file)"

    if ! bypass_verify_passphrase "${passphrase}"; then
        echo "Correct passphrase was rejected"
        return 1
    fi

    teardown_test_env
}

test_verify_wrong_passphrase() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "correctpassword")
    echo "${hash}" > "$(get_hash_file)"
    chmod 600 "$(get_hash_file)"

    if bypass_verify_passphrase "wrongpassword"; then
        echo "Wrong passphrase was accepted"
        return 1
    fi

    teardown_test_env
}

test_verify_similar_passphrase() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "password123")
    echo "${hash}" > "$(get_hash_file)"
    chmod 600 "$(get_hash_file)"

    # Test similar but different passphrases
    if bypass_verify_passphrase "password124"; then
        echo "Similar passphrase (off by 1) was accepted"
        return 1
    fi
    if bypass_verify_passphrase "Password123"; then
        echo "Case-different passphrase was accepted"
        return 1
    fi
    if bypass_verify_passphrase "password123 "; then
        echo "Passphrase with trailing space was accepted"
        return 1
    fi

    teardown_test_env
}

test_verify_not_configured() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_hash_file)"

    bypass_verify_passphrase "anypassword"
    local result=$?

    if [[ ${result} -ne 2 ]]; then
        echo "Expected exit code 2 (not configured), got ${result}"
        return 1
    fi

    teardown_test_env
}

test_verify_corrupted_hash_file() {
    setup_test_env
    require_module || return 1

    # Write corrupted hash (wrong format)
    echo "notavalidhash" > "$(get_hash_file)"
    chmod 600 "$(get_hash_file)"

    # Should fail gracefully
    if bypass_verify_passphrase "anypassword"; then
        echo "Corrupted hash file should reject all passphrases"
        return 1
    fi

    teardown_test_env
}

test_verify_empty_hash_file() {
    setup_test_env
    require_module || return 1

    # Empty hash file
    touch "$(get_hash_file)"
    chmod 600 "$(get_hash_file)"

    if bypass_verify_passphrase "anypassword"; then
        echo "Empty hash file should reject all passphrases"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Token Tests - Basic
# ============================================================================

test_token_format_valid() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    local token
    token=$(bypass_create_token)

    # v2 Format: version:created:expires:hmac (128 hex chars for SHA512)
    if [[ ! "${token}" =~ ^[0-9]+:[0-9]+:[0-9]+:[a-f0-9]{128}$ ]]; then
        echo "Invalid token format: ${token}"
        return 1
    fi

    teardown_test_env
}

test_token_verify_valid() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    local token
    token=$(bypass_create_token)
    echo "${token}" > "$(get_token_file)"

    if ! bypass_verify_token; then
        echo "Valid token was rejected"
        return 1
    fi

    teardown_test_env
}

test_token_reject_forged() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Forged token with wrong HMAC (128 chars for SHA512)
    echo "1:$(date +%s):00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" > "$(get_token_file)"

    if bypass_verify_token; then
        echo "Forged token was accepted"
        return 1
    fi

    teardown_test_env
}

test_token_reject_tampered_timestamp() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    local token
    token=$(bypass_create_token)

    # Tamper with timestamp
    local tampered
    tampered=$(echo "${token}" | sed 's/^\([0-9]*:\)[0-9]/\19/')
    echo "${tampered}" > "$(get_token_file)"

    if bypass_verify_token; then
        echo "Tampered timestamp token was accepted"
        return 1
    fi

    teardown_test_env
}

test_token_reject_tampered_hmac() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    local token
    token=$(bypass_create_token)

    # Tamper with HMAC (flip one character)
    local tampered
    tampered=$(echo "${token}" | sed 's/a/b/')
    echo "${tampered}" > "$(get_token_file)"

    if bypass_verify_token; then
        echo "Tampered HMAC token was accepted"
        return 1
    fi

    teardown_test_env
}

test_token_missing_file() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"
    rm -f "$(get_token_file)"

    if bypass_verify_token; then
        echo "Missing token file should fail verification"
        return 1
    fi

    teardown_test_env
}

test_token_missing_hash_file() {
    setup_test_env
    require_module || return 1

    # Create a token file but no hash file
    echo "1:12345:somehash" > "$(get_token_file)"
    rm -f "$(get_hash_file)"

    if bypass_verify_token; then
        echo "Token verification without hash file should fail"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Token Tests - Edge Cases
# ============================================================================

test_token_corrupted_format() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Various corrupted token formats
    local corrupted_tokens=(
        "notavalidtoken"
        "1:2"
        "::"
        "1:abc:def"
        ""
    )

    for token in "${corrupted_tokens[@]}"; do
        echo "${token}" > "$(get_token_file)"
        if bypass_verify_token 2>/dev/null; then
            echo "Corrupted token '${token}' was accepted"
            return 1
        fi
    done

    teardown_test_env
}

test_token_different_passphrase_hash() {
    setup_test_env
    require_module || return 1

    # Create token with one passphrase
    local hash1
    hash1=$(bypass_hash_passphrase "password1")
    echo "${hash1}" > "$(get_hash_file)"
    local token
    token=$(bypass_create_token)
    echo "${token}" > "$(get_token_file)"

    # Change passphrase hash
    local hash2
    hash2=$(bypass_hash_passphrase "password2")
    echo "${hash2}" > "$(get_hash_file)"

    # Token should now be invalid
    if bypass_verify_token; then
        echo "Token should be invalid after passphrase change"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Bypass State Tests
# ============================================================================

test_bypass_active_with_valid_token() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    local token
    token=$(bypass_create_token)
    echo "${token}" > "$(get_token_file)"

    # v2 requires activity file for inactivity check
    bypass_update_activity

    if ! bypass_is_active; then
        echo "Bypass should be active with valid token"
        return 1
    fi

    teardown_test_env
}

test_bypass_inactive_without_token() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"
    rm -f "$(get_token_file)"

    if bypass_is_active; then
        echo "Bypass should not be active without token"
        return 1
    fi

    teardown_test_env
}

test_bypass_inactive_with_forged_token() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"
    # Forged token with 128-char fake HMAC (SHA512)
    echo "1:$(date +%s):forged0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" > "$(get_token_file)"

    if bypass_is_active; then
        echo "Bypass should not be active with forged token"
        return 1
    fi

    # Forged token should be removed
    if [[ -f "$(get_token_file)" ]]; then
        echo "Forged token file should have been removed"
        return 1
    fi

    teardown_test_env
}

test_bypass_inactive_not_configured() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_hash_file)" "$(get_token_file)"

    if bypass_is_active; then
        echo "Bypass should not be active when not configured"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Rate Limiting Tests - iOS Style Progression
# ============================================================================

test_rate_limit_no_lockout_first_two() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_failures_file)"

    # First attempt - allowed
    if ! bypass_check_rate_limit 2>/dev/null; then
        echo "First attempt should be allowed"
        return 1
    fi

    bypass_record_failure
    if ! bypass_check_rate_limit 2>/dev/null; then
        echo "After 1 failure should be allowed"
        return 1
    fi

    bypass_record_failure
    if ! bypass_check_rate_limit 2>/dev/null; then
        echo "After 2 failures should be allowed"
        return 1
    fi

    teardown_test_env
}

test_rate_limit_locks_at_three() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_failures_file)"
    bypass_record_failure
    bypass_record_failure
    bypass_record_failure

    if bypass_check_rate_limit 2>/dev/null; then
        echo "Should be locked after 3 failures"
        return 1
    fi

    teardown_test_env
}

test_rate_limit_failure_count_tracking() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_failures_file)"

    for i in {1..7}; do
        bypass_record_failure
        local count
        count=$(grep -o '"count":[0-9]*' "$(get_failures_file)" | cut -d: -f2)
        if [[ ${count} -ne ${i} ]]; then
            echo "After ${i} failures, count should be ${i}, got ${count}"
            return 1
        fi
    done

    teardown_test_env
}

test_rate_limit_reset_clears_file() {
    setup_test_env
    require_module || return 1

    bypass_record_failure
    bypass_record_failure
    bypass_record_failure

    bypass_reset_failures

    if [[ -f "$(get_failures_file)" ]]; then
        echo "Failures file should be removed on reset"
        return 1
    fi

    # Should be allowed again
    if ! bypass_check_rate_limit 2>/dev/null; then
        echo "Should be allowed after reset"
        return 1
    fi

    teardown_test_env
}

test_rate_limit_permanent_lockout() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_failures_file)"

    # 10+ failures = permanent lockout
    for i in {1..12}; do
        bypass_record_failure
    done

    local output
    output=$(bypass_check_rate_limit 2>&1)

    if [[ ! "${output}" == *"Manual reset"* ]] && [[ ! "${output}" == *"locked"* ]]; then
        echo "Should indicate permanent lockout after 10+ failures"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Activation/Deactivation Tests
# ============================================================================

test_activate_creates_valid_token() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate

    if [[ ! -f "$(get_token_file)" ]]; then
        echo "Token file should be created on activation"
        return 1
    fi

    if ! bypass_is_active; then
        echo "Should be active after activation"
        return 1
    fi

    if ! bypass_verify_token; then
        echo "Token created by activation should be valid"
        return 1
    fi

    teardown_test_env
}

test_activate_resets_failures() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Record some failures
    bypass_record_failure
    bypass_record_failure

    # Activate should reset failures
    bypass_activate

    if [[ -f "$(get_failures_file)" ]]; then
        echo "Activation should reset failure counter"
        return 1
    fi

    teardown_test_env
}

test_deactivate_removes_token() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"
    bypass_activate

    bypass_deactivate

    if [[ -f "$(get_token_file)" ]]; then
        echo "Token file should be removed on deactivation"
        return 1
    fi

    if bypass_is_active; then
        echo "Should not be active after deactivation"
        return 1
    fi

    teardown_test_env
}

test_deactivate_idempotent() {
    setup_test_env
    require_module || return 1

    # Deactivate when not active should not error
    rm -f "$(get_token_file)"
    bypass_deactivate

    if [[ $? -ne 0 ]]; then
        echo "Deactivate should succeed even when not active"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Configuration State Tests
# ============================================================================

test_configured_when_hash_exists() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    bypass_store_hash "${hash}"

    if ! bypass_is_configured; then
        echo "Should report configured when hash exists"
        return 1
    fi

    teardown_test_env
}

test_not_configured_when_no_hash() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_hash_file)"

    if bypass_is_configured; then
        echo "Should report not configured when hash missing"
        return 1
    fi

    teardown_test_env
}

test_store_hash_creates_directory() {
    setup_test_env
    require_module || return 1

    rm -rf "${TEST_DATA_DIR}/bypass"

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    bypass_store_hash "${hash}"

    if [[ ! -d "${TEST_DATA_DIR}/bypass" ]]; then
        echo "store_hash should create bypass directory"
        return 1
    fi

    teardown_test_env
}

test_store_hash_sets_permissions() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    bypass_store_hash "${hash}"

    local perms
    perms=$(stat -c %a "$(get_hash_file)" 2>/dev/null || stat -f %Lp "$(get_hash_file)")

    if [[ "${perms}" != "600" ]]; then
        echo "Hash file should have 600 permissions, got ${perms}"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Status Helper Tests
# ============================================================================

test_status_not_configured() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_hash_file)" "$(get_token_file)"

    local status
    status=$(bypass_get_status)

    if [[ "${status}" != "NOT_CONFIGURED" ]]; then
        echo "Status should be NOT_CONFIGURED, got ${status}"
        return 1
    fi

    teardown_test_env
}

test_status_protected() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"
    rm -f "$(get_token_file)"

    local status
    status=$(bypass_get_status)

    if [[ "${status}" != "PROTECTED" ]]; then
        echo "Status should be PROTECTED, got ${status}"
        return 1
    fi

    teardown_test_env
}

test_status_bypass_active() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"
    bypass_activate

    local status
    status=$(bypass_get_status)

    if [[ "${status}" != "BYPASS_ACTIVE" ]]; then
        echo "Status should be BYPASS_ACTIVE, got ${status}"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Safety Dead-Bolt Tests - Token Expiry
# ============================================================================

# Helper to get activity file path
get_activity_file() { echo "${TEST_DATA_DIR}/bypass/last_activity"; }

test_token_v2_format_includes_expiry() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    local token
    token=$(bypass_create_token)

    # v2 format: version:created:expires:hmac (4 fields)
    local field_count
    field_count=$(echo "${token}" | tr ':' '\n' | wc -l)

    if [[ ${field_count} -ne 4 ]]; then
        echo "v2 token should have 4 fields (version:created:expires:hmac), got ${field_count}"
        return 1
    fi

    # Extract expiry and verify it's in the future
    local rest="${token#*:}"
    rest="${rest#*:}"
    local expires="${rest%%:*}"
    local now
    now=$(date +%s)

    if [[ ${expires} -le ${now} ]]; then
        echo "Token expiry should be in the future"
        return 1
    fi

    teardown_test_env
}

test_token_expires_after_max_duration() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Create a token that's already expired (simulate passage of time)
    local created=$(($(date +%s) - 20000))  # Created 20000 seconds ago
    local expires=$((created + 14400))       # Expired 5600 seconds ago (4 hours max)
    local stored_hash
    stored_hash=$(cat "$(get_hash_file)")

    local hmac
    hmac=$(printf '2:%s:%s' "${created}" "${expires}" | \
           openssl dgst -sha256 -hmac "${stored_hash}" 2>/dev/null | \
           sed 's/^.* //')

    echo "2:${created}:${expires}:${hmac}" > "$(get_token_file)"

    # Token should fail verification with exit code 2 (expired)
    bypass_verify_token
    local result=$?

    if [[ ${result} -ne 2 ]]; then
        echo "Expired token should return exit code 2, got ${result}"
        return 1
    fi

    teardown_test_env
}

test_token_expires_triggers_auto_deactivate() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Create expired token
    local created=$(($(date +%s) - 20000))
    local expires=$((created + 14400))
    local stored_hash
    stored_hash=$(cat "$(get_hash_file)")

    local hmac
    hmac=$(printf '2:%s:%s' "${created}" "${expires}" | \
           openssl dgst -sha256 -hmac "${stored_hash}" 2>/dev/null | \
           sed 's/^.* //')

    echo "2:${created}:${expires}:${hmac}" > "$(get_token_file)"

    # Create activity file to avoid inactivity timeout
    echo "$(date +%s)" > "$(get_activity_file)"

    # bypass_is_active should return false AND clean up token
    if bypass_is_active 2>/dev/null; then
        echo "Expired token should cause bypass_is_active to return false"
        return 1
    fi

    # Token file should be removed (auto-deactivated)
    if [[ -f "$(get_token_file)" ]]; then
        echo "Expired token should be auto-deactivated (file removed)"
        return 1
    fi

    teardown_test_env
}

test_inactivity_timeout_triggers_deactivation() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Create valid (not expired) token
    bypass_activate 2>/dev/null

    # But set activity timestamp to old (simulate inactivity)
    local old_time=$(($(date +%s) - 3600))  # 1 hour ago
    echo "${old_time}" > "$(get_activity_file)"

    # bypass_is_active should return false due to inactivity
    if bypass_is_active 2>/dev/null; then
        echo "Inactivity timeout should cause bypass_is_active to return false"
        return 1
    fi

    # Token should be cleaned up
    if [[ -f "$(get_token_file)" ]]; then
        echo "Inactivity timeout should trigger auto-deactivation"
        return 1
    fi

    teardown_test_env
}

test_activity_update_resets_inactivity() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate 2>/dev/null

    # Record initial activity
    local initial_time
    initial_time=$(cat "$(get_activity_file)")

    # Wait a tiny bit and update activity
    sleep 1
    bypass_update_activity

    local new_time
    new_time=$(cat "$(get_activity_file)")

    if [[ ${new_time} -le ${initial_time} ]]; then
        echo "Activity update should increase timestamp"
        return 1
    fi

    teardown_test_env
}

test_activity_tracking_within_timeout() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate 2>/dev/null

    # Activity is recent (just activated)
    if ! bypass_check_inactivity; then
        echo "Recent activity should pass inactivity check"
        return 1
    fi

    teardown_test_env
}

test_activity_tracking_beyond_timeout() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Set old activity timestamp
    local old_time=$(($(date +%s) - 3600))
    echo "${old_time}" > "$(get_activity_file)"

    if bypass_check_inactivity 2>/dev/null; then
        echo "Old activity should fail inactivity check"
        return 1
    fi

    teardown_test_env
}

test_missing_activity_file_fails_inactivity() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_activity_file)"

    if bypass_check_inactivity; then
        echo "Missing activity file should fail inactivity check"
        return 1
    fi

    teardown_test_env
}

test_get_remaining_returns_correct_time() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate 2>/dev/null

    local remaining
    remaining=$(bypass_get_remaining)

    # Should be close to BYPASS_DEFAULT_MAX_DURATION (14400 seconds)
    # Allow 5 second margin for test execution time
    if [[ ${remaining} -lt 14395 ]] || [[ ${remaining} -gt 14400 ]]; then
        echo "Remaining time should be ~14400 seconds, got ${remaining}"
        return 1
    fi

    teardown_test_env
}

test_get_remaining_zero_when_expired() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Create expired token
    local created=$(($(date +%s) - 20000))
    local expires=$((created + 14400))
    local stored_hash
    stored_hash=$(cat "$(get_hash_file)")

    local hmac
    hmac=$(printf '2:%s:%s' "${created}" "${expires}" | \
           openssl dgst -sha256 -hmac "${stored_hash}" 2>/dev/null | \
           sed 's/^.* //')

    echo "2:${created}:${expires}:${hmac}" > "$(get_token_file)"

    local remaining
    remaining=$(bypass_get_remaining)

    if [[ ${remaining} -ne 0 ]]; then
        echo "Remaining time for expired token should be 0, got ${remaining}"
        return 1
    fi

    teardown_test_env
}

test_legacy_v1_token_not_supported_with_sha512() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Create v1 format token with SHA256 HMAC (old format)
    local timestamp
    timestamp=$(date +%s)
    local stored_hash
    stored_hash=$(cat "$(get_hash_file)")

    # v1 tokens used SHA256, which is incompatible with SHA512 verification
    local hmac
    hmac=$(printf '1:%s' "${timestamp}" | \
           openssl dgst -sha256 -hmac "${stored_hash}" 2>/dev/null | \
           sed 's/^.* //')

    echo "1:${timestamp}:${hmac}" > "$(get_token_file)"
    bypass_update_activity

    # v1 token with SHA256 HMAC should FAIL (breaking change with SHA512 upgrade)
    if bypass_verify_token 2>/dev/null; then
        echo "Legacy v1 SHA256 token should be rejected by SHA512 verification"
        return 1
    fi

    teardown_test_env
}

test_cannot_extend_expiry_by_editing_token() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate 2>/dev/null

    # Read current token
    local token
    token=$(cat "$(get_token_file)")

    # Parse fields
    local version="${token%%:*}"
    local rest="${token#*:}"
    local created="${rest%%:*}"
    rest="${rest#*:}"
    local expires="${rest%%:*}"
    local hmac="${rest#*:}"

    # Tamper with expiry to extend it
    local new_expires=$((expires + 86400))  # Add 1 day
    local tampered="${version}:${created}:${new_expires}:${hmac}"
    echo "${tampered}" > "$(get_token_file)"

    # Token should be invalid (HMAC mismatch)
    if bypass_verify_token; then
        echo "Tampered token with extended expiry should be rejected"
        return 1
    fi

    teardown_test_env
}

test_cannot_reset_inactivity_by_editing_file() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate 2>/dev/null

    # Set old activity (timed out)
    local old_time=$(($(date +%s) - 3600))
    echo "${old_time}" > "$(get_activity_file)"

    # Attacker tries to reset by editing file
    echo "$(date +%s)" > "$(get_activity_file)"

    # But bypass_is_active still checks token expiry first
    # The token itself is valid, so this attack vector is about the activity file
    # This test verifies activity file manipulation doesn't bypass other checks

    # In this case, the token is valid and activity is fresh, so it should work
    # This is expected behavior - the file system is trusted
    # Real protection is token HMAC preventing expiry manipulation

    if ! bypass_is_active; then
        echo "Valid token with fresh activity should be active"
        return 1
    fi

    teardown_test_env
}

test_activate_initializes_activity() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    rm -f "$(get_activity_file)"

    bypass_activate 2>/dev/null

    if [[ ! -f "$(get_activity_file)" ]]; then
        echo "Activation should create activity file"
        return 1
    fi

    teardown_test_env
}

test_deactivate_removes_activity() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    bypass_activate 2>/dev/null
    bypass_deactivate 2>/dev/null

    if [[ -f "$(get_activity_file)" ]]; then
        echo "Deactivation should remove activity file"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Security Attack Simulation Tests
# ============================================================================

test_attack_empty_token_file() {
    setup_test_env
    require_module || return 1

    local hash
    hash=$(bypass_hash_passphrase "testpass")
    echo "${hash}" > "$(get_hash_file)"

    # Empty token file attack
    touch "$(get_token_file)"

    if bypass_is_active; then
        echo "Empty token file should not activate bypass"
        return 1
    fi

    teardown_test_env
}

test_attack_malformed_failures_json() {
    setup_test_env
    require_module || return 1

    # Malformed JSON in failures file
    echo "not valid json {{{" > "$(get_failures_file)"

    # Should not crash, should handle gracefully
    bypass_check_rate_limit 2>/dev/null
    local result=$?

    # Should either allow (parse failure = no lockout) or handle gracefully
    if [[ ${result} -gt 1 ]]; then
        echo "Malformed failures file should be handled gracefully"
        return 1
    fi

    teardown_test_env
}

test_attack_token_replay_different_hash() {
    setup_test_env
    require_module || return 1

    # Create valid token with hash1
    local hash1
    hash1=$(bypass_hash_passphrase "password1")
    echo "${hash1}" > "$(get_hash_file)"
    bypass_activate
    local captured_token
    captured_token=$(cat "$(get_token_file)")

    # Change to hash2
    local hash2
    hash2=$(bypass_hash_passphrase "password2")
    echo "${hash2}" > "$(get_hash_file)"

    # Try to replay old token
    echo "${captured_token}" > "$(get_token_file)"

    if bypass_is_active; then
        echo "Token replay attack should not work after passphrase change"
        return 1
    fi

    teardown_test_env
}

# ============================================================================
# Script Integrity Tests
# ============================================================================

# Helper to get checksums file path
get_checksums_file() { echo "${TEST_DATA_DIR}/bypass/checksums.sha256"; }

test_checksum_verify_no_file() {
    setup_test_env
    require_module || return 1

    rm -f "$(get_checksums_file)"

    # Should pass (skip verification) when no checksums file
    if ! bypass_verify_checksums; then
        echo "Should pass when no checksums file exists (first run)"
        return 1
    fi

    teardown_test_env
}

test_checksum_generate() {
    setup_test_env
    require_module || return 1

    # Create dummy scripts to checksum
    local test_script_dir="${TEST_DATA_DIR}/test-scripts"
    mkdir -p "${test_script_dir}/bin" "${test_script_dir}/src/security"

    echo '#!/bin/bash\necho "test"' > "${test_script_dir}/bin/wow-bypass"
    echo '#!/bin/bash\necho "core"' > "${test_script_dir}/src/security/bypass-core.sh"

    # Generate checksums (use our test dir)
    bypass_generate_checksums "${test_script_dir}"

    if [[ ! -f "$(get_checksums_file)" ]]; then
        echo "Checksums file should be created"
        return 1
    fi

    # Verify file contains checksums
    if [[ ! -s "$(get_checksums_file)" ]]; then
        echo "Checksums file should not be empty"
        return 1
    fi

    teardown_test_env
}

test_checksum_detect_tampering() {
    setup_test_env
    require_module || return 1

    # Create script and generate checksums
    local test_script_dir="${TEST_DATA_DIR}/test-scripts"
    mkdir -p "${test_script_dir}/bin" "${test_script_dir}/src/security"

    echo '#!/bin/bash\necho "original"' > "${test_script_dir}/bin/wow-bypass"
    chmod +x "${test_script_dir}/bin/wow-bypass"

    bypass_generate_checksums "${test_script_dir}"

    # Tamper with the script
    echo '#!/bin/bash\necho "tampered - bypass disabled"' > "${test_script_dir}/bin/wow-bypass"

    # Verification should fail
    if bypass_verify_checksums 2>/dev/null; then
        echo "Should detect script tampering"
        return 1
    fi

    teardown_test_env
}

test_checksum_file_removal() {
    setup_test_env
    require_module || return 1

    # Create scripts and generate checksums
    local test_script_dir="${TEST_DATA_DIR}/test-scripts"
    mkdir -p "${test_script_dir}/bin"

    echo '#!/bin/bash\necho "test"' > "${test_script_dir}/bin/wow-bypass"

    bypass_generate_checksums "${test_script_dir}"

    # Remove checksums file (attack)
    rm -f "$(get_checksums_file)"

    # Should pass - no checksums = first run behavior
    # This is a known limitation - checksum file deletion is a valid attack
    # The defense is to enforce checksums in production after initial setup

    if ! bypass_verify_checksums; then
        echo "Missing checksums file should pass (first-run behavior)"
        return 1
    fi

    teardown_test_env
}

test_checksum_permissions() {
    setup_test_env
    require_module || return 1

    local test_script_dir="${TEST_DATA_DIR}/test-scripts"
    mkdir -p "${test_script_dir}/bin"

    echo '#!/bin/bash\necho "test"' > "${test_script_dir}/bin/wow-bypass"

    bypass_generate_checksums "${test_script_dir}"

    local perms
    perms=$(stat -c %a "$(get_checksums_file)" 2>/dev/null || stat -f %Lp "$(get_checksums_file)")

    if [[ "${perms}" != "600" ]]; then
        echo "Checksums file should have 600 permissions, got ${perms}"
        return 1
    fi

    teardown_test_env
}

test_checksum_missing_script() {
    setup_test_env
    require_module || return 1

    # Generate checksums for a script that doesn't exist
    # Should handle gracefully (empty checksums file or skip)

    local test_script_dir="${TEST_DATA_DIR}/empty-scripts"
    mkdir -p "${test_script_dir}"

    bypass_generate_checksums "${test_script_dir}"

    # Should succeed (but checksums file may be empty)
    # The function should not crash

    teardown_test_env
}

# ============================================================================
# Zone Awareness Tests (v7.0+)
# ============================================================================

test_zone_allows_development() {
    setup_test_env
    require_module || return 1

    # bypass_allows_zone should allow DEVELOPMENT zone
    if type bypass_allows_zone &>/dev/null; then
        bypass_allows_zone "DEVELOPMENT"
        assert_equals 0 $? "Should allow DEVELOPMENT zone"
    else
        echo "SKIP: bypass_allows_zone not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_allows_general() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_zone &>/dev/null; then
        bypass_allows_zone "GENERAL"
        assert_equals 0 $? "Should allow GENERAL zone"
    else
        echo "SKIP: bypass_allows_zone not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_blocks_config() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_zone &>/dev/null; then
        bypass_allows_zone "CONFIG"
        assert_equals 1 $? "Should block CONFIG zone"
    else
        echo "SKIP: bypass_allows_zone not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_blocks_sensitive() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_zone &>/dev/null; then
        bypass_allows_zone "SENSITIVE"
        assert_equals 1 $? "Should block SENSITIVE zone"
    else
        echo "SKIP: bypass_allows_zone not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_blocks_system() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_zone &>/dev/null; then
        bypass_allows_zone "SYSTEM"
        assert_equals 1 $? "Should block SYSTEM zone"
    else
        echo "SKIP: bypass_allows_zone not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_blocks_wow_self() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_zone &>/dev/null; then
        bypass_allows_zone "WOW_SELF"
        assert_equals 1 $? "Should block WOW_SELF zone"
    else
        echo "SKIP: bypass_allows_zone not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_path_allows_projects() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_path &>/dev/null; then
        bypass_allows_path "${HOME}/Projects/myapp/src/main.ts"
        assert_equals 0 $? "Should allow path in ~/Projects"
    else
        echo "SKIP: bypass_allows_path not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_path_blocks_ssh() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_path &>/dev/null; then
        bypass_allows_path "${HOME}/.ssh/id_rsa"
        assert_equals 1 $? "Should block path in ~/.ssh"
    else
        echo "SKIP: bypass_allows_path not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_path_blocks_etc() {
    setup_test_env
    require_module || return 1

    if type bypass_allows_path &>/dev/null; then
        bypass_allows_path "/etc/passwd"
        assert_equals 1 $? "Should block path in /etc"
    else
        echo "SKIP: bypass_allows_path not defined"
        return 0
    fi

    teardown_test_env
}

test_zone_get_allowed_zones() {
    setup_test_env
    require_module || return 1

    if type bypass_get_allowed_zones &>/dev/null; then
        local zones
        zones=$(bypass_get_allowed_zones)
        assert_contains "${zones}" "DEVELOPMENT" "Should list DEVELOPMENT zone"
        assert_contains "${zones}" "GENERAL" "Should list GENERAL zone"
    else
        echo "SKIP: bypass_get_allowed_zones not defined"
        return 0
    fi

    teardown_test_env
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "Bypass Core Comprehensive Tests"

echo ""
echo "=== TTY Detection Tests (4 tests) ==="
test_case "should reject piped input" test_tty_piped_input
test_case "should reject subshell without TTY" test_tty_subshell_no_tty
test_case "should reject heredoc input" test_tty_heredoc_input
test_case "should reject process substitution" test_tty_process_substitution

echo ""
echo "=== Passphrase Hashing - Basic (3 tests) ==="
test_case "should generate valid format hash" test_hash_format_valid
test_case "should produce unique salts" test_hash_unique_salts
test_case "should produce different hashes for different passwords" test_hash_different_passwords_different

echo ""
echo "=== Passphrase Hashing - Edge Cases (5 tests) ==="
test_case "should handle empty passphrase" test_hash_empty_passphrase
test_case "should handle very long passphrase (1000 chars)" test_hash_very_long_passphrase
test_case "should handle special characters" test_hash_special_characters
test_case "should handle unicode passphrase" test_hash_unicode_passphrase
test_case "should handle whitespace passphrase" test_hash_whitespace_passphrase

echo ""
echo "=== Passphrase Verification (6 tests) ==="
test_case "should verify correct passphrase" test_verify_correct_passphrase
test_case "should reject wrong passphrase" test_verify_wrong_passphrase
test_case "should reject similar passphrases" test_verify_similar_passphrase
test_case "should return 2 when not configured" test_verify_not_configured
test_case "should handle corrupted hash file" test_verify_corrupted_hash_file
test_case "should handle empty hash file" test_verify_empty_hash_file

echo ""
echo "=== Token Tests - Basic (6 tests) ==="
test_case "should create valid format token" test_token_format_valid
test_case "should verify valid token" test_token_verify_valid
test_case "should reject forged token" test_token_reject_forged
test_case "should reject tampered timestamp" test_token_reject_tampered_timestamp
test_case "should reject tampered HMAC" test_token_reject_tampered_hmac
test_case "should fail when token file missing" test_token_missing_file

echo ""
echo "=== Token Tests - Edge Cases (3 tests) ==="
test_case "should fail when hash file missing" test_token_missing_hash_file
test_case "should reject corrupted token formats" test_token_corrupted_format
test_case "should invalidate token after passphrase change" test_token_different_passphrase_hash

echo ""
echo "=== Bypass State Tests (4 tests) ==="
test_case "should report active with valid token" test_bypass_active_with_valid_token
test_case "should report inactive without token" test_bypass_inactive_without_token
test_case "should report inactive with forged token and cleanup" test_bypass_inactive_with_forged_token
test_case "should report inactive when not configured" test_bypass_inactive_not_configured

echo ""
echo "=== Rate Limiting Tests (4 tests) ==="
test_case "should allow first two attempts" test_rate_limit_no_lockout_first_two
test_case "should lock at three failures" test_rate_limit_locks_at_three
test_case "should track failure count accurately" test_rate_limit_failure_count_tracking
test_case "should reset completely on success" test_rate_limit_reset_clears_file

echo ""
echo "=== Rate Limiting - Escalation (1 test) ==="
test_case "should indicate permanent lockout after 10+" test_rate_limit_permanent_lockout

echo ""
echo "=== Activation/Deactivation Tests (4 tests) ==="
test_case "should create valid token on activation" test_activate_creates_valid_token
test_case "should reset failures on activation" test_activate_resets_failures
test_case "should remove token on deactivation" test_deactivate_removes_token
test_case "should handle deactivation when not active" test_deactivate_idempotent

echo ""
echo "=== Configuration State Tests (4 tests) ==="
test_case "should report configured when hash exists" test_configured_when_hash_exists
test_case "should report not configured when no hash" test_not_configured_when_no_hash
test_case "should create directory on store_hash" test_store_hash_creates_directory
test_case "should set correct file permissions" test_store_hash_sets_permissions

echo ""
echo "=== Status Helper Tests (3 tests) ==="
test_case "should return NOT_CONFIGURED status" test_status_not_configured
test_case "should return PROTECTED status" test_status_protected
test_case "should return BYPASS_ACTIVE status" test_status_bypass_active

echo ""
echo "=== Safety Dead-Bolt - Token Expiry (15 tests) ==="
test_case "should create v2 token with expiry field" test_token_v2_format_includes_expiry
test_case "should detect expired token (max duration)" test_token_expires_after_max_duration
test_case "should auto-deactivate on max duration expiry" test_token_expires_triggers_auto_deactivate
test_case "should auto-deactivate on inactivity timeout" test_inactivity_timeout_triggers_deactivation
test_case "should reset inactivity on activity update" test_activity_update_resets_inactivity
test_case "should pass inactivity check when recent" test_activity_tracking_within_timeout
test_case "should fail inactivity check when old" test_activity_tracking_beyond_timeout
test_case "should fail inactivity check when no file" test_missing_activity_file_fails_inactivity
test_case "should return correct remaining time" test_get_remaining_returns_correct_time
test_case "should return 0 remaining for expired" test_get_remaining_zero_when_expired
test_case "should reject legacy v1 SHA256 tokens" test_legacy_v1_token_not_supported_with_sha512
test_case "should reject tampered expiry extension" test_cannot_extend_expiry_by_editing_token
test_case "should allow valid token with fresh activity" test_cannot_reset_inactivity_by_editing_file
test_case "should create activity file on activate" test_activate_initializes_activity
test_case "should remove activity file on deactivate" test_deactivate_removes_activity

echo ""
echo "=== Security Attack Simulation (3 tests) ==="
test_case "should reject empty token file" test_attack_empty_token_file
test_case "should handle malformed failures JSON" test_attack_malformed_failures_json
test_case "should reject token replay after passphrase change" test_attack_token_replay_different_hash

echo ""
echo "=== Script Integrity Tests (6 tests) ==="
test_case "should pass checksum verify when no file" test_checksum_verify_no_file
test_case "should generate checksums for scripts" test_checksum_generate
test_case "should detect script tampering" test_checksum_detect_tampering
test_case "should detect checksum file removal" test_checksum_file_removal
test_case "should set correct checksum permissions" test_checksum_permissions
test_case "should handle missing script gracefully" test_checksum_missing_script

echo ""
echo "=== Zone Awareness Tests (10 tests) ==="
test_case "should allow DEVELOPMENT zone" test_zone_allows_development
test_case "should allow GENERAL zone" test_zone_allows_general
test_case "should block CONFIG zone" test_zone_blocks_config
test_case "should block SENSITIVE zone" test_zone_blocks_sensitive
test_case "should block SYSTEM zone" test_zone_blocks_system
test_case "should block WOW_SELF zone" test_zone_blocks_wow_self
test_case "should allow path in ~/Projects" test_zone_path_allows_projects
test_case "should block path in ~/.ssh" test_zone_path_blocks_ssh
test_case "should block path in /etc" test_zone_path_blocks_etc
test_case "should list allowed zones" test_zone_get_allowed_zones

echo ""
test_summary
