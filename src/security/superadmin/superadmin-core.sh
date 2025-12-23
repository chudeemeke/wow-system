#!/bin/bash
# WoW System - SuperAdmin Core Library
# Provides: Biometric-enforced SuperAdmin authentication for high-privilege operations
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Biometric First: Fingerprint authentication preferred (fprintd/Touch ID)
# - Fallback Auth: Strong passphrase for systems without biometrics
# - Defense in Depth: Multiple layers (TTY + biometric/passphrase + HMAC + short timeouts)
# - Fail-Secure: Errors keep protection ON
# - Shorter Timeouts: 15 min max, 5 min inactivity (vs 4hr/30min for bypass)

# Prevent double-sourcing
if [[ -n "${WOW_SUPERADMIN_CORE_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_SUPERADMIN_CORE_LOADED=1

# Source dependencies
_SUPERADMIN_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SUPERADMIN_CORE_DIR}/../../core/utils.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

# Data directory (uses WOW_DATA_DIR or falls back)
readonly SUPERADMIN_DATA_DIR="${SUPERADMIN_DATA_DIR:-${WOW_DATA_DIR:-${HOME}/.wow-data}/superadmin}"
readonly SUPERADMIN_TOKEN_FILE="${SUPERADMIN_DATA_DIR}/active.token"
readonly SUPERADMIN_HASH_FILE="${SUPERADMIN_DATA_DIR}/fallback.hash"
readonly SUPERADMIN_ACTIVITY_FILE="${SUPERADMIN_DATA_DIR}/last_activity"
readonly SUPERADMIN_FAILURES_FILE="${SUPERADMIN_DATA_DIR}/failures.json"

# Token version
readonly SUPERADMIN_TOKEN_VERSION="1"

# Safety Dead-Bolt: SHORTER timeouts than bypass (more restrictive)
readonly SUPERADMIN_MAX_DURATION="${SUPERADMIN_MAX_DURATION:-900}"           # 15 minutes (vs 4 hours for bypass)
readonly SUPERADMIN_INACTIVITY_TIMEOUT="${SUPERADMIN_INACTIVITY_TIMEOUT:-300}"  # 5 minutes (vs 30 min for bypass)

# Minimum passphrase length for fallback auth
readonly SUPERADMIN_MIN_PASSPHRASE_LENGTH=12  # Longer than bypass (8)

# ============================================================================
# Initialization
# ============================================================================

superadmin_init() {
    if [[ ! -d "${SUPERADMIN_DATA_DIR}" ]]; then
        mkdir -p "${SUPERADMIN_DATA_DIR}" 2>/dev/null || {
            wow_error "Failed to create SuperAdmin data directory" 2>/dev/null || true
            return 1
        }
        chmod 700 "${SUPERADMIN_DATA_DIR}"
    fi
    return 0
}

# ============================================================================
# TTY Detection (Core Security - same as bypass)
# ============================================================================

superadmin_check_tty() {
    # Must have stdin as TTY
    if [[ ! -t 0 ]]; then
        wow_debug "SuperAdmin TTY check failed: stdin is not a TTY" 2>/dev/null || true
        return 1
    fi

    # Must be able to read from /dev/tty
    if [[ ! -r /dev/tty ]]; then
        wow_debug "SuperAdmin TTY check failed: /dev/tty not readable" 2>/dev/null || true
        return 1
    fi

    # Check for pipe input
    if [[ -p /dev/stdin ]]; then
        wow_debug "SuperAdmin TTY check failed: stdin is a pipe" 2>/dev/null || true
        return 1
    fi

    return 0
}

# ============================================================================
# Biometric Detection
# ============================================================================

# Check if system has biometric (fingerprint) capability
superadmin_has_biometric() {
    # Check for fprintd (Linux fingerprint daemon)
    if command -v fprintd-verify &>/dev/null; then
        # Check if any fingerprint devices are enrolled
        if fprintd-list "$(whoami)" 2>/dev/null | grep -q "finger"; then
            return 0
        fi
    fi

    # Check for Touch ID (macOS)
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v bioutil &>/dev/null || [[ -f /usr/bin/security ]]; then
            # Check if Touch ID is available
            if system_profiler SPiBridgeDataType 2>/dev/null | grep -q "Touch ID"; then
                return 0
            fi
        fi
    fi

    # Check for Windows Hello (WSL - limited support)
    if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
        # WSL detected - Windows Hello might be available via PowerShell
        # For now, return false - requires additional setup
        return 1
    fi

    return 1
}

# ============================================================================
# Fingerprint Authentication
# ============================================================================

# Attempt fingerprint verification
# Returns: 0=success, 1=failed, 2=not available
superadmin_check_fingerprint() {
    # Mock mode for testing
    if [[ "${SUPERADMIN_MOCK_AUTH:-0}" == "1" ]]; then
        return 0
    fi

    # Check if biometric is available
    if ! superadmin_has_biometric; then
        return 2  # Not available
    fi

    # Linux: Use fprintd
    if command -v fprintd-verify &>/dev/null; then
        echo "Place your finger on the reader..." > /dev/tty 2>/dev/null || true

        # fprintd-verify returns 0 on success
        if fprintd-verify 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi

    # macOS: Touch ID
    if [[ "$(uname)" == "Darwin" ]]; then
        # Use osascript to prompt for Touch ID
        if osascript -e 'tell application "System Events" to authenticate' 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi

    return 2  # Not available
}

# ============================================================================
# Fallback Authentication (for systems without biometrics)
# ============================================================================

# Read passphrase from TTY (same pattern as bypass)
superadmin_read_passphrase() {
    local prompt="${1:-Enter SuperAdmin passphrase: }"
    local passphrase=""
    local char

    printf '%s' "${prompt}" > /dev/tty

    while IFS= read -rs -n1 char < /dev/tty 2>/dev/null; do
        if [[ -z "${char}" ]]; then
            break
        fi

        if [[ "${char}" == $'\x7f' ]] || [[ "${char}" == $'\b' ]]; then
            if [[ -n "${passphrase}" ]]; then
                passphrase="${passphrase%?}"
                printf '\b \b' > /dev/tty
            fi
        else
            passphrase+="${char}"
            printf '*' > /dev/tty
        fi
    done

    echo "" > /dev/tty
    printf '%s' "${passphrase}"
    return 0
}

# Hash passphrase (same algorithm as bypass)
superadmin_hash_passphrase() {
    local passphrase="$1"
    local salt
    local hash

    salt=$(head -c 16 /dev/urandom | xxd -p 2>/dev/null) || {
        salt=$(openssl rand -hex 16 2>/dev/null) || {
            return 1
        }
    }

    hash=$(printf '%s%s' "${salt}" "${passphrase}" | sha512sum | cut -d' ' -f1)
    printf '%s:%s' "${salt}" "${hash}"
}

# Verify passphrase
superadmin_verify_passphrase() {
    local passphrase="$1"
    local stored_data
    local salt
    local expected_hash
    local computed_hash

    if [[ ! -f "${SUPERADMIN_HASH_FILE}" ]]; then
        return 2  # Not configured
    fi

    stored_data=$(cat "${SUPERADMIN_HASH_FILE}" 2>/dev/null) || return 2

    if [[ ! "${stored_data}" =~ ^[a-f0-9]+:[a-f0-9]{128}$ ]]; then
        return 2
    fi

    salt="${stored_data%%:*}"
    expected_hash="${stored_data#*:}"

    computed_hash=$(printf '%s%s' "${salt}" "${passphrase}" | sha512sum | cut -d' ' -f1)

    # Constant-time comparison
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

# Store fallback passphrase hash
superadmin_store_hash() {
    local hash="$1"

    superadmin_init || return 1

    echo "${hash}" > "${SUPERADMIN_HASH_FILE}" || return 1
    chmod 600 "${SUPERADMIN_HASH_FILE}"

    wow_info "SuperAdmin fallback passphrase configured" 2>/dev/null || true
    return 0
}

# Fallback authentication (passphrase-based)
superadmin_fallback_auth() {
    # Check if fallback is configured
    if [[ ! -f "${SUPERADMIN_HASH_FILE}" ]]; then
        echo "SuperAdmin fallback not configured." > /dev/tty
        echo "Run 'wow superadmin setup' to configure." > /dev/tty
        return 2
    fi

    # Read and verify passphrase
    local passphrase
    passphrase=$(superadmin_read_passphrase "Enter SuperAdmin passphrase: ")

    if superadmin_verify_passphrase "${passphrase}"; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Token Management (HMAC-based, shorter expiry)
# ============================================================================

superadmin_create_token() {
    local created
    local expires
    local hmac
    local secret

    created=$(date +%s)
    expires=$((created + SUPERADMIN_MAX_DURATION))

    # Use fallback hash as HMAC secret, or generate ephemeral one
    if [[ -f "${SUPERADMIN_HASH_FILE}" ]]; then
        secret=$(cat "${SUPERADMIN_HASH_FILE}" 2>/dev/null)
    else
        # Generate ephemeral secret for this session
        secret=$(head -c 32 /dev/urandom | xxd -p 2>/dev/null || openssl rand -hex 32 2>/dev/null)
        superadmin_init
        echo "${secret}" > "${SUPERADMIN_DATA_DIR}/.ephemeral_secret"
        chmod 600 "${SUPERADMIN_DATA_DIR}/.ephemeral_secret"
    fi

    hmac=$(printf '%s:%s:%s' "${SUPERADMIN_TOKEN_VERSION}" "${created}" "${expires}" | \
           openssl dgst -sha512 -hmac "${secret}" 2>/dev/null | \
           sed 's/^.* //')

    if [[ -z "${hmac}" ]]; then
        return 1
    fi

    printf '%s:%s:%s:%s' "${SUPERADMIN_TOKEN_VERSION}" "${created}" "${expires}" "${hmac}"
}

superadmin_verify_token() {
    local token=""
    local version=""
    local created=""
    local expires=""
    local stored_hmac=""
    local secret=""
    local expected_hmac=""
    local now=""

    if [[ ! -f "${SUPERADMIN_TOKEN_FILE}" ]]; then
        return 1
    fi

    token=$(cat "${SUPERADMIN_TOKEN_FILE}" 2>/dev/null) || return 1

    # Parse token: version:created:expires:hmac
    local field_count
    field_count=$(echo "${token}" | tr ':' '\n' | wc -l)

    if [[ ${field_count} -lt 4 ]]; then
        return 1
    fi

    version="${token%%:*}"
    local rest="${token#*:}"
    created="${rest%%:*}"
    rest="${rest#*:}"
    expires="${rest%%:*}"
    stored_hmac="${rest#*:}"

    # Validate parsed fields
    if [[ -z "${version}" ]] || [[ -z "${created}" ]] || [[ -z "${expires}" ]] || [[ -z "${stored_hmac}" ]]; then
        return 1
    fi

    # Check if expires is a valid number
    if ! [[ "${expires}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Check expiry
    now=$(date +%s)
    if [[ ${now} -gt ${expires} ]]; then
        return 2  # Expired
    fi

    # Get secret for HMAC verification
    if [[ -f "${SUPERADMIN_HASH_FILE}" ]]; then
        secret=$(cat "${SUPERADMIN_HASH_FILE}" 2>/dev/null)
    elif [[ -f "${SUPERADMIN_DATA_DIR}/.ephemeral_secret" ]]; then
        secret=$(cat "${SUPERADMIN_DATA_DIR}/.ephemeral_secret" 2>/dev/null)
    else
        return 1  # No secret to verify
    fi

    expected_hmac=$(printf '%s:%s:%s' "${version}" "${created}" "${expires}" | \
                   openssl dgst -sha512 -hmac "${secret}" 2>/dev/null | \
                   sed 's/^.* //')

    if [[ "${stored_hmac}" != "${expected_hmac}" ]]; then
        return 1
    fi

    return 0
}

# ============================================================================
# State Management
# ============================================================================

superadmin_update_activity() {
    local now
    now=$(date +%s)
    echo "${now}" > "${SUPERADMIN_ACTIVITY_FILE}" 2>/dev/null
    chmod 600 "${SUPERADMIN_ACTIVITY_FILE}" 2>/dev/null
}

superadmin_check_inactivity() {
    local last_activity
    local now
    local elapsed

    if [[ ! -f "${SUPERADMIN_ACTIVITY_FILE}" ]]; then
        return 1
    fi

    last_activity=$(cat "${SUPERADMIN_ACTIVITY_FILE}" 2>/dev/null) || return 1
    now=$(date +%s)
    elapsed=$((now - last_activity))

    if [[ ${elapsed} -gt ${SUPERADMIN_INACTIVITY_TIMEOUT} ]]; then
        return 1
    fi

    return 0
}

superadmin_is_active() {
    local verify_result

    if [[ ! -f "${SUPERADMIN_TOKEN_FILE}" ]]; then
        return 1
    fi

    superadmin_verify_token
    verify_result=$?

    if [[ ${verify_result} -eq 2 ]]; then
        # Expired
        superadmin_deactivate
        return 1
    elif [[ ${verify_result} -ne 0 ]]; then
        # Invalid
        rm -f "${SUPERADMIN_TOKEN_FILE}" 2>/dev/null
        rm -f "${SUPERADMIN_ACTIVITY_FILE}" 2>/dev/null
        return 1
    fi

    # Check inactivity
    if ! superadmin_check_inactivity; then
        superadmin_deactivate
        return 1
    fi

    return 0
}

superadmin_get_remaining() {
    local token
    local expires
    local now
    local remaining

    if [[ ! -f "${SUPERADMIN_TOKEN_FILE}" ]]; then
        echo "0"
        return 1
    fi

    token=$(cat "${SUPERADMIN_TOKEN_FILE}" 2>/dev/null) || { echo "0"; return 1; }

    local field_count
    field_count=$(echo "${token}" | tr ':' '\n' | wc -l)

    if [[ ${field_count} -ge 4 ]]; then
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
        echo "0"
    fi
}

superadmin_activate() {
    local token

    # Mock mode for testing
    if [[ "${SUPERADMIN_MOCK_AUTH:-0}" != "1" ]]; then
        # Require TTY
        if ! superadmin_check_tty; then
            echo "SuperAdmin requires interactive terminal" >&2
            return 1
        fi

        # Try biometric first
        local bio_result
        superadmin_check_fingerprint
        bio_result=$?

        if [[ ${bio_result} -eq 2 ]]; then
            # Biometric not available, try fallback
            if ! superadmin_fallback_auth; then
                superadmin_record_failure
                return 1
            fi
        elif [[ ${bio_result} -ne 0 ]]; then
            # Biometric failed
            superadmin_record_failure
            return 1
        fi
    fi

    # Create token
    token=$(superadmin_create_token) || return 1

    superadmin_init || return 1

    echo "${token}" > "${SUPERADMIN_TOKEN_FILE}" || return 1
    chmod 600 "${SUPERADMIN_TOKEN_FILE}"

    # Initialize activity tracking
    superadmin_update_activity

    # Reset failure counter
    superadmin_reset_failures

    # Track event
    if type session_track_event &>/dev/null; then
        session_track_event "superadmin_activated" "SuperAdmin mode activated (max: ${SUPERADMIN_MAX_DURATION}s)"
    fi

    wow_info "SuperAdmin mode activated (expires in $((SUPERADMIN_MAX_DURATION / 60)) minutes)" 2>/dev/null || true
    return 0
}

superadmin_deactivate() {
    rm -f "${SUPERADMIN_TOKEN_FILE}" 2>/dev/null
    rm -f "${SUPERADMIN_ACTIVITY_FILE}" 2>/dev/null
    rm -f "${SUPERADMIN_DATA_DIR}/.ephemeral_secret" 2>/dev/null

    if type session_track_event &>/dev/null; then
        session_track_event "superadmin_deactivated" "SuperAdmin mode deactivated"
    fi

    wow_info "SuperAdmin mode deactivated" 2>/dev/null || true
    return 0
}

# ============================================================================
# Rate Limiting
# ============================================================================

superadmin_record_failure() {
    local count
    local now

    now=$(date +%s)

    if [[ -f "${SUPERADMIN_FAILURES_FILE}" ]]; then
        count=$(grep -o '"count":[0-9]*' "${SUPERADMIN_FAILURES_FILE}" 2>/dev/null | cut -d: -f2)
        count=$((count + 1))
    else
        count=1
    fi

    superadmin_init
    cat > "${SUPERADMIN_FAILURES_FILE}" << EOF
{"count":${count},"last_failure":${now}}
EOF
    chmod 600 "${SUPERADMIN_FAILURES_FILE}"

    wow_warn "SuperAdmin authentication failed (attempt ${count})" 2>/dev/null || true
}

superadmin_reset_failures() {
    rm -f "${SUPERADMIN_FAILURES_FILE}" 2>/dev/null
    return 0
}

superadmin_check_rate_limit() {
    local count
    local last_failure
    local now
    local lockout_duration
    local unlock_time
    local remaining

    if [[ ! -f "${SUPERADMIN_FAILURES_FILE}" ]]; then
        return 0
    fi

    count=$(grep -o '"count":[0-9]*' "${SUPERADMIN_FAILURES_FILE}" 2>/dev/null | cut -d: -f2)
    last_failure=$(grep -o '"last_failure":[0-9]*' "${SUPERADMIN_FAILURES_FILE}" 2>/dev/null | cut -d: -f2)
    now=$(date +%s)

    # Stricter rate limiting than bypass (fewer attempts before lockout)
    case ${count} in
        0|1) lockout_duration=0 ;;         # No lockout for first attempt
        2)   lockout_duration=60 ;;        # 1 minute
        3)   lockout_duration=300 ;;       # 5 minutes
        4)   lockout_duration=900 ;;       # 15 minutes
        5|*) lockout_duration=3600 ;;      # 1 hour (stricter than bypass)
    esac

    if [[ ${lockout_duration} -eq 0 ]]; then
        return 0
    fi

    unlock_time=$((last_failure + lockout_duration))

    if [[ ${now} -lt ${unlock_time} ]]; then
        remaining=$((unlock_time - now))
        echo "Rate limited. Try again in ${remaining} seconds." >&2
        return 1
    fi

    return 0
}

# ============================================================================
# Status Helpers
# ============================================================================

superadmin_get_status() {
    if [[ ! -f "${SUPERADMIN_HASH_FILE}" ]] && ! superadmin_has_biometric; then
        echo "NOT_CONFIGURED"
    elif superadmin_is_active; then
        echo "UNLOCKED"
    else
        echo "LOCKED"
    fi
}

superadmin_is_configured() {
    # Configured if biometric is available OR fallback hash exists
    superadmin_has_biometric || [[ -f "${SUPERADMIN_HASH_FILE}" ]]
}

# Check if SuperAdmin can unlock a specific operation
# (Returns false for CRITICAL tier - those are never unlockable)
superadmin_can_unlock() {
    local operation="$1"

    # Source security policies if available
    local policies_file="${_SUPERADMIN_CORE_DIR}/../security-policies.sh"
    if [[ -f "${policies_file}" ]]; then
        source "${policies_file}" 2>/dev/null || true
    fi

    # CRITICAL tier cannot be unlocked by anyone
    if type policy_check_critical &>/dev/null; then
        if policy_check_critical "${operation}"; then
            return 1  # Cannot unlock
        fi
    fi

    return 0  # Can unlock
}

# ============================================================================
# Self-Test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "SuperAdmin Core Self-Test"
    echo "========================="

    echo -n "Data directory: "
    echo "${SUPERADMIN_DATA_DIR}"

    echo -n "Biometric available: "
    superadmin_has_biometric && echo "Yes" || echo "No"

    echo -n "Configured: "
    superadmin_is_configured && echo "Yes" || echo "No"

    echo -n "Active: "
    superadmin_is_active && echo "Yes" || echo "No"

    echo -n "TTY available: "
    superadmin_check_tty && echo "Yes" || echo "No"

    echo ""
    echo "Max duration: $((SUPERADMIN_MAX_DURATION / 60)) minutes"
    echo "Inactivity timeout: $((SUPERADMIN_INACTIVITY_TIMEOUT / 60)) minutes"

    echo ""
    echo "Self-test complete"
fi
