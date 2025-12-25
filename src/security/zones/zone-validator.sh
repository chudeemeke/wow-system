#!/bin/bash
# WoW System - Zone Validator
# Classifies paths into security zones and validates authorization
# Author: Chude <chude@emeke.org>
#
# Provides:
# - zone_classify_path(): Determine zone from file path
# - zone_get_required_tier(): Get tier required for a zone
# - zone_is_nuclear(): Check if operation is nuclear (never unlockable)
# - zone_check_authorization(): Check if auth level allows zone access

# Prevent double-sourcing
if [[ -n "${WOW_ZONE_VALIDATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ZONE_VALIDATOR_LOADED=1

# Source dependencies
_ZONE_VALIDATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ZONE_VALIDATOR_DIR}/zone-definitions.sh"

# ============================================================================
# Path Classification
# ============================================================================

# Classify a file path into its security zone
# Returns: Zone name (DEVELOPMENT, CONFIG, SENSITIVE, SYSTEM, WOW_SELF, GENERAL)
zone_classify_path() {
    local path="$1"
    local pattern

    # Normalize path (expand ~ and resolve relative paths)
    if [[ "${path}" == "~"* ]]; then
        path="${HOME}${path:1}"
    fi

    # Check WoW Self zone FIRST (highest priority for self-protection)
    for pattern in "${ZONE_WOW_SELF_PATTERNS[@]}"; do
        if [[ "${path}" =~ ${pattern} ]]; then
            echo "${ZONE_WOW_SELF}"
            return 0
        fi
    done

    # Check Sensitive zone (credentials)
    for pattern in "${ZONE_SENSITIVE_PATTERNS[@]}"; do
        if [[ "${path}" =~ ${pattern} ]]; then
            echo "${ZONE_SENSITIVE}"
            return 0
        fi
    done

    # Check Config zone
    for pattern in "${ZONE_CONFIG_PATTERNS[@]}"; do
        if [[ "${path}" =~ ${pattern} ]]; then
            echo "${ZONE_CONFIG}"
            return 0
        fi
    done

    # Check System zone
    for pattern in "${ZONE_SYSTEM_PATTERNS[@]}"; do
        if [[ "${path}" =~ ${pattern} ]]; then
            echo "${ZONE_SYSTEM}"
            return 0
        fi
    done

    # Check Development zone (after system to avoid /usr/Projects edge case)
    for pattern in "${ZONE_DEVELOPMENT_PATTERNS[@]}"; do
        if [[ "${path}" =~ ${pattern} ]]; then
            echo "${ZONE_DEVELOPMENT}"
            return 0
        fi
    done

    # Default: General zone (no restrictions)
    echo "${ZONE_GENERAL}"
    return 0
}

# ============================================================================
# Tier Requirements
# ============================================================================

# Get the required tier for a zone
# Returns: Tier number (0, 1, or 2)
zone_get_required_tier() {
    local zone="$1"

    zone_definition_get_tier "${zone}"
}

# ============================================================================
# Nuclear Detection
# ============================================================================

# Check if an operation matches nuclear patterns (never unlockable)
# Returns: 0 if nuclear, 1 if not
zone_is_nuclear() {
    local operation="$1"
    local pattern

    for pattern in "${ZONE_NUCLEAR_PATTERNS[@]}"; do
        if [[ "${operation}" =~ ${pattern} ]]; then
            return 0  # Is nuclear
        fi
    done

    return 1  # Not nuclear
}

# Get reason for nuclear block
zone_get_nuclear_reason() {
    local operation="$1"

    if [[ "${operation}" =~ rm.*-rf.*/ ]]; then
        echo "System destruction (rm -rf)"
    elif [[ "${operation}" =~ dd.*of=/dev/ ]]; then
        echo "Disk destruction (dd to device)"
    elif [[ "${operation}" =~ mkfs\. ]]; then
        echo "Filesystem destruction (mkfs)"
    elif [[ "${operation}" =~ :\(\) ]]; then
        echo "Fork bomb detected"
    elif [[ "${operation}" =~ shutdown|halt|init.*0 ]]; then
        echo "System shutdown"
    else
        echo "Destructive operation"
    fi
}

# ============================================================================
# Authorization Check
# ============================================================================

# Check if current auth level allows access to zone
# Parameters:
#   zone: The zone being accessed
#   auth_level: Current auth level (0=none, 1=bypass, 2=superadmin)
# Returns:
#   0 = Allowed
#   2 = Tier 1 (Bypass) required
#   3 = Tier 2 (SuperAdmin) required
zone_check_authorization() {
    local zone="$1"
    local auth_level="${2:-0}"
    local required_tier

    required_tier=$(zone_get_required_tier "${zone}")

    # Tier 0 zones always allowed
    if [[ ${required_tier} -eq 0 ]]; then
        return "${ZONE_EXIT_ALLOW}"
    fi

    # Progressive disclosure: higher auth includes lower
    # SuperAdmin (2) grants access to both Tier 1 and Tier 2
    # Bypass (1) only grants access to Tier 1
    if [[ ${auth_level} -ge ${required_tier} ]]; then
        return "${ZONE_EXIT_ALLOW}"
    fi

    # Insufficient authorization
    if [[ ${required_tier} -eq ${TIER_BYPASS} ]]; then
        return "${ZONE_EXIT_TIER1_BLOCKED}"
    elif [[ ${required_tier} -eq ${TIER_SUPERADMIN} ]]; then
        return "${ZONE_EXIT_TIER2_BLOCKED}"
    fi

    # Default: blocked
    return "${ZONE_EXIT_TIER2_BLOCKED}"
}

# ============================================================================
# Full Operation Check (combines path + nuclear)
# ============================================================================

# Check operation authorization (path-based zone + nuclear patterns)
# Parameters:
#   path: File path being accessed
#   operation: Full operation string (for nuclear check)
#   auth_level: Current auth level (0=none, 1=bypass, 2=superadmin)
# Returns:
#   0 = Allowed
#   2 = Tier 1 (Bypass) required
#   3 = Tier 2 (SuperAdmin) required
#   4 = Nuclear blocked (never unlockable)
zone_check_operation() {
    local path="$1"
    local operation="${2:-${path}}"
    local auth_level="${3:-0}"

    # Check nuclear FIRST (never unlockable)
    if zone_is_nuclear "${operation}"; then
        return "${ZONE_EXIT_NUCLEAR_BLOCKED}"
    fi

    # Classify path and check authorization
    local zone
    zone=$(zone_classify_path "${path}")

    zone_check_authorization "${zone}" "${auth_level}"
}

# ============================================================================
# Current Auth Level Detection
# ============================================================================

# Get current authentication level
# Returns: 0=none, 1=bypass active, 2=superadmin active
zone_get_current_auth_level() {
    # Check SuperAdmin first (higher privilege)
    if type superadmin_is_active &>/dev/null && superadmin_is_active; then
        echo "${TIER_SUPERADMIN}"
        return 0
    fi

    # Check Bypass
    if type bypass_is_active &>/dev/null && bypass_is_active; then
        echo "${TIER_BYPASS}"
        return 0
    fi

    # No active auth
    echo "${TIER_NORMAL}"
    return 0
}

# ============================================================================
# Rate Limiting for Tier 1
# ============================================================================

# Rate limit state file
readonly ZONE_RATE_LIMIT_FILE="${WOW_DATA_DIR:-${HOME}/.wow-data}/zone-rate-limit.state"
readonly ZONE_RATE_LIMIT_OPS_PER_MIN=50
readonly ZONE_RATE_LIMIT_WINDOW=60  # seconds

# Check rate limit for Tier 1 operations
# Returns: 0 if within limit, 1 if rate limited
zone_check_rate_limit() {
    local now count window_start

    now=$(date +%s)

    # Read current state
    if [[ -f "${ZONE_RATE_LIMIT_FILE}" ]]; then
        local state
        state=$(cat "${ZONE_RATE_LIMIT_FILE}" 2>/dev/null)
        window_start=$(echo "${state}" | cut -d: -f1)
        count=$(echo "${state}" | cut -d: -f2)

        # Check if window expired
        if [[ $((now - window_start)) -ge ${ZONE_RATE_LIMIT_WINDOW} ]]; then
            # New window
            window_start=${now}
            count=0
        fi
    else
        window_start=${now}
        count=0
    fi

    # Increment count
    ((count++))

    # Save state
    mkdir -p "$(dirname "${ZONE_RATE_LIMIT_FILE}")" 2>/dev/null
    echo "${window_start}:${count}" > "${ZONE_RATE_LIMIT_FILE}" 2>/dev/null

    # Check limit
    if [[ ${count} -gt ${ZONE_RATE_LIMIT_OPS_PER_MIN} ]]; then
        return 1  # Rate limited
    fi

    return 0  # Within limit
}

# Reset rate limit counter (called on bypass deactivation)
zone_reset_rate_limit() {
    rm -f "${ZONE_RATE_LIMIT_FILE}" 2>/dev/null
    return 0
}

# Get current rate limit stats
zone_get_rate_limit_stats() {
    if [[ -f "${ZONE_RATE_LIMIT_FILE}" ]]; then
        local state now window_start count remaining
        state=$(cat "${ZONE_RATE_LIMIT_FILE}" 2>/dev/null)
        window_start=$(echo "${state}" | cut -d: -f1)
        count=$(echo "${state}" | cut -d: -f2)
        now=$(date +%s)
        remaining=$((ZONE_RATE_LIMIT_WINDOW - (now - window_start)))

        if [[ ${remaining} -lt 0 ]]; then
            remaining=0
            count=0
        fi

        echo "ops=${count}/${ZONE_RATE_LIMIT_OPS_PER_MIN} window_remaining=${remaining}s"
    else
        echo "ops=0/${ZONE_RATE_LIMIT_OPS_PER_MIN} window_remaining=${ZONE_RATE_LIMIT_WINDOW}s"
    fi
}

# ============================================================================
# Convenience Functions
# ============================================================================

# Format exit code as user-friendly message
zone_format_block_message() {
    local exit_code="$1"
    local zone="${2:-}"
    local path="${3:-}"

    local zone_desc=""
    if [[ -n "${zone}" ]]; then
        zone_desc=$(zone_definition_get_description "${zone}")
    fi

    local action=""
    action=$(zone_definition_get_action "${exit_code}")

    case "${exit_code}" in
        "${ZONE_EXIT_TIER1_BLOCKED}")
            echo "TIER 1 BLOCKED: ${zone_desc}"
            echo "Path: ${path}"
            echo "Action: ${action}"
            ;;
        "${ZONE_EXIT_TIER2_BLOCKED}")
            echo "TIER 2 BLOCKED: ${zone_desc}"
            echo "Path: ${path}"
            echo "Action: ${action}"
            ;;
        "${ZONE_EXIT_NUCLEAR_BLOCKED}")
            echo "NUCLEAR BLOCKED: Destructive operation"
            echo "Action: ${action}"
            ;;
    esac
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Zone Validator - Self Test"
    echo "=========================="

    echo ""
    echo "Path Classification Tests:"
    echo "  ~/Projects/test -> $(zone_classify_path "${HOME}/Projects/test")"
    echo "  ~/.ssh/id_rsa -> $(zone_classify_path "${HOME}/.ssh/id_rsa")"
    echo "  /etc/passwd -> $(zone_classify_path "/etc/passwd")"
    echo "  /tmp/file -> $(zone_classify_path "/tmp/file")"

    echo ""
    echo "Tier Requirements:"
    echo "  DEVELOPMENT -> $(zone_get_required_tier "DEVELOPMENT")"
    echo "  SENSITIVE -> $(zone_get_required_tier "SENSITIVE")"
    echo "  SYSTEM -> $(zone_get_required_tier "SYSTEM")"
    echo "  GENERAL -> $(zone_get_required_tier "GENERAL")"

    echo ""
    echo "Nuclear Detection:"
    echo "  'rm -rf /' -> $(zone_is_nuclear "rm -rf /" && echo "NUCLEAR" || echo "safe")"
    echo "  'rm file.txt' -> $(zone_is_nuclear "rm file.txt" && echo "NUCLEAR" || echo "safe")"

    echo ""
    echo "Current Auth Level: $(zone_get_current_auth_level)"

    echo ""
    echo "Rate Limit Stats: $(zone_get_rate_limit_stats)"

    echo ""
    echo "Self-test complete"
fi
