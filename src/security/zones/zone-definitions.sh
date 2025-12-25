#!/bin/bash
# WoW System - Zone Definitions
# Defines filesystem security zones and their tier requirements
# Author: Chude <chude@emeke.org>
#
# Security Zones:
# - DEVELOPMENT: ~/Projects/* - User's work area (Tier 1)
# - CONFIG: ~/.claude/*, ~/.config/* - Configuration files (Tier 2)
# - SENSITIVE: ~/.ssh/*, ~/.aws/*, ~/.gnupg/* - Credentials (Tier 2)
# - SYSTEM: /etc/*, /bin/*, /usr/*, /boot/* - OS files (Tier 2)
# - WOW_SELF: WoW handlers, hooks, security - Security infrastructure (Tier 2)
# - GENERAL: Everything else - No restrictions (Tier 0)
#
# Security Tiers:
# - Tier 0: Normal - No auth required
# - Tier 1: Bypass - Passphrase auth, 4hr/30min timeout
# - Tier 2: SuperAdmin - Biometric auth, 20min/5min timeout
# - Tier 3: Nuclear - Never unlockable (destructive operations)

# Prevent double-sourcing
if [[ -n "${WOW_ZONE_DEFINITIONS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ZONE_DEFINITIONS_LOADED=1

# ============================================================================
# Zone Constants
# ============================================================================

readonly ZONE_DEVELOPMENT="DEVELOPMENT"
readonly ZONE_CONFIG="CONFIG"
readonly ZONE_SENSITIVE="SENSITIVE"
readonly ZONE_SYSTEM="SYSTEM"
readonly ZONE_WOW_SELF="WOW_SELF"
readonly ZONE_GENERAL="GENERAL"

# ============================================================================
# Tier Constants
# ============================================================================

readonly TIER_NORMAL=0       # No auth required
readonly TIER_BYPASS=1       # Passphrase auth (wow bypass)
readonly TIER_SUPERADMIN=2   # Biometric auth (wow superadmin unlock)
readonly TIER_NUCLEAR=3      # Never unlockable

# ============================================================================
# Exit Code Constants (aligned with handler-router)
# ============================================================================

readonly ZONE_EXIT_ALLOW=0           # Operation allowed
readonly ZONE_EXIT_WARN=1            # Warning (non-blocking)
readonly ZONE_EXIT_TIER1_BLOCKED=2   # Tier 1 (Bypass) required
readonly ZONE_EXIT_TIER2_BLOCKED=3   # Tier 2 (SuperAdmin) required
readonly ZONE_EXIT_NUCLEAR_BLOCKED=4 # Nuclear - never unlockable

# ============================================================================
# Zone Path Patterns
# ============================================================================

# Development Zone: User's project work area
# Tier 1 (Bypass) required
readonly -a ZONE_DEVELOPMENT_PATTERNS=(
    "^${HOME}/Projects/"
    "^${HOME}/projects/"
    "^/home/[^/]+/Projects/"
    "^/home/[^/]+/projects/"
)

# Config Zone: User configuration files
# Tier 2 (SuperAdmin) required
readonly -a ZONE_CONFIG_PATTERNS=(
    "^${HOME}/\.claude/"
    "^${HOME}/\.config/"
    "^${HOME}/\.local/share/"
    "^/home/[^/]+/\.claude/"
    "^/home/[^/]+/\.config/"
    "^/root/\.claude/"
    "^/root/\.config/"
)

# Sensitive Zone: Credential and key files
# Tier 2 (SuperAdmin) required
readonly -a ZONE_SENSITIVE_PATTERNS=(
    "^${HOME}/\.ssh/"
    "^${HOME}/\.aws/"
    "^${HOME}/\.azure/"
    "^${HOME}/\.gcloud/"
    "^${HOME}/\.gnupg/"
    "^${HOME}/\.kube/"
    "^/home/[^/]+/\.ssh/"
    "^/home/[^/]+/\.aws/"
    "^/home/[^/]+/\.gnupg/"
    "^/root/\.ssh/"
    "^/root/\.aws/"
    "^/root/\.gnupg/"
)

# System Zone: Operating system files
# Tier 2 (SuperAdmin) required
readonly -a ZONE_SYSTEM_PATTERNS=(
    "^/etc/"
    "^/bin/"
    "^/sbin/"
    "^/lib/"
    "^/lib64/"
    "^/usr/"
    "^/boot/"
    "^/sys/"
    "^/proc/"
    "^/dev/"
    "^/var/lib/"
    "^/var/log/"
)

# WoW Self Zone: WoW security infrastructure
# Tier 2 (SuperAdmin) required
# These patterns protect WoW from self-modification attacks
readonly -a ZONE_WOW_SELF_PATTERNS=(
    # Hook files (bootstrap protection)
    "\.claude/hooks/"
    "user-prompt-submit\.sh"
    # WoW source files
    "wow-system/src/"
    "wow-system/hooks/"
    "wow-system/bin/"
    # Bypass/SuperAdmin data
    "\.wow-data/bypass/"
    "\.wow-data/superadmin/"
    # Security files by name
    "bypass-core\.sh"
    "bypass-always-block\.sh"
    "superadmin-core\.sh"
    "security-policies\.sh"
    "zone-definitions\.sh"
    "zone-validator\.sh"
)

# ============================================================================
# Nuclear Patterns (Tier 3 - Never Unlockable)
# These operations are NEVER allowed, regardless of auth level
# ============================================================================

readonly -a ZONE_NUCLEAR_PATTERNS=(
    # System destruction
    'rm[[:space:]]+-rf[[:space:]]+/$'
    'rm[[:space:]]+-rf[[:space:]]+/\*'
    'rm[[:space:]]+-rf[[:space:]]+--no-preserve-root'
    'rm[[:space:]]+-rf[[:space:]]+/(bin|lib|lib64|usr|var|home|root|etc|sbin)([[:space:]]|/?$)'
    # Disk destruction
    'dd[[:space:]].*of=/dev/[sh]da'
    'dd[[:space:]].*of=/dev/nvme'
    'dd[[:space:]].*if=/dev/zero.*of=/dev/'
    'dd[[:space:]].*if=/dev/random.*of=/dev/'
    # Filesystem destruction
    'mkfs\.[[:alnum:]]+[[:space:]]+/dev/'
    'fdisk[[:space:]]+/dev/[sh]da'
    'parted[[:space:]]+/dev/'
    # Fork bombs
    ':\(\)[[:space:]]*\{[[:space:]]*:'
    'fork[[:space:]]*\(\)[[:space:]]*while'
    # Shutdown/reboot
    'shutdown[[:space:]]+-h[[:space:]]+now'
    'init[[:space:]]+0'
    'halt[[:space:]]+-f'
)

# ============================================================================
# Tier to Zone Mapping
# ============================================================================

# Get required tier for a zone
zone_definition_get_tier() {
    local zone="$1"

    case "${zone}" in
        "${ZONE_DEVELOPMENT}")
            echo "${TIER_BYPASS}"
            ;;
        "${ZONE_CONFIG}"|"${ZONE_SENSITIVE}"|"${ZONE_SYSTEM}"|"${ZONE_WOW_SELF}")
            echo "${TIER_SUPERADMIN}"
            ;;
        "${ZONE_GENERAL}"|*)
            echo "${TIER_NORMAL}"
            ;;
    esac
}

# Get zone description for user-facing messages
zone_definition_get_description() {
    local zone="$1"

    case "${zone}" in
        "${ZONE_DEVELOPMENT}")
            echo "Development projects (~/Projects/*)"
            ;;
        "${ZONE_CONFIG}")
            echo "Configuration files (~/.config/*, ~/.claude/*)"
            ;;
        "${ZONE_SENSITIVE}")
            echo "Credential files (~/.ssh/*, ~/.aws/*)"
            ;;
        "${ZONE_SYSTEM}")
            echo "System files (/etc/*, /usr/*, /bin/*)"
            ;;
        "${ZONE_WOW_SELF}")
            echo "WoW security infrastructure"
            ;;
        "${ZONE_GENERAL}"|*)
            echo "General files"
            ;;
    esac
}

# Get user action for blocked operation
zone_definition_get_action() {
    local exit_code="$1"

    case "${exit_code}" in
        "${ZONE_EXIT_TIER1_BLOCKED}")
            echo "Run 'wow bypass' to temporarily unlock project files"
            ;;
        "${ZONE_EXIT_TIER2_BLOCKED}")
            echo "Run 'wow superadmin unlock' to temporarily unlock protected files"
            ;;
        "${ZONE_EXIT_NUCLEAR_BLOCKED}")
            echo "This operation cannot be unlocked. Perform manually outside Claude Code if truly needed."
            ;;
        *)
            echo ""
            ;;
    esac
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Zone Definitions - Self Test"
    echo "============================="

    echo ""
    echo "Zones defined:"
    echo "  - ${ZONE_DEVELOPMENT}"
    echo "  - ${ZONE_CONFIG}"
    echo "  - ${ZONE_SENSITIVE}"
    echo "  - ${ZONE_SYSTEM}"
    echo "  - ${ZONE_WOW_SELF}"
    echo "  - ${ZONE_GENERAL}"

    echo ""
    echo "Tiers defined:"
    echo "  - TIER_NORMAL: ${TIER_NORMAL}"
    echo "  - TIER_BYPASS: ${TIER_BYPASS}"
    echo "  - TIER_SUPERADMIN: ${TIER_SUPERADMIN}"
    echo "  - TIER_NUCLEAR: ${TIER_NUCLEAR}"

    echo ""
    echo "Exit codes:"
    echo "  - ALLOW: ${ZONE_EXIT_ALLOW}"
    echo "  - WARN: ${ZONE_EXIT_WARN}"
    echo "  - TIER1_BLOCKED: ${ZONE_EXIT_TIER1_BLOCKED}"
    echo "  - TIER2_BLOCKED: ${ZONE_EXIT_TIER2_BLOCKED}"
    echo "  - NUCLEAR_BLOCKED: ${ZONE_EXIT_NUCLEAR_BLOCKED}"

    echo ""
    echo "Pattern counts:"
    echo "  - Development: ${#ZONE_DEVELOPMENT_PATTERNS[@]}"
    echo "  - Config: ${#ZONE_CONFIG_PATTERNS[@]}"
    echo "  - Sensitive: ${#ZONE_SENSITIVE_PATTERNS[@]}"
    echo "  - System: ${#ZONE_SYSTEM_PATTERNS[@]}"
    echo "  - WoW Self: ${#ZONE_WOW_SELF_PATTERNS[@]}"
    echo "  - Nuclear: ${#ZONE_NUCLEAR_PATTERNS[@]}"

    echo ""
    echo "Self-test complete"
fi
