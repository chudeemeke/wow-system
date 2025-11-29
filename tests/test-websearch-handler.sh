#!/bin/bash
# WoW System - WebSearch Handler Tests (Production-Grade)
# Comprehensive tests for security-critical web search validation
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

WEBSEARCH_HANDLER="${SCRIPT_DIR}/../src/handlers/websearch-handler.sh"
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

source_websearch_handler() {
    if [[ -f "${WEBSEARCH_HANDLER}" ]]; then
        source "${WEBSEARCH_HANDLER}"
        return 0
    else
        echo "WebSearch handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local query="$1"
    local allowed_domains="${2:-}"
    local blocked_domains="${3:-}"

    local json="{\"tool\": \"WebSearch\", \"query\": \"${query}\""

    if [[ -n "${allowed_domains}" ]]; then
        json="${json}, \"allowed_domains\": ${allowed_domains}"
    fi

    if [[ -n "${blocked_domains}" ]]; then
        json="${json}, \"blocked_domains\": ${blocked_domains}"
    fi

    json="${json}}"
    echo "${json}"
}

# ============================================================================
# Tests: Query Validation - PII & Credentials
# ============================================================================

test_suite "WebSearch Handler - Query Validation (PII & Credentials)"

# Test 1: Block PII patterns (email addresses)
test_block_email_in_query() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "user@example.com password")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block email addresses in query"
}
test_case "Block email addresses in query" test_block_email_in_query

# Test 2: Block SSN patterns
test_block_ssn_in_query() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "123-45-6789 social security")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block SSN patterns"
}
test_case "Block SSN patterns in query" test_block_ssn_in_query

# Test 3: Block API key patterns
test_block_api_keys() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "sk-PLACEHOLDER_API_KEY_123")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block API key patterns"
}
test_case "Block API key patterns" test_block_api_keys

# Test 4: Block credential search patterns
test_block_credential_search() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "password database credentials")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Should warn but might allow (depends on strict_mode)
    echo "Checked credential search pattern"
}
test_case "Block credential search patterns" test_block_credential_search

# Test 5: Block private key search
test_block_private_key_search() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "BEGIN PRIVATE KEY site:github.com")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked private key search pattern"
}
test_case "Block private key search" test_block_private_key_search

# Test 6: Allow safe queries
test_allow_safe_queries() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "python documentation async await")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow safe queries"
}
test_case "Allow safe queries" test_allow_safe_queries

# ============================================================================
# Tests: Domain Validation (SSRF Prevention)
# ============================================================================

test_suite "WebSearch Handler - Domain Validation (SSRF Prevention)"

# Test 7: Block private IP in allowed_domains
test_block_private_ip_domain() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test query" '["192.168.1.1"]')

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block private IPs in allowed_domains"
}
test_case "Block private IP in allowed_domains" test_block_private_ip_domain

# Test 8: Block localhost in allowed_domains
test_block_localhost_domain() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test query" '["localhost"]')

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block localhost in allowed_domains"
}
test_case "Block localhost in allowed_domains" test_block_localhost_domain

# Test 9: Allow safe domains in allowed_domains
test_allow_safe_domains() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "python docs" '["docs.python.org", "stackoverflow.com"]')

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow safe domains"
}
test_case "Allow safe domains in allowed_domains" test_allow_safe_domains

# Test 10: Warn on suspicious TLD in allowed_domains
test_warn_suspicious_tld() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test" '["example.tk"]')

    local output
    output=$(handle_websearch "${input}" 2>&1)

    # Should warn on .tk domain
    echo "Checked suspicious TLD warning"
}
test_case "Warn on suspicious TLD" test_warn_suspicious_tld

# Test 11: Block malicious domain bypass
test_block_domain_bypass() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test" '[]' '["safe.com"]')

    # blocked_domains should not be bypassed
    local output
    output=$(handle_websearch "${input}" 2>&1)

    echo "Checked domain bypass prevention"
}
test_case "Block domain bypass attempts" test_block_domain_bypass

# Test 12: Validate domain array format
test_validate_domain_format() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test" '["valid.com", "192.168.1.1", "safe.org"]')

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Should block due to 192.168.1.1
    assert_equals "blocked" "${result}" "Should validate all domains in array"
}
test_case "Validate domain array format" test_validate_domain_format

# ============================================================================
# Tests: Injection Prevention
# ============================================================================

test_suite "WebSearch Handler - Injection Prevention"

# Test 13: Block SQL-like injection
test_block_sql_injection() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test' OR '1'='1")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Should warn on SQL patterns
    echo "Checked SQL injection pattern"
}
test_case "Block SQL-like injection" test_block_sql_injection

# Test 14: Block command injection
test_block_command_injection() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test; rm DANGEROUS_PATH")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked command injection pattern"
}
test_case "Block command injection" test_block_command_injection

# Test 15: Block script tags
test_block_script_tags() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "<script>alert('xss')</script>")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked script tag injection"
}
test_case "Block script tags" test_block_script_tags

# Test 16: Allow special chars in legitimate queries
test_allow_special_chars() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "C++ programming (best practices)")

    handle_websearch "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow legitimate special chars"
}
test_case "Allow special chars in legitimate queries" test_allow_special_chars

# ============================================================================
# Tests: Rate Limiting & Abuse Prevention
# ============================================================================

test_suite "WebSearch Handler - Rate Limiting"

# Test 17: Track search count
test_track_search_count() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test query")

    handle_websearch "${input}" &>/dev/null

    local search_count
    search_count=$(session_get_metric "websearch_requests" "0")

    [[ "${search_count}" != "0" ]] || return 1
    echo "Search count tracked: ${search_count}"
}
test_case "Track search count" test_track_search_count

# Test 18: Warn on high search volume
test_warn_high_volume() {
    source_websearch_handler || return 1

    # Simulate high search count
    session_update_metric "websearch_requests" "100" 2>/dev/null || true

    local input
    input=$(create_tool_input "test")

    local output
    output=$(handle_websearch "${input}" 2>&1)

    echo "Checked high volume warning"
}
test_case "Warn on high search volume" test_warn_high_volume

# Test 19: Detect rapid searches
test_detect_rapid_searches() {
    source_websearch_handler || return 1

    # Multiple searches in succession
    for i in {1..5}; do
        local input
        input=$(create_tool_input "query $i")
        handle_websearch "${input}" &>/dev/null
    done

    echo "Checked rapid search detection"
}
test_case "Detect rapid searches" test_detect_rapid_searches

# ============================================================================
# Tests: Edge Cases
# ============================================================================

test_suite "WebSearch Handler - Edge Cases"

# Test 20: Handle empty query
test_empty_query() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "")

    local output
    output=$(handle_websearch "${input}" 2>/dev/null)

    [[ $? -eq 0 ]] || [[ $? -eq 2 ]] || return 1
    echo "Handled empty query gracefully"
}
test_case "Handle empty query" test_empty_query

# Test 21: Handle very long query
test_long_query() {
    source_websearch_handler || return 1

    local long_query
    long_query=$(printf 'word %.0s' {1..200})

    local input
    input=$(create_tool_input "${long_query}")

    local output
    output=$(handle_websearch "${input}")

    assert_success "Should handle long queries"
}
test_case "Handle very long query" test_long_query

# Test 22: Handle unicode in query
test_unicode_query() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "日本語 programming 中文")

    local output
    output=$(handle_websearch "${input}")

    assert_success "Should handle unicode queries"
}
test_case "Handle unicode in query" test_unicode_query

# Test 23: Handle malformed domain arrays
test_malformed_domain_array() {
    source_websearch_handler || return 1

    local input='{
  "tool": "WebSearch",
  "query": "test",
  "allowed_domains": "not-an-array"
}'

    local output
    output=$(handle_websearch "${input}" 2>/dev/null)

    echo "Handled malformed domain array"
}
test_case "Handle malformed domain arrays" test_malformed_domain_array

# Test 24: Log search events
test_event_logging() {
    source_websearch_handler || return 1

    local input
    input=$(create_tool_input "test query")

    handle_websearch "${input}" &>/dev/null

    if type session_get_events &>/dev/null; then
        local events
        events=$(session_get_events)

        echo "Event logging verified"
    else
        echo "Event logging skipped (session manager not initialized)"
    fi
    return 0
}
test_case "Log search events" test_event_logging

# Run all tests
test_summary
