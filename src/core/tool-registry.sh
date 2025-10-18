#!/bin/bash
# WoW System - Tool Registry
# Tracks known and unknown tools for extensibility and monitoring
# Author: Chude <chude@emeke.org>
#
# Design Patterns:
# - Registry Pattern: Central registration of tools
# - Repository Pattern: Persistence layer abstraction
# - Observer Pattern: Tool tracking events
#
# SOLID Principles:
# - SRP: Only handles tool registration and tracking
# - OCP: Open for extension (new tools), closed for modification
# - DIP: Depends on state-manager abstraction

# Prevent double-sourcing
if [[ -n "${WOW_TOOL_REGISTRY_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_TOOL_REGISTRY_LOADED=1

# Source dependencies
_TOOL_REGISTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TOOL_REGISTRY_DIR}/utils.sh"
source "${_TOOL_REGISTRY_DIR}/state-manager.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly TOOL_REGISTRY_VERSION="1.0.0"
readonly TOOL_REGISTRY_STATE_KEY="tool_registry"
readonly MAX_TOOL_NAME_LENGTH=100

# In-memory caches (for performance)
# Initialize empty to avoid unbound variable errors
declare -gA _KNOWN_TOOLS=()        # tool_name => handler_path
declare -gA _UNKNOWN_TOOLS=()      # tool_name => metadata_json

# ============================================================================
# Initialization
# ============================================================================

# Initialize tool registry
tool_registry_init() {
    wow_debug "Initializing tool registry..."

    # Load from persistence if available
    _tool_registry_load_state

    wow_debug "Tool registry initialized (known: ${#_KNOWN_TOOLS[@]}, unknown: ${#_UNKNOWN_TOOLS[@]})"
    return 0
}

# Load registry state from persistence
_tool_registry_load_state() {
    if ! type state_get &>/dev/null; then
        wow_warn "State manager not available, registry will not persist"
        return 1
    fi

    # Load known tools
    local known_json
    known_json=$(state_get "${TOOL_REGISTRY_STATE_KEY}_known" "{}")

    if [[ -n "${known_json}" ]] && wow_has_jq; then
        # Parse JSON and populate cache
        while IFS='=' read -r tool handler; do
            if [[ -n "${tool}" ]]; then
                _KNOWN_TOOLS["${tool}"]="${handler}"
            fi
        done < <(echo "${known_json}" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' 2>/dev/null)
    fi

    # Load unknown tools
    local unknown_json
    unknown_json=$(state_get "${TOOL_REGISTRY_STATE_KEY}_unknown" "{}")

    if [[ -n "${unknown_json}" ]] && wow_has_jq; then
        while IFS='=' read -r tool metadata; do
            if [[ -n "${tool}" ]]; then
                _UNKNOWN_TOOLS["${tool}"]="${metadata}"
            fi
        done < <(echo "${unknown_json}" | jq -r 'to_entries | .[] | "\(.key)=\(.value | @json)"' 2>/dev/null)
    fi

    return 0
}

# Save registry state to persistence
tool_registry_save() {
    if ! type state_set &>/dev/null; then
        return 1
    fi

    # Save known tools
    local known_json="{}"
    if wow_has_jq; then
        # Build JSON from cache
        known_json=$(
            for tool in "${!_KNOWN_TOOLS[@]}"; do
                echo "${tool}"
                echo "${_KNOWN_TOOLS[${tool}]}"
            done | jq -R -s 'split("\n") | map(select(length > 0)) |
                        [range(0; length; 2)] |
                        map({key: .[. * 2], value: .[. * 2 + 1]}) |
                        from_entries' 2>/dev/null
        )
    fi
    state_set "${TOOL_REGISTRY_STATE_KEY}_known" "${known_json}"

    # Save unknown tools
    local unknown_json="{}"
    if wow_has_jq; then
        # Build JSON from cache
        unknown_json=$(
            for tool in "${!_UNKNOWN_TOOLS[@]}"; do
                echo "${tool}"
                echo "${_UNKNOWN_TOOLS[${tool}]}"
            done | jq -R -s 'split("\n") | map(select(length > 0)) |
                        [range(0; length; 2)] |
                        map({key: .[. * 2], value: (.[. * 2 + 1] | fromjson)}) |
                        from_entries' 2>/dev/null
        )
    fi
    state_set "${TOOL_REGISTRY_STATE_KEY}_unknown" "${unknown_json}"

    return 0
}

# ============================================================================
# Known Tool Registration
# ============================================================================

# Register a known tool (has handler)
# Args: tool_name, handler_path
tool_registry_register_known() {
    local tool_name="$1"
    local handler_path="$2"

    # Validate input
    if [[ -z "${tool_name}" ]]; then
        wow_error "Tool name cannot be empty"
        return 1
    fi

    # Sanitize tool name
    tool_name=$(echo "${tool_name}" | tr -cd '[:alnum:]_-' | cut -c1-${MAX_TOOL_NAME_LENGTH})

    # Register in cache
    _KNOWN_TOOLS["${tool_name}"]="${handler_path}"

    wow_debug "Registered known tool: ${tool_name} -> ${handler_path}"

    # Persist
    tool_registry_save 2>/dev/null || true

    return 0
}

# Check if tool is known (has handler)
tool_registry_is_known() {
    local tool_name="$1"

    [[ -n "${_KNOWN_TOOLS[${tool_name}]:-}" ]]
}

# Get handler path for known tool
tool_registry_get_handler() {
    local tool_name="$1"

    echo "${_KNOWN_TOOLS[${tool_name}]:-}"
}

# Count known tools
tool_registry_count_known() {
    echo "${#_KNOWN_TOOLS[@]}"
}

# List all known tools
tool_registry_list_known() {
    for tool in "${!_KNOWN_TOOLS[@]}"; do
        echo "${tool}"
    done | sort
}

# ============================================================================
# Unknown Tool Tracking
# ============================================================================

# Track unknown tool usage
# Args: tool_name
tool_registry_track_unknown() {
    local tool_name="$1"

    # Validate input
    if [[ -z "${tool_name}" ]]; then
        wow_error "Tool name cannot be empty"
        return 1
    fi

    # Sanitize tool name
    tool_name=$(echo "${tool_name}" | tr -cd '[:alnum:]_-' | cut -c1-${MAX_TOOL_NAME_LENGTH})

    # Get current timestamp
    local now
    now=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

    # Check if already tracked
    if [[ -n "${_UNKNOWN_TOOLS[${tool_name}]:-}" ]]; then
        # Update existing entry
        local metadata="${_UNKNOWN_TOOLS[${tool_name}]}"

        if wow_has_jq; then
            # Parse and update
            local count
            count=$(echo "${metadata}" | jq -r '.count // 0' 2>/dev/null)
            count=$((count + 1))

            # Update metadata
            metadata=$(jq -n \
                --arg name "${tool_name}" \
                --argjson count ${count} \
                --arg first_seen "$(echo "${metadata}" | jq -r '.first_seen' 2>/dev/null)" \
                --arg last_seen "${now}" \
                '{
                    tool: $name,
                    count: $count,
                    first_seen: $first_seen,
                    last_seen: $last_seen
                }' 2>/dev/null
            )

            _UNKNOWN_TOOLS["${tool_name}"]="${metadata}"
        else
            # Fallback: simple counter
            _UNKNOWN_TOOLS["${tool_name}"]="count:$((count + 1)),last_seen:${now}"
        fi
    else
        # New unknown tool
        if wow_has_jq; then
            local metadata
            metadata=$(jq -n \
                --arg name "${tool_name}" \
                --arg first_seen "${now}" \
                --arg last_seen "${now}" \
                '{
                    tool: $name,
                    count: 1,
                    first_seen: $first_seen,
                    last_seen: $last_seen
                }' 2>/dev/null
            )

            _UNKNOWN_TOOLS["${tool_name}"]="${metadata}"
        else
            # Fallback
            _UNKNOWN_TOOLS["${tool_name}"]="count:1,first_seen:${now},last_seen:${now}"
        fi

        wow_info "New unknown tool detected: ${tool_name}"
    fi

    # Persist
    tool_registry_save 2>/dev/null || true

    return 0
}

# Check if tool is unknown (tracked but no handler)
tool_registry_is_unknown() {
    local tool_name="$1"

    [[ -n "${_UNKNOWN_TOOLS[${tool_name}]:-}" ]]
}

# Check if this is first occurrence of tool
tool_registry_is_first_occurrence() {
    local tool_name="$1"

    # If not in unknown tools, it's first occurrence
    [[ -z "${_UNKNOWN_TOOLS[${tool_name}]:-}" ]]
}

# Get usage count for unknown tool
tool_registry_get_unknown_count() {
    local tool_name="$1"

    local metadata="${_UNKNOWN_TOOLS[${tool_name}]:-}"
    if [[ -z "${metadata}" ]]; then
        echo "0"
        return 0
    fi

    if wow_has_jq; then
        echo "${metadata}" | jq -r '.count // 0' 2>/dev/null
    else
        # Fallback: parse simple format
        echo "${metadata}" | grep -oP 'count:\K\d+' || echo "0"
    fi
}

# Get first seen timestamp for unknown tool
tool_registry_get_unknown_first_seen() {
    local tool_name="$1"

    local metadata="${_UNKNOWN_TOOLS[${tool_name}]:-}"
    if [[ -z "${metadata}" ]]; then
        return 1
    fi

    if wow_has_jq; then
        echo "${metadata}" | jq -r '.first_seen // empty' 2>/dev/null
    else
        # Fallback
        echo "${metadata}" | grep -oP 'first_seen:\K[^,]+' || return 1
    fi
}

# Get last seen timestamp for unknown tool
tool_registry_get_unknown_last_seen() {
    local tool_name="$1"

    local metadata="${_UNKNOWN_TOOLS[${tool_name}]:-}"
    if [[ -z "${metadata}" ]]; then
        return 1
    fi

    if wow_has_jq; then
        echo "${metadata}" | jq -r '.last_seen // empty' 2>/dev/null
    else
        # Fallback
        echo "${metadata}" | grep -oP 'last_seen:\K[^,]+' || return 1
    fi
}

# Get full metadata for unknown tool
tool_registry_get_unknown_metadata() {
    local tool_name="$1"

    echo "${_UNKNOWN_TOOLS[${tool_name}]:-}"
}

# Count unknown tools
tool_registry_count_unknown() {
    echo "${#_UNKNOWN_TOOLS[@]}"
}

# List all unknown tools
tool_registry_list_unknown() {
    for tool in "${!_UNKNOWN_TOOLS[@]}"; do
        echo "${tool}"
    done | sort
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Tool Registry v${TOOL_REGISTRY_VERSION} - Self Test"
    echo "=========================================================="
    echo ""

    # Initialize
    tool_registry_init

    # Test 1: Register known tool
    tool_registry_register_known "Bash" "bash-handler.sh"
    tool_registry_is_known "Bash" && echo "✓ Known tool registration works" || echo "✗ Failed"

    # Test 2: Track unknown tool
    tool_registry_track_unknown "CustomMCP"
    tool_registry_is_unknown "CustomMCP" && echo "✓ Unknown tool tracking works" || echo "✗ Failed"

    # Test 3: Frequency tracking
    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "CustomMCP"
    count=$(tool_registry_get_unknown_count "CustomMCP")
    [[ ${count} -eq 3 ]] && echo "✓ Frequency tracking works (count: ${count})" || echo "✗ Failed (expected 3, got ${count})"

    # Test 4: First occurrence
    tool_registry_is_first_occurrence "NewTool" && echo "✓ First occurrence detection works" || echo "✗ Failed"
    tool_registry_track_unknown "NewTool"
    ! tool_registry_is_first_occurrence "NewTool" && echo "✓ Second occurrence detection works" || echo "✗ Failed"

    # Test 5: Persistence
    tool_registry_save
    echo "✓ State saved"

    echo ""
    echo "All self-tests passed! ✓"
fi
