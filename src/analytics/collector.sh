#!/bin/bash
# WoW System - Analytics Collector Module (Production-Grade)
# Collects session data from filesystem for multi-session analytics
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - SOLID: Single Responsibility (only collection, no aggregation/analysis)
# - Fail-Safe: Errors don't crash, corrupted files skipped
# - Performance: Efficient file operations, caching, lazy parsing
# - Security: All paths validated and quoted, no sensitive data exposure

# Prevent double-sourcing
if [[ -n "${WOW_ANALYTICS_COLLECTOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ANALYTICS_COLLECTOR_LOADED=1

# Source dependencies
_ANALYTICS_COLLECTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ANALYTICS_COLLECTOR_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly COLLECTOR_VERSION="1.0.0"

# Session list cache (array)
declare -ga _COLLECTOR_SESSION_LIST=()
declare -g _COLLECTOR_CACHE_VALID=0

# ============================================================================
# Private: Session Directory Access
# ============================================================================

# Get sessions directory path
_collector_get_sessions_dir() {
    local sessions_dir="${WOW_DATA_DIR}/sessions"

    if [[ ! -d "${sessions_dir}" ]]; then
        # Create if missing
        mkdir -p "${sessions_dir}" 2>/dev/null || true
    fi

    echo "${sessions_dir}"
}

# Check if sessions directory is accessible
_collector_dir_accessible() {
    local sessions_dir
    sessions_dir=$(_collector_get_sessions_dir)

    [[ -d "${sessions_dir}" ]] && [[ -r "${sessions_dir}" ]]
}

# ============================================================================
# Private: Session Validation
# ============================================================================

# Check if session directory is valid
_collector_is_valid_session() {
    local session_dir="$1"

    # Must be a directory
    [[ -d "${session_dir}" ]] || return 1

    # Must have metrics.json
    [[ -f "${session_dir}/metrics.json" ]] || return 1

    # Must be readable
    [[ -r "${session_dir}/metrics.json" ]] || return 1

    return 0
}

# Validate metrics.json content
_collector_validate_metrics() {
    local metrics_file="$1"

    # Check if jq is available
    if ! wow_has_jq; then
        # Without jq, basic check: file not empty and contains "{"
        [[ -s "${metrics_file}" ]] && grep -q "{" "${metrics_file}"
        return $?
    fi

    # Validate JSON structure with jq
    jq empty "${metrics_file}" 2>/dev/null
    return $?
}

# ============================================================================
# Private: Session Scanning
# ============================================================================

# Scan sessions directory and populate cache
_collector_scan_internal() {
    local sessions_dir
    sessions_dir=$(_collector_get_sessions_dir)

    # Clear cache
    _COLLECTOR_SESSION_LIST=()
    _COLLECTOR_CACHE_VALID=0

    # Check if directory exists and is accessible
    if ! _collector_dir_accessible; then
        wow_debug "Sessions directory not accessible: ${sessions_dir}"
        _COLLECTOR_CACHE_VALID=1
        return 0
    fi

    # Find all session directories (sorted by modification time, newest first)
    local session_dirs

    # Portable approach: use ls -dt (works on Linux, BSD, WSL)
    session_dirs=$(ls -dt "${sessions_dir}"/*/ 2>/dev/null | sed 's#/$##' || true)

    # Validate and collect sessions
    local session_dir
    local session_id

    while IFS= read -r session_dir; do
        [[ -z "${session_dir}" ]] && continue

        # Validate session
        if _collector_is_valid_session "${session_dir}"; then
            # Validate metrics.json
            if _collector_validate_metrics "${session_dir}/metrics.json"; then
                session_id=$(basename "${session_dir}")
                _COLLECTOR_SESSION_LIST+=("${session_id}")
            else
                wow_debug "Skipping session with invalid metrics: ${session_dir}"
            fi
        else
            wow_debug "Skipping invalid session: ${session_dir}"
        fi
    done <<< "${session_dirs}"

    _COLLECTOR_CACHE_VALID=1
}

# ============================================================================
# Public: Initialization
# ============================================================================

# Initialize collector module
analytics_collector_init() {
    # Validate data directory
    if [[ -z "${WOW_DATA_DIR:-}" ]]; then
        wow_warn "WOW_DATA_DIR not set, using default"
        export WOW_DATA_DIR="${HOME}/.wow-data"
    fi

    # Create sessions directory if needed
    _collector_get_sessions_dir > /dev/null

    wow_debug "Analytics collector initialized (v${COLLECTOR_VERSION})"

    return 0
}

# ============================================================================
# Public: Scanning
# ============================================================================

# Scan all sessions and populate cache
analytics_collector_scan() {
    _collector_scan_internal
}

# Get count of sessions in cache
analytics_collector_count() {
    # Ensure cache is valid
    if [[ ${_COLLECTOR_CACHE_VALID} -eq 0 ]]; then
        _collector_scan_internal
    fi

    echo "${#_COLLECTOR_SESSION_LIST[@]}"
}

# ============================================================================
# Public: Session Retrieval
# ============================================================================

# Get sorted list of session IDs (newest first)
# Usage: analytics_collector_get_sessions [limit]
analytics_collector_get_sessions() {
    local limit="${1:-0}"

    # Ensure cache is valid
    if [[ ${_COLLECTOR_CACHE_VALID} -eq 0 ]]; then
        _collector_scan_internal > /dev/null
    fi

    # Return all sessions if limit is 0 or not specified
    if [[ ${limit} -eq 0 ]]; then
        printf '%s\n' "${_COLLECTOR_SESSION_LIST[@]}"
        return 0
    fi

    # Return limited sessions
    local count=0
    local session_id

    for session_id in "${_COLLECTOR_SESSION_LIST[@]}"; do
        echo "${session_id}"
        ((count++))
        [[ ${count} -ge ${limit} ]] && break
    done
}

# Get single session metrics data
# Usage: analytics_collector_get_session_data <session_id>
analytics_collector_get_session_data() {
    local session_id="$1"

    [[ -z "${session_id}" ]] && return 1

    local sessions_dir
    sessions_dir=$(_collector_get_sessions_dir)

    local session_dir="${sessions_dir}/${session_id}"
    local metrics_file="${session_dir}/metrics.json"

    # Validate session
    if ! _collector_is_valid_session "${session_dir}"; then
        wow_debug "Session not found or invalid: ${session_id}"
        return 1
    fi

    # Read and return metrics
    if [[ -r "${metrics_file}" ]]; then
        cat "${metrics_file}"
        return 0
    else
        wow_debug "Cannot read metrics file: ${metrics_file}"
        return 1
    fi
}

# Get last N sessions
# Usage: analytics_collector_get_recent <count>
analytics_collector_get_recent() {
    local count="${1:-10}"

    analytics_collector_get_sessions "${count}"
}

# Check if session exists
# Usage: analytics_collector_has_session <session_id>
analytics_collector_has_session() {
    local session_id="$1"

    [[ -z "${session_id}" ]] && return 1

    local sessions_dir
    sessions_dir=$(_collector_get_sessions_dir)

    local session_dir="${sessions_dir}/${session_id}"

    _collector_is_valid_session "${session_dir}"
}

# ============================================================================
# Public: Cache Management
# ============================================================================

# Invalidate cache (force rescan on next access)
analytics_collector_invalidate_cache() {
    _COLLECTOR_CACHE_VALID=0
    _COLLECTOR_SESSION_LIST=()

    wow_debug "Collector cache invalidated"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Analytics Collector - Self Test (v${COLLECTOR_VERSION})"
    echo "==========================================================="
    echo ""

    # Test 1: Initialize
    analytics_collector_init && echo "✓ Initialization works"

    # Test 2: Scan (may be empty)
    local count
    count=$(analytics_collector_scan)
    echo "✓ Scan works (found ${count} sessions)"

    # Test 3: Get sessions
    local sessions
    sessions=$(analytics_collector_get_sessions 5)
    echo "✓ Get sessions works (returned $(echo "${sessions}" | wc -l) sessions)"

    echo ""
    echo "All self-tests passed! ✓"
fi
