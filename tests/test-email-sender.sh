#!/bin/bash
# WoW System - Email Sender Test Suite
# Comprehensive tests for email functionality
# Author: Chude <chude@emeke.org>

set -euo pipefail

# ============================================================================
# Test Setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOW_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the email sender
source "$WOW_ROOT/src/tools/email-sender.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Test Framework
# ============================================================================

print_test_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_success() {
    local command="$1"
    local test_name="$2"

    ((TESTS_RUN++))

    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Command failed: $command"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_failure() {
    local command="$1"
    local test_name="$2"

    ((TESTS_RUN++))

    if ! eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Command should have failed: $command"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  String does not contain: '$needle'"
        echo "  Actual: '$haystack'"
        ((TESTS_FAILED++))
        return 1
    fi
}

# ============================================================================
# Test: OS Detection
# ============================================================================

test_os_detection() {
    print_test_header "Test 1: OS Detection"

    local os
    os=$(_email_detect_os)

    assert_contains "WSL LINUX MAC UNKNOWN" "$os" "OS detection returns valid value"

    if [[ "$os" == "UNKNOWN" ]]; then
        echo -e "${YELLOW}⚠${NC}  Warning: Running on unknown OS"
    fi
}

# ============================================================================
# Test: Keychain Availability
# ============================================================================

test_keychain_availability() {
    print_test_header "Test 2: Keychain Availability"

    local os
    os=$(_email_detect_os)

    case "$os" in
        WSL|LINUX)
            if command -v secret-tool &>/dev/null; then
                assert_success "_email_has_keychain" "Keychain tools available (libsecret-tools)"
            else
                echo -e "${YELLOW}⚠${NC}  libsecret-tools not installed - skipping keychain tests"
                echo "  Install with: sudo apt-get install libsecret-tools"
            fi
            ;;
        MAC)
            assert_success "_email_has_keychain" "Keychain tools available (macOS security)"
            ;;
        *)
            echo -e "${YELLOW}⚠${NC}  Unsupported OS - skipping keychain tests"
            ;;
    esac
}

# ============================================================================
# Test: Initialization
# ============================================================================

test_initialization() {
    print_test_header "Test 3: Initialization"

    assert_success "email_init" "Email system initializes successfully"
    assert_success "test -d '$WOW_DATA_DIR'" "Data directory created"
}

# ============================================================================
# Test: Configuration
# ============================================================================

test_configuration() {
    print_test_header "Test 4: Configuration Reading"

    # Test reading config values
    local enabled
    enabled=$(_email_get_config "enabled" "false")
    assert_contains "true false" "$enabled" "Config 'enabled' is boolean"

    local priority_threshold
    priority_threshold=$(_email_get_config "priority_threshold" "HIGH")
    assert_contains "LOW NORMAL HIGH CRITICAL" "$priority_threshold" "Priority threshold is valid"

    local rate_limit
    rate_limit=$(_email_get_config "rate_limit" "5")
    [[ "$rate_limit" =~ ^[0-9]+$ ]]
    assert_equals "0" "$?" "Rate limit is numeric"
}

# ============================================================================
# Test: Sensitive Data Filtering
# ============================================================================

test_sensitive_filtering() {
    print_test_header "Test 5: Sensitive Data Filtering"

    local test_output="This contains a password: secret123"
    local filtered
    filtered=$(echo "$test_output" | _email_filter_sensitive)

    assert_equals "(sensitive data filtered)" "$filtered" "Password filtered from output"

    test_output="Normal log message without secrets"
    filtered=$(echo "$test_output" | _email_filter_sensitive)

    assert_equals "$test_output" "$filtered" "Non-sensitive data passes through"
}

# ============================================================================
# Test: Rate Limiting
# ============================================================================

test_rate_limiting() {
    print_test_header "Test 6: Rate Limiting"

    # Clear rate limit file
    rm -f "$EMAIL_RATE_LIMIT_FILE"

    # Record some emails
    _email_record_sent "Test 1"
    _email_record_sent "Test 2"
    _email_record_sent "Test 3"

    # Check file exists
    assert_success "test -f '$EMAIL_RATE_LIMIT_FILE'" "Rate limit file created"

    # Check content
    local count
    count=$(wc -l < "$EMAIL_RATE_LIMIT_FILE")
    assert_equals "3" "$count" "Rate limit tracking records emails"

    # Clean up
    rm -f "$EMAIL_RATE_LIMIT_FILE"
}

# ============================================================================
# Test: Fallback to File
# ============================================================================

test_fallback_to_file() {
    print_test_header "Test 7: Fallback to File"

    local alert_file="${WOW_DATA_DIR}/email-alerts.log"
    rm -f "$alert_file"

    email_fallback_to_file "Test Subject" "Test Body" "NORMAL"

    assert_success "test -f '$alert_file'" "Alert file created"

    local content
    content=$(cat "$alert_file")
    assert_contains "$content" "Test Subject" "Alert file contains subject"
    assert_contains "$content" "Test Body" "Alert file contains body"
    assert_contains "$content" "Priority: NORMAL" "Alert file contains priority"

    # Clean up
    rm -f "$alert_file"
}

# ============================================================================
# Test: Email Alert Formatting
# ============================================================================

test_email_alert_formatting() {
    print_test_header "Test 8: Email Alert Formatting"

    # This test captures the alert to a file instead of sending
    local alert_file="${WOW_DATA_DIR}/email-alerts.log"
    rm -f "$alert_file"

    email_send_alert "TEST" "This is a test message"

    # Since email is likely not configured, it should fallback to file
    if [[ -f "$alert_file" ]]; then
        local content
        content=$(cat "$alert_file")
        assert_contains "$content" "Alert Type: TEST" "Alert contains type"
        assert_contains "$content" "This is a test message" "Alert contains message"
    else
        echo -e "${YELLOW}⚠${NC}  Email might be configured - skipping fallback test"
    fi

    # Clean up
    rm -f "$alert_file"
}

# ============================================================================
# Test: Configuration Status
# ============================================================================

test_configuration_status() {
    print_test_header "Test 9: Configuration Status"

    local status
    status=$(email_get_credentials_status)

    assert_contains "CONFIGURED NOT_CONFIGURED" "$status" "Credentials status is valid"

    if email_is_configured; then
        echo -e "${GREEN}✓${NC} Email is fully configured"
    else
        echo -e "${YELLOW}⚠${NC}  Email is not configured (this is normal for fresh install)"
    fi
}

# ============================================================================
# Test: SMTP Config Parsing
# ============================================================================

test_smtp_config_parsing() {
    print_test_header "Test 10: SMTP Config Parsing"

    if _email_get_smtp_config &>/dev/null; then
        local smtp_config
        smtp_config=$(_email_get_smtp_config)

        local smtp_host smtp_port from_address to_address
        IFS='|' read -r smtp_host smtp_port from_address to_address <<< "$smtp_config"

        assert_success "test -n '$smtp_host'" "SMTP host is set"
        assert_success "test -n '$smtp_port'" "SMTP port is set"
        assert_success "[[ '$smtp_port' =~ ^[0-9]+$ ]]" "SMTP port is numeric"

        echo -e "${GREEN}✓${NC} SMTP configuration is valid"
    else
        echo -e "${YELLOW}⚠${NC}  SMTP not configured - this is normal for fresh install"
    fi
}

# ============================================================================
# Test Summary
# ============================================================================

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Test Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Total Tests:  $TESTS_RUN"
    echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
    else
        echo "Failed:       $TESTS_FAILED"
    fi

    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         WoW System - Email Sender Test Suite                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"

    test_os_detection
    test_keychain_availability
    test_initialization
    test_configuration
    test_sensitive_filtering
    test_rate_limiting
    test_fallback_to_file
    test_email_alert_formatting
    test_configuration_status
    test_smtp_config_parsing

    print_summary
}

# Run tests
main
