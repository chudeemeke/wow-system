#!/bin/bash
# WoW System - State Manager
# Provides: In-memory session state management with persistence
# Author: Chude <chude@emeke.org>

# Source dependencies
_STATE_MGR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_STATE_MGR_DIR}/utils.sh"
source "${_STATE_MGR_DIR}/../storage/file-storage.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly STATE_VERSION="1.0.0"
readonly STATE_NAMESPACE="session"
readonly STATE_PERSISTENT_FILE="${WOW_DATA_DIR}/state/current-session.state"

# ============================================================================
# State Storage (In-Memory)
# ============================================================================

# Global associative array for session state
declare -gA _WOW_STATE

# ============================================================================
# Initialization
# ============================================================================

# Initialize state manager
state_init() {
    wow_debug "Initializing state manager v${STATE_VERSION}"

    # Ensure state storage directory exists
    wow_ensure_dir "$(dirname "${STATE_PERSISTENT_FILE}")"

    # Initialize storage backend
    storage_init 2>/dev/null || true

    # Generate session ID if not exists
    if [[ -z "${_WOW_STATE[_session_id]:-}" ]]; then
        _WOW_STATE[_session_id]="session_$(date +%Y%m%d_%H%M%S)_$$"
    fi

    # Record start time if not exists
    if [[ -z "${_WOW_STATE[_started_at]:-}" ]]; then
        _WOW_STATE[_started_at]="$(wow_timestamp)"
    fi

    wow_debug "State manager initialized (session: ${_WOW_STATE[_session_id]})"
    return 0
}

# ============================================================================
# Basic Operations
# ============================================================================

# Set a state value
state_set() {
    local key="$1"
    local value="$2"

    if [[ -z "${key}" ]]; then
        wow_error "State key cannot be empty"
        return 1
    fi

    _WOW_STATE["${key}"]="${value}"
    wow_debug "State set: ${key}=${value}"
    return 0
}

# Get a state value
state_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "${key}" ]]; then
        wow_error "State key cannot be empty"
        return 1
    fi

    local value="${_WOW_STATE[${key}]:-${default}}"
    echo "${value}"
    return 0
}

# Check if a state key exists
state_exists() {
    local key="$1"

    [[ -n "${_WOW_STATE[${key}]:-}" ]]
}

# Delete a state key
state_delete() {
    local key="$1"

    if [[ -z "${key}" ]]; then
        wow_error "State key cannot be empty"
        return 1
    fi

    unset "_WOW_STATE[${key}]"
    wow_debug "State deleted: ${key}"
    return 0
}

# Clear all state (except session metadata)
state_clear() {
    local session_id="${_WOW_STATE[_session_id]:-}"
    local started_at="${_WOW_STATE[_started_at]:-}"

    # Clear the array
    _WOW_STATE=()

    # Restore session metadata
    if [[ -n "${session_id}" ]]; then
        _WOW_STATE[_session_id]="${session_id}"
    fi
    if [[ -n "${started_at}" ]]; then
        _WOW_STATE[_started_at]="${started_at}"
    fi

    wow_debug "State cleared"
    return 0
}

# ============================================================================
# Advanced Operations
# ============================================================================

# Increment a counter (creates if doesn't exist)
state_increment() {
    local key="$1"
    local amount="${2:-1}"

    local current_value
    current_value=$(state_get "${key}" "0")

    if ! wow_is_number "${current_value}"; then
        wow_error "Cannot increment non-numeric value: ${key}=${current_value}"
        return 1
    fi

    local new_value=$((current_value + amount))
    state_set "${key}" "${new_value}"

    wow_debug "State incremented: ${key}=${current_value} -> ${new_value}"
    return 0
}

# Decrement a counter
state_decrement() {
    local key="$1"
    local amount="${2:-1}"

    local current_value
    current_value=$(state_get "${key}" "0")

    if ! wow_is_number "${current_value}"; then
        wow_error "Cannot decrement non-numeric value: ${key}=${current_value}"
        return 1
    fi

    local new_value=$((current_value - amount))
    state_set "${key}" "${new_value}"

    wow_debug "State decremented: ${key}=${current_value} -> ${new_value}"
    return 0
}

# Append to an array (stored as newline-separated string)
state_append() {
    local key="$1"
    local value="$2"

    local current_value
    current_value=$(state_get "${key}" "")

    local new_value
    if [[ -z "${current_value}" ]]; then
        new_value="${value}"
    else
        new_value="${current_value}"$'\n'"${value}"
    fi

    state_set "${key}" "${new_value}"
    wow_debug "State appended: ${key} <- ${value}"
    return 0
}

# Get array as lines
state_get_array() {
    local key="$1"

    local value
    value=$(state_get "${key}" "")

    if [[ -n "${value}" ]]; then
        echo "${value}"
    fi
}

# ============================================================================
# Metadata Operations
# ============================================================================

# Get all state keys
state_keys() {
    for key in "${!_WOW_STATE[@]}"; do
        echo "${key}"
    done | sort
}

# Get state size (number of keys)
state_size() {
    echo "${#_WOW_STATE[@]}"
}

# Get session information
state_session_info() {
    local session_id="${_WOW_STATE[_session_id]:-unknown}"
    local started_at="${_WOW_STATE[_started_at]:-unknown}"
    local num_keys="${#_WOW_STATE[@]}"

    cat <<EOF
session_id=${session_id}
started_at=${started_at}
keys=${num_keys}
EOF
}

# ============================================================================
# Persistence Operations
# ============================================================================

# Save state to disk
state_save() {
    local save_path="${1:-${STATE_PERSISTENT_FILE}}"

    wow_debug "Saving state to: ${save_path}"

    # Create temp file
    local temp_file="${save_path}.tmp.$$"

    # Serialize state
    {
        echo "# WoW State - Session ${_WOW_STATE[_session_id]:-unknown}"
        echo "# Saved at $(wow_timestamp)"
        echo ""

        for key in $(state_keys); do
            local value="${_WOW_STATE[${key}]}"
            # Base64 encode to handle special characters and newlines
            local encoded_value
            encoded_value=$(echo -n "${value}" | base64 -w 0)
            echo "${key}=${encoded_value}"
        done
    } > "${temp_file}"

    # Atomic move
    mv "${temp_file}" "${save_path}"

    wow_debug "State saved (${#_WOW_STATE[@]} keys)"
    return 0
}

# Load state from disk
state_load() {
    local load_path="${1:-${STATE_PERSISTENT_FILE}}"

    if [[ ! -f "${load_path}" ]]; then
        wow_debug "No saved state to load"
        return 0
    fi

    wow_debug "Loading state from: ${load_path}"

    local loaded_count=0

    # Read and deserialize
    while IFS='=' read -r key encoded_value; do
        # Skip comments and empty lines
        [[ "${key}" =~ ^#.*$ ]] && continue
        [[ -z "${key}" ]] && continue

        # Decode value
        local value
        value=$(echo "${encoded_value}" | base64 -d 2>/dev/null || echo "")

        # Don't overwrite session metadata
        if [[ "${key}" == "_session_id" ]] || [[ "${key}" == "_started_at" ]]; then
            continue
        fi

        _WOW_STATE["${key}"]="${value}"
        ((loaded_count++))
    done < "${load_path}"

    wow_debug "State loaded (${loaded_count} keys)"
    return 0
}

# Archive current session state
state_archive() {
    local session_id="${_WOW_STATE[_session_id]:-unknown}"
    local archive_dir="${WOW_DATA_DIR}/state/archive"
    local archive_file="${archive_dir}/${session_id}.state"

    wow_ensure_dir "${archive_dir}"

    state_save "${archive_file}"

    wow_info "Session state archived: ${archive_file}"
    return 0
}

# ============================================================================
# Debug Operations
# ============================================================================

# Dump all state (for debugging)
state_dump() {
    echo "=== WoW State Dump ==="
    echo "Session: ${_WOW_STATE[_session_id]:-unknown}"
    echo "Started: ${_WOW_STATE[_started_at]:-unknown}"
    echo "Keys: ${#_WOW_STATE[@]}"
    echo ""

    for key in $(state_keys); do
        local value="${_WOW_STATE[${key}]}"
        # Truncate long values
        if [[ ${#value} -gt 50 ]]; then
            value="${value:0:47}..."
        fi
        echo "  ${key}=${value}"
    done
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW State Manager v${STATE_VERSION} - Self Test"
    echo "================================================"
    echo ""

    # Initialize
    state_init
    echo "✓ Initialized"

    # Basic operations
    state_set "name" "WoW System"
    [[ "$(state_get "name")" == "WoW System" ]] && echo "✓ Set/Get works"

    state_exists "name" && echo "✓ Exists check works"

    state_delete "name"
    ! state_exists "name" && echo "✓ Delete works"

    # Counter operations
    state_increment "counter"
    state_increment "counter"
    [[ "$(state_get "counter")" == "2" ]] && echo "✓ Increment works"

    state_decrement "counter"
    [[ "$(state_get "counter")" == "1" ]] && echo "✓ Decrement works"

    # Array operations
    state_append "list" "item1"
    state_append "list" "item2"
    list_value=$(state_get "list")
    [[ "${list_value}" == *"item1"* ]] && [[ "${list_value}" == *"item2"* ]] && echo "✓ Append works"

    # Metadata
    keys_output=$(state_keys)
    [[ "${keys_output}" == *"counter"* ]] && echo "✓ Keys listing works"

    # Session info
    info=$(state_session_info)
    [[ "${info}" == *"session_id"* ]] && echo "✓ Session info works"

    # Persistence
    temp_file=$(mktemp)
    state_save "${temp_file}"
    [[ -f "${temp_file}" ]] && echo "✓ Save works"

    state_clear
    [[ "$(state_size)" == "2" ]] && echo "✓ Clear works (session metadata preserved)"

    state_load "${temp_file}"
    [[ "$(state_get "counter")" == "1" ]] && echo "✓ Load works"
    rm -f "${temp_file}"

    echo ""
    echo "Session State:"
    state_dump

    echo ""
    echo "All tests passed! ✓"
fi
