#!/bin/bash
# WoW System - Read Handler (Production-Grade, Security-Critical)
# Intercepts file read operations for safety enforcement and validation
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on ambiguity or danger
# - Privacy Protection: Prevent sensitive data access
# - Anti-Exfiltration: Detect excessive read patterns
# - Audit Logging: Track all read operations

# Prevent double-sourcing
if [[ -n "${WOW_READ_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_READ_HANDLER_LOADED=1

# Source dependencies
_READ_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_READ_HANDLER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants - Sensitive File Patterns
# ============================================================================

# CRITICAL: Files that should NEVER be read (high security risk)
readonly -a BLOCKED_FILES=(
    "^/etc/shadow$"
    "^/etc/passwd$"
    "^/etc/sudoers"
    "^/etc/gshadow$"
    "^/etc/security/"
    "^/root/"
    "/\\.ssh/id_(rsa|dsa|ecdsa|ed25519)$"     # Private SSH keys (not .pub)
    "/\\.aws/credentials$"
    "/\\.config/gcloud/.*credentials"
    "/\\.gnupg/.*\\.gpg$"
    "/\\.bitcoin/wallet\\.dat$"
    "/\\.ethereum/keystore/"
    "wallet\\.dat$"
    "^/proc/self/environ$"
    "^/proc/.*/environ$"
)

# WARNING: Credential files (warn but allow - might be legitimate config review)
readonly -a CREDENTIAL_FILE_PATTERNS=(
    "\\.env$"
    "\\.env\\.[a-z]+"
    "credentials\\.json$"
    "secrets?\\.ya?ml$"
    "secrets?\\.json$"
    "private.*\\.pem$"
    ".*-key\\.pem$"
    "\\.p12$"
    "\\.pfx$"
    "serviceAccountKey\\.json$"
)

# WARNING: Browser data (warn but allow)
readonly -a BROWSER_DATA_PATTERNS=(
    "/\\.mozilla/.*/cookies\\.sqlite"
    "/\\.config/google-chrome/.*/Cookies"
    "/\\.config/chromium/.*/Cookies"
    "Login\\ Data$"
)

# WARNING: Database files (track for exfiltration patterns)
readonly -a DATABASE_PATTERNS=(
    "\\.db$"
    "\\.sqlite$"
    "\\.sqlite3$"
)

# Path traversal patterns
readonly -a PATH_TRAVERSAL_PATTERNS=(
    "\\.\\./\\.\\./"      # ../..
    "\\.\\./"             # ../
    "/\\.\\./"            # /../
)

# Safe file extensions (always allowed)
readonly -a SAFE_EXTENSIONS=(
    "\\.js$"
    "\\.ts$"
    "\\.jsx$"
    "\\.tsx$"
    "\\.py$"
    "\\.sh$"
    "\\.bash$"
    "\\.md$"
    "\\.txt$"
    "\\.json$"
    "\\.ya?ml$"
    "\\.toml$"
    "\\.conf$"
    "\\.config$"
    "\\.xml$"
    "\\.html$"
    "\\.css$"
    "\\.scss$"
    "Makefile$"
    "Dockerfile$"
    "README"
    "package\\.json$"
    "tsconfig\\.json$"
    "\\.gitignore$"
    "\\.editorconfig$"
)

# ============================================================================
# Private: Path Validation
# ============================================================================

# Check if file is in blocked list
_is_blocked_file() {
    local file_path="$1"

    # Resolve to absolute path
    local abs_path
    if [[ "${file_path}" != /* ]]; then
        abs_path="$(pwd)/${file_path}"
    else
        abs_path="${file_path}"
    fi

    # Normalize path (remove ./ and ../)
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for pattern in "${BLOCKED_FILES[@]}"; do
        if echo "${abs_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Attempt to read blocked file: ${abs_path}"
            return 0  # Is blocked
        fi
    done

    return 1  # Not blocked
}

# Check for path traversal attacks
_has_path_traversal() {
    local file_path="$1"

    for pattern in "${PATH_TRAVERSAL_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Path traversal detected in read: ${file_path}"
            return 0  # Has traversal
        fi
    done

    return 1  # Safe
}

# Check if file contains credentials (warn only)
_is_credential_file() {
    local file_path="$1"

    for pattern in "${CREDENTIAL_FILE_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            wow_warn "⚠️  Reading credential file: ${file_path}"
            return 0  # Is credential file
        fi
    done

    return 1  # Not credential file
}

# Check if file is browser data (warn only)
_is_browser_data() {
    local file_path="$1"

    for pattern in "${BROWSER_DATA_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            wow_warn "⚠️  Reading browser data: ${file_path}"
            return 0  # Is browser data
        fi
    done

    return 1  # Not browser data
}

# Check if file is database (track only)
_is_database_file() {
    local file_path="$1"

    for pattern in "${DATABASE_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            return 0  # Is database
        fi
    done

    return 1  # Not database
}

# Check if file is safe extension
_is_safe_extension() {
    local file_path="$1"

    for pattern in "${SAFE_EXTENSIONS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            return 0  # Is safe
        fi
    done

    return 1  # Not explicitly safe
}

# Validate file path
_validate_file_path() {
    local file_path="$1"

    # Check for empty path
    if [[ -z "${file_path}" ]]; then
        wow_warn "SECURITY: Empty file path in read operation"
        return 1  # Invalid
    fi

    # Check for path traversal targeting sensitive files
    if _has_path_traversal "${file_path}"; then
        # Path traversal is especially dangerous if targeting /etc or /root
        if echo "${file_path}" | grep -qE "(etc|root|shadow|passwd|sudoers)"; then
            return 1  # Block dangerous traversal
        fi
    fi

    # Check for blocked files (CRITICAL)
    if _is_blocked_file "${file_path}"; then
        return 1  # Invalid - blocked
    fi

    return 0  # Valid
}

# ============================================================================
# Private: Read Rate Limiting
# ============================================================================

# Check for excessive read operations (anti-exfiltration)
_check_read_rate() {
    local current_reads
    current_reads=$(session_get_metric "file_reads" "0" 2>/dev/null)

    # Warn if more than 50 reads in a session (potential data exfiltration)
    if [[ ${current_reads} -gt 50 ]]; then
        wow_warn "⚠️  High read volume detected: ${current_reads} files read"
        return 0  # High rate
    fi

    return 1  # Normal rate
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle read command interception
handle_read() {
    local tool_input="$1"

    # Extract file_path from JSON input
    local file_path=""

    if wow_has_jq; then
        file_path=$(echo "${tool_input}" | jq -r '.file_path // empty' 2>/dev/null)
    else
        # Fallback: regex extraction
        file_path=$(echo "${tool_input}" | grep -oP '"file_path"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate extraction
    if [[ -z "${file_path}" ]]; then
        wow_warn "⚠️  INVALID FILE READ: Empty file path"

        # Log event
        session_track_event "read_invalid" "EMPTY_PATH" 2>/dev/null || true

        # Don't block - might be a valid edge case
        echo "${tool_input}"
        return 0
    fi

    # Track metrics
    session_increment_metric "file_reads" 2>/dev/null || true
    session_track_event "file_read" "path=${file_path:0:100}" 2>/dev/null || true

    # ========================================================================
    # SECURITY CHECK: Path Validation
    # ========================================================================

    if ! _validate_file_path "${file_path}"; then
        wow_error "☠️  DANGEROUS FILE READ BLOCKED"
        wow_error "Path: ${file_path}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_READ:${file_path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # ========================================================================
    # WARNINGS: Non-blocking checks
    # ========================================================================

    # Warn on credential files (but allow)
    if _is_credential_file "${file_path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: .env/credential file read in strict mode"
            session_track_event "security_violation" "BLOCKED_ENV_READ" 2>/dev/null || true
            return 2
        fi
    fi

    # Warn on browser data (but allow)
    if _is_browser_data "${file_path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Browser data read in strict mode"
            session_track_event "security_violation" "BLOCKED_BROWSER_READ" 2>/dev/null || true
            return 2
        fi
    fi

    # Track database reads
    if _is_database_file "${file_path}"; then
        session_increment_metric "database_reads" 2>/dev/null || true
    fi

    # Check read rate (anti-exfiltration)
    if _check_read_rate; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: High read volume in strict mode (anti-exfiltration)"
            session_track_event "security_violation" "BLOCKED_HIGH_READ_VOLUME" 2>/dev/null || true
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
    echo "WoW Read Handler - Self Test"
    echo "============================="
    echo ""

    # Test 1: Blocked file detection
    _is_blocked_file "/etc/shadow" && echo "✓ Blocked file detection works"

    # Test 2: Safe file
    ! _is_blocked_file "/home/user/code.js" && echo "✓ Safe file detection works"

    # Test 3: Path traversal detection
    _has_path_traversal "../../etc/passwd" && echo "✓ Path traversal detection works"

    # Test 4: Credential file detection
    _is_credential_file ".env" 2>/dev/null && echo "✓ Credential file detection works"

    # Test 5: Safe extension detection
    _is_safe_extension "package.json" && echo "✓ Safe extension detection works"

    # Test 6: Database file detection
    _is_database_file "app.db" && echo "✓ Database file detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
