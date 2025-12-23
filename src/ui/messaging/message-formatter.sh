#!/bin/bash
# WoW System - Message Formatter (Strategy Pattern)
# Provides different formatting strategies for different output contexts
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Strategy Pattern: Swap formatters without changing client code
# - Single Responsibility: Only handles formatting, not display
# - Open/Closed: Add new formatters without modifying existing
#
# Formatters:
# - terminal: Colored output for human-readable terminal display
# - json: Structured JSON for Claude Code hook responses
# - log: Timestamped plain text for log files
# - plain: No colors, for non-TTY environments
#
# Usage:
#   source message-formatter.sh
#   msg_formatter_set "terminal"
#   formatted=$(msg_format "warning" "Something happened" "Details here")

# Prevent double-sourcing
if [[ -n "${WOW_MESSAGE_FORMATTER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_MESSAGE_FORMATTER_LOADED=1

# Source dependencies
_FORMATTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_FORMATTER_DIR}/message-types.sh"

# ============================================================================
# Formatter State
# ============================================================================

# Current active formatter (default: terminal)
_MSG_CURRENT_FORMATTER="terminal"

# ============================================================================
# Formatter Registry (Strategy Pattern)
# ============================================================================

declare -gA _MSG_FORMATTER_REGISTRY=(
    ["terminal"]="_fmt_terminal"
    ["json"]="_fmt_json"
    ["log"]="_fmt_log"
    ["plain"]="_fmt_plain"
)

# ============================================================================
# Formatter Strategies
# ============================================================================

# Terminal formatter: Colored, human-readable (Apple-style)
# Design: Clean, aligned, minimal but informative
_fmt_terminal() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    local color icon prefix
    color=$(msg_type_get_color "${type}")
    icon=$(msg_type_get_icon "${type}")
    prefix=$(msg_type_get_prefix "${type}")

    local output=""

    # Apple-style: Icon + colored prefix + message
    # Consistent 2-space indent for visual hierarchy
    output="  ${icon} ${color}${prefix}${MSG_STYLE_RESET}  ${message}"

    # Details (indented, dimmed, aligned with message)
    if [[ -n "${details}" ]]; then
        output="${output}"$'\n'"     ${MSG_STYLE_DIM}${details}${MSG_STYLE_RESET}"
    fi

    echo "${output}"
}

# JSON formatter: Structured output for programmatic consumption
_fmt_json() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    local prefix
    prefix=$(msg_type_get_prefix "${type}")

    # Build JSON (without jq dependency for speed)
    local json="{"
    json+="\"type\":\"${type}\","
    json+="\"prefix\":\"${prefix}\","
    json+="\"message\":\"${message//\"/\\\"}\""

    if [[ -n "${details}" ]]; then
        json+=",\"details\":\"${details//\"/\\\"}\""
    fi

    json+="}"

    echo "${json}"
}

# Log formatter: Timestamped plain text for log files
_fmt_log() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    local prefix
    prefix=$(msg_type_get_prefix "${type}")
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")

    local output="[${timestamp}] [${prefix}] ${message}"

    if [[ -n "${details}" ]]; then
        output="${output} | ${details}"
    fi

    echo "${output}"
}

# Plain formatter: No colors, for non-TTY environments
_fmt_plain() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    local prefix
    prefix=$(msg_type_get_prefix "${type}")

    local output="${prefix}: ${message}"

    if [[ -n "${details}" ]]; then
        output="${output}"$'\n'"         ${details}"
    fi

    echo "${output}"
}

# ============================================================================
# Formatter API
# ============================================================================

# Set the active formatter
msg_formatter_set() {
    local formatter="$1"

    if [[ -z "${_MSG_FORMATTER_REGISTRY[${formatter}]:-}" ]]; then
        echo "ERROR: Unknown formatter: ${formatter}" >&2
        return 1
    fi

    _MSG_CURRENT_FORMATTER="${formatter}"
}

# Get the current formatter name
msg_formatter_get() {
    echo "${_MSG_CURRENT_FORMATTER}"
}

# Format a message using the current formatter
msg_format() {
    local type="$1"
    local message="$2"
    local details="${3:-}"

    local formatter_func="${_MSG_FORMATTER_REGISTRY[${_MSG_CURRENT_FORMATTER}]}"

    if [[ -z "${formatter_func}" ]]; then
        formatter_func="_fmt_plain"  # Fallback
    fi

    "${formatter_func}" "${type}" "${message}" "${details}"
}

# Format using a specific formatter (without changing default)
msg_format_as() {
    local formatter="$1"
    local type="$2"
    local message="$3"
    local details="${4:-}"

    local formatter_func="${_MSG_FORMATTER_REGISTRY[${formatter}]:-_fmt_plain}"
    "${formatter_func}" "${type}" "${message}" "${details}"
}

# ============================================================================
# Block Formatter (Multi-line messages)
# ============================================================================

# Format a block message (title + multiple detail lines)
# Apple-style: Clean box with consistent indentation
msg_format_block() {
    local type="$1"
    local title="$2"
    shift 2
    local lines=("$@")

    local color icon prefix
    color=$(msg_type_get_color "${type}")
    icon=$(msg_type_get_icon "${type}")
    prefix=$(msg_type_get_prefix "${type}")

    local output=""

    # Empty line before block
    output=$'\n'

    # Title line (Apple-style: 2-space indent)
    output+="  ${icon} ${color}${prefix}${MSG_STYLE_RESET}  ${title}"

    # Detail lines (aligned, 5-space indent for visual hierarchy)
    for line in "${lines[@]}"; do
        output+=$'\n'"     ${line}"
    done

    # Empty line after block
    output+=$'\n'

    echo "${output}"
}

# ============================================================================
# Auto-Detection
# ============================================================================

# Auto-select formatter based on environment
msg_formatter_auto() {
    # JSON if explicitly requested
    if [[ "${WOW_MSG_FORMAT:-}" == "json" ]]; then
        msg_formatter_set "json"
        return
    fi

    # Log if writing to file
    if [[ "${WOW_MSG_FORMAT:-}" == "log" ]]; then
        msg_formatter_set "log"
        return
    fi

    # Plain if not a TTY
    if [[ ! -t 2 ]]; then
        msg_formatter_set "plain"
        return
    fi

    # Default: terminal (colored)
    msg_formatter_set "terminal"
}

# ============================================================================
# Formatter Registration (OCP - extend without modifying)
# ============================================================================

# Register a custom formatter
msg_formatter_register() {
    local name="$1"
    local func="$2"

    _MSG_FORMATTER_REGISTRY["${name}"]="${func}"
}

# List available formatters
msg_formatter_list() {
    local name
    for name in "${!_MSG_FORMATTER_REGISTRY[@]}"; do
        echo "${name}"
    done | sort
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Message Formatter - Self Test"
    echo "=============================="
    echo ""

    echo "Available formatters:"
    msg_formatter_list
    echo ""

    echo "Format comparison for 'warning' type:"
    echo ""

    for fmt in terminal json log plain; do
        echo "--- ${fmt} ---"
        msg_format_as "${fmt}" "warning" "Something happened" "Check the logs"
        echo ""
    done

    echo "Block format example:"
    msg_format_block "security" "Security Warning" \
        "Line 1: First detail" \
        "Line 2: Second detail" \
        "Line 3: Run: ${MSG_COLOR_CYAN}some command${MSG_STYLE_RESET}"

    echo "Self-test complete"
fi
