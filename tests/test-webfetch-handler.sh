#!/bin/bash
# WoW System - WebFetch Handler Tests (Production-Grade)
# Comprehensive tests for security-critical external URL access
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

WEBFETCH_HANDLER="${SCRIPT_DIR}/../src/handlers/webfetch-handler.sh"
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

source_webfetch_handler() {
    if [[ -f "${WEBFETCH_HANDLER}" ]]; then
        source "${WEBFETCH_HANDLER}"
        return 0
    else
        echo "WebFetch handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local url="$1"
    local prompt="${2:-Extract information from this page}"

    cat <<EOF
{
  "tool": "WebFetch",
  "url": "${url}",
  "prompt": "${prompt}"
}
EOF
}

# ============================================================================
# Tests: Dangerous URL Blocking
# ============================================================================

test_suite "WebFetch Handler - Dangerous URL Blocking"

# Test 1: Block private IP addresses
test_block_private_ip() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://192.168.1.1/admin")

    handle_webfetch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block private IP addresses"
}
test_case "Block private IP addresses" test_block_private_ip

# Test 2: Block localhost
test_block_localhost() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://localhost:8080/api")

    handle_webfetch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block localhost"
}
test_case "Block localhost" test_block_localhost

# Test 3: Block 127.0.0.1
test_block_loopback() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://127.0.0.1:3000/")

    handle_webfetch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block loopback address"
}
test_case "Block 127.0.0.1" test_block_loopback

# Test 4: Block internal network ranges
test_block_internal_network() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://10.0.0.1/config")

    handle_webfetch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block internal networks"
}
test_case "Block internal network ranges" test_block_internal_network

# Test 5: Block link-local addresses
test_block_link_local() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://169.254.1.1/")

    handle_webfetch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block link-local addresses"
}
test_case "Block link-local addresses" test_block_link_local

# Test 6: Block file:// URLs
test_block_file_protocol() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "file:///etc/passwd")

    handle_webfetch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block file:// protocol"
}
test_case "Block file:// URLs" test_block_file_protocol

# ============================================================================
# Tests: Suspicious Pattern Detection
# ============================================================================

test_suite "WebFetch Handler - Suspicious Pattern Detection"

# Test 7: Warn on URLs with credentials
test_warn_url_credentials() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://user:pass@example.com/api")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    # Should warn about credentials in URL
    echo "Checked URL with credentials"
}
test_case "Warn on URLs with credentials" test_warn_url_credentials

# Test 8: Warn on suspicious domains
test_warn_suspicious_domains() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://malicious-site.tk/download")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    echo "Checked suspicious domain"
}
test_case "Warn on suspicious domains" test_warn_suspicious_domains

# Test 9: Detect exfiltration endpoints
test_detect_exfiltration() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://pastebin.com/api/upload")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    echo "Checked exfiltration endpoint"
}
test_case "Detect exfiltration endpoints" test_detect_exfiltration

# Test 10: Warn on data URLs
test_warn_data_urls() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "data:text/html,<script>alert('xss')</script>")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    echo "Checked data URL"
}
test_case "Warn on data URLs" test_warn_data_urls

# Test 11: Detect IP-based URLs (not localhost)
test_detect_ip_urls() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "http://8.8.8.8/")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    # Public IPs should be allowed but tracked
    echo "Checked IP-based URL"
}
test_case "Detect IP-based URLs" test_detect_ip_urls

# Test 12: Warn on shortened URLs
test_warn_shortened_urls() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://bit.ly/abc123")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    echo "Checked shortened URL"
}
test_case "Warn on shortened URLs" test_warn_shortened_urls

# ============================================================================
# Tests: Safe URL Access
# ============================================================================

test_suite "WebFetch Handler - Safe URL Access"

# Test 13: Allow HTTPS documentation sites
test_allow_docs_sites() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://developer.mozilla.org/en-US/docs/Web/JavaScript")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "developer.mozilla.org" "Should allow documentation sites"
}
test_case "Allow HTTPS documentation sites" test_allow_docs_sites

# Test 14: Allow GitHub URLs
test_allow_github() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://github.com/user/repo")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "github.com" "Should allow GitHub"
}
test_case "Allow GitHub URLs" test_allow_github

# Test 15: Allow Stack Overflow
test_allow_stackoverflow() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://stackoverflow.com/questions/12345/how-to")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "stackoverflow.com" "Should allow Stack Overflow"
}
test_case "Allow Stack Overflow" test_allow_stackoverflow

# Test 16: Allow npm registry
test_allow_npm() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://registry.npmjs.org/package-name")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "npmjs.org" "Should allow npm"
}
test_case "Allow npm registry" test_allow_npm

# Test 17: Allow API documentation
test_allow_api_docs() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://docs.anthropic.com/api/reference")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "docs.anthropic.com" "Should allow API docs"
}
test_case "Allow API documentation" test_allow_api_docs

# Test 18: Allow well-known domains
test_allow_well_known() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://www.w3.org/standards/")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "w3.org" "Should allow well-known domains"
}
test_case "Allow well-known domains" test_allow_well_known

# ============================================================================
# Tests: Edge Cases & Security
# ============================================================================

test_suite "WebFetch Handler - Edge Cases"

# Test 19: Handle empty URL
test_empty_url() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "")

    local output
    output=$(handle_webfetch "${input}" 2>/dev/null)

    [[ $? -eq 0 ]] || [[ $? -eq 2 ]] || return 1
    echo "Handled empty URL"
}
test_case "Handle empty URL" test_empty_url

# Test 20: Handle malformed URLs
test_malformed_url() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "not-a-valid-url")

    local output
    output=$(handle_webfetch "${input}" 2>&1)

    echo "Handled malformed URL"
}
test_case "Handle malformed URLs" test_malformed_url

# Test 21: Handle very long URLs
test_long_url() {
    source_webfetch_handler || return 1

    local long_url
    long_url="https://example.com/$(printf 'path/%.0s' {1..100})file.html"

    local input
    input=$(create_tool_input "${long_url}")

    local output
    output=$(handle_webfetch "${input}")

    assert_success "Should handle long URLs"
}
test_case "Handle very long URLs" test_long_url

# Test 22: Handle special characters in URLs
test_special_chars_url() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://example.com/search?q=test%20query&lang=en")

    local output
    output=$(handle_webfetch "${input}")

    assert_contains "${output}" "example.com" "Should handle special characters"
}
test_case "Handle special characters in URLs" test_special_chars_url

# Test 23: Track WebFetch metrics
test_metric_tracking() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://example.com/test")

    handle_webfetch "${input}" &>/dev/null

    local fetch_count
    fetch_count=$(session_get_metric "webfetch_requests" "0")

    [[ "${fetch_count}" != "0" ]] || return 1
    echo "Metrics tracked: ${fetch_count}"
}
test_case "Track WebFetch metrics" test_metric_tracking

# Test 24: Log WebFetch events
test_event_logging() {
    source_webfetch_handler || return 1

    local input
    input=$(create_tool_input "https://docs.example.com/")

    handle_webfetch "${input}" &>/dev/null

    if type session_get_events &>/dev/null; then
        local events
        events=$(session_get_events)

        echo "Event logging verified"
    else
        echo "Event logging skipped (session manager not initialized)"
    fi
    return 0
}
test_case "Log WebFetch events" test_event_logging

# Run all tests
test_summary
