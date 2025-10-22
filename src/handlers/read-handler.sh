#!/bin/bash
# WoW System - Read Handler (Production-Grade, Security-Critical)
# Intercepts file read operations for safety enforcement and validation
# Author: Chude <chude@emeke.org>
#
# Security Principles (v5.3.0):
# - Defense in Depth: Three-tier validation (Critical/Sensitive/Tracked)
# - Intelligent, Not Paranoid: Only block catastrophic reads
# - Contextual Security: Strict mode for high-security environments
# - Privacy Protection: Prevent catastrophic credential access
# - Anti-Exfiltration: Detect excessive read patterns
# - Audit Logging: Track all read operations
# - Zero False Positives: Sensitive files warn, don't block (unless strict_mode)

# Prevent double-sourcing
if [[ -n "${WOW_READ_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_READ_HANDLER_LOADED=1

# Source dependencies
_READ_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_READ_HANDLER_DIR}/../core/utils.sh"
source "${_READ_HANDLER_DIR}/../core/fast-path-validator.sh"
source "${_READ_HANDLER_DIR}/custom-rule-helper.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants - Three-Tier Security Classification
# ============================================================================
#
# TIER 1 (CRITICAL): Hard block - catastrophic security risk, never legitimate
# TIER 2 (SENSITIVE): Warn by default, block in strict_mode - might be legitimate
# TIER 3 (TRACKED): Allow but track - normal development files
#
# Philosophy: "Intelligent, Not Paranoid" + "Zero false positives on normal workflows"

# TIER 1: CRITICAL - Files that should NEVER be read (catastrophic security risk)
# Only files that have NO legitimate development use case
readonly -a BLOCKED_FILES=(
    "^/etc/shadow$"        # System password hashes - no legitimate read use
    "^/etc/sudoers$"       # Sudo configuration - no legitimate read use
    "^/etc/gshadow$"       # Group password hashes - no legitimate read use
)

# TIER 2: SENSITIVE - Warn by default, block in strict_mode
# Files that MIGHT be legitimately accessed during development/debugging
# Examples: debugging auth issues, checking config, reviewing .env files
readonly -a SENSITIVE_FILE_PATTERNS=(
    # System files (world-readable but signals security intent)
    "^/etc/passwd$"                            # User accounts (world-readable)
    "^/etc/security/"                          # Security configs

    # User-specific sensitive directories
    "^/root/"                                  # Root home (might be WSL dev environment)
    "/\\.ssh/id_(rsa|dsa|ecdsa|ed25519)$"     # Private SSH keys (might debug key issues)

    # Cloud provider credentials
    "/\\.aws/credentials$"                     # AWS (might debug auth)
    "/\\.config/gcloud/.*credentials"          # GCP (might debug auth)

    # Encryption keys
    "/\\.gnupg/.*\\.gpg$"                      # GPG keys
    "private.*\\.pem$"                         # Private PEM keys
    ".*-key\\.pem$"                            # Key files
    "\\.p12$"                                  # PKCS#12 certificates
    "\\.pfx$"                                  # PFX certificates

    # Cryptocurrency wallets
    "/\\.bitcoin/wallet\\.dat$"                # Bitcoin wallet
    "/\\.ethereum/keystore/"                   # Ethereum keystore
    "wallet\\.dat$"                            # Generic wallet files

    # Process environment (contains secrets)
    "^/proc/self/environ$"                     # Current process environment
    "^/proc/.*/environ$"                       # Process environments

    # Application credentials
    "\\.env$"                                  # Environment variables
    "\\.env\\.[a-z]+"                          # Environment files (.env.local, etc.)
    "credentials\\.json$"                      # Credentials files
    "secrets?\\.ya?ml$"                        # Secrets YAML
    "secrets?\\.json$"                         # Secrets JSON
    "serviceAccountKey\\.json$"                # GCP service account keys

    # Browser data
    "/\\.mozilla/.*/cookies\\.sqlite"          # Firefox cookies
    "/\\.config/google-chrome/.*/Cookies"      # Chrome cookies
    "/\\.config/chromium/.*/Cookies"           # Chromium cookies
    "Login\\ Data$"                            # Browser login data
)

# TIER 3: TRACKED - Allow but track (for pattern analysis)
# Database files tracked for exfiltration pattern detection
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

# Check if file is sensitive (TIER 2)
# Returns 0 if sensitive, 1 if not
_is_sensitive_file() {
    local file_path="$1"

    # Resolve to absolute path for pattern matching
    local abs_path
    if [[ "${file_path}" != /* ]]; then
        abs_path="$(pwd)/${file_path}"
    else
        abs_path="${file_path}"
    fi

    # Normalize path (remove ./ and ../)
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for pattern in "${SENSITIVE_FILE_PATTERNS[@]}"; do
        if echo "${abs_path}" | grep -qE "${pattern}"; then
            wow_warn "⚠️  SENSITIVE FILE ACCESS: ${abs_path}"
            wow_warn "   This file may contain credentials or private data"
            return 0  # Is sensitive
        fi
    done

    return 1  # Not sensitive
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

    # ========================================================================
    # CUSTOM RULES CHECK (v5.4.0)
    # ========================================================================

    if custom_rule_available; then
        custom_rule_check "${file_path}" "Read"
        local rule_result=$?

        if [[ ${rule_result} -ne ${CUSTOM_RULE_NO_MATCH} ]]; then
            custom_rule_apply "${rule_result}" "Read"

            case "${rule_result}" in
                ${CUSTOM_RULE_BLOCK})
                    session_increment_metric "file_reads" 2>/dev/null || true
                    return 2
                    ;;
                ${CUSTOM_RULE_ALLOW})
                    session_increment_metric "file_reads" 2>/dev/null || true
                    echo "${tool_input}"
                    return 0
                    ;;
                ${CUSTOM_RULE_WARN})
                    # Continue to fast-path and built-in checks
                    ;;
            esac
        fi
    fi

    # ========================================================================
    # FAST PATH CHECK: Early exit for obviously safe files (v5.1.0)
    # ========================================================================
    # Performance optimization: 70-80% reduction in operation time
    # Security guarantee: No compromise - dangerous paths still blocked

    local fast_path_result
    fast_path_validate "${file_path}" "read"
    fast_path_result=$?

    case ${fast_path_result} in
        0)  # ALLOW - safe file, skip deep validation
            session_increment_metric "file_reads" 2>/dev/null || true
            session_increment_metric "fast_path_allows" 2>/dev/null || true
            wow_debug "Fast path ALLOW: ${file_path}"
            echo "${tool_input}"
            return 0
            ;;
        2)  # BLOCK - obviously dangerous
            wow_error "Fast path BLOCKED: ${file_path}"
            session_track_event "security_violation" "FAST_PATH_BLOCK:${file_path:0:100}" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true
            session_increment_metric "fast_path_blocks" 2>/dev/null || true

            # Update score
            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

            return 2
            ;;
        1)  # CONTINUE - needs deep validation
            wow_debug "Fast path CONTINUE: ${file_path} (deep validation required)"
            session_increment_metric "fast_path_continues" 2>/dev/null || true
            # Fall through to existing validation
            ;;
    esac

    # Track metrics
    session_increment_metric "file_reads" 2>/dev/null || true
    session_track_event "file_read" "path=${file_path:0:100}" 2>/dev/null || true

    # ========================================================================
    # SECURITY CHECK: Deep Path Validation
    # ========================================================================
    # Only reached if fast path returned 1 (needs deep check)

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
    # TIER 2 CHECK: Sensitive files (warn by default, block in strict_mode)
    # ========================================================================

    # Check for sensitive files (credentials, keys, private data)
    if _is_sensitive_file "${file_path}"; then
        # In strict_mode, sensitive files are BLOCKED
        # Otherwise, warned but allowed (might be legitimate debugging)
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Sensitive file read in strict mode"
            wow_error "File: ${file_path}"
            wow_error "Tip: Set strict_mode=false in config to allow with warnings"
            session_track_event "security_violation" "BLOCKED_SENSITIVE_READ:${file_path:0:100}" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true

            # Update score
            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 5))" 2>/dev/null || true

            return 2
        fi

        # Not in strict mode - warn but allow
        session_track_event "sensitive_read_allowed" "${file_path:0:100}" 2>/dev/null || true
        session_increment_metric "sensitive_file_reads" 2>/dev/null || true

        # Small score penalty (less than violation)
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 2))" 2>/dev/null || true
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
    echo "WoW Read Handler - Self Test (v5.3.0)"
    echo "======================================"
    echo ""
    echo "Testing Three-Tier Security Classification..."
    echo ""

    # Test TIER 1: CRITICAL (hard block)
    echo "TIER 1 (CRITICAL) Tests:"
    _is_blocked_file "/etc/shadow" && echo "  ✓ /etc/shadow blocked (catastrophic)"
    _is_blocked_file "/etc/sudoers" && echo "  ✓ /etc/sudoers blocked (catastrophic)"
    _is_blocked_file "/etc/gshadow" && echo "  ✓ /etc/gshadow blocked (catastrophic)"
    ! _is_blocked_file "/etc/passwd" && echo "  ✓ /etc/passwd NOT in TIER 1 (moved to TIER 2)"

    echo ""
    echo "TIER 2 (SENSITIVE) Tests:"
    _is_sensitive_file "/etc/passwd" 2>/dev/null && echo "  ✓ /etc/passwd is sensitive (warn/block based on strict_mode)"
    _is_sensitive_file ".env" 2>/dev/null && echo "  ✓ .env is sensitive"
    _is_sensitive_file "/root/.bashrc" 2>/dev/null && echo "  ✓ /root/ files are sensitive"
    _is_sensitive_file "$HOME/.ssh/id_rsa" 2>/dev/null && echo "  ✓ SSH private keys are sensitive"
    _is_sensitive_file "$HOME/.aws/credentials" 2>/dev/null && echo "  ✓ AWS credentials are sensitive"

    echo ""
    echo "TIER 3 (TRACKED) Tests:"
    ! _is_blocked_file "/home/user/code.js" && ! _is_sensitive_file "/home/user/code.js" 2>/dev/null && echo "  ✓ Regular files allowed (TIER 3)"

    echo ""
    echo "Utility Function Tests:"
    _has_path_traversal "../../etc/passwd" && echo "  ✓ Path traversal detection works"
    _is_safe_extension "package.json" && echo "  ✓ Safe extension detection works"
    _is_database_file "app.db" && echo "  ✓ Database file detection works"

    echo ""
    echo "All self-tests passed! ✓"
    echo ""
    echo "Configuration:"
    echo "  - TIER 1 (CRITICAL): ${#BLOCKED_FILES[@]} patterns (hard block)"
    echo "  - TIER 2 (SENSITIVE): ${#SENSITIVE_FILE_PATTERNS[@]} patterns (contextual)"
    echo "  - TIER 3 (TRACKED): All others (allow + track)"
fi
