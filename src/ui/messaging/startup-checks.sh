#!/bin/bash
# WoW System - Startup Checks (Registry Pattern)
# Extensible system for session startup notifications
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Registry Pattern: Register checks dynamically
# - Open/Closed: Add new checks without modifying existing
# - Single Responsibility: Only handles startup check orchestration
# - Template Method: Standard check interface, custom implementations
#
# Usage:
#   source startup-checks.sh
#   startup_checks_init
#   startup_checks_run_all
#
# Adding custom checks:
#   startup_check_register "my_check" my_check_function 50
#   # Function signature: my_check_function() -> uses wow_msg for output

# Prevent double-sourcing
if [[ -n "${WOW_STARTUP_CHECKS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_STARTUP_CHECKS_LOADED=1

# Source dependencies
_STARTUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_STARTUP_DIR}/messages.sh"

# ============================================================================
# Check Registry
# ============================================================================

# Array of registered checks: "name:function:priority:enabled"
declare -ga _STARTUP_CHECKS=()

# Track which checks have run (prevent duplicates)
declare -gA _STARTUP_CHECKS_RAN=()

# ============================================================================
# Registry API
# ============================================================================

# Register a startup check
# Args: name function [priority] [enabled]
# Priority: 1=first, 99=last (default: 50)
# Enabled: 1=yes, 0=no (default: 1)
startup_check_register() {
    local name="$1"
    local func="$2"
    local priority="${3:-50}"
    local enabled="${4:-1}"

    _STARTUP_CHECKS+=("${name}:${func}:${priority}:${enabled}")
}

# Enable a check by name
startup_check_enable() {
    local target_name="$1"
    local i

    for i in "${!_STARTUP_CHECKS[@]}"; do
        local entry="${_STARTUP_CHECKS[$i]}"
        local name="${entry%%:*}"

        if [[ "${name}" == "${target_name}" ]]; then
            local rest="${entry#*:}"
            local func="${rest%%:*}"
            rest="${rest#*:}"
            local priority="${rest%%:*}"

            _STARTUP_CHECKS[$i]="${name}:${func}:${priority}:1"
            return 0
        fi
    done

    return 1  # Check not found
}

# Disable a check by name
startup_check_disable() {
    local target_name="$1"
    local i

    for i in "${!_STARTUP_CHECKS[@]}"; do
        local entry="${_STARTUP_CHECKS[$i]}"
        local name="${entry%%:*}"

        if [[ "${name}" == "${target_name}" ]]; then
            local rest="${entry#*:}"
            local func="${rest%%:*}"
            rest="${rest#*:}"
            local priority="${rest%%:*}"

            _STARTUP_CHECKS[$i]="${name}:${func}:${priority}:0"
            return 0
        fi
    done

    return 1  # Check not found
}

# List registered checks
startup_check_list() {
    local entry
    for entry in "${_STARTUP_CHECKS[@]}"; do
        local name="${entry%%:*}"
        local rest="${entry#*:}"
        local func="${rest%%:*}"
        rest="${rest#*:}"
        local priority="${rest%%:*}"
        local enabled="${rest##*:}"

        local status="enabled"
        [[ "${enabled}" != "1" ]] && status="disabled"

        echo "${priority} ${name} (${status})"
    done | sort -n
}

# ============================================================================
# Check Execution
# ============================================================================

# Run all registered checks (sorted by priority)
startup_checks_run_all() {
    # Reset run tracker
    _STARTUP_CHECKS_RAN=()

    # Sort by priority and run
    local sorted_checks
    sorted_checks=$(printf '%s\n' "${_STARTUP_CHECKS[@]}" | sort -t: -k3 -n)

    local check
    while IFS= read -r check; do
        [[ -z "${check}" ]] && continue

        local name func priority enabled
        IFS=':' read -r name func priority enabled <<< "${check}"

        # Skip disabled checks
        [[ "${enabled}" != "1" ]] && continue

        # Skip already-run checks
        [[ -n "${_STARTUP_CHECKS_RAN[${name}]:-}" ]] && continue

        # Run the check function if it exists
        if type "${func}" &>/dev/null; then
            "${func}"
            _STARTUP_CHECKS_RAN["${name}"]=1
        fi
    done <<< "${sorted_checks}"
}

# Run a specific check by name
startup_check_run() {
    local target_name="$1"

    local entry
    for entry in "${_STARTUP_CHECKS[@]}"; do
        local name="${entry%%:*}"

        if [[ "${name}" == "${target_name}" ]]; then
            local rest="${entry#*:}"
            local func="${rest%%:*}"

            if type "${func}" &>/dev/null; then
                "${func}"
                return 0
            fi
        fi
    done

    return 1  # Check not found
}

# ============================================================================
# Built-in Checks
# ============================================================================

# Check: Hook immutable protection
_sc_hook_immutable() {
    local hook_file="${HOME}/.claude/hooks/user-prompt-submit.sh"

    # Skip if lsattr not available
    command -v lsattr &>/dev/null || return 0

    # Skip if file doesn't exist
    [[ -f "${hook_file}" ]] || return 0

    # Check for immutable flag
    local attrs
    attrs=$(lsattr "${hook_file}" 2>/dev/null | cut -c5) || return 0

    if [[ "${attrs}" != "i" ]]; then
        wow_msg_block "security" \
            "WoW hook file is NOT protected with chattr +i" \
            "Run: ${WOW_C_CYAN}sudo ~/Projects/wow-system/bin/wow-immutable lock${WOW_C_RESET}" \
            "This prevents AI from disabling WoW by moving/deleting the hook"
    fi
}

# Check: Bypass mode active
_sc_bypass_active() {
    # Only check if bypass functions are available
    type bypass_is_active &>/dev/null || return 0

    if bypass_is_active 2>/dev/null; then
        local remaining="unknown"
        if type bypass_time_remaining &>/dev/null; then
            remaining=$(bypass_time_remaining 2>/dev/null || echo "unknown")
        fi

        wow_msg_block "warning" \
            "WoW BYPASS MODE IS ACTIVE" \
            "Protection is temporarily disabled" \
            "Time remaining: ${remaining}" \
            "Run: ${WOW_C_CYAN}wow protect${WOW_C_RESET} to re-enable protection"
    fi
}

# Check: SuperAdmin mode active
_sc_superadmin_active() {
    type superadmin_is_active &>/dev/null || return 0

    if superadmin_is_active 2>/dev/null; then
        local remaining="unknown"
        if type superadmin_time_remaining &>/dev/null; then
            remaining=$(superadmin_time_remaining 2>/dev/null || echo "unknown")
        fi

        wow_msg_block "warning" \
            "WoW SUPERADMIN MODE IS ACTIVE" \
            "Extended permissions are temporarily enabled" \
            "Time remaining: ${remaining}" \
            "Run: ${WOW_C_CYAN}wow superadmin lock${WOW_C_RESET} when done"
    fi
}

# Check: Low WoW score
_sc_low_score() {
    type scoring_get_score &>/dev/null || return 0

    local score
    score=$(scoring_get_score 2>/dev/null || echo "70")

    if [[ "${score}" -lt 50 ]]; then
        wow_msg "warning" "WoW score is low: ${WOW_C_RED}${score}/100${WOW_C_RESET}" \
            "Operate carefully to improve your score"
    fi
}

# Check: Bypass not configured
_sc_bypass_not_configured() {
    type bypass_is_configured &>/dev/null || return 0

    if ! bypass_is_configured 2>/dev/null; then
        wow_msg "info" "Bypass not configured" \
            "Run: ${WOW_C_CYAN}wow bypass-setup${WOW_C_RESET} to enable bypass functionality"
    fi
}

# Check: Development mode (WOW_DEV=1)
_sc_dev_mode() {
    if [[ "${WOW_DEV:-0}" == "1" ]]; then
        wow_msg "warning" "Development mode is active" \
            "Some security checks may be relaxed"
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize with default checks
startup_checks_init() {
    # Clear existing checks
    _STARTUP_CHECKS=()
    _STARTUP_CHECKS_RAN=()

    # Register built-in checks (ordered by priority)
    startup_check_register "dev_mode"           "_sc_dev_mode"            5
    startup_check_register "bypass_active"      "_sc_bypass_active"       10
    startup_check_register "superadmin_active"  "_sc_superadmin_active"   11
    startup_check_register "hook_immutable"     "_sc_hook_immutable"      20
    startup_check_register "low_score"          "_sc_low_score"           50
    startup_check_register "bypass_not_config"  "_sc_bypass_not_configured" 60 0  # Disabled by default
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Startup Checks - Self Test"
    echo "==========================="
    echo ""

    # Initialize
    startup_checks_init

    echo "Registered checks:"
    startup_check_list
    echo ""

    echo "Running all checks:"
    startup_checks_run_all
    echo ""

    echo "Adding custom check:"
    _custom_check() {
        wow_msg "info" "Custom check ran successfully"
    }
    startup_check_register "custom" "_custom_check" 99
    startup_check_run "custom"
    echo ""

    echo "Self-test complete"
fi
