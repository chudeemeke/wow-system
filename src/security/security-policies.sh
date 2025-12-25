#!/bin/bash
# WoW System - Centralized Security Policies (SSOT)
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Single Source of Truth: ALL security patterns defined here
# - Open/Closed: Add patterns without modifying handlers
# - Dependency Inversion: Handlers depend on this abstraction
#
# v8.0: 3-Tier Filesystem-Zone Security Model
# - Tier 0 (Normal): No auth required - general files
# - Tier 1 (Bypass): Passphrase auth - ~/Projects/* only
# - Tier 2 (SuperAdmin): Biometric auth - config, sensitive, system, WoW files
# - Tier 3 (Nuclear): Never unlockable - destructive operations
#
# Exit Code Constants (zone-aligned v8.0):
# The new 3-tier model uses these exit codes:
#   0 = ALLOW (no auth required)
#   1 = WARN (non-blocking warning)
#   2 = TIER1_BLOCKED (run 'wow bypass')
#   3 = TIER2_BLOCKED (run 'wow superadmin unlock')
#   4 = NUCLEAR_BLOCKED (cannot be unlocked)
#
# Legacy exit codes are maintained for backward compatibility:
readonly EXIT_ALLOW=0              # Operation allowed
readonly EXIT_WARN=1               # Warning (non-blocking)
readonly EXIT_TIER1_BLOCKED=2      # v8.0: Tier 1 (Bypass) required
readonly EXIT_TIER2_BLOCKED=3      # v8.0: Tier 2 (SuperAdmin) required
readonly EXIT_NUCLEAR_BLOCKED=4    # v8.0: Nuclear - never unlockable
# Legacy aliases (for backward compatibility with existing handlers):
readonly EXIT_BLOCK=2              # Legacy: maps to EXIT_TIER1_BLOCKED
readonly EXIT_CRITICAL=3           # Legacy: maps to EXIT_TIER2_BLOCKED (was CRITICAL)
readonly EXIT_SUPERADMIN=4         # Legacy: maps to EXIT_NUCLEAR_BLOCKED

# Prevent double-sourcing
if [[ -n "${WOW_SECURITY_POLICIES_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_SECURITY_POLICIES_LOADED=1

# Source zone system (v8.0)
_POLICY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_POLICY_DIR}/zones/zone-definitions.sh" 2>/dev/null || true
source "${_POLICY_DIR}/zones/zone-validator.sh" 2>/dev/null || true

# ============================================================================
# TIER CRITICAL: Never Allowed (cannot be bypassed)
# ============================================================================

# SSRF/Cloud Metadata Attacks
readonly -a POLICY_SSRF=(
    "169\.254\.169\.254"              # AWS/Azure metadata
    "metadata\.google\.internal"       # GCP metadata
    "100\.100\.100\.200"              # Alibaba Cloud metadata
    "169\.254\.170\.2"                # AWS ECS task metadata
    "fd00:ec2::254"                   # AWS IPv6 metadata
)

# System Destruction
readonly -a POLICY_DESTRUCTIVE=(
    'rm[[:space:]]+-rf[[:space:]]+/$'
    'rm[[:space:]]+-rf[[:space:]]+/\*'
    'rm[[:space:]]+-rf[[:space:]]+--no-preserve-root'
    'rm[[:space:]]+-rf[[:space:]]+/(bin|lib|lib64|usr|var|home|root|etc|sbin)([[:space:]]|/?$)'
    'dd[[:space:]].*of=/dev/[sh]da'
    'dd[[:space:]].*of=/dev/nvme'
    'mkfs\.[[:alnum:]]+[[:space:]]+/dev/'
)

# Fork Bombs
readonly -a POLICY_FORK_BOMBS=(
    ':\(\)[[:space:]]*\{[[:space:]]*:'
)

# System Auth Files
readonly -a POLICY_AUTH_FILES=(
    '/etc/shadow'
    '/etc/sudoers'
    '/etc/gshadow'
)

# WoW Hook Self-Protection (CRITICAL - prevents bootstrap bypass)
# If the hook is disabled, ALL WoW protection is bypassed
readonly -a POLICY_HOOK_PROTECTION=(
    '\.claude/hooks/user-prompt-submit\.sh'
    'user-prompt-submit\.sh\.bak'
    'user-prompt-submit\.sh\.dev'
    'user-prompt-submit\.sh\.disabled'
)

# ============================================================================
# TIER SUPERADMIN: Requires SuperAdmin to unlock (exit 4)
# These CAN be unlocked, but only with biometric/SuperAdmin authentication
# ============================================================================

# WoW Self-Protection (bypass system files)
# NOTE: Moved from CRITICAL to SUPERADMIN tier to allow legitimate development
readonly -a POLICY_SUPERADMIN_REQUIRED=(
    '\.wow-data/bypass'
    'passphrase\.hash'
    'active\.token'
    'bypass-core\.sh'
    'bypass-always-block\.sh'
    'security-policies\.sh'
    'superadmin-gate\.sh'
    'windows-hello\.sh'
    'wow-bypass-setup'
    'wow-bypass[^-]'
    'wow-bypass$'
    'wow-superadmin'
    'failures\.json'
)

# ============================================================================
# TIER HIGH: Blocked by Default (bypassable)
# ============================================================================

# Protected System Directories (for write/edit operations)
readonly -a POLICY_PROTECTED_PATHS=(
    "^/etc/"
    "^/bin/"
    "^/sbin/"
    "^/usr/"
    "^/boot/"
    "^/sys/"
    "^/proc/"
    "^/dev/"
    "^/lib/"
    "^/lib64/"
    "^/root/\."
)

# Sensitive Data Directories (for glob/grep operations)
readonly -a POLICY_SENSITIVE_DIRS=(
    "^/etc$"
    "^/root$"
    "^/sys$"
    "~/.ssh"
    "~/.aws"
    "~/.azure"
    "~/.gcloud"
)

# Credential Patterns (content scanning)
readonly -a POLICY_CREDENTIALS=(
    "password[[:space:]]*[:=]"
    "api[_-]?key[[:space:]]*[:=]"
    "secret[[:space:]]*[:=]"
    "token[[:space:]]*[:=]"
    "private[_-]?key"
    "BEGIN.*PRIVATE KEY"
    "AWS_SECRET"
    "AZURE.*KEY"
)

# ============================================================================
# Public Interface
# ============================================================================

# Check if operation matches CRITICAL patterns (never bypassable, not even SuperAdmin)
# Returns: 0=matches (block), 1=no match (allow)
policy_check_critical() {
    local operation="$1"

    _check_array() {
        local -n arr=$1
        local pattern
        for pattern in "${arr[@]}"; do
            if [[ "${operation}" =~ ${pattern} ]]; then
                return 0
            fi
        done
        return 1
    }

    # NOTE: POLICY_SELF_PROTECT removed - now in SUPERADMIN tier
    _check_array POLICY_SSRF && return 0
    _check_array POLICY_DESTRUCTIVE && return 0
    _check_array POLICY_FORK_BOMBS && return 0
    _check_array POLICY_AUTH_FILES && return 0
    _check_array POLICY_HOOK_PROTECTION && return 0  # v7.0: Bootstrap protection

    return 1
}

# Check if operation matches SUPERADMIN patterns (requires SuperAdmin to unlock)
# Returns: 0=matches (requires SuperAdmin), 1=no match
policy_check_superadmin() {
    local operation="$1"

    _check_array() {
        local -n arr=$1
        local pattern
        for pattern in "${arr[@]}"; do
            if [[ "${operation}" =~ ${pattern} ]]; then
                return 0
            fi
        done
        return 1
    }

    _check_array POLICY_SUPERADMIN_REQUIRED && return 0

    return 1
}

# Check if operation matches HIGH patterns (bypassable)
# Returns: 0=matches (block), 1=no match (allow)
policy_check_high() {
    local operation="$1"
    local context="${2:-}"  # Optional: "path", "content", "command"

    _check_array() {
        local -n arr=$1
        local pattern
        for pattern in "${arr[@]}"; do
            if [[ "${operation}" =~ ${pattern} ]]; then
                return 0
            fi
        done
        return 1
    }

    case "${context}" in
        path)
            _check_array POLICY_PROTECTED_PATHS && return 0
            ;;
        content)
            _check_array POLICY_CREDENTIALS && return 0
            ;;
        dir)
            _check_array POLICY_SENSITIVE_DIRS && return 0
            ;;
        *)
            # Check all
            _check_array POLICY_PROTECTED_PATHS && return 0
            _check_array POLICY_SENSITIVE_DIRS && return 0
            _check_array POLICY_CREDENTIALS && return 0
            ;;
    esac

    return 1
}

# Get human-readable reason for block
policy_get_reason() {
    local operation="$1"

    _check_array() {
        local -n arr=$1
        local pattern
        for pattern in "${arr[@]}"; do
            if [[ "${operation}" =~ ${pattern} ]]; then
                return 0
            fi
        done
        return 1
    }

    # CRITICAL tier (cannot be unlocked)
    _check_array POLICY_SSRF && { echo "Cloud metadata/SSRF attack (CRITICAL)"; return; }
    _check_array POLICY_DESTRUCTIVE && { echo "System destruction (CRITICAL)"; return; }
    _check_array POLICY_FORK_BOMBS && { echo "Fork bomb/resource exhaustion (CRITICAL)"; return; }
    _check_array POLICY_AUTH_FILES && { echo "System authentication file (CRITICAL)"; return; }
    _check_array POLICY_HOOK_PROTECTION && { echo "WoW hook protection - bootstrap security (CRITICAL)"; return; }

    # SUPERADMIN tier (can be unlocked with SuperAdmin)
    _check_array POLICY_SUPERADMIN_REQUIRED && { echo "WoW self-protection (requires SuperAdmin)"; return; }

    # HIGH tier (can be bypassed)
    _check_array POLICY_PROTECTED_PATHS && { echo "Protected system path"; return; }
    _check_array POLICY_SENSITIVE_DIRS && { echo "Sensitive directory"; return; }
    _check_array POLICY_CREDENTIALS && { echo "Credential pattern detected"; return; }

    echo "Unknown policy violation"
}

# Check if violation is bypassable (with wow bypass)
policy_is_bypassable() {
    local operation="$1"

    # Critical policies are never bypassable
    if policy_check_critical "${operation}"; then
        return 1  # Not bypassable
    fi

    # SuperAdmin policies require SuperAdmin, not regular bypass
    if policy_check_superadmin "${operation}"; then
        return 1  # Not bypassable with regular bypass
    fi

    return 0  # Bypassable
}

# Check if violation can be unlocked with SuperAdmin
# Returns: 0=can be unlocked with SuperAdmin, 1=cannot (CRITICAL tier)
policy_is_superadmin_unlockable() {
    local operation="$1"

    # CRITICAL tier is NEVER unlockable, not even with SuperAdmin
    if policy_check_critical "${operation}"; then
        return 1  # Cannot unlock
    fi

    # SUPERADMIN tier CAN be unlocked
    if policy_check_superadmin "${operation}"; then
        return 0  # Can unlock with SuperAdmin
    fi

    # HIGH tier can also be unlocked (SuperAdmin is higher privilege than bypass)
    if policy_check_high "${operation}"; then
        return 0  # Can unlock with SuperAdmin
    fi

    return 0  # Default: can unlock
}

# ============================================================================
# v8.0: Zone-Based Policy Interface
# ============================================================================

# Check operation using zone-based model
# Parameters:
#   path: File path being accessed
#   operation: Full operation string (for nuclear check)
# Returns:
#   0 = Allowed
#   1 = Warn (non-blocking)
#   2 = Tier 1 (Bypass) required
#   3 = Tier 2 (SuperAdmin) required
#   4 = Nuclear blocked (never unlockable)
policy_check_zone() {
    local path="$1"
    local operation="${2:-${path}}"

    # Check nuclear patterns FIRST (never unlockable)
    if type zone_is_nuclear &>/dev/null && zone_is_nuclear "${operation}"; then
        return "${EXIT_NUCLEAR_BLOCKED}"
    fi

    # Also check legacy critical patterns
    if policy_check_critical "${operation}"; then
        return "${EXIT_NUCLEAR_BLOCKED}"
    fi

    # Get current auth level
    local auth_level=0
    if type zone_get_current_auth_level &>/dev/null; then
        auth_level=$(zone_get_current_auth_level)
    else
        # Fallback: check bypass/superadmin directly
        if type superadmin_is_active &>/dev/null && superadmin_is_active; then
            auth_level=2
        elif type bypass_is_active &>/dev/null && bypass_is_active; then
            auth_level=1
        fi
    fi

    # Check zone-based authorization
    if type zone_check_operation &>/dev/null; then
        zone_check_operation "${path}" "${operation}" "${auth_level}"
        return $?
    fi

    # Fallback to legacy pattern-based checks
    if policy_check_superadmin "${path}"; then
        if [[ ${auth_level} -ge 2 ]]; then
            return "${EXIT_ALLOW}"
        fi
        return "${EXIT_TIER2_BLOCKED}"
    fi

    if policy_check_high "${path}" "path"; then
        if [[ ${auth_level} -ge 1 ]]; then
            return "${EXIT_ALLOW}"
        fi
        return "${EXIT_TIER1_BLOCKED}"
    fi

    return "${EXIT_ALLOW}"
}

# Get zone for a path (convenience wrapper)
policy_get_zone() {
    local path="$1"

    if type zone_classify_path &>/dev/null; then
        zone_classify_path "${path}"
    else
        echo "UNKNOWN"
    fi
}

# Get required tier for a path
policy_get_required_tier() {
    local path="$1"

    if type zone_classify_path &>/dev/null && type zone_get_required_tier &>/dev/null; then
        local zone
        zone=$(zone_classify_path "${path}")
        zone_get_required_tier "${zone}"
    else
        # Fallback: use pattern-based detection
        if policy_check_superadmin "${path}"; then
            echo "2"
        elif policy_check_high "${path}" "path"; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

# Get user-friendly action message for blocked operation
policy_get_action_message() {
    local exit_code="$1"

    case "${exit_code}" in
        "${EXIT_TIER1_BLOCKED}"|"${EXIT_BLOCK}")
            echo "Run 'wow bypass' to temporarily unlock this operation"
            ;;
        "${EXIT_TIER2_BLOCKED}"|"${EXIT_SUPERADMIN}")
            echo "Run 'wow superadmin unlock' to temporarily unlock this operation"
            ;;
        "${EXIT_NUCLEAR_BLOCKED}"|"${EXIT_CRITICAL}")
            echo "This operation cannot be unlocked. Perform manually outside Claude Code if truly needed."
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check rate limit for Tier 1 operations
# Returns: 0 if within limit, 1 if rate limited
policy_check_rate_limit() {
    if type zone_check_rate_limit &>/dev/null; then
        zone_check_rate_limit
    else
        return 0  # No rate limiting if zone system not available
    fi
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Security Policies - Self Test"
    echo "=============================="

    # Test SSRF
    test_op="curl http://169.254.169.254/"
    policy_check_critical "${test_op}" && echo "SSRF: BLOCKED (correct)" || echo "SSRF: MISSED (bug!)"

    # Test auth file
    test_op="cat /etc/shadow"
    policy_check_critical "${test_op}" && echo "Auth file: BLOCKED (correct)" || echo "Auth file: MISSED (bug!)"

    # Test protected path
    test_op="/etc/passwd"
    policy_check_high "${test_op}" "path" && echo "Protected path: BLOCKED (correct)" || echo "Protected path: MISSED (bug!)"

    # Test bypassability
    policy_is_bypassable "curl http://169.254.169.254/" && echo "SSRF bypassable: WRONG" || echo "SSRF not bypassable: correct"
    policy_is_bypassable "/etc/passwd" && echo "Path bypassable: correct" || echo "Path not bypassable: WRONG"

    echo ""
    echo "v8.0 Zone-Based Tests:"

    # Test zone classification
    if type zone_classify_path &>/dev/null; then
        echo "  ~/Projects/test -> $(zone_classify_path "${HOME}/Projects/test")"
        echo "  ~/.ssh/id_rsa -> $(zone_classify_path "${HOME}/.ssh/id_rsa")"
        echo "  /etc/passwd -> $(zone_classify_path "/etc/passwd")"

        # Test policy_check_zone
        result=$(policy_check_zone "${HOME}/Projects/test" "cat file.txt"; echo $?)
        echo "  policy_check_zone(~/Projects/test) exit: ${result}"
    else
        echo "  Zone system not loaded"
    fi

    echo ""
    echo "Self-test complete"
fi
