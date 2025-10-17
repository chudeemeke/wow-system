#!/bin/bash
# WoW System - Grep Handler (Production-Grade, Security-Critical)
# Intercepts grep/search operations for safety enforcement and validation
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on ambiguity or danger
# - Privacy Protection: Prevent sensitive data fishing
# - Anti-Credential-Harvesting: Detect credential searches
# - Audit Logging: Track all grep operations

# Prevent double-sourcing
if [[ -n "${WOW_GREP_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_GREP_HANDLER_LOADED=1

# Source dependencies
_GREP_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_GREP_HANDLER_DIR}/../core/utils.sh"
source "${_GREP_HANDLER_DIR}/../core/fast-path-validator.sh"

set -uo pipefail

# ============================================================================
# Constants - Protected Directories
# ============================================================================

# CRITICAL: Directories that should NEVER be searched
readonly -a PROTECTED_GREP_DIRS=(
    "^/etc(/|$)"
    "^/root(/|$)"
    "^/sys(/|$)"
    "^/proc(/|$)"
    "^/dev(/|$)"
    "^/boot(/|$)"
    "^/bin(/|$)"
    "^/sbin(/|$)"
    "^/usr/bin(/|$)"
    "^/usr/sbin(/|$)"
    "^/lib(/|$)"
    "^/lib64(/|$)"
    "/\\.ssh(/|$)"
    "/\\.aws(/|$)"
    "/\\.gnupg(/|$)"
)

# ============================================================================
# Constants - Suspicious Patterns
# ============================================================================

# Credential/secret searching patterns (warn - might be legitimate code search)
readonly -a CREDENTIAL_PATTERNS=(
    "password\\s*=|password\\s*:"
    "api[_-]?key"
    "secret\\s*=|secret\\s*:"
    "token\\s*=|token\\s*:"
    "BEGIN.*PRIVATE KEY"
    "aws_access_key|aws_secret"
    "mongodb://.*@"
    "mysql://.*@"
    "postgres://.*@"
    "redis://.*@"
    "sk_live_"         # Stripe live keys
    "rk_live_"         # Stripe restricted keys
)

# PII patterns (warn)
readonly -a PII_PATTERNS=(
    "[0-9]{3}-[0-9]{2}-[0-9]{4}"     # SSN
    "[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}"  # Credit card
)

# Safe patterns (common code searches)
readonly -a SAFE_CODE_PATTERNS=(
    "function"
    "class\\s+"
    "import"
    "require"
    "TODO|FIXME|BUG"
    "Error:|Exception:"
    "interface"
    "const\\s+"
    "let\\s+"
    "var\\s+"
)

# ============================================================================
# Private: Path Validation
# ============================================================================

# Check if path is a protected directory
_is_protected_directory() {
    local path="$1"

    # Default to current directory if empty
    if [[ -z "${path}" ]]; then
        path="$(pwd)"
    fi

    # Resolve to absolute path
    local abs_path
    if [[ "${path}" != /* ]]; then
        abs_path="$(pwd)/${path}"
    else
        abs_path="${path}"
    fi

    # Normalize path
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for protected in "${PROTECTED_GREP_DIRS[@]}"; do
        if echo "${abs_path}" | grep -qE "${protected}"; then
            wow_warn "SECURITY: Attempt to grep in protected directory: ${abs_path}"
            return 0  # Is protected
        fi
    done

    return 1  # Not protected
}

# Detect path traversal
_has_path_traversal() {
    local path="$1"

    if [[ -n "${path}" ]] && echo "${path}" | grep -qE "\\.\\./"; then
        wow_warn "⚠️  Path traversal detected in grep path: ${path}"
        return 0
    fi

    return 1
}

# ============================================================================
# Private: Pattern Validation
# ============================================================================

# Check if pattern is searching for credentials
_is_credential_search() {
    local pattern="$1"

    for cred in "${CREDENTIAL_PATTERNS[@]}"; do
        if echo "${pattern}" | grep -qiE "${cred}"; then
            wow_warn "⚠️  Searching for credential patterns: ${pattern:0:50}"
            return 0  # Is credential search
        fi
    done

    return 1  # Not credential search
}

# Check if pattern is searching for PII
_is_pii_search() {
    local pattern="$1"

    for pii in "${PII_PATTERNS[@]}"; do
        if echo "${pattern}" | grep -qE "${pii}"; then
            wow_warn "⚠️  Searching for PII patterns: ${pattern:0:50}"
            return 0  # Is PII search
        fi
    done

    return 1  # Not PII search
}

# Check if pattern is safe code search
_is_safe_code_search() {
    local pattern="$1"

    for safe in "${SAFE_CODE_PATTERNS[@]}"; do
        if echo "${pattern}" | grep -qiE "${safe}"; then
            return 0  # Is safe
        fi
    done

    return 1  # Not explicitly safe
}

# Validate pattern
_validate_pattern() {
    local pattern="$1"

    # Check for empty pattern
    if [[ -z "${pattern}" ]]; then
        wow_warn "⚠️  Empty grep pattern"
        return 1  # Invalid
    fi

    # Check for credential searches (warn but allow)
    _is_credential_search "${pattern}" || true

    # Check for PII searches (warn but allow)
    _is_pii_search "${pattern}" || true

    return 0  # Valid (we warn but don't block patterns)
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle grep command interception
handle_grep() {
    local tool_input="$1"

    # Extract pattern and path from JSON input
    local pattern=""
    local path=""
    local output_mode=""

    if wow_has_jq; then
        pattern=$(echo "${tool_input}" | jq -r '.pattern // empty' 2>/dev/null)
        path=$(echo "${tool_input}" | jq -r '.path // empty' 2>/dev/null)
        output_mode=$(echo "${tool_input}" | jq -r '.output_mode // empty' 2>/dev/null)
    else
        # Fallback: regex extraction
        pattern=$(echo "${tool_input}" | grep -oP '"pattern"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        path=$(echo "${tool_input}" | grep -oP '"path"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        output_mode=$(echo "${tool_input}" | grep -oP '"output_mode"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate extraction
    if [[ -z "${pattern}" ]]; then
        wow_warn "⚠️  INVALID GREP: Empty pattern"

        # Log event
        session_track_event "grep_invalid" "EMPTY_PATTERN" 2>/dev/null || true

        # Don't block - might be valid edge case
        echo "${tool_input}"
        return 0
    fi

    # ========================================================================
    # FAST PATH CHECK: Early exit for obviously safe paths (v5.1.0)
    # ========================================================================
    # Grep operations search within files, so we validate the target path

    if [[ -n "${path}" ]]; then
        local fast_path_result
        fast_path_validate "${path}" "grep"
        fast_path_result=$?

        case ${fast_path_result} in
            0)  # ALLOW - safe path, check pattern too
                # Path is safe, still validate pattern isn't credential search
                if ! _is_credential_search_pattern "${pattern}"; then
                    session_increment_metric "grep_operations" 2>/dev/null || true
                    session_increment_metric "fast_path_allows" 2>/dev/null || true
                    wow_debug "Fast path ALLOW: grep pattern=${pattern} path=${path}"
                    echo "${tool_input}"
                    return 0
                fi
                # Credential search - fall through to deep validation
                ;;
            2)  # BLOCK - dangerous path
                wow_error "Fast path BLOCKED: grep in dangerous path ${path}"
                session_track_event "security_violation" "FAST_PATH_GREP_BLOCK:${path:0:100}" 2>/dev/null || true
                session_increment_metric "violations" 2>/dev/null || true
                session_increment_metric "fast_path_blocks" 2>/dev/null || true

                # Update score
                local current_score
                current_score=$(session_get_metric "wow_score" "70")
                session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

                return 2
                ;;
            1)  # CONTINUE - needs deep validation
                wow_debug "Fast path CONTINUE: grep path needs deep check"
                session_increment_metric "fast_path_continues" 2>/dev/null || true
                # Fall through to existing validation
                ;;
        esac
    fi

    # Track metrics
    session_increment_metric "grep_operations" 2>/dev/null || true
    session_track_event "grep_operation" "pattern=${pattern:0:50}" 2>/dev/null || true

    # ========================================================================
    # SECURITY CHECK: Deep Protected Directory Validation
    # ========================================================================
    # Only reached if fast path returned 1 or path not provided

    if _is_protected_directory "${path}"; then
        wow_error "☠️  DANGEROUS GREP OPERATION BLOCKED"
        wow_error "Path: ${path}"
        wow_error "Pattern: ${pattern}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_GREP:${path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # ========================================================================
    # WARNINGS: Pattern Validation (non-blocking)
    # ========================================================================

    # Check for credential searches
    if _is_credential_search "${pattern}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Credential pattern search in strict mode"
            session_track_event "security_violation" "BLOCKED_CREDENTIAL_GREP" 2>/dev/null || true
            return 2
        fi
    fi

    # Check for PII searches
    if _is_pii_search "${pattern}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: PII pattern search in strict mode"
            session_track_event "security_violation" "BLOCKED_PII_GREP" 2>/dev/null || true
            return 2
        fi
    fi

    # Check for path traversal
    if _has_path_traversal "${path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Path traversal in grep path in strict mode"
            session_track_event "security_violation" "BLOCKED_GREP_TRAVERSAL" 2>/dev/null || true
            return 2
        fi
    fi

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
    echo "WoW Grep Handler - Self Test"
    echo "============================="
    echo ""

    # Test 1: Protected directory detection
    _is_protected_directory "/etc" && echo "✓ Protected directory detection works"

    # Test 2: Safe directory
    ! _is_protected_directory "/home/user/project" && echo "✓ Safe directory detection works"

    # Test 3: Credential search detection
    _is_credential_search "password\\s*=" 2>/dev/null && echo "✓ Credential search detection works"

    # Test 4: PII search detection
    _is_pii_search "[0-9]{3}-[0-9]{2}-[0-9]{4}" 2>/dev/null && echo "✓ PII search detection works"

    # Test 5: Safe code search detection
    _is_safe_code_search "function.*onClick" && echo "✓ Safe code search detection works"

    # Test 6: Path traversal detection
    _has_path_traversal "../../etc" 2>/dev/null && echo "✓ Path traversal detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
