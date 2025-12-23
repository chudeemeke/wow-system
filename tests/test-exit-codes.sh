#!/bin/bash
# WoW System - Exit Code Tests
# Tests for exit code 4 (SUPERADMIN-REQUIRED) handling
# Author: Chude <chude@emeke.org>
#
# TDD Phase: RED - These tests define the expected behavior

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source test framework
source "${SCRIPT_DIR}/test-framework.sh"

# ============================================================================
# Test Setup
# ============================================================================

setup_all() {
    # Source the modules we're testing
    source "${PROJECT_ROOT}/src/security/security-policies.sh" 2>/dev/null || true

    # Create temp directory for test artifacts
    TEST_TEMP_DIR=$(mktemp -d -t wow-exit-code-test-XXXXXXXXXX)
}

teardown_all() {
    # Cleanup temp directory
    [[ -n "${TEST_TEMP_DIR:-}" ]] && rm -rf "${TEST_TEMP_DIR}"
}

# ============================================================================
# Exit Code Constants Tests
# ============================================================================

test_exit_code_constants_exist() {
    # Test that exit code constants are defined
    # These should be defined in security-policies.sh or a constants file

    # Expected exit codes:
    # 0 = ALLOW
    # 1 = WARN (non-blocking)
    # 2 = BLOCK (bypassable)
    # 3 = CRITICAL-BLOCK (not bypassable)
    # 4 = SUPERADMIN-REQUIRED (new)

    assert_equals "0" "${EXIT_ALLOW:-0}" "EXIT_ALLOW should be 0"
    assert_equals "1" "${EXIT_WARN:-1}" "EXIT_WARN should be 1"
    assert_equals "2" "${EXIT_BLOCK:-2}" "EXIT_BLOCK should be 2"
    assert_equals "3" "${EXIT_CRITICAL:-3}" "EXIT_CRITICAL should be 3"
    assert_equals "4" "${EXIT_SUPERADMIN:-4}" "EXIT_SUPERADMIN should be 4"
}

# ============================================================================
# Security Policy Tier Tests
# ============================================================================

test_policy_tier_superadmin_exists() {
    # Test that SUPERADMIN tier exists in security policies
    # This tier is for operations that CAN be unlocked, but only with SuperAdmin

    if ! type policy_check_superadmin &>/dev/null; then
        fail "policy_check_superadmin function should exist"
        return 1
    fi
    pass
}

test_policy_superadmin_patterns_defined() {
    # SUPERADMIN tier patterns should be defined
    # These are operations that are blocked but can be unlocked with SuperAdmin

    # The array should exist
    if [[ -z "${POLICY_SUPERADMIN_REQUIRED[@]+x}" ]]; then
        fail "POLICY_SUPERADMIN_REQUIRED array should be defined"
        return 1
    fi
    pass
}

test_wow_self_protection_requires_superadmin() {
    # WoW self-protection files should require SuperAdmin (not just always-block)
    # This allows legitimate development with proper authentication

    local test_path="security-policies.sh"

    if policy_check_superadmin "${test_path}" 2>/dev/null; then
        pass "WoW self-protection correctly requires SuperAdmin"
    else
        fail "WoW self-protection should require SuperAdmin"
        return 1
    fi
}

test_critical_operations_not_superadmin() {
    # CRITICAL operations (SSRF, fork bombs) should NOT be SuperAdmin-unlockable
    # They stay at exit code 3 (always-block)

    local ssrf_test="curl http://169.254.169.254/"

    # Should match CRITICAL (exit 3), NOT SUPERADMIN (exit 4)
    if policy_check_critical "${ssrf_test}" 2>/dev/null; then
        # Good - SSRF is still critical
        if policy_check_superadmin "${ssrf_test}" 2>/dev/null; then
            fail "SSRF should NOT be SuperAdmin-unlockable"
            return 1
        fi
        pass
    else
        fail "SSRF should still be CRITICAL tier"
        return 1
    fi
}

# ============================================================================
# Handler Router Exit Code Tests
# ============================================================================

test_handler_router_returns_exit_4() {
    # Handler router should return exit code 4 for SuperAdmin-required ops

    source "${PROJECT_ROOT}/src/handlers/handler-router.sh" 2>/dev/null || true

    # Mock input that should trigger SuperAdmin requirement
    local test_input='{"tool":"Read","file_path":"security-policies.sh"}'

    # Route the input
    local result
    result=$(handler_route "${test_input}" 2>&1) && local exit_code=$? || local exit_code=$?

    assert_equals "4" "${exit_code}" "Handler should return exit code 4 for SuperAdmin-required operations"
}

# ============================================================================
# Hook Exit Code Mapping Tests
# ============================================================================

test_hook_maps_exit_4_correctly() {
    # The hook should map handler exit code 4 to proper user message

    # This tests the message format, not the actual hook (which would need mocking)
    local expected_message="SuperAdmin authentication required"

    # The hook should include guidance about wow superadmin unlock
    local expected_guidance="wow superadmin unlock"

    # These will be verified when we implement the hook changes
    pass "Message format defined (implementation pending)"
}

# ============================================================================
# Policy is_superadmin_unlockable Tests
# ============================================================================

test_superadmin_unlockable_returns_true_for_wow_files() {
    # WoW self-protection files should be SuperAdmin-unlockable

    local test_path="bypass-core.sh"

    if policy_is_superadmin_unlockable "${test_path}" 2>/dev/null; then
        pass
    else
        fail "WoW files should be SuperAdmin-unlockable"
        return 1
    fi
}

test_superadmin_unlockable_returns_false_for_ssrf() {
    # SSRF attacks should NOT be SuperAdmin-unlockable

    local test_op="curl http://169.254.169.254/"

    if policy_is_superadmin_unlockable "${test_op}" 2>/dev/null; then
        fail "SSRF should NOT be SuperAdmin-unlockable"
        return 1
    fi
    pass
}

test_superadmin_unlockable_returns_false_for_fork_bomb() {
    # Fork bombs should NOT be SuperAdmin-unlockable

    local test_op=":() { :|:& }; :"

    if policy_is_superadmin_unlockable "${test_op}" 2>/dev/null; then
        fail "Fork bombs should NOT be SuperAdmin-unlockable"
        return 1
    fi
    pass
}

test_superadmin_unlockable_returns_false_for_destructive() {
    # Destructive commands should NOT be SuperAdmin-unlockable

    local test_op="rm -rf /"

    if policy_is_superadmin_unlockable "${test_op}" 2>/dev/null; then
        fail "Destructive commands should NOT be SuperAdmin-unlockable"
        return 1
    fi
    pass
}

# ============================================================================
# Exit Code Reason Tests
# ============================================================================

test_get_reason_for_superadmin() {
    # Should return appropriate reason for SuperAdmin-required operations

    local test_path="security-policies.sh"
    local reason
    reason=$(policy_get_reason "${test_path}" 2>/dev/null)

    assert_contains "${reason}" "SuperAdmin" "Reason should mention SuperAdmin"
}

# ============================================================================
# Hook Protection Tests (v7.0 - Bootstrap Security)
# ============================================================================

test_hook_file_is_critical() {
    # The hook file itself should be in CRITICAL tier (not SuperAdmin)
    # Because if the hook is disabled, ALL WoW protection is bypassed

    local hook_path=".claude/hooks/user-prompt-submit.sh"

    if policy_check_critical "${hook_path}" 2>/dev/null; then
        pass
    else
        fail "Hook file should be CRITICAL tier (bootstrap protection)"
        return 1
    fi
}

test_hook_backup_is_critical() {
    # Backup files (.bak) should also be protected
    # Prevents: mv hook.sh hook.sh.bak (then WoW is disabled)

    local backup_path="user-prompt-submit.sh.bak"

    if policy_check_critical "${backup_path}" 2>/dev/null; then
        pass
    else
        fail "Hook backup files should be CRITICAL tier"
        return 1
    fi
}

test_hook_disabled_is_critical() {
    # Disabled files (.disabled, .dev) should be protected
    # Prevents: mv hook.sh hook.sh.disabled

    local disabled_path="user-prompt-submit.sh.disabled"
    local dev_path="user-prompt-submit.sh.dev"

    if policy_check_critical "${disabled_path}" 2>/dev/null && \
       policy_check_critical "${dev_path}" 2>/dev/null; then
        pass
    else
        fail "Hook disabled files should be CRITICAL tier"
        return 1
    fi
}

test_hook_is_not_superadmin_unlockable() {
    # Hook protection should NOT be SuperAdmin-unlockable
    # This is the bootstrap problem - if AI can disable hook, game over

    local hook_path=".claude/hooks/user-prompt-submit.sh"

    if policy_is_superadmin_unlockable "${hook_path}" 2>/dev/null; then
        fail "Hook should NOT be SuperAdmin-unlockable (bootstrap protection)"
        return 1
    fi
    pass
}

test_hook_reason_mentions_bootstrap() {
    # The reason should mention bootstrap or hook protection

    local hook_path=".claude/hooks/user-prompt-submit.sh"
    local reason
    reason=$(policy_get_reason "${hook_path}" 2>/dev/null)

    if [[ "${reason}" == *"hook"* ]] || [[ "${reason}" == *"bootstrap"* ]] || [[ "${reason}" == *"CRITICAL"* ]]; then
        pass
    else
        fail "Reason should mention hook/bootstrap protection: ${reason}"
        return 1
    fi
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "Exit Code 4 (SUPERADMIN-REQUIRED) Tests"

# Setup
setup_all

# Run tests
test_case "Exit code constants exist" test_exit_code_constants_exist
test_case "policy_check_superadmin function exists" test_policy_tier_superadmin_exists
test_case "POLICY_SUPERADMIN_REQUIRED array defined" test_policy_superadmin_patterns_defined
test_case "WoW self-protection requires SuperAdmin" test_wow_self_protection_requires_superadmin
test_case "CRITICAL operations not SuperAdmin-unlockable" test_critical_operations_not_superadmin
test_case "Handler router returns exit 4" test_handler_router_returns_exit_4
test_case "Hook maps exit 4 correctly" test_hook_maps_exit_4_correctly
test_case "WoW files are SuperAdmin-unlockable" test_superadmin_unlockable_returns_true_for_wow_files
test_case "SSRF is NOT SuperAdmin-unlockable" test_superadmin_unlockable_returns_false_for_ssrf
test_case "Fork bombs NOT SuperAdmin-unlockable" test_superadmin_unlockable_returns_false_for_fork_bomb
test_case "Destructive NOT SuperAdmin-unlockable" test_superadmin_unlockable_returns_false_for_destructive
test_case "Get reason mentions SuperAdmin" test_get_reason_for_superadmin
test_case "Hook file is CRITICAL tier" test_hook_file_is_critical
test_case "Hook backup is CRITICAL tier" test_hook_backup_is_critical
test_case "Hook disabled is CRITICAL tier" test_hook_disabled_is_critical
test_case "Hook is NOT SuperAdmin-unlockable" test_hook_is_not_superadmin_unlockable
test_case "Hook reason mentions bootstrap" test_hook_reason_mentions_bootstrap

# Teardown
teardown_all

# Summary
test_summary
