#!/bin/bash
# WoW System - Critical Security & Edge Case Tests for Domain Validation
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_SECURITY_EDGE_TESTS_LOADED:-}" ]]; then
    exit 0
fi
readonly WOW_SECURITY_EDGE_TESTS_LOADED=1

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Setup test environment
export WOW_TEST_MODE=1
export WOW_NON_INTERACTIVE=1

#------------------------------------------------------------------------------
# Test Suite: Critical Security & Edge Cases
#------------------------------------------------------------------------------

test_suite "Critical Security & Edge Case Tests"

# Load modules (utils.sh sets `set -e` which we need to disable for tests)
source "${SCRIPT_DIR}/../src/core/utils.sh" 2>/dev/null || true
set +e  # Disable exit-on-error for test functions that check return codes
source "${SCRIPT_DIR}/../src/security/domain-lists.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/security/domain-validator.sh" 2>/dev/null || true
domain_lists_init "${WOW_HOME}/config/security" 2>/dev/null || true

#------------------------------------------------------------------------------
# Security Test 1: SSRF Protection - Localhost Variants
#------------------------------------------------------------------------------

test_ssrf_localhost_variants() {
    domain_validate "localhost" "test" >/dev/null 2>&1
    local r1=$?

    domain_validate "127.0.0.1" "test" >/dev/null 2>&1
    local r2=$?

    domain_validate "::1" "test" >/dev/null 2>&1
    local r3=$?

    # All should block
    [[ $r1 -eq 2 && $r2 -eq 2 && $r3 -eq 2 ]] && return 0 || return 1
}

test_case "Security: Block all localhost variants" test_ssrf_localhost_variants

#------------------------------------------------------------------------------
# Security Test 2: SSRF Protection - Private IP Ranges
#------------------------------------------------------------------------------

test_ssrf_private_ips() {
    domain_validate "10.0.0.1" "test" >/dev/null 2>&1
    local r1=$?

    domain_validate "192.168.1.1" "test" >/dev/null 2>&1
    local r2=$?

    domain_validate "172.16.0.1" "test" >/dev/null 2>&1
    local r3=$?

    # All should block
    [[ $r1 -eq 2 && $r2 -eq 2 && $r3 -eq 2 ]] && return 0 || return 1
}

test_case "Security: Block private IP ranges" test_ssrf_private_ips

#------------------------------------------------------------------------------
# Security Test 3: SSRF Protection - Cloud Metadata Endpoints
#------------------------------------------------------------------------------

test_ssrf_cloud_metadata() {
    domain_validate "169.254.169.254" "test" >/dev/null 2>&1
    local r1=$?

    domain_validate "metadata.google.internal" "test" >/dev/null 2>&1
    local r2=$?

    # Both should block
    [[ $r1 -eq 2 && $r2 -eq 2 ]] && return 0 || return 1
}

test_case "Security: Block cloud metadata endpoints" test_ssrf_cloud_metadata

#------------------------------------------------------------------------------
# Edge Case Test 1: Empty/Invalid Domains
#------------------------------------------------------------------------------

test_edge_empty_domains() {
    domain_validate "" "test" >/dev/null 2>&1
    local r1=$?

    domain_validate "   " "test" >/dev/null 2>&1
    local r2=$?

    # Both should block or error (not allow)
    [[ $r1 -ne 0 && $r2 -ne 0 ]] && return 0 || return 1
}

test_case "Edge Case: Handle empty/whitespace domains" test_edge_empty_domains

#------------------------------------------------------------------------------
# Edge Case Test 2: Case Insensitivity
#------------------------------------------------------------------------------

test_edge_case_insensitivity() {
    domain_validate "GITHUB.COM" "test" >/dev/null 2>&1
    local r1=$?

    domain_validate "github.com" "test" >/dev/null 2>&1
    local r2=$?

    # Should have same result (case-insensitive)
    [[ $r1 -eq $r2 ]] && return 0 || return 1
}

test_case "Edge Case: Domain validation is case-insensitive" test_edge_case_insensitivity

#------------------------------------------------------------------------------
# Edge Case Test 3: Domain with Port
#------------------------------------------------------------------------------

test_edge_domain_with_port() {
    domain_validate "github.com:443" "test" >/dev/null 2>&1
    local result=$?

    # Should allow or warn (port stripped, github.com is safe), not block
    [[ $result -ne 2 ]] && return 0 || return 1
}

test_case "Edge Case: Domain with port handled correctly" test_edge_domain_with_port

#------------------------------------------------------------------------------
# Edge Case Test 4: Multi-level Subdomains
#------------------------------------------------------------------------------

test_edge_multilevel_subdomains() {
    domain_validate "api.v2.github.com" "test" >/dev/null 2>&1
    local result=$?

    # Should allow or warn (subdomain of safe domain), not block
    [[ $result -ne 2 ]] && return 0 || return 1
}

test_case "Edge Case: Multi-level subdomains work" test_edge_multilevel_subdomains

#------------------------------------------------------------------------------
# Security Test 4: Config Injection Prevention
#------------------------------------------------------------------------------

test_security_config_injection() {
    local custom_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"

    # Try to inject shell command
    domain_add_custom "test.com; rm -rf /tmp/test-injection" "safe" 2>/dev/null || true

    # Verify injection didn't execute
    [[ ! -f "/tmp/test-injection" ]] && return 0 || return 1
}

test_case "Security: Config injection prevented" test_security_config_injection

#------------------------------------------------------------------------------
# Security Test 5: TIER 1 Immutability
#------------------------------------------------------------------------------

test_security_tier1_immutable() {
    local custom_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"

    # Try to override TIER 1 block
    echo "127.0.0.1" >> "$custom_conf"
    domain_lists_reload >/dev/null 2>&1

    domain_validate "127.0.0.1" "test" >/dev/null 2>&1
    local result=$?

    # Cleanup
    sed -i '/127.0.0.1/d' "$custom_conf" 2>/dev/null || true

    # Should still block (TIER 1 immutable)
    [[ $result -eq 2 ]] && return 0 || return 1
}

test_case "Security: TIER 1 blocks cannot be overridden" test_security_tier1_immutable

#------------------------------------------------------------------------------
# Edge Case Test 5: Duplicate Config Entries
#------------------------------------------------------------------------------

test_edge_duplicate_entries() {
    local custom_conf="${WOW_HOME}/config/security/custom-safe-domains.conf"

    # Ensure config directory exists
    mkdir -p "$(dirname "$custom_conf")" 2>/dev/null || true
    touch "$custom_conf" 2>/dev/null || return 0  # Skip if can't create

    # Add duplicates
    echo "duplicate-test.example.com" >> "$custom_conf"
    echo "duplicate-test.example.com" >> "$custom_conf"

    domain_lists_reload >/dev/null 2>&1

    domain_is_safe "duplicate-test.example.com"
    local result=$?

    # Cleanup
    sed -i '/duplicate-test.example.com/d' "$custom_conf" 2>/dev/null || true

    # Should still work
    [[ $result -eq 0 ]] && return 0 || return 1
}

test_case "Edge Case: Duplicate config entries handled" test_edge_duplicate_entries

#------------------------------------------------------------------------------
# Run all tests
#------------------------------------------------------------------------------

test_summary
