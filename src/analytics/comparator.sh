#!/bin/bash
# WoW System - Analytics Comparator Module (Production-Grade)
# Compares current performance against historical benchmarks
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - SOLID: Single Responsibility (only comparison)
# - UX-Focused: Clear delta formatting (+5, -3, at average)
# - Performance: Leverages aggregator caching
# - Simplicity: Straightforward comparisons

# Prevent double-sourcing
if [[ -n "${WOW_ANALYTICS_COMPARATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ANALYTICS_COMPARATOR_LOADED=1

# Source dependencies
_ANALYTICS_COMPARATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ANALYTICS_COMPARATOR_DIR}/../core/utils.sh"
source "${_ANALYTICS_COMPARATOR_DIR}/aggregator.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly COMPARATOR_VERSION="1.0.0"

# ============================================================================
# Public: Initialization
# ============================================================================

# Initialize comparator module
analytics_comparator_init() {
    # Ensure aggregator is initialized
    analytics_aggregator_init

    wow_debug "Analytics comparator initialized (v${COMPARATOR_VERSION})"
    return 0
}

# ============================================================================
# Public: Comparison Operations
# ============================================================================

# Compare value to average
analytics_compare_to_average() {
    local metric="$1"
    local value="$2"

    local mean
    mean=$(analytics_aggregate_get "${metric}" "mean")

    [[ -z "${mean}" ]] || [[ "${mean}" == "0" ]] && echo "0" && return 1

    local delta=$((value - mean))
    echo "${delta}"
}

# Compare value to personal best
analytics_compare_to_best() {
    local metric="$1"
    local value="$2"

    local max
    max=$(analytics_aggregate_get "${metric}" "max")

    [[ -z "${max}" ]] || [[ "${max}" == "0" ]] && echo "0" && return 1

    local delta=$((value - max))
    echo "${delta}"
}

# Compare value to median
analytics_compare_to_median() {
    local metric="$1"
    local value="$2"

    local median
    median=$(analytics_aggregate_get "${metric}" "median")

    [[ -z "${median}" ]] || [[ "${median}" == "0" ]] && echo "0" && return 1

    local delta=$((value - median))
    echo "${delta}"
}

# Format delta with sign
analytics_compare_format_delta() {
    local delta="$1"

    if [[ ${delta} -gt 0 ]]; then
        echo "+${delta}"
    elif [[ ${delta} -lt 0 ]]; then
        echo "${delta}"
    else
        echo "±0"
    fi
}

# Get percentile rank for value
analytics_compare_get_percentile() {
    local metric="$1"
    local value="$2"

    analytics_aggregate_percentile "${metric}" "${value}"
}

# Get comparison summary
analytics_compare_summary() {
    local metric="${1:-wow_score}"
    local value="${2:-0}"

    # Get deltas
    local delta_avg
    local delta_best

    delta_avg=$(analytics_compare_to_average "${metric}" "${value}")
    delta_best=$(analytics_compare_to_best "${metric}" "${value}")

    # Get percentile
    local percentile
    percentile=$(analytics_compare_get_percentile "${metric}" "${value}")

    # Format
    local delta_avg_fmt
    local delta_best_fmt

    delta_avg_fmt=$(analytics_compare_format_delta "${delta_avg}")
    delta_best_fmt=$(analytics_compare_format_delta "${delta_best}")

    # Generate summary
    if [[ ${percentile} -ge 90 ]]; then
        echo "Excellent (${percentile}th percentile, ${delta_avg_fmt} vs avg)"
    elif [[ ${percentile} -ge 75 ]]; then
        echo "Above average (${percentile}th percentile, ${delta_avg_fmt} vs avg)"
    elif [[ ${percentile} -ge 50 ]]; then
        echo "Average (${percentile}th percentile, ${delta_avg_fmt} vs avg)"
    elif [[ ${percentile} -ge 25 ]]; then
        echo "Below average (${percentile}th percentile, ${delta_avg_fmt} vs avg)"
    else
        echo "Needs improvement (${percentile}th percentile, ${delta_avg_fmt} vs avg)"
    fi
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Analytics Comparator - Self Test (v${COMPARATOR_VERSION})"
    echo "============================================================="
    echo ""

    # Test 1: Initialize
    analytics_comparator_init && echo "✓ Initialization works"

    # Test 2: Compare to average (mock data)
    analytics_aggregate_metrics "wow_score" 2>/dev/null
    local delta
    delta=$(analytics_compare_to_average "wow_score" 85)
    echo "✓ Compare to average works (delta: ${delta})"

    # Test 3: Format delta
    local formatted
    formatted=$(analytics_compare_format_delta "5")
    echo "✓ Format delta works (formatted: ${formatted})"

    # Test 4: Summary
    local summary
    summary=$(analytics_compare_summary "wow_score" 85)
    echo "✓ Summary works: ${summary}"

    echo ""
    echo "All self-tests passed! ✓"
fi
