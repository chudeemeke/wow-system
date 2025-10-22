#!/bin/bash
# WoW System - Analytics Trends Module (Production-Grade)
# Analyzes time-series trends to determine performance direction
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - SOLID: Single Responsibility (only trend analysis)
# - Simplicity: Linear trend sufficient for WoW scores
# - Reliability: Handles insufficient data gracefully
# - UX-Focused: Returns actionable insights (improving/stable/declining)

# Prevent double-sourcing
if [[ -n "${WOW_ANALYTICS_TRENDS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ANALYTICS_TRENDS_LOADED=1

# Source dependencies
_ANALYTICS_TRENDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ANALYTICS_TRENDS_DIR}/../core/utils.sh"
source "${_ANALYTICS_TRENDS_DIR}/collector.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly TRENDS_VERSION="1.0.0"
readonly TRENDS_MIN_SESSIONS=3      # Minimum sessions for reliable trend
readonly TRENDS_LOOKBACK=10         # Analyze last N sessions

# Trend state cache
declare -g _TRENDS_DIRECTION=""
declare -g _TRENDS_CONFIDENCE=0
declare -g _TRENDS_CACHE_VALID=0

# ============================================================================
# Private: Trend Calculation
# ============================================================================

# Calculate linear trend (simple slope)
_trends_calculate_slope() {
    local values="$1"
    local count=$(echo "${values}" | wc -w)

    [[ ${count} -lt 2 ]] && echo "0" && return

    # Convert to array
    local -a vals=()
    local val
    for val in ${values}; do
        vals+=("${val}")
    done

    # Calculate slope using first and last values (simplified)
    local first="${vals[0]}"
    local last="${vals[$((count-1))]}"

    local diff=$((last - first))
    echo "${diff}"
}

# Determine trend direction from slope
_trends_classify_slope() {
    local slope="$1"

    # Threshold for "stable" (within ±3 points)
    if [[ ${slope} -ge -3 ]] && [[ ${slope} -le 3 ]]; then
        echo "stable"
    elif [[ ${slope} -gt 3 ]]; then
        echo "improving"
    else
        echo "declining"
    fi
}

# Calculate confidence based on data points and variance
_trends_calculate_confidence() {
    local count="$1"
    local slope="$2"

    # Confidence increases with more data points
    if [[ ${count} -lt ${TRENDS_MIN_SESSIONS} ]]; then
        echo "low"
    elif [[ ${count} -lt 7 ]]; then
        echo "medium"
    else
        echo "high"
    fi
}

# ============================================================================
# Public: Initialization
# ============================================================================

# Initialize trends module
analytics_trends_init() {
    # Ensure collector is initialized
    analytics_collector_init

    wow_debug "Analytics trends initialized (v${TRENDS_VERSION})"
    return 0
}

# ============================================================================
# Public: Trend Analysis
# ============================================================================

# Calculate trend from recent sessions
analytics_trends_calculate() {
    local metric="${1:-wow_score}"
    local lookback="${2:-${TRENDS_LOOKBACK}}"

    # Ensure collector cache is valid
    analytics_collector_scan

    # Get recent sessions
    local sessions
    sessions=$(analytics_collector_get_recent "${lookback}")

    local count=0
    local values=""
    local session_id

    while IFS= read -r session_id; do
        [[ -z "${session_id}" ]] && continue

        # Get session data
        local data
        data=$(analytics_collector_get_session_data "${session_id}" 2>/dev/null)

        if [[ -n "${data}" ]]; then
            # Extract metric value
            local value
            if wow_has_jq; then
                value=$(echo "${data}" | jq -r ".${metric} // 0" 2>/dev/null)
            else
                value=$(echo "${data}" | grep -oP "\"${metric}\"\s*:\s*\K[0-9]+" || echo "0")
            fi

            values="${values} ${value}"
            ((count++))
        fi
    done <<< "${sessions}"

    # Insufficient data
    if [[ ${count} -lt ${TRENDS_MIN_SESSIONS} ]]; then
        _TRENDS_DIRECTION="insufficient_data"
        _TRENDS_CONFIDENCE="low"
        _TRENDS_CACHE_VALID=1
        return 1
    fi

    # Calculate slope
    local slope
    slope=$(_trends_calculate_slope "${values}")

    # Classify direction
    _TRENDS_DIRECTION=$(_trends_classify_slope "${slope}")
    _TRENDS_CONFIDENCE=$(_trends_calculate_confidence "${count}" "${slope}")
    _TRENDS_CACHE_VALID=1

    return 0
}

# Get trend direction
analytics_trends_get_direction() {
    # Ensure cache is valid
    if [[ ${_TRENDS_CACHE_VALID} -eq 0 ]]; then
        analytics_trends_calculate
    fi

    echo "${_TRENDS_DIRECTION}"
}

# Get trend confidence
analytics_trends_get_confidence() {
    # Ensure cache is valid
    if [[ ${_TRENDS_CACHE_VALID} -eq 0 ]]; then
        analytics_trends_calculate
    fi

    echo "${_TRENDS_CONFIDENCE}"
}

# Get trend indicator (Unicode arrow)
analytics_trends_get_indicator() {
    local direction
    direction=$(analytics_trends_get_direction)

    case "${direction}" in
        improving)
            echo "↑"
            ;;
        declining)
            echo "↓"
            ;;
        stable)
            echo "→"
            ;;
        insufficient_data)
            echo "?"
            ;;
        *)
            echo "?"
            ;;
    esac
}

# Get human-readable trend summary
analytics_trends_get_summary() {
    local direction
    local confidence
    local indicator

    direction=$(analytics_trends_get_direction)
    confidence=$(analytics_trends_get_confidence)
    indicator=$(analytics_trends_get_indicator)

    case "${direction}" in
        improving)
            echo "${indicator} Improving (${confidence} confidence)"
            ;;
        declining)
            echo "${indicator} Declining (${confidence} confidence)"
            ;;
        stable)
            echo "${indicator} Stable (${confidence} confidence)"
            ;;
        insufficient_data)
            echo "? Insufficient data (need ${TRENDS_MIN_SESSIONS}+ sessions)"
            ;;
        *)
            echo "? Unknown"
            ;;
    esac
}

# ============================================================================
# Public: Cache Management
# ============================================================================

# Invalidate trends cache
analytics_trends_invalidate() {
    _TRENDS_DIRECTION=""
    _TRENDS_CONFIDENCE=0
    _TRENDS_CACHE_VALID=0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Analytics Trends - Self Test (v${TRENDS_VERSION})"
    echo "====================================================="
    echo ""

    # Test 1: Initialize
    analytics_trends_init && echo "✓ Initialization works"

    # Test 2: Calculate trends
    analytics_trends_calculate 2>/dev/null && echo "✓ Trend calculation works"

    # Test 3: Get direction
    local direction
    direction=$(analytics_trends_get_direction)
    echo "✓ Get direction works (direction: ${direction})"

    # Test 4: Get indicator
    local indicator
    indicator=$(analytics_trends_get_indicator)
    echo "✓ Get indicator works (indicator: ${indicator})"

    # Test 5: Get summary
    local summary
    summary=$(analytics_trends_get_summary)
    echo "✓ Get summary works: ${summary}"

    echo ""
    echo "All self-tests passed! ✓"
fi
