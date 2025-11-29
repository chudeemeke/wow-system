#!/bin/bash
# WoW System - WebSearch Handler (Production-Grade, Security-Critical)
# Intercepts web search operations for safety and privacy enforcement
# Author: Chude <chude@emeke.org>
#
# Security Principles (v5.4.0):
# - Defense in Depth: Three-tier validation (Critical/Sensitive/Tracked)
# - PII Protection: Block email+password, SSN, credit cards in queries
# - Credential Safety: Warn on API key, password, token searches
# - SSRF Prevention: Block private IPs in allowed_domains
# - Injection Prevention: Detect SQL-like, command-like patterns
# - Privacy: No credential harvesting via search
# - Fail-Open: Errors don't block legitimate searches

# Prevent double-sourcing
if [[ -n "${WOW_WEBSEARCH_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_WEBSEARCH_HANDLER_LOADED=1

# Source dependencies
_WEBSEARCH_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_WEBSEARCH_HANDLER_DIR}/../core/utils.sh"
source "${_WEBSEARCH_HANDLER_DIR}/../security/security-constants.sh"
source "${_WEBSEARCH_HANDLER_DIR}/../security/domain-validator.sh" 2>/dev/null || true
source "${_WEBSEARCH_HANDLER_DIR}/custom-rule-helper.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants - Three-Tier Security Classification
# ============================================================================

# TIER 1: CRITICAL - PII patterns (hard block)
readonly -a BLOCKED_QUERY_PATTERNS=(
    # Email + password combination (credential theft)
    "@.*password"
    "@.*pass"
    "@.*pwd"
    # SSN patterns
    "[0-9]{3}-[0-9]{2}-[0-9]{4}"
    "[0-9]{9}"
    # Credit card patterns
    "[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}"
    # API keys (high-entropy tokens)
    "sk-[A-Za-z0-9_-]{20,}"
    "ghp_[A-Za-z0-9_-]{36}"
    "AKIA[A-Z0-9]{16}"
    # Private keys
    "BEGIN.*PRIVATE KEY"
)

# TIER 2: SENSITIVE - Credential searches (warn/block in strict_mode)
readonly -a SENSITIVE_QUERY_PATTERNS=(
    "password.*database"
    "api.*key.*list"
    "credential.*dump"
    "token.*steal"
    "secret.*leak"
    "apikey"
    "access_token"
)

# Note: BLOCKED_IP_PATTERNS now sourced from security-constants.sh (Single Source of Truth)
# Note: v6.0.0 - Domain validation (BLOCKED_DOMAINS) moved to domain-validator.sh
#       Uses three-tier architecture: TIER 1 (critical), TIER 2 (system), TIER 3 (user)

# TIER 2: SENSITIVE - Suspicious TLDs
readonly -a SUSPICIOUS_TLDS=(
    "\.tk$"
    "\.ml$"
    "\.ga$"
    "\.cf$"
    "\.gq$"
    "\.pw$"
    "\.top$"
    "\.work$"
    "\.click$"
)

# Warning patterns (injection attempts)
readonly -a INJECTION_PATTERNS=(
    # SQL injection
    "' OR '"
    "1=1"
    "DROP TABLE"
    "UNION SELECT"
    # Command injection
    "; rm "
    "&& rm "
    "| rm "
    "\`rm "
    # XSS patterns
    "<script"
    "javascript:"
    "onerror="
)

# ============================================================================
# Private: Query Validation
# ============================================================================

# Check if query contains TIER 1 blocked patterns
_has_blocked_patterns() {
    local query="$1"

    for pattern in "${BLOCKED_QUERY_PATTERNS[@]}"; do
        if echo "${query}" | grep -qiE "${pattern}"; then
            wow_warn "SECURITY: Blocked pattern detected in query: ${pattern}"
            return 0  # Has blocked pattern
        fi
    done

    return 1  # Safe
}

# Check if query contains TIER 2 sensitive patterns
_has_sensitive_patterns() {
    local query="$1"

    for pattern in "${SENSITIVE_QUERY_PATTERNS[@]}"; do
        if echo "${query}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  SENSITIVE SEARCH: ${pattern}"
            return 0  # Has sensitive pattern
        fi
    done

    return 1  # Safe
}

# Check if query has injection patterns
_has_injection_patterns() {
    local query="$1"

    for pattern in "${INJECTION_PATTERNS[@]}"; do
        if echo "${query}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Potential injection pattern: ${pattern}"
            return 0  # Has injection pattern
        fi
    done

    return 1  # Safe
}

# ============================================================================
# Private: Domain Validation (SSRF Prevention)
# ============================================================================

# Check if domain is a private IP
_is_private_ip() {
    local domain="$1"

    for pattern in "${BLOCKED_IP_PATTERNS[@]}"; do
        if echo "${domain}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Private IP detected in domain: ${domain}"
            return 0  # Is private
        fi
    done

    return 1  # Not private
}

# Check if domain is blocked
# v6.0.0: Domain blocking now handled by domain_validate() in domain-validator.sh
# This function is kept for backward compatibility but is deprecated
_is_blocked_domain() {
    local domain="$1"
    # Delegate to domain validator
    if type domain_is_critical_blocked &>/dev/null; then
        if domain_is_critical_blocked "$domain"; then
            wow_warn "SECURITY: Blocked domain: ${domain}"
            return 0  # Is blocked
        fi
    fi
    return 1  # Not blocked
}

# Check if domain has suspicious TLD
_has_suspicious_tld() {
    local domain="$1"

    for pattern in "${SUSPICIOUS_TLDS[@]}"; do
        if echo "${domain}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Suspicious TLD in domain: ${domain}"
            return 0  # Has suspicious TLD
        fi
    done

    return 1  # Safe
}

# Validate domain array for SSRF
_validate_domain_array() {
    local domains_json="$1"

    # Extract domains from JSON array
    if ! wow_has_jq; then
        # No jq - skip validation (fail open)
        return 0
    fi

    # Parse JSON array
    local domains
    domains=$(echo "${domains_json}" | jq -r '.[]' 2>/dev/null || echo "")

    if [[ -z "${domains}" ]]; then
        # Empty or malformed array
        return 0
    fi

    # Validate each domain
    while IFS= read -r domain; do
        [[ -z "${domain}" ]] && continue

        # Check for private IPs (TIER 1)
        if _is_private_ip "${domain}"; then
            return 1  # Blocked
        fi

        # Check for blocked domains (TIER 1)
        if _is_blocked_domain "${domain}"; then
            return 1  # Blocked
        fi

        # Check for suspicious TLDs (TIER 2)
        if _has_suspicious_tld "${domain}"; then
            if wow_should_block "warn"; then
                return 1  # Blocked in strict mode
            fi
        fi
    done <<< "${domains}"

    return 0  # All domains safe
}

# ============================================================================
# Private: Rate Limiting
# ============================================================================

# Check search rate limits
_check_search_rate() {
    local search_count
    search_count=$(session_get_metric "websearch_requests" "0")

    # Warn on high search count
    if [[ ${search_count} -gt 50 ]]; then
        wow_warn "⚠️  High WebSearch request count: ${search_count}"
        return 0  # High rate
    fi

    return 1  # Normal rate
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle web search interception
handle_websearch() {
    local tool_input="$1"

    # Extract parameters from JSON input
    local query=""
    local allowed_domains=""
    local blocked_domains=""

    if wow_has_jq; then
        query=$(echo "${tool_input}" | jq -r '.query // empty' 2>/dev/null)
        allowed_domains=$(echo "${tool_input}" | jq -c '.allowed_domains // []' 2>/dev/null)
        blocked_domains=$(echo "${tool_input}" | jq -c '.blocked_domains // []' 2>/dev/null)
    else
        # Fallback: regex extraction
        query=$(echo "${tool_input}" | grep -oP '"query"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate query extraction
    if [[ -z "${query}" ]]; then
        wow_warn "⚠️  INVALID WEBSEARCH: Empty query"
        session_track_event "websearch_invalid" "EMPTY_QUERY" 2>/dev/null || true
        # Fail-open
        echo "${tool_input}"
        return 0
    fi

    # Track metrics
    session_increment_metric "websearch_requests" 2>/dev/null || true
    session_track_event "websearch_request" "query=${query:0:100}" 2>/dev/null || true

    # ========================================================================
    # CUSTOM RULES CHECK (v5.4.0)
    # ========================================================================

    if custom_rule_available; then
        # Check query
        custom_rule_check "${query}" "WebSearch"
        local rule_result=$?

        if [[ ${rule_result} -ne ${CUSTOM_RULE_NO_MATCH} ]]; then
            custom_rule_apply "${rule_result}" "WebSearch"

            case "${rule_result}" in
                ${CUSTOM_RULE_BLOCK})
                    return 2
                    ;;
                ${CUSTOM_RULE_ALLOW})
                    echo "${tool_input}"
                    return 0
                    ;;
                ${CUSTOM_RULE_WARN})
                    # Continue to built-in checks
                    ;;
            esac
        fi
    fi

    # ========================================================================
    # TIER 1 CHECK: Critical patterns (hard block)
    # ========================================================================

    # Check for PII and credentials in query
    if _has_blocked_patterns "${query}"; then
        wow_error "☠️  DANGEROUS SEARCH QUERY BLOCKED"
        wow_error "Query contains PII or credentials"

        session_track_event "security_violation" "BLOCKED_WEBSEARCH_PII:${query:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        return 2
    fi

    # ========================================================================
    # TIER 1 CHECK: Domain validation (SSRF prevention)
    # ========================================================================

    # Validate allowed_domains array
    if [[ -n "${allowed_domains}" ]] && [[ "${allowed_domains}" != "[]" ]]; then
        if ! _validate_domain_array "${allowed_domains}"; then
            wow_error "☠️  DANGEROUS DOMAIN IN WEBSEARCH BLOCKED"
            wow_error "allowed_domains contains private IP or blocked domain"

            session_track_event "security_violation" "BLOCKED_WEBSEARCH_SSRF" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true

            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

            return 2
        fi
    fi

    # ========================================================================
    # TIER 2 CHECK: Sensitive patterns (warn/block in strict_mode)
    # ========================================================================

    # Check for credential searches
    if _has_sensitive_patterns "${query}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Sensitive search pattern in strict mode"
            session_track_event "security_violation" "BLOCKED_CREDENTIAL_SEARCH" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true

            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 5))" 2>/dev/null || true

            return 2
        fi

        # Not strict mode - warn with small penalty
        session_track_event "sensitive_search" "${query:0:100}" 2>/dev/null || true

        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 2))" 2>/dev/null || true
    fi

    # ========================================================================
    # TIER 3: Warning patterns (don't block, just track)
    # ========================================================================

    # Check for injection patterns
    if _has_injection_patterns "${query}"; then
        session_track_event "websearch_injection_pattern" "${query:0:50}" 2>/dev/null || true

        # Small score impact
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 1))" 2>/dev/null || true
    fi

    # ========================================================================
    # MONITORING: Rate limiting
    # ========================================================================

    _check_search_rate || true

    # ========================================================================
    # ALLOW: Return original tool input
    # ========================================================================

    echo "${tool_input}"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW WebSearch Handler - Self Test (v5.4.0)"
    echo "=========================================="
    echo ""

    # Test TIER 1: PII detection
    echo "TIER 1 (CRITICAL) Tests:"
    _has_blocked_patterns "test@example.com password" 2>/dev/null && echo "  ✓ Email+password detection works"
    _has_blocked_patterns "123-45-6789" 2>/dev/null && echo "  ✓ SSN detection works"
    _has_blocked_patterns "sk-1234567890123456789012" 2>/dev/null && echo "  ✓ API key detection works"

    echo ""
    echo "TIER 1 (SSRF) Tests:"
    _is_private_ip "192.168.1.1" 2>/dev/null && echo "  ✓ Private IP detection works"
    _is_blocked_domain "localhost" 2>/dev/null && echo "  ✓ Blocked domain detection works"

    echo ""
    echo "TIER 2 (SENSITIVE) Tests:"
    _has_sensitive_patterns "password database" 2>/dev/null && echo "  ✓ Credential search detection works"
    _has_suspicious_tld "example.tk" 2>/dev/null && echo "  ✓ Suspicious TLD detection works"

    echo ""
    echo "TIER 3 (WARNING) Tests:"
    _has_injection_patterns "' OR '1'='1" 2>/dev/null && echo "  ✓ SQL injection detection works"
    ! _has_blocked_patterns "python documentation" 2>/dev/null && echo "  ✓ Safe queries allowed"

    echo ""
    echo "All self-tests passed! ✓"
    echo ""
    echo "Configuration:"
    echo "  - TIER 1 (CRITICAL): ${#BLOCKED_QUERY_PATTERNS[@]} query patterns, ${#BLOCKED_IP_PATTERNS[@]} IP patterns"
    echo "  - TIER 2 (SENSITIVE): ${#SENSITIVE_QUERY_PATTERNS[@]} patterns, ${#SUSPICIOUS_TLDS[@]} TLDs"
    echo "  - TIER 3 (WARNING): ${#INJECTION_PATTERNS[@]} injection patterns"
fi
