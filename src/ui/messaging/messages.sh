#!/bin/bash
# WoW System - Messages API (Facade Pattern)
# Simple, unified interface for all WoW messaging
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Facade Pattern: Simple interface hiding complex subsystem
# - Single Responsibility: Only handles message dispatch
# - Apple Philosophy: Simple interface, complex internals
#
# Usage:
#   source messages.sh
#   wow_msg "info" "System initialized"
#   wow_msg "warning" "Low score" "Current: 45/100"
#   wow_msg_block "security" "BYPASS ACTIVE" "Protection disabled" "Run: wow protect"
#
# This is the ONLY file most code needs to source for messaging.

# Prevent double-sourcing
if [[ -n "${WOW_MESSAGES_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_MESSAGES_LOADED=1

# Source dependencies
_MESSAGES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_MESSAGES_DIR}/message-types.sh"
source "${_MESSAGES_DIR}/message-formatter.sh"

# ============================================================================
# Configuration
# ============================================================================

# Output file descriptor (default: stderr)
WOW_MSG_FD="${WOW_MSG_FD:-2}"

# Enable/disable messaging globally
WOW_MSG_ENABLED="${WOW_MSG_ENABLED:-1}"

# Minimum level to display (debug < info < warning < error)
WOW_MSG_MIN_LEVEL="${WOW_MSG_MIN_LEVEL:-info}"

# ============================================================================
# Level Hierarchy
# ============================================================================

declare -gA _MSG_LEVELS=(
    ["debug"]=0
    ["info"]=1
    ["success"]=1
    ["score"]=1
    ["allowed"]=1
    ["warning"]=2
    ["security"]=2
    ["error"]=3
    ["blocked"]=3
)

_msg_should_show() {
    local type="$1"
    local type_level="${_MSG_LEVELS[${type}]:-1}"
    local min_level="${_MSG_LEVELS[${WOW_MSG_MIN_LEVEL}]:-1}"

    [[ ${type_level} -ge ${min_level} ]]
}

# ============================================================================
# Primary API (Simple Interface)
# ============================================================================

# Display a message
# Args: type message [details]
wow_msg() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    # Check if messaging is enabled
    [[ "${WOW_MSG_ENABLED}" != "1" ]] && return 0

    # Check minimum level
    _msg_should_show "${type}" || return 0

    # Format and output
    msg_format "${type}" "${message}" "${details}" >&${WOW_MSG_FD}
}

# Display a block message (multi-line)
# Args: type title line1 line2 ...
wow_msg_block() {
    local type="$1"
    local title="$2"
    shift 2

    # Check if messaging is enabled
    [[ "${WOW_MSG_ENABLED}" != "1" ]] && return 0

    # Check minimum level
    _msg_should_show "${type}" || return 0

    # Format and output
    msg_format_block "${type}" "${title}" "$@" >&${WOW_MSG_FD}
}

# ============================================================================
# Convenience Functions (Type-Specific)
# ============================================================================

wow_msg_info() {
    wow_msg "info" "$1" "${2:-}"
}

wow_msg_success() {
    wow_msg "success" "$1" "${2:-}"
}

wow_msg_warning() {
    wow_msg "warning" "$1" "${2:-}"
}

wow_msg_error() {
    wow_msg "error" "$1" "${2:-}"
}

wow_msg_security() {
    wow_msg "security" "$1" "${2:-}"
}

wow_msg_debug() {
    wow_msg "debug" "$1" "${2:-}"
}

wow_msg_blocked() {
    wow_msg "blocked" "$1" "${2:-}"
}

wow_msg_allowed() {
    wow_msg "allowed" "$1" "${2:-}"
}

# ============================================================================
# Formatted Output Helpers
# ============================================================================

# Display a command suggestion (highlighted)
wow_msg_command() {
    local description="$1"
    local command="$2"

    wow_msg "info" "${description}" "Run: ${MSG_COLOR_CYAN}${command}${MSG_STYLE_RESET}"
}

# Display a score update
wow_msg_score() {
    local action="$1"     # "improved", "decreased", "unchanged"
    local score="$2"      # Current score
    local change="${3:-}" # Optional: "+5" or "-10"

    local color
    case "${action}" in
        improved)   color="${MSG_COLOR_GREEN}" ;;
        decreased)  color="${MSG_COLOR_RED}" ;;
        *)          color="${MSG_COLOR_CYAN}" ;;
    esac

    local details=""
    [[ -n "${change}" ]] && details="Change: ${change}"

    wow_msg "score" "Score ${action}: ${color}${score}/100${MSG_STYLE_RESET}" "${details}"
}

# Display a countdown/timer message
wow_msg_timer() {
    local message="$1"
    local time_remaining="$2"

    wow_msg "info" "${message}" "Time remaining: ${time_remaining}"
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize messaging system with auto-detection
wow_msg_init() {
    msg_formatter_auto
}

# Set formatter explicitly
wow_msg_set_formatter() {
    msg_formatter_set "$1"
}

# Set minimum display level
wow_msg_set_level() {
    WOW_MSG_MIN_LEVEL="$1"
}

# Enable/disable messaging
wow_msg_enable() {
    WOW_MSG_ENABLED=1
}

wow_msg_disable() {
    WOW_MSG_ENABLED=0
}

# ============================================================================
# Advanced: Direct Formatter Access
# ============================================================================

# Get formatted string without outputting (for embedding)
wow_msg_format() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    msg_format "${type}" "${message}" "${details}"
}

# Format as JSON (for hook responses)
wow_msg_as_json() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    msg_format_as "json" "${type}" "${message}" "${details}"
}

# ============================================================================
# Color/Style Exports (for inline formatting)
# ============================================================================

# Re-export commonly used colors for inline use
readonly WOW_C_RED="${MSG_COLOR_RED}"
readonly WOW_C_GREEN="${MSG_COLOR_GREEN}"
readonly WOW_C_YELLOW="${MSG_COLOR_YELLOW}"
readonly WOW_C_CYAN="${MSG_COLOR_CYAN}"
readonly WOW_C_BOLD="${MSG_STYLE_BOLD}"
readonly WOW_C_DIM="${MSG_STYLE_DIM}"
readonly WOW_C_RESET="${MSG_STYLE_RESET}"

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Messages API - Self Test"
    echo "========================"
    echo ""

    # Initialize
    wow_msg_init

    echo "Basic message types:"
    wow_msg_info "This is an info message"
    wow_msg_success "This is a success message"
    wow_msg_warning "This is a warning message" "With some details"
    wow_msg_error "This is an error message"
    wow_msg_security "This is a security message"
    wow_msg_debug "This is a debug message"
    echo ""

    echo "Handler messages:"
    wow_msg_blocked "Operation blocked" "rm -rf / is not allowed"
    wow_msg_allowed "Operation allowed"
    echo ""

    echo "Special formats:"
    wow_msg_command "Protect the hook" "sudo wow-immutable lock"
    wow_msg_score "improved" "85" "+5"
    wow_msg_timer "Bypass active" "3:45"
    echo ""

    echo "Block message:"
    wow_msg_block "security" "BYPASS MODE ACTIVE" \
        "Protection is temporarily disabled" \
        "Time remaining: 3:45:00" \
        "Run: ${WOW_C_CYAN}wow protect${WOW_C_RESET} to re-enable"

    echo "Inline colors: ${WOW_C_GREEN}green${WOW_C_RESET} and ${WOW_C_RED}red${WOW_C_RESET}"
    echo ""

    echo "Self-test complete"
fi
