#!/bin/bash
# WoW System - Message Types (SSOT)
# Single Source of Truth for all message type definitions
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Single Responsibility: Only defines types, colors, icons
# - Open/Closed: Add new types without modifying existing code
# - DRY: All styling defined once, referenced everywhere
#
# Usage:
#   source message-types.sh
#   msg_type_get_color "warning"  # Returns color code
#   msg_type_get_icon "error"     # Returns icon

# Prevent double-sourcing
if [[ -n "${WOW_MESSAGE_TYPES_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_MESSAGE_TYPES_LOADED=1

# ============================================================================
# Color Palette (SSOT)
# Using ANSI-C quoting for proper terminal rendering
# ============================================================================

# Base colors
readonly MSG_COLOR_RED=$'\033[0;31m'
readonly MSG_COLOR_GREEN=$'\033[0;32m'
readonly MSG_COLOR_YELLOW=$'\033[0;33m'
readonly MSG_COLOR_BLUE=$'\033[0;34m'
readonly MSG_COLOR_MAGENTA=$'\033[0;35m'
readonly MSG_COLOR_CYAN=$'\033[0;36m'
readonly MSG_COLOR_WHITE=$'\033[0;37m'

# Styles
readonly MSG_STYLE_BOLD=$'\033[1m'
readonly MSG_STYLE_DIM=$'\033[2m'
readonly MSG_STYLE_ITALIC=$'\033[3m'
readonly MSG_STYLE_UNDERLINE=$'\033[4m'
readonly MSG_STYLE_RESET=$'\033[0m'

# Semantic aliases (map meaning to color)
readonly MSG_COLOR_SUCCESS="${MSG_COLOR_GREEN}"
readonly MSG_COLOR_WARNING="${MSG_COLOR_YELLOW}"
readonly MSG_COLOR_ERROR="${MSG_COLOR_RED}"
readonly MSG_COLOR_INFO="${MSG_COLOR_CYAN}"
readonly MSG_COLOR_SECURITY="${MSG_COLOR_YELLOW}"
readonly MSG_COLOR_DEBUG="${MSG_COLOR_MAGENTA}"
readonly MSG_COLOR_MUTED="${MSG_STYLE_DIM}"

# ============================================================================
# Icon Set (SSOT)
# ============================================================================

readonly MSG_ICON_INFO="ℹ️ "
readonly MSG_ICON_SUCCESS="✅"
readonly MSG_ICON_WARNING="⚠️ "
readonly MSG_ICON_ERROR="❌"
readonly MSG_ICON_SECURITY="🔒"
readonly MSG_ICON_DEBUG="🔧"
readonly MSG_ICON_BLOCKED="🚫"
readonly MSG_ICON_ALLOWED="✓"
readonly MSG_ICON_SCORE="📊"
readonly MSG_ICON_TIME="⏱️ "

# ============================================================================
# Message Type Registry
# Format: TYPE:COLOR:ICON:PREFIX
# ============================================================================

declare -gA _MSG_TYPE_REGISTRY=(
    ["info"]="${MSG_COLOR_INFO}:${MSG_ICON_INFO}:INFO"
    ["success"]="${MSG_COLOR_SUCCESS}:${MSG_ICON_SUCCESS}:OK"
    ["warning"]="${MSG_COLOR_WARNING}:${MSG_ICON_WARNING}:WARNING"
    ["error"]="${MSG_COLOR_ERROR}:${MSG_ICON_ERROR}:ERROR"
    ["security"]="${MSG_COLOR_SECURITY}:${MSG_ICON_SECURITY}:SECURITY"
    ["debug"]="${MSG_COLOR_DEBUG}:${MSG_ICON_DEBUG}:DEBUG"
    ["blocked"]="${MSG_COLOR_ERROR}:${MSG_ICON_BLOCKED}:BLOCKED"
    ["allowed"]="${MSG_COLOR_SUCCESS}:${MSG_ICON_ALLOWED}:ALLOWED"
    ["score"]="${MSG_COLOR_INFO}:${MSG_ICON_SCORE}:SCORE"
)

# ============================================================================
# Type Query API
# ============================================================================

# Check if a message type exists
msg_type_exists() {
    local type="$1"
    [[ -n "${_MSG_TYPE_REGISTRY[${type}]:-}" ]]
}

# Get color for a message type
msg_type_get_color() {
    local type="$1"
    local entry="${_MSG_TYPE_REGISTRY[${type}]:-}"

    if [[ -z "${entry}" ]]; then
        echo "${MSG_STYLE_RESET}"
        return 1
    fi

    echo "${entry%%:*}"
}

# Get icon for a message type
msg_type_get_icon() {
    local type="$1"
    local entry="${_MSG_TYPE_REGISTRY[${type}]:-}"

    if [[ -z "${entry}" ]]; then
        echo ""
        return 1
    fi

    # Extract second field (icon)
    local rest="${entry#*:}"
    echo "${rest%%:*}"
}

# Get prefix for a message type
msg_type_get_prefix() {
    local type="$1"
    local entry="${_MSG_TYPE_REGISTRY[${type}]:-}"

    if [[ -z "${entry}" ]]; then
        echo "NOTE"
        return 1
    fi

    # Extract third field (prefix)
    echo "${entry##*:}"
}

# Get all components at once (more efficient)
# Returns: color icon prefix (space-separated)
msg_type_get_all() {
    local type="$1"
    local entry="${_MSG_TYPE_REGISTRY[${type}]:-}"

    if [[ -z "${entry}" ]]; then
        echo "${MSG_STYLE_RESET}  NOTE"
        return 1
    fi

    local color="${entry%%:*}"
    local rest="${entry#*:}"
    local icon="${rest%%:*}"
    local prefix="${rest##*:}"

    # Return as associative-style output
    echo "${color}"
    echo "${icon}"
    echo "${prefix}"
}

# ============================================================================
# Type Registration (OCP - extend without modifying)
# ============================================================================

# Register a new message type
msg_type_register() {
    local type="$1"
    local color="$2"
    local icon="$3"
    local prefix="$4"

    _MSG_TYPE_REGISTRY["${type}"]="${color}:${icon}:${prefix}"
}

# List all registered types
msg_type_list() {
    local type
    for type in "${!_MSG_TYPE_REGISTRY[@]}"; do
        echo "${type}"
    done | sort
}

# ============================================================================
# Formatting Constants
# ============================================================================

# Indentation for multi-line messages
readonly MSG_INDENT="         "  # 9 spaces

# Default output file descriptor
MSG_OUTPUT_FD=2  # stderr

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Message Types - Self Test"
    echo "========================="
    echo ""

    echo "Registered types:"
    msg_type_list
    echo ""

    echo "Type queries:"
    for type in info success warning error security; do
        color=$(msg_type_get_color "${type}")
        icon=$(msg_type_get_icon "${type}")
        prefix=$(msg_type_get_prefix "${type}")
        echo "  ${type}: ${color}${icon} ${prefix}${MSG_STYLE_RESET}"
    done
    echo ""

    echo "Color palette demo:"
    echo "  ${MSG_COLOR_RED}Red${MSG_STYLE_RESET}"
    echo "  ${MSG_COLOR_GREEN}Green${MSG_STYLE_RESET}"
    echo "  ${MSG_COLOR_YELLOW}Yellow${MSG_STYLE_RESET}"
    echo "  ${MSG_COLOR_BLUE}Blue${MSG_STYLE_RESET}"
    echo "  ${MSG_COLOR_CYAN}Cyan${MSG_STYLE_RESET}"
    echo "  ${MSG_STYLE_BOLD}Bold${MSG_STYLE_RESET}"
    echo "  ${MSG_STYLE_DIM}Dim${MSG_STYLE_RESET}"
    echo ""

    echo "Self-test complete"
fi
