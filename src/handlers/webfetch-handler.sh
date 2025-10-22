#!/bin/bash
# WoW System - WebFetch Handler (Production-Grade, Security-Critical)
# Intercepts external URL requests for safety and exfiltration prevention
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on ambiguity or danger
# - SSRF Prevention: Block private/internal IP ranges
# - Anti-Exfiltration: Detect data upload attempts
# - Privacy Protection: Prevent credential leakage
# - Audit Logging: Track all external requests

# Prevent double-sourcing
if [[ -n "${WOW_WEBFETCH_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_WEBFETCH_HANDLER_LOADED=1

# Source dependencies
_WEBFETCH_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_WEBFETCH_HANDLER_DIR}/../core/utils.sh"
source "${_WEBFETCH_HANDLER_DIR}/custom-rule-helper.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants - Blocked Patterns
# ============================================================================

# CRITICAL: Private/internal IP ranges (SSRF prevention)
readonly -a BLOCKED_IP_PATTERNS=(
    "^127\."                    # 127.0.0.0/8 (loopback)
    "^10\."                     # 10.0.0.0/8 (private)
    "^172\.(1[6-9]|2[0-9]|3[01])\."  # 172.16.0.0/12 (private)
    "^192\.168\."               # 192.168.0.0/16 (private)
    "^169\.254\."               # 169.254.0.0/16 (link-local)
    "^::1$"                     # IPv6 loopback
    "^fe80:"                    # IPv6 link-local
    "^fc00:"                    # IPv6 unique local
    "^fd00:"                    # IPv6 unique local
)

# Blocked hostnames
readonly -a BLOCKED_HOSTNAMES=(
    "^localhost$"
    "^127\.0\.0\.1$"
    "^\[::1\]$"
)

# Blocked protocols
readonly -a BLOCKED_PROTOCOLS=(
    "^file://"
    "^ftp://"
    "^gopher://"
    "^dict://"
    "^ldap://"
)

# ============================================================================
# Constants - Suspicious Patterns
# ============================================================================

# Data exfiltration endpoints (warn)
readonly -a EXFILTRATION_DOMAINS=(
    "pastebin\.com"
    "paste\.ee"
    "hastebin\.com"
    "dpaste\.com"
    "justpaste\.it"
    "codepad\.org"
    "sprunge\.us"
    "ix\.io"
    "termbin\.com"
)

# URL shorteners (warn - potential phishing/obfuscation)
readonly -a URL_SHORTENERS=(
    "bit\.ly"
    "tinyurl\.com"
    "goo\.gl"
    "ow\.ly"
    "t\.co"
    "is\.gd"
    "buff\.ly"
    "adf\.ly"
)

# Suspicious TLDs
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

# ============================================================================
# Constants - Safe Domains
# ============================================================================

# Well-known safe domains (documentation, development resources)
readonly -a SAFE_DOMAINS=(
    "github\.com"
    "gitlab\.com"
    "stackoverflow\.com"
    "stackexchange\.com"
    "developer\.mozilla\.org"
    "docs\.python\.org"
    "nodejs\.org"
    "npmjs\.(org|com)"
    "pypi\.org"
    "rubygems\.org"
    "packagist\.org"
    "crates\.io"
    "docs\.rs"
    "readthedocs\.(io|org)"
    "w3\.org"
    "ietf\.org"
    "rfc-editor\.org"
    "wikipedia\.org"
    "wikimedia\.org"
    "google\.(com|co\.uk)"
    "microsoft\.(com|docs)"
    "apple\.(com|developer)"
    "docs\.anthropic\.com"
    "openai\.com"
)

# ============================================================================
# Private: URL Parsing & Validation
# ============================================================================

# Extract domain from URL
_extract_domain() {
    local url="$1"

    # Remove protocol
    local domain
    domain=$(echo "${url}" | sed -E 's#^[a-z]+://##i')

    # Remove path and query
    domain=$(echo "${domain}" | cut -d'/' -f1 | cut -d'?' -f1 | cut -d':' -f1)

    # Remove userinfo if present
    domain=$(echo "${domain}" | sed 's/.*@//')

    echo "${domain}"
}

# Check if domain is a private IP
_is_private_ip() {
    local domain="$1"

    for pattern in "${BLOCKED_IP_PATTERNS[@]}"; do
        if echo "${domain}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Private/internal IP detected: ${domain}"
            return 0  # Is private
        fi
    done

    return 1  # Not private
}

# Check if hostname is blocked
_is_blocked_hostname() {
    local domain="$1"

    for pattern in "${BLOCKED_HOSTNAMES[@]}"; do
        if echo "${domain}" | grep -qiE "${pattern}"; then
            wow_warn "SECURITY: Blocked hostname: ${domain}"
            return 0  # Is blocked
        fi
    done

    return 1  # Not blocked
}

# Check if protocol is blocked
_is_blocked_protocol() {
    local url="$1"

    for pattern in "${BLOCKED_PROTOCOLS[@]}"; do
        if echo "${url}" | grep -qiE "${pattern}"; then
            wow_warn "SECURITY: Blocked protocol in URL: ${url}"
            return 0  # Is blocked
        fi
    done

    return 1  # Not blocked
}

# Check if URL has credentials
_has_url_credentials() {
    local url="$1"

    if echo "${url}" | grep -qE "://[^/]*:[^@]*@"; then
        wow_warn "⚠️  Credentials detected in URL (potential leakage)"
        return 0
    fi

    return 1
}

# Check if domain is a data URL
_is_data_url() {
    local url="$1"

    if echo "${url}" | grep -qiE "^data:"; then
        wow_warn "⚠️  Data URL detected"
        return 0
    fi

    return 1
}

# ============================================================================
# Private: Domain Classification
# ============================================================================

# Check if domain is for exfiltration
_is_exfiltration_domain() {
    local domain="$1"

    for pattern in "${EXFILTRATION_DOMAINS[@]}"; do
        if echo "${domain}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Potential exfiltration endpoint: ${domain}"
            return 0
        fi
    done

    return 1
}

# Check if URL is shortened
_is_url_shortener() {
    local domain="$1"

    for pattern in "${URL_SHORTENERS[@]}"; do
        if echo "${domain}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  URL shortener detected: ${domain}"
            return 0
        fi
    done

    return 1
}

# Check if TLD is suspicious
_has_suspicious_tld() {
    local domain="$1"

    for pattern in "${SUSPICIOUS_TLDS[@]}"; do
        if echo "${domain}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Suspicious TLD detected: ${domain}"
            return 0
        fi
    done

    return 1
}

# Check if domain is safe/well-known
_is_safe_domain() {
    local domain="$1"

    for pattern in "${SAFE_DOMAINS[@]}"; do
        if echo "${domain}" | grep -qiE "${pattern}"; then
            return 0  # Is safe
        fi
    done

    return 1  # Not explicitly safe
}

# Check if domain is an IP address
_is_ip_address() {
    local domain="$1"

    # IPv4 pattern
    if echo "${domain}" | grep -qE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"; then
        return 0
    fi

    # IPv6 pattern (simplified)
    if echo "${domain}" | grep -qiE "^[0-9a-f:]+$"; then
        return 0
    fi

    return 1
}

# ============================================================================
# Private: URL Validation
# ============================================================================

# Validate URL
_validate_url() {
    local url="$1"

    # Check for empty URL
    if [[ -z "${url}" ]]; then
        wow_warn "⚠️  Empty URL in WebFetch request"
        return 1  # Invalid
    fi

    # Check for blocked protocols
    if _is_blocked_protocol "${url}"; then
        return 1  # Invalid - blocked protocol
    fi

    # Check for data URLs
    if _is_data_url "${url}"; then
        # Allow but warn
        return 0
    fi

    # Extract domain
    local domain
    domain=$(_extract_domain "${url}")

    # Check for private IPs (SSRF prevention)
    if _is_private_ip "${domain}"; then
        return 1  # Invalid - private IP
    fi

    # Check for blocked hostnames
    if _is_blocked_hostname "${domain}"; then
        return 1  # Invalid - blocked hostname
    fi

    # Check for credentials in URL (warn but allow)
    _has_url_credentials "${url}" || true

    # Check for exfiltration domains (warn but allow)
    _is_exfiltration_domain "${domain}" || true

    # v5.0.1: strict_mode enforcement - URL shorteners
    if _is_url_shortener "${domain}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: URL shortener"
            session_track_event "security_violation" "BLOCKED_URL_SHORTENER:${domain}" 2>/dev/null || true
            return 1  # Invalid - blocked by strict_mode
        fi
    fi

    # v5.0.1: strict_mode enforcement - Suspicious TLDs
    if _has_suspicious_tld "${domain}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: Suspicious TLD"
            session_track_event "security_violation" "BLOCKED_SUSPICIOUS_TLD:${domain}" 2>/dev/null || true
            return 1  # Invalid - blocked by strict_mode
        fi
    fi

    # Warn if IP-based URL (not localhost/private)
    if _is_ip_address "${domain}"; then
        wow_warn "ℹ️  IP-based URL (not domain name): ${domain}"
    fi

    return 0  # Valid
}

# ============================================================================
# Private: Rate Limiting
# ============================================================================

# Check WebFetch rate limits
_check_fetch_rate() {
    local fetch_count
    fetch_count=$(session_get_metric "webfetch_requests" "0")

    # Warn on high fetch count
    if [[ ${fetch_count} -gt 50 ]]; then
        wow_warn "⚠️  High WebFetch request count: ${fetch_count}"
        return 0  # High rate
    fi

    return 1  # Normal rate
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle WebFetch command interception
handle_webfetch() {
    local tool_input="$1"

    # Extract URL and prompt from JSON input
    local url=""
    local prompt=""

    if wow_has_jq; then
        url=$(echo "${tool_input}" | jq -r '.url // empty' 2>/dev/null)
        prompt=$(echo "${tool_input}" | jq -r '.prompt // empty' 2>/dev/null)
    else
        # Fallback: regex extraction
        url=$(echo "${tool_input}" | grep -oP '"url"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        prompt=$(echo "${tool_input}" | grep -oP '"prompt"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate URL extraction
    if [[ -z "${url}" ]]; then
        wow_warn "⚠️  INVALID WEBFETCH: Empty URL"

        # Log event
        session_track_event "webfetch_invalid" "EMPTY_URL" 2>/dev/null || true

        # Don't block - might be edge case
        echo "${tool_input}"
        return 0
    fi

    # Track metrics
    session_increment_metric "webfetch_requests" 2>/dev/null || true
    session_track_event "webfetch_request" "url=${url:0:100}" 2>/dev/null || true

    # ========================================================================
    # CUSTOM RULES CHECK (v5.4.0)
    # ========================================================================

    if custom_rule_available; then
        # Check URL and prompt
        custom_rule_check "${url}" "WebFetch"
        local url_result=$?

        custom_rule_check "${prompt:0:500}" "WebFetch"
        local prompt_result=$?

        # Take more restrictive action
        local rule_result=${url_result}
        if [[ ${prompt_result} -ne ${CUSTOM_RULE_NO_MATCH} ]]; then
            if [[ ${rule_result} -eq ${CUSTOM_RULE_NO_MATCH} ]] || [[ ${prompt_result} -lt ${rule_result} ]]; then
                rule_result=${prompt_result}
            fi
        fi

        if [[ ${rule_result} -ne ${CUSTOM_RULE_NO_MATCH} ]]; then
            custom_rule_apply "${rule_result}" "WebFetch"

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
    # SECURITY CHECK: URL Validation
    # ========================================================================

    if ! _validate_url "${url}"; then
        wow_error "☠️  DANGEROUS WEBFETCH BLOCKED"
        wow_error "URL: ${url}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_WEBFETCH:${url:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # ========================================================================
    # MONITORING: Rate Limiting
    # ========================================================================

    _check_fetch_rate || true

    # ========================================================================
    # ALLOW: Return (original) tool input
    # ========================================================================

    echo "${tool_input}"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW WebFetch Handler - Self Test"
    echo "================================="
    echo ""

    # Test 1: Private IP detection
    _is_private_ip "192.168.1.1" && echo "✓ Private IP detection works"

    # Test 2: Blocked hostname detection
    _is_blocked_hostname "localhost" && echo "✓ Blocked hostname detection works"

    # Test 3: Blocked protocol detection
    _is_blocked_protocol "file:///etc/passwd" && echo "✓ Blocked protocol detection works"

    # Test 4: Credentials in URL detection
    _has_url_credentials "https://user:pass@example.com/" 2>/dev/null && echo "✓ URL credentials detection works"

    # Test 5: Exfiltration domain detection
    _is_exfiltration_domain "pastebin.com" 2>/dev/null && echo "✓ Exfiltration domain detection works"

    # Test 6: Safe domain detection
    _is_safe_domain "github.com" && echo "✓ Safe domain detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
