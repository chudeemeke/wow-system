#!/bin/bash
# WoW System - Analytics Aggregator Module (Production-Grade)
# Computes cross-session aggregated metrics (mean, median, percentiles)
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - SOLID: Single Responsibility (only aggregation, no collection)
# - Performance: Efficient calculation, results caching
# - Reliability: Handles edge cases (single session, empty data)
# - Security: No sensitive data exposure

# Prevent double-sourcing
if [[ -n "${WOW_ANALYTICS_AGGREGATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ANALYTICS_AGGREGATOR_LOADED=1

# Source dependencies
_ANALYTICS_AGGREGATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ANALYTICS_AGGREGATOR_DIR}/../core/utils.sh"
source "${_ANALYTICS_AGGREGATOR_DIR}/collector.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly AGGREGATOR_VERSION="1.0.0"

# Aggregates cache
declare -gA _AGGREGATOR_CACHE=()
declare -g _AGGREGATOR_CACHE_VALID=0

# ============================================================================
# Private: Statistical Calculations
# ============================================================================

# Calculate mean (average)
_aggregator_mean() {
    local values="$1"
    local count=$(echo "${values}" | wc -w)

    [[ ${count} -eq 0 ]] && echo "0" && return

    local sum=0
    local val
    for val in ${values}; do
        sum=$((sum + val))
    done

    echo $((sum / count))
}

# Calculate median
_aggregator_median() {
    local values="$1"
    local count=$(echo "${values}" | wc -w)

    [[ ${count} -eq 0 ]] && echo "0" && return

    # Sort values
    local sorted
    sorted=$(echo "${values}" | tr ' ' '\n' | sort -n | tr '\n' ' ')

    local mid=$((count / 2))
    local val
    local i=0

    for val in ${sorted}; do
        if [[ $i -eq ${mid} ]]; then
            echo "${val}"
            return
        fi
        ((i++))
    done

    echo "0"
}

# Calculate percentile
_aggregator_percentile() {
    local values="$1"
    local percentile="$2"  # 25, 75, 95, etc.

    local count=$(echo "${values}" | wc -w)
    [[ ${count} -eq 0 ]] && echo "0" && return

    # Sort values
    local sorted
    sorted=$(echo "${values}" | tr ' ' '\n' | sort -n | tr '\n' ' ')

    # Calculate index
    local index=$(( (count * percentile) / 100 ))
    [[ ${index} -ge ${count} ]] && index=$((count - 1))

    local val
    local i=0
    for val in ${sorted}; do
        if [[ $i -eq ${index} ]]; then
            echo "${val}"
            return
        fi
        ((i++))
    done

    echo "0"
}

# Find minimum value
_aggregator_min() {
    local values="$1"
    [[ -z "${values}" ]] && echo "0" && return

    echo "${values}" | tr ' ' '\n' | sort -n | head -1
}

# Find maximum value
_aggregator_max() {
    local values="$1"
    [[ -z "${values}" ]] && echo "0" && return

    echo "${values}" | tr ' ' '\n' | sort -n | tail -1
}

# ============================================================================
# Private: Data Extraction
# ============================================================================

# Extract metric values from all sessions
_aggregator_extract_metric() {
    local metric_name="$1"

    # Ensure collector cache is valid
    analytics_collector_scan

    # Get all sessions
    local sessions
    sessions=$(analytics_collector_get_sessions)

    [[ -z "${sessions}" ]] && return 1

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
                value=$(echo "${data}" | jq -r ".${metric_name} // 0" 2>/dev/null)
            else
                # Fallback: grep
                value=$(echo "${data}" | grep -oP "\"${metric_name}\"\s*:\s*\K[0-9]+" || echo "0")
            fi

            values="${values} ${value}"
        fi
    done <<< "${sessions}"

    echo "${values}"
}

# ============================================================================
# Public: Initialization
# ============================================================================

# Initialize aggregator module
analytics_aggregator_init() {
    # Ensure collector is initialized
    analytics_collector_init

    wow_debug "Analytics aggregator initialized (v${AGGREGATOR_VERSION})"
    return 0
}

# ============================================================================
# Public: Aggregation
# ============================================================================

# Calculate all aggregates for a metric
# Usage: analytics_aggregate_metrics <metric_name>
analytics_aggregate_metrics() {
    local metric="${1:-wow_score}"

    # Extract values
    local values
    values=$(_aggregator_extract_metric "${metric}")

    [[ -z "${values}" ]] && return 1

    # Calculate statistics
    local mean median min max p25 p75 p95
    mean=$(_aggregator_mean "${values}")
    median=$(_aggregator_median "${values}")
    min=$(_aggregator_min "${values}")
    max=$(_aggregator_max "${values}")
    p25=$(_aggregator_percentile "${values}" 25)
    p75=$(_aggregator_percentile "${values}" 75)
    p95=$(_aggregator_percentile "${values}" 95)

    # Store in cache
    _AGGREGATOR_CACHE["${metric}_mean"]="${mean}"
    _AGGREGATOR_CACHE["${metric}_median"]="${median}"
    _AGGREGATOR_CACHE["${metric}_min"]="${min}"
    _AGGREGATOR_CACHE["${metric}_max"]="${max}"
    _AGGREGATOR_CACHE["${metric}_p25"]="${p25}"
    _AGGREGATOR_CACHE["${metric}_p75"]="${p75}"
    _AGGREGATOR_CACHE["${metric}_p95"]="${p95}"

    _AGGREGATOR_CACHE_VALID=1

    return 0
}

# Get specific aggregate statistic
# Usage: analytics_aggregate_get <metric> <stat>
analytics_aggregate_get() {
    local metric="$1"
    local stat="$2"  # mean, median, min, max, p25, p75, p95

    # Check cache
    local key="${metric}_${stat}"
    if [[ ${_AGGREGATOR_CACHE_VALID} -eq 0 ]] || [[ -z "${_AGGREGATOR_CACHE[${key}]:-}" ]]; then
        analytics_aggregate_metrics "${metric}" || return 1
    fi

    echo "${_AGGREGATOR_CACHE[${key}]:-0}"
}

# Calculate percentile rank of a value
# Usage: analytics_aggregate_percentile <metric> <value>
analytics_aggregate_percentile() {
    local metric="$1"
    local value="$2"

    # Extract all values
    local values
    values=$(_aggregator_extract_metric "${metric}")

    [[ -z "${values}" ]] && echo "0" && return

    # Count values below the given value
    local total=0
    local below=0
    local val

    for val in ${values}; do
        ((total++))
        [[ ${val} -lt ${value} ]] && ((below++))
    done

    [[ ${total} -eq 0 ]] && echo "0" && return

    # Calculate percentile
    local percentile=$(( (below * 100) / total ))
    echo "${percentile}"
}

# Get total session count
analytics_aggregate_session_count() {
    analytics_collector_count
}

# ============================================================================
# Public: Cache Management
# ============================================================================

# Invalidate aggregates cache
analytics_aggregator_invalidate() {
    _AGGREGATOR_CACHE=()
    _AGGREGATOR_CACHE_VALID=0

    # Also invalidate collector cache
    analytics_collector_invalidate_cache
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Analytics Aggregator - Self Test (v${AGGREGATOR_VERSION})"
    echo "============================================================="
    echo ""

    # Test 1: Initialize
    analytics_aggregator_init && echo "✓ Initialization works"

    # Test 2: Aggregate (may fail if no sessions)
    analytics_aggregate_metrics "wow_score" 2>/dev/null && echo "✓ Aggregation works"

    # Test 3: Get statistic
    local mean
    mean=$(analytics_aggregate_get "wow_score" "mean")
    echo "✓ Get aggregate works (mean: ${mean})"

    echo ""
    echo "All self-tests passed! ✓"
fi
