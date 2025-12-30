#!/bin/bash
# WoW System - Interactive Duration Module
# Handles duration argument resolution, defaults, and confirmation
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_INTERACTIVE_DURATION_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_INTERACTIVE_DURATION_LOADED=1

# Source duration parser
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/duration-parser.sh" 2>/dev/null || true

# ============================================================================
# Default Durations
# ============================================================================

# Get default duration for a mode (in seconds)
duration_get_default() {
    local mode="$1"

    case "${mode}" in
        bypass)
            echo "14400"  # 4 hours
            ;;
        superadmin)
            echo "1200"   # 20 minutes
            ;;
        *)
            echo "3600"   # 1 hour fallback
            ;;
    esac
}

# ============================================================================
# Inactivity Calculation
# ============================================================================

# Calculate inactivity timeout based on main duration
# Bypass: 1:8 ratio (4h main = 30m inactivity)
# Superadmin: 1:4 ratio (20m main = 5m inactivity)
duration_calculate_inactivity() {
    local main_duration="$1"
    local mode="$2"
    local ratio

    case "${mode}" in
        bypass)
            ratio=8
            ;;
        superadmin)
            ratio=4
            ;;
        *)
            ratio=6  # Default ratio
            ;;
    esac

    echo "$((main_duration / ratio))"
}

# ============================================================================
# Argument Resolution
# ============================================================================

# Resolve duration from argument or use default
# Returns: Duration in seconds
duration_resolve_arg() {
    local arg="$1"
    local mode="$2"
    local result

    if [[ -n "${arg}" ]]; then
        result=$(duration_parse "${arg}")
        if [[ $? -eq 0 && -n "${result}" ]]; then
            echo "${result}"
            return 0
        fi
    fi

    # Return default if no arg or invalid
    duration_get_default "${mode}"
}

# ============================================================================
# Confirmation Formatting
# ============================================================================

# Format confirmation message with duration details
duration_format_confirmation() {
    local duration_seconds="$1"
    local mode="$2"
    local formatted_main
    local inactivity_seconds
    local formatted_inactivity

    formatted_main=$(duration_format "${duration_seconds}")
    inactivity_seconds=$(duration_calculate_inactivity "${duration_seconds}" "${mode}")
    formatted_inactivity=$(duration_format "${inactivity_seconds}")

    echo "${mode} mode for ${formatted_main} (auto-lock after ${formatted_inactivity} inactivity)"
}

# ============================================================================
# User Input Validation
# ============================================================================

# Validate user-provided duration input
# Empty is OK (means use default)
# Returns: 0=valid, 1=invalid
duration_validate_user_input() {
    local input="$1"

    # Empty input is OK (use default)
    if [[ -z "${input}" ]]; then
        return 0
    fi

    # Check if it parses correctly
    duration_parse "${input}" >/dev/null 2>&1
}

# ============================================================================
# Interactive Prompts (TTY Required)
# ============================================================================

# Prompt user for duration with default confirmation
# Returns: Duration in seconds
# Usage: duration=$(duration_prompt_interactive "bypass" "4h")
duration_prompt_interactive() {
    local mode="$1"
    local default_formatted="$2"
    local default_seconds
    local user_input
    local result

    default_seconds=$(duration_get_default "${mode}")

    # Print prompt
    echo "" >&2
    echo "  Duration for ${mode} mode" >&2
    echo "" >&2
    echo "  Default: ${default_formatted} (press Enter to accept)" >&2
    echo "  Or enter custom duration (e.g., 2h, 30m, 1h30m):" >&2
    echo "" >&2
    printf "  > " >&2

    # Read user input from TTY
    if [[ -t 0 ]]; then
        read -r user_input < /dev/tty 2>/dev/null || user_input=""
    else
        user_input=""
    fi

    # Empty input = use default
    if [[ -z "${user_input}" ]]; then
        echo "${default_seconds}"
        return 0
    fi

    # Parse user input
    result=$(duration_parse "${user_input}")
    if [[ $? -eq 0 && -n "${result}" ]]; then
        echo "${result}"
        return 0
    fi

    # Invalid input, return default
    echo "  Invalid format. Using default." >&2
    echo "${default_seconds}"
}

# Confirm duration with user before proceeding
# Returns: 0=confirmed, 1=cancelled
duration_confirm_interactive() {
    local duration_seconds="$1"
    local mode="$2"
    local confirmation
    local formatted_main
    local inactivity_seconds
    local formatted_inactivity

    formatted_main=$(duration_format "${duration_seconds}")
    inactivity_seconds=$(duration_calculate_inactivity "${duration_seconds}" "${mode}")
    formatted_inactivity=$(duration_format "${inactivity_seconds}")

    echo "" >&2
    echo "  Confirm:" >&2
    echo "    Mode:       ${mode}" >&2
    echo "    Duration:   ${formatted_main}" >&2
    echo "    Inactivity: ${formatted_inactivity} (auto-lock)" >&2
    echo "" >&2
    printf "  Proceed? [Y/n] " >&2

    # Read confirmation from TTY
    if [[ -t 0 ]]; then
        read -r confirmation < /dev/tty 2>/dev/null || confirmation="n"
    else
        confirmation="y"  # Non-interactive: assume yes
    fi

    case "${confirmation}" in
        ""| [Yy]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================================
# Self-Test
# ============================================================================

duration_interactive_self_test() {
    echo "Interactive Duration Self-Test"
    echo "==============================="

    echo -n "Bypass default: "
    duration_get_default "bypass"

    echo -n "Superadmin default: "
    duration_get_default "superadmin"

    echo -n "Bypass 4h inactivity: "
    duration_calculate_inactivity 14400 "bypass"

    echo -n "Resolve arg '2h' for bypass: "
    duration_resolve_arg "2h" "bypass"

    echo ""
    echo "Self-test complete"
}
