#!/bin/bash
# handler-factory.sh - Factory pattern for handler creation
# Author: Chude <chude@emeke.org>
#
# Design Pattern: Factory Method
# Purpose: Control handler instantiation, enable DI, apply decorators

# Double-sourcing protection
[[ -n "${WOW_HANDLER_FACTORY_LOADED:-}" ]] && return 0
readonly WOW_HANDLER_FACTORY_LOADED=1

# ============================================================================
# State Management
# ============================================================================

# Handler registry: tool_type => handler_path
declare -gA _FACTORY_HANDLER_REGISTRY
# Handler cache: tool_type => cached_handler_instance
declare -gA _FACTORY_HANDLER_CACHE
# Initialization flag
_FACTORY_INITIALIZED=false

# ============================================================================
# Initialization
# ============================================================================

factory_init() {
    if [[ "${_FACTORY_INITIALIZED}" == "true" ]]; then
        return 0  # Idempotent
    fi

    # Initialize arrays if needed
    if ! declare -p _FACTORY_HANDLER_REGISTRY &>/dev/null; then
        declare -gA _FACTORY_HANDLER_REGISTRY
    fi

    if ! declare -p _FACTORY_HANDLER_CACHE &>/dev/null; then
        declare -gA _FACTORY_HANDLER_CACHE
    fi

    _FACTORY_INITIALIZED=true
    return 0
}

# ============================================================================
# Registration
# ============================================================================

factory_register_handler() {
    local tool_type="$1"
    local handler_path="$2"

    # Validation
    if [[ -z "$tool_type" ]]; then
        return 1
    fi

    if [[ -z "$handler_path" ]]; then
        return 1
    fi

    # Register
    _FACTORY_HANDLER_REGISTRY["$tool_type"]="$handler_path"

    return 0
}

# ============================================================================
# Handler Creation
# ============================================================================

factory_create_handler() {
    local tool_type="$1"
    shift
    local params=("$@")

    # Check if registered
    if [[ -z "${_FACTORY_HANDLER_REGISTRY[$tool_type]:-}" ]]; then
        return 1
    fi

    # Check cache (singleton pattern)
    if [[ -n "${_FACTORY_HANDLER_CACHE[$tool_type]:-}" ]]; then
        echo "${_FACTORY_HANDLER_CACHE[$tool_type]}"
        return 0
    fi

    local handler_path="${_FACTORY_HANDLER_REGISTRY[$tool_type]}"

    # Source handler if file exists
    if [[ -f "$handler_path" ]]; then
        source "$handler_path" 2>/dev/null || return 1
    fi

    # Create handler instance (simple string for now)
    local handler_instance="${tool_type}Handler"

    # Cache it
    _FACTORY_HANDLER_CACHE["$tool_type"]="$handler_instance"

    echo "$handler_instance"
    return 0
}

# ============================================================================
# Query Functions
# ============================================================================

factory_supports_handler() {
    local tool_type="$1"

    if [[ -n "${_FACTORY_HANDLER_REGISTRY[$tool_type]:-}" ]]; then
        return 0
    else
        return 1
    fi
}

factory_get_all_handlers() {
    for tool_type in "${!_FACTORY_HANDLER_REGISTRY[@]}"; do
        echo "$tool_type"
    done | sort
}

# ============================================================================
# Cache Management
# ============================================================================

factory_clear_cache() {
    for tool_type in "${!_FACTORY_HANDLER_CACHE[@]}"; do
        unset "_FACTORY_HANDLER_CACHE[$tool_type]"
    done
    return 0
}

# ============================================================================
# Integration with Handler Router
# ============================================================================

# Auto-register all existing handlers
factory_auto_register() {
    local handler_dir="${1:-.}"

    if [[ ! -d "$handler_dir" ]]; then
        return 1
    fi

    # Register each handler
    for handler_file in "$handler_dir"/*-handler.sh; do
        if [[ -f "$handler_file" ]]; then
            local basename=$(basename "$handler_file")
            local tool_name=$(echo "$basename" | sed 's/-handler.sh$//' | sed 's/^./\U&/')

            # Convert: bash -> Bash, write -> Write, etc.
            tool_name=$(echo "$tool_name" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')

            factory_register_handler "$tool_name" "$handler_file"
        fi
    done

    return 0
}

