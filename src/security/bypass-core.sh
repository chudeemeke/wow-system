#!/bin/bash
# WoW System - Bypass Core Library
# Provides: TTY-enforced bypass authentication system
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Human-Only Activation: TTY enforcement prevents script/AI bypass
# - Defense in Depth: Multiple security layers (TTY + passphrase + HMAC + checksums)
# - Fail-Secure: Errors keep protection ON
# - Integration: Uses WoW infrastructure (logging, paths, metrics)

# Prevent double-sourcing
if [[ -n "${WOW_BYPASS_CORE_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_BYPASS_CORE_LOADED=1

# Source dependencies (use WoW infrastructure)
_BYPASS_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_BYPASS_CORE_DIR}/../core/utils.sh" 2>/dev/null || true

# v8.0: Zone system integration
source "${_BYPASS_CORE_DIR}/zones/zone-definitions.sh" 2>/dev/null || true
source "${_BYPASS_CORE_DIR}/zones/zone-validator.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants (Integrated with WoW paths)
# ============================================================================

# Use WoW's standard data directory pattern
# When running as root (Claude Code context), this becomes /root/.wow-data/bypass
readonly BYPASS_DATA_DIR="${WOW_DATA_DIR:-${HOME}/.wow-data}/bypass"
readonly BYPASS_HASH_FILE="${BYPASS_DATA_DIR}/passphrase.hash"
readonly BYPASS_TOKEN_FILE="${BYPASS_DATA_DIR}/active.token"
readonly BYPASS_FAILURES_FILE="${BYPASS_DATA_DIR}/failures.json"
readonly BYPASS_CHECKSUMS_FILE="${BYPASS_DATA_DIR}/checksums.sha256"
readonly BYPASS_ACTIVITY_FILE="${BYPASS_DATA_DIR}/last_activity"

# Token version for future compatibility (v2 includes expiry)
readonly BYPASS_TOKEN_VERSION="2"

# Minimum passphrase length
readonly BYPASS_MIN_PASSPHRASE_LENGTH=8

# Safety Dead-Bolt: Auto-expiry settings (in seconds)
# These can be overridden by config or environment
readonly BYPASS_DEFAULT_MAX_DURATION="${BYPASS_MAX_DURATION:-14400}"      # 4 hours
readonly BYPASS_DEFAULT_INACTIVITY="${BYPASS_INACTIVITY_TIMEOUT:-1800}"   # 30 minutes

# ============================================================================
# Initialization
# ============================================================================

# Initialize bypass data directory
bypass_init() {
    if [[ ! -d "${BYPASS_DATA_DIR}" ]]; then
        mkdir -p "${BYPASS_DATA_DIR}" 2>/dev/null || {
            wow_error "Failed to create bypass data directory" 2>/dev/null || true
            return 1
        }
        chmod 700 "${BYPASS_DATA_DIR}"
    fi
    return 0
}

# ============================================================================
# TTY Detection (Core Security)
# ============================================================================

# Check if running in interactive TTY
# This is the PRIMARY security mechanism - prevents AI/script activation
bypass_check_tty() {
    # Must have stdin as TTY
    if [[ ! -t 0 ]]; then
        wow_debug "TTY check failed: stdin is not a TTY" 2>/dev/null || true
        return 1
    fi

    # Must be able to read from /dev/tty
    if [[ ! -r /dev/tty ]]; then
        wow_debug "TTY check failed: /dev/tty not readable" 2>/dev/null || true
        return 1
    fi

    # Check for pipe input (additional safety)
    if [[ -p /dev/stdin ]]; then
        wow_debug "TTY check failed: stdin is a pipe" 2>/dev/null || true
        return 1
    fi

    return 0
}

# ============================================================================
# Passphrase Management
# ============================================================================

# Read passphrase from TTY with asterisk feedback
# CRITICAL: Reads directly from /dev/tty to prevent piping attacks
bypass_read_passphrase() {
    local prompt="${1:-Enter passphrase: }"
    local passphrase=""
    local char

    # Print prompt
    printf '%s' "${prompt}" > /dev/tty

    # Read character by character, showing asterisks
    while IFS= read -rs -n1 char < /dev/tty 2>/dev/null; do
        # Enter key (empty char) ends input
        if [[ -z "${char}" ]]; then
            break
        fi

        # Handle backspace (ASCII 127 or \b)
        if [[ "${char}" == $'\x7f' ]] || [[ "${char}" == $'\b' ]]; then
            if [[ -n "${passphrase}" ]]; then
                # Remove last character
                passphrase="${passphrase%?}"
                # Erase asterisk: backspace, space, backspace
                printf '\b \b' > /dev/tty
            fi
        else
            # Add character to passphrase and show asterisk
            passphrase+="${char}"
            printf '*' > /dev/tty
        fi
    done

    # Print newline after input
    echo "" > /dev/tty

    # Output passphrase (caller captures)
    printf '%s' "${passphrase}"
    return 0
}

# Generate salted hash of passphrase
# Format: salt:hash (32 hex chars : 128 hex chars for SHA512)
bypass_hash_passphrase() {
    local passphrase="$1"
    local salt
    local hash

    # Generate random salt (32 hex chars = 16 bytes)
    salt=$(head -c 16 /dev/urandom | xxd -p 2>/dev/null) || {
        # Fallback if xxd not available
        salt=$(openssl rand -hex 16 2>/dev/null) || {
            wow_error "Cannot generate salt: xxd and openssl not available" 2>/dev/null || true
            return 1
        }
    }

    # Create SHA512 hash of salt+passphrase (128 hex chars)
    hash=$(printf '%s%s' "${salt}" "${passphrase}" | sha512sum | cut -d' ' -f1)

    printf '%s:%s' "${salt}" "${hash}"
}

# Verify passphrase against stored hash
# Returns: 0=correct, 1=wrong, 2=not configured
bypass_verify_passphrase() {
    local passphrase="$1"
    local stored_data
    local salt
    local expected_hash
    local computed_hash

    # Check if configured
    if [[ ! -f "${BYPASS_HASH_FILE}" ]]; then
        return 2
    fi

    # Read stored salt:hash
    stored_data=$(cat "${BYPASS_HASH_FILE}" 2>/dev/null) || return 2

    # Validate format: must contain colon and have proper hash length (128 hex for SHA512)
    if [[ ! "${stored_data}" =~ ^[a-f0-9]+:[a-f0-9]{128}$ ]]; then
        wow_warn "Invalid hash file format" 2>/dev/null || true
        return 2
    fi

    salt="${stored_data%%:*}"
    expected_hash="${stored_data#*:}"

    # Compute SHA512 hash of provided passphrase
    computed_hash=$(printf '%s%s' "${salt}" "${passphrase}" | sha512sum | cut -d' ' -f1)

    # Constant-time comparison (prevent timing attacks)
    # Always compare all characters regardless of mismatch
    local match=0
    local i
    local len=${#expected_hash}

    for ((i=0; i<len; i++)); do
        if [[ "${expected_hash:$i:1}" != "${computed_hash:$i:1}" ]]; then
            match=1
        fi
    done

    return ${match}
}

# Store passphrase hash
bypass_store_hash() {
    local hash="$1"

    bypass_init || return 1

    echo "${hash}" > "${BYPASS_HASH_FILE}" || {
        wow_error "Failed to store passphrase hash" 2>/dev/null || true
        return 1
    }
    chmod 600 "${BYPASS_HASH_FILE}"

    wow_info "Bypass passphrase configured" 2>/dev/null || true
    return 0
}

# ============================================================================
# Token Management (HMAC-based)
# ============================================================================

# Create HMAC-verified token with expiry (Safety Dead-Bolt)
# Format v2: version:created:expires:hmac
# Usage: bypass_create_token [custom_duration_seconds]
bypass_create_token() {
    local custom_duration="${1:-}"
    local created
    local expires
    local stored_hash
    local hmac
    local max_duration

    # Use custom duration if provided, else default
    if [[ -n "${custom_duration}" && "${custom_duration}" =~ ^[0-9]+$ ]]; then
        max_duration="${custom_duration}"
    else
        max_duration="${BYPASS_DEFAULT_MAX_DURATION}"
    fi

    created=$(date +%s)
    expires=$((created + max_duration))

    # Read passphrase hash (used as HMAC key)
    stored_hash=$(cat "${BYPASS_HASH_FILE}" 2>/dev/null) || {
        wow_error "Cannot create token: passphrase not configured" 2>/dev/null || true
        return 1
    }

    # HMAC-SHA512 of version:created:expires using passphrase hash as key
    hmac=$(printf '%s:%s:%s' "${BYPASS_TOKEN_VERSION}" "${created}" "${expires}" | \
           openssl dgst -sha512 -hmac "${stored_hash}" 2>/dev/null | \
           sed 's/^.* //')

    if [[ -z "${hmac}" ]]; then
        wow_error "Failed to create HMAC token" 2>/dev/null || true
        return 1
    fi

    printf '%s:%s:%s:%s' "${BYPASS_TOKEN_VERSION}" "${created}" "${expires}" "${hmac}"
}

# Verify token is valid (not forged)
# Returns: 0=valid, 1=invalid/missing, 2=expired
bypass_verify_token() {
    local token
    local version
    local created
    local expires
    local stored_hmac
    local stored_hash
    local expected_hmac
    local now

    # Check token file exists
    if [[ ! -f "${BYPASS_TOKEN_FILE}" ]]; then
        return 1
    fi

    # Check hash file exists
    if [[ ! -f "${BYPASS_HASH_FILE}" ]]; then
        return 1
    fi

    # Read token
    token=$(cat "${BYPASS_TOKEN_FILE}" 2>/dev/null) || return 1

    # Parse v2 format: version:created:expires:hmac
    # Also support v1 format: version:timestamp:hmac (treat as never-expiring for upgrade path)
    local field_count
    field_count=$(echo "${token}" | tr ':' '\n' | wc -l)

    if [[ ${field_count} -eq 4 ]]; then
        # v2 format with expiry
        version="${token%%:*}"
        local rest="${token#*:}"
        created="${rest%%:*}"
        rest="${rest#*:}"
        expires="${rest%%:*}"
        stored_hmac="${rest#*:}"

        # Check absolute expiry (Safety Dead-Bolt)
        now=$(date +%s)
        if [[ ${now} -gt ${expires} ]]; then
            wow_warn "Bypass token expired (max duration reached)" 2>/dev/null || true
            return 2
        fi
    else
        # v1 format (legacy) - treat as valid for HMAC but log warning
        version="${token%%:*}"
        local temp_token="${token#*:}"
        created="${temp_token%%:*}"
        expires=""
        stored_hmac="${temp_token#*:}"
        wow_debug "Legacy v1 token detected - consider re-activating for expiry support" 2>/dev/null || true
    fi

    # Read stored passphrase hash (used as HMAC key)
    stored_hash=$(cat "${BYPASS_HASH_FILE}" 2>/dev/null) || return 1

    # Compute expected HMAC based on format (SHA512)
    if [[ -n "${expires}" ]]; then
        expected_hmac=$(printf '%s:%s:%s' "${version}" "${created}" "${expires}" | \
                       openssl dgst -sha512 -hmac "${stored_hash}" 2>/dev/null | \
                       sed 's/^.* //')
    else
        expected_hmac=$(printf '%s:%s' "${version}" "${created}" | \
                       openssl dgst -sha512 -hmac "${stored_hash}" 2>/dev/null | \
                       sed 's/^.* //')
    fi

    # Constant-time comparison
    if [[ "${stored_hmac}" != "${expected_hmac}" ]]; then
        wow_warn "Token verification failed: HMAC mismatch" 2>/dev/null || true
        return 1
    fi

    return 0
}

# ============================================================================
# Bypass State Management
# ============================================================================

# Update last activity timestamp (called by handler-router on each bypassed operation)
bypass_update_activity() {
    local now
    now=$(date +%s)
    echo "${now}" > "${BYPASS_ACTIVITY_FILE}" 2>/dev/null
    chmod 600 "${BYPASS_ACTIVITY_FILE}" 2>/dev/null
}

# Check if inactivity timeout exceeded
# Returns: 0=within timeout, 1=timed out
bypass_check_inactivity() {
    local last_activity
    local now
    local elapsed
    local timeout="${BYPASS_DEFAULT_INACTIVITY}"

    # No activity file = no activity recorded = treat as timed out
    if [[ ! -f "${BYPASS_ACTIVITY_FILE}" ]]; then
        return 1
    fi

    last_activity=$(cat "${BYPASS_ACTIVITY_FILE}" 2>/dev/null) || return 1
    now=$(date +%s)
    elapsed=$((now - last_activity))

    if [[ ${elapsed} -gt ${timeout} ]]; then
        wow_warn "Bypass expired (inactivity timeout: ${elapsed}s > ${timeout}s)" 2>/dev/null || true
        return 1
    fi

    return 0
}

# Check if bypass mode is currently active (with Safety Dead-Bolt checks)
bypass_is_active() {
    local verify_result

    # Token file must exist
    if [[ ! -f "${BYPASS_TOKEN_FILE}" ]]; then
        return 1
    fi

    # Token must be valid (HMAC verified + not expired)
    bypass_verify_token
    verify_result=$?

    if [[ ${verify_result} -eq 2 ]]; then
        # Expired - auto-deactivate (Safety Dead-Bolt triggered)
        wow_warn "Safety Dead-Bolt: Auto-deactivating expired bypass" 2>/dev/null || true
        bypass_deactivate
        return 1
    elif [[ ${verify_result} -ne 0 ]]; then
        # Invalid token - remove it (security cleanup)
        rm -f "${BYPASS_TOKEN_FILE}" 2>/dev/null
        rm -f "${BYPASS_ACTIVITY_FILE}" 2>/dev/null
        wow_warn "Invalid bypass token removed" 2>/dev/null || true
        return 1
    fi

    # Check inactivity timeout (Safety Dead-Bolt)
    if ! bypass_check_inactivity; then
        wow_warn "Safety Dead-Bolt: Auto-deactivating due to inactivity" 2>/dev/null || true
        bypass_deactivate
        return 1
    fi

    return 0
}

# Get remaining bypass time (for display)
bypass_get_remaining() {
    local token
    local expires
    local now
    local remaining

    if [[ ! -f "${BYPASS_TOKEN_FILE}" ]]; then
        echo "0"
        return 1
    fi

    token=$(cat "${BYPASS_TOKEN_FILE}" 2>/dev/null) || { echo "0"; return 1; }

    # Parse v2 format to get expires
    local field_count
    field_count=$(echo "${token}" | tr ':' '\n' | wc -l)

    if [[ ${field_count} -eq 4 ]]; then
        local rest="${token#*:}"
        rest="${rest#*:}"
        expires="${rest%%:*}"
        now=$(date +%s)
        remaining=$((expires - now))
        if [[ ${remaining} -lt 0 ]]; then
            remaining=0
        fi
        echo "${remaining}"
    else
        echo "-1"  # v1 token, no expiry
    fi
}

# Activate bypass mode
# Usage: bypass_activate [custom_duration_seconds] [custom_inactivity_seconds]
bypass_activate() {
    local custom_duration="${1:-}"
    local custom_inactivity="${2:-}"
    local token
    local max_duration
    local inactivity

    # Use custom duration if provided
    if [[ -n "${custom_duration}" && "${custom_duration}" =~ ^[0-9]+$ ]]; then
        max_duration="${custom_duration}"
    else
        max_duration="${BYPASS_DEFAULT_MAX_DURATION}"
    fi

    # Use custom inactivity if provided
    if [[ -n "${custom_inactivity}" && "${custom_inactivity}" =~ ^[0-9]+$ ]]; then
        inactivity="${custom_inactivity}"
    else
        inactivity="${BYPASS_DEFAULT_INACTIVITY}"
    fi

    token=$(bypass_create_token "${max_duration}") || return 1

    bypass_init || return 1

    echo "${token}" > "${BYPASS_TOKEN_FILE}" || {
        wow_error "Failed to activate bypass" 2>/dev/null || true
        return 1
    }
    chmod 600 "${BYPASS_TOKEN_FILE}"

    # Initialize activity tracking (Safety Dead-Bolt)
    bypass_update_activity

    # Reset failure counter on successful activation
    bypass_reset_failures

    # Track event (if session manager available)
    if type session_track_event &>/dev/null; then
        session_track_event "bypass_activated" "Bypass mode activated (max: ${max_duration}s, idle: ${inactivity}s)"
    fi

    wow_info "Bypass mode activated (expires in $((max_duration / 60)) minutes or after $((inactivity / 60)) min inactivity)" 2>/dev/null || true
    return 0
}

# Deactivate bypass mode (re-enable protection)
bypass_deactivate() {
    rm -f "${BYPASS_TOKEN_FILE}" 2>/dev/null
    rm -f "${BYPASS_ACTIVITY_FILE}" 2>/dev/null

    # v8.0: Reset zone rate limit counter
    if type zone_reset_rate_limit &>/dev/null; then
        zone_reset_rate_limit
    fi

    # Track event (if session manager available)
    if type session_track_event &>/dev/null; then
        session_track_event "bypass_deactivated" "Protection re-enabled"
    fi

    wow_info "WoW protection re-enabled" 2>/dev/null || true
    return 0
}

# Check if bypass is configured
bypass_is_configured() {
    [[ -f "${BYPASS_HASH_FILE}" ]]
}

# ============================================================================
# Rate Limiting (iOS-Style)
# ============================================================================

# Record authentication failure
bypass_record_failure() {
    local count
    local now

    now=$(date +%s)

    if [[ -f "${BYPASS_FAILURES_FILE}" ]]; then
        # Extract current count
        count=$(grep -o '"count":[0-9]*' "${BYPASS_FAILURES_FILE}" 2>/dev/null | cut -d: -f2)
        count=$((count + 1))
    else
        count=1
    fi

    # Write updated failures
    bypass_init
    cat > "${BYPASS_FAILURES_FILE}" << EOF
{"count":${count},"last_failure":${now}}
EOF
    chmod 600 "${BYPASS_FAILURES_FILE}"

    wow_warn "Bypass authentication failed (attempt ${count})" 2>/dev/null || true
}

# Reset failure counter
bypass_reset_failures() {
    rm -f "${BYPASS_FAILURES_FILE}" 2>/dev/null
    return 0
}

# Check if currently rate limited
# Returns: 0=allowed, 1=locked out (prints message)
bypass_check_rate_limit() {
    local count
    local last_failure
    local now
    local lockout_duration
    local unlock_time
    local remaining

    # No failures file = no lockout
    if [[ ! -f "${BYPASS_FAILURES_FILE}" ]]; then
        return 0
    fi

    # Parse failures file
    count=$(grep -o '"count":[0-9]*' "${BYPASS_FAILURES_FILE}" 2>/dev/null | cut -d: -f2)
    last_failure=$(grep -o '"last_failure":[0-9]*' "${BYPASS_FAILURES_FILE}" 2>/dev/null | cut -d: -f2)
    now=$(date +%s)

    # iOS-style exponential backoff
    case ${count} in
        0|1|2) lockout_duration=0 ;;        # No lockout for first 2 attempts
        3)     lockout_duration=60 ;;       # 1 minute
        4)     lockout_duration=300 ;;      # 5 minutes
        5)     lockout_duration=900 ;;      # 15 minutes
        6|7|8|9) lockout_duration=3600 ;;   # 1 hour
        *)     lockout_duration=999999 ;;   # Permanent (manual reset required)
    esac

    if [[ ${lockout_duration} -eq 0 ]]; then
        return 0
    fi

    unlock_time=$((last_failure + lockout_duration))

    if [[ ${now} -lt ${unlock_time} ]]; then
        remaining=$((unlock_time - now))
        if [[ ${lockout_duration} -eq 999999 ]]; then
            echo "Account locked. Too many failed attempts." >&2
            echo "Manual reset required: rm ${BYPASS_FAILURES_FILE}" >&2
        else
            echo "Rate limited. Try again in ${remaining} seconds." >&2
        fi
        return 1
    fi

    return 0
}

# ============================================================================
# Checksum Verification (Script Integrity)
# ============================================================================

# Verify script checksums
bypass_verify_checksums() {
    local checksums_file="${BYPASS_CHECKSUMS_FILE}"

    # If no checksums file, skip verification (first run or not set up)
    if [[ ! -f "${checksums_file}" ]]; then
        return 0
    fi

    # Verify each checksum
    if ! sha256sum -c "${checksums_file}" --quiet 2>/dev/null; then
        wow_error "Script integrity check failed - possible tampering" 2>/dev/null || true
        return 1
    fi

    return 0
}

# Generate checksums for bypass scripts
bypass_generate_checksums() {
    local wow_dir="${1:-${WOW_HOME:-${HOME}/.claude/wow-system}}"
    local checksums_file="${BYPASS_CHECKSUMS_FILE}"

    bypass_init || return 1

    # Generate checksums for all bypass-related scripts
    {
        [[ -f "${wow_dir}/bin/wow-bypass-setup" ]] && sha256sum "${wow_dir}/bin/wow-bypass-setup"
        [[ -f "${wow_dir}/bin/wow-bypass" ]] && sha256sum "${wow_dir}/bin/wow-bypass"
        [[ -f "${wow_dir}/bin/wow-protect" ]] && sha256sum "${wow_dir}/bin/wow-protect"
        [[ -f "${wow_dir}/bin/wow-bypass-status" ]] && sha256sum "${wow_dir}/bin/wow-bypass-status"
        [[ -f "${wow_dir}/src/security/bypass-core.sh" ]] && sha256sum "${wow_dir}/src/security/bypass-core.sh"
        [[ -f "${wow_dir}/src/security/bypass-always-block.sh" ]] && sha256sum "${wow_dir}/src/security/bypass-always-block.sh"
    } > "${checksums_file}" 2>/dev/null

    chmod 600 "${checksums_file}"

    wow_debug "Generated bypass script checksums" 2>/dev/null || true
    return 0
}

# ============================================================================
# v8.0: Zone Awareness
# Bypass (Tier 1) only allows Development zone (~/Projects/*)
# ============================================================================

# Check if bypass mode allows a specific zone
# Returns: 0=allowed, 1=not allowed (needs higher tier)
bypass_allows_zone() {
    local zone="$1"

    # Bypass (Tier 1) only allows Development zone
    case "${zone}" in
        "${ZONE_DEVELOPMENT:-DEVELOPMENT}")
            return 0
            ;;
        "${ZONE_GENERAL:-GENERAL}")
            # General zone is always allowed (no auth required)
            return 0
            ;;
        *)
            # All other zones require Tier 2 (SuperAdmin)
            return 1
            ;;
    esac
}

# Check if bypass mode allows operations on a path
# Returns: 0=allowed, 1=not allowed (needs higher tier)
bypass_allows_path() {
    local path="$1"
    local zone

    # Classify the path into a zone
    if type zone_classify_path &>/dev/null; then
        zone=$(zone_classify_path "${path}")
    else
        # Fallback: legacy pattern matching for ~/Projects
        if [[ "${path}" =~ ^${HOME}/[Pp]rojects/ ]]; then
            zone="DEVELOPMENT"
        else
            zone="UNKNOWN"
        fi
    fi

    bypass_allows_zone "${zone}"
}

# Get allowed zones for bypass mode (for display)
bypass_get_allowed_zones() {
    echo "DEVELOPMENT (~/Projects/*)"
    echo "GENERAL (no restrictions)"
}

# ============================================================================
# Integration Helpers
# ============================================================================

# Get bypass status for display
bypass_get_status() {
    if ! bypass_is_configured; then
        echo "NOT_CONFIGURED"
    elif bypass_is_active; then
        echo "BYPASS_ACTIVE"
    else
        echo "PROTECTED"
    fi
}

# Get bypass data directory (for other modules)
bypass_get_data_dir() {
    echo "${BYPASS_DATA_DIR}"
}

# ============================================================================
# Self-Test (for validation)
# ============================================================================

bypass_self_test() {
    echo "Bypass Core Self-Test"
    echo "====================="

    echo -n "Data directory: "
    echo "${BYPASS_DATA_DIR}"

    echo -n "Configured: "
    bypass_is_configured && echo "Yes" || echo "No"

    echo -n "Active: "
    bypass_is_active && echo "Yes" || echo "No"

    echo -n "TTY available: "
    bypass_check_tty && echo "Yes" || echo "No"

    echo ""
    echo "Self-test complete"
}
