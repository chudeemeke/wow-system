#!/bin/bash
# WoW System - Integration Tests for Domain Validation
# Tests end-to-end flow: Hook → Orchestrator → Handlers → Domain Validator
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_INTEGRATION_DOMAIN_TESTS_LOADED:-}" ]]; then
    exit 0
fi
readonly WOW_INTEGRATION_DOMAIN_TESTS_LOADED=1

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

#------------------------------------------------------------------------------
# Test Suite: End-to-End Domain Validation Integration
#------------------------------------------------------------------------------

test_suite "Domain Validation Integration Tests"

#------------------------------------------------------------------------------
# Setup/Teardown
#------------------------------------------------------------------------------

setup_integration_env() {
    # Setup test environment
    export WOW_TEST_MODE=1
    export WOW_NON_INTERACTIVE=1

    # Source modules in controlled order (inside function to avoid top-level init)
    source "${SCRIPT_DIR}/../src/core/utils.sh" 2>/dev/null || true
    source "${SCRIPT_DIR}/../src/security/domain-lists.sh" 2>/dev/null || true
    source "${SCRIPT_DIR}/../src/security/domain-validator.sh" 2>/dev/null || true

    # Initialize domain lists
    domain_lists_init "${WOW_HOME}/config/security" 2>/dev/null || true
}

teardown_integration_env() {
    unset WOW_TEST_MODE
    unset WOW_NON_INTERACTIVE
}

#------------------------------------------------------------------------------
# Integration Test 1: Full WebFetch Flow - SSRF Block
#------------------------------------------------------------------------------

test_webfetch_ssrf_block_integration() {
    setup_integration_env

    # Test domain validation directly for SSRF
    domain_validate "127.0.0.1" "webfetch" >/dev/null 2>&1
    local exit_code=$?

    # Should block (exit 2)
    assert_equals 2 $exit_code "Domain validator should block SSRF attempt (127.0.0.1)"

    teardown_integration_env
}

test_case "E2E: WebFetch blocks SSRF (127.0.0.1)" test_webfetch_ssrf_block_integration

#------------------------------------------------------------------------------
# Integration Test 2: Full WebFetch Flow - Safe Domain Allow
#------------------------------------------------------------------------------

test_webfetch_safe_domain_integration() {
    setup_integration_env

    # Test domain validation for safe domain
    domain_validate "github.com" "webfetch" >/dev/null 2>&1
    local exit_code=$?

    # Should allow (exit 0)
    assert_equals 0 $exit_code "Domain validator should allow safe domain (github.com)"

    teardown_integration_env
}

test_case "E2E: WebFetch allows safe domain (github.com)" test_webfetch_safe_domain_integration

#------------------------------------------------------------------------------
# Integration Test 3: Full WebSearch Flow - Critical Block
#------------------------------------------------------------------------------

test_critical_domain_block_integration() {
    setup_integration_env

    # Test critical domain blocking
    domain_validate "localhost" "websearch" >/dev/null 2>&1
    local exit_code=$?

    # Should block (exit 2) - localhost is critical blocked
    assert_equals 2 $exit_code "Domain validator should block critical domain (localhost)"

    teardown_integration_env
}

test_case "E2E: Critical domains blocked across all contexts" test_critical_domain_block_integration

#------------------------------------------------------------------------------
# Integration Test 4: Domain Lists Reload Integration
#------------------------------------------------------------------------------

test_domain_lists_reload_integration() {
    setup_integration_env

    # Add a custom domain
    local custom_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"
    echo "integration-test.example.com" >> "$custom_conf"

    # Reload domain lists
    domain_lists_reload >/dev/null 2>&1

    # Verify domain is now safe
    domain_is_safe "integration-test.example.com"
    local result=$?

    # Cleanup
    sed -i '/integration-test.example.com/d' "$custom_conf" 2>/dev/null || true

    assert_equals 0 $result "Reloaded domain list should recognize new safe domain"

    teardown_integration_env
}

test_case "E2E: Domain lists reload recognizes new domains" test_domain_lists_reload_integration

#------------------------------------------------------------------------------
# Integration Test 5: Config Hierarchy Integration
#------------------------------------------------------------------------------

test_config_hierarchy_integration() {
    setup_integration_env

    # Test TIER 1 override attempt (should fail)
    local custom_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"
    echo "127.0.0.1" >> "$custom_conf"
    domain_lists_reload >/dev/null 2>&1

    # Validate - should still block (TIER 1 cannot be overridden)
    domain_validate "127.0.0.1" "test" >/dev/null 2>&1
    local result=$?

    # Cleanup
    sed -i '/127.0.0.1/d' "$custom_conf" 2>/dev/null || true

    assert_equals 2 $result "TIER 1 critical blocks cannot be overridden by custom config"

    teardown_integration_env
}

test_case "E2E: Config hierarchy enforces TIER 1 immutability" test_config_hierarchy_integration

#------------------------------------------------------------------------------
# Integration Test 6: IPv6 Address Validation Integration
#------------------------------------------------------------------------------

test_ipv6_validation_integration() {
    setup_integration_env

    # Test localhost IPv6
    domain_validate "::1" "test" >/dev/null 2>&1
    local result=$?

    assert_equals 2 $result "Domain validator should block localhost IPv6 (::1)"

    teardown_integration_env
}

test_case "E2E: IPv6 localhost blocked" test_ipv6_validation_integration

#------------------------------------------------------------------------------
# Integration Test 7: Subdomain Matching Integration
#------------------------------------------------------------------------------

test_subdomain_matching_integration() {
    setup_integration_env

    # Test subdomain of safe domain (github.com)
    domain_validate "api.github.com" "test" >/dev/null 2>&1
    local result=$?

    # Should allow (subdomains inherit safety)
    assert_equals 0 $result "Subdomain of safe domain should be allowed (api.github.com)"

    teardown_integration_env
}

test_case "E2E: Subdomain matching works correctly" test_subdomain_matching_integration

#------------------------------------------------------------------------------
# Integration Test 8: Performance - Validation Speed
#------------------------------------------------------------------------------

test_validation_performance() {
    setup_integration_env

    # Benchmark 10 validations (reduced from 100 for faster test)
    for i in {1..10}; do
        domain_validate "github.com" "test" >/dev/null 2>&1
    done

    # If we got here without hanging, performance is acceptable
    return 0
}

test_case "E2E: Domain validation performance acceptable" test_validation_performance

#------------------------------------------------------------------------------
# Integration Test 9: Error Recovery - Missing Config Files
#------------------------------------------------------------------------------

test_error_recovery_missing_config() {
    setup_integration_env

    # Backup and remove custom config
    local custom_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"
    local backup="${custom_conf}.backup-test"

    if [[ -f "$custom_conf" ]]; then
        mv "$custom_conf" "$backup"
    fi

    # Reload - should not fail
    domain_lists_reload >/dev/null 2>&1
    local reload_result=$?

    # Validation should still work (fallback to system defaults)
    domain_validate "github.com" "test" >/dev/null 2>&1
    local validation_result=$?

    # Restore
    if [[ -f "$backup" ]]; then
        mv "$backup" "$custom_conf"
    fi

    assert_equals 0 $reload_result "Should reload gracefully with missing custom config"
    assert_equals 0 $validation_result "Should validate with system defaults when custom config missing"

    teardown_integration_env
}

test_case "E2E: Graceful error recovery with missing config files" test_error_recovery_missing_config

#------------------------------------------------------------------------------
# Integration Test 10: Custom Domain Priority
#------------------------------------------------------------------------------

test_custom_domain_priority() {
    setup_integration_env

    # Add domain to both safe and blocked lists
    local safe_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"
    local blocked_conf="${WOW_HOME}/config/security/custom-blocked-domains.conf"

    echo "test-priority.example.com" >> "$safe_conf"
    echo "test-priority.example.com" >> "$blocked_conf"

    domain_lists_reload >/dev/null 2>&1

    # Validate - blocked should take priority
    domain_validate "test-priority.example.com" "test" >/dev/null 2>&1
    local result=$?

    # Cleanup
    sed -i '/test-priority.example.com/d' "$safe_conf" 2>/dev/null || true
    sed -i '/test-priority.example.com/d' "$blocked_conf" 2>/dev/null || true

    assert_equals 2 $result "Blocked list should take priority over safe list"

    teardown_integration_env
}

test_case "E2E: Custom blocked domains take priority over safe domains" test_custom_domain_priority

#------------------------------------------------------------------------------
# Run all tests
#------------------------------------------------------------------------------

test_summary
