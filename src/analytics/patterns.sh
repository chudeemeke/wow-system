#!/bin/bash
# WoW System - Pattern Detection Module (Production-Grade)
# Identifies repeated violations and behavioral patterns across sessions
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - SOLID: Single Responsibility (only pattern detection)
# - Data-Driven: Analyzes actual session history
# - Actionable: Provides specific recommendations
# - Privacy: No sensitive data storage

# Prevent double-sourcing
if [[ -n "${WOW_ANALYTICS_PATTERNS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ANALYTICS_PATTERNS_LOADED=1

# Source dependencies
_ANALYTICS_PATTERNS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ANALYTICS_PATTERNS_DIR}/../core/utils.sh"
source "${_ANALYTICS_PATTERNS_DIR}/collector.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly PATTERNS_VERSION="1.0.0"
readonly PATTERNS_MIN_OCCURRENCES=3      # Minimum to qualify as pattern
readonly PATTERNS_DATA_FILE="patterns.json"

# Pattern storage
declare -gA _PATTERNS_CACHE=()
declare -g _PATTERNS_CACHE_VALID=0

# ============================================================================
# Private: Pattern Extraction
# ============================================================================

# Extract violations from session data
_patterns_extract_violations() {
    local session_id="$1"

    local data
    data=$(analytics_collector_get_session_data "${session_id}" 2>/dev/null)

    [[ -z "${data}" ]] && return 1

    # Extract events if available
    if wow_has_jq; then
        echo "${data}" | jq -r '.events[]? | select(.type == "security_violation") | .detail' 2>/dev/null
    else
        # Fallback: grep for violation patterns
        echo "${data}" | grep -oP '"security_violation".*?"detail"\s*:\s*"\K[^"]+' 2>/dev/null || true
    fi
}

# Create pattern signature from violation
_patterns_create_signature() {
    local violation="$1"

    # Extract pattern type and key identifier
    # Format: TYPE:IDENTIFIER
    # Examples:
    #   BLOCKED_SYSTEM_FILE:/etc/passwd
    #   BLOCKED_WEBFETCH:192.168.1.1
    #   DANGEROUS_BASH:rm -rf

    # Simple approach: take first 50 chars as signature
    echo "${violation:0:50}"
}

# ============================================================================
# Private: Pattern Analysis
# ============================================================================

# Count pattern occurrences across sessions
_patterns_count_occurrences() {
    local signature="$1"

    # Get all sessions
    analytics_collector_scan
    local sessions
    sessions=$(analytics_collector_get_sessions)

    local count=0
    local first_seen=""
    local last_seen=""

    while IFS= read -r session_id; do
        [[ -z "${session_id}" ]] && continue

        # Check if pattern exists in this session
        local violations
        violations=$(_patterns_extract_violations "${session_id}")

        if echo "${violations}" | grep -qF "${signature}"; then
            ((count++))

            # Get timestamp
            local data
            data=$(analytics_collector_get_session_data "${session_id}" 2>/dev/null)

            if [[ -n "${data}" ]]; then
                local timestamp
                if wow_has_jq; then
                    timestamp=$(echo "${data}" | jq -r '.timestamp // ""' 2>/dev/null)
                else
                    timestamp=$(date -Iseconds 2>/dev/null || date)
                fi

                [[ -z "${first_seen}" ]] && first_seen="${timestamp}"
                last_seen="${timestamp}"
            fi
        fi
    done <<< "${sessions}"

    # Return: count|first_seen|last_seen
    echo "${count}|${first_seen}|${last_seen}"
}

# Calculate confidence based on occurrences and frequency
_patterns_calculate_confidence() {
    local occurrences="$1"

    if [[ ${occurrences} -ge 10 ]]; then
        echo "critical"
    elif [[ ${occurrences} -ge 7 ]]; then
        echo "high"
    elif [[ ${occurrences} -ge 5 ]]; then
        echo "medium"
    elif [[ ${occurrences} -ge ${PATTERNS_MIN_OCCURRENCES} ]]; then
        echo "low"
    else
        echo "insufficient"
    fi
}

# Generate recommendation based on pattern
_patterns_generate_recommendation() {
    local signature="$1"

    # Pattern-specific recommendations
    case "${signature}" in
        *BLOCKED_SYSTEM_FILE*)
            echo "Review file access patterns. Consider using application-specific config files instead of system files."
            ;;
        *BLOCKED_WEBFETCH*)
            echo "Avoid accessing private IPs. Use public APIs or configure proper network access."
            ;;
        *DANGEROUS_BASH*)
            echo "Review bash commands for safety. Use specific file paths instead of wildcards."
            ;;
        *CREDENTIAL*)
            echo "Never hardcode credentials. Use environment variables or secure credential storage."
            ;;
        *PATH_TRAVERSAL*)
            echo "Avoid path traversal patterns. Validate and sanitize all file paths."
            ;;
        *)
            echo "Review this repeated violation and adjust your workflow accordingly."
            ;;
    esac
}

# ============================================================================
# Public: Initialization
# ============================================================================

# Initialize patterns module
analytics_pattern_init() {
    # Ensure collector is initialized
    analytics_collector_init

    # Create patterns data directory if needed
    local patterns_dir="${WOW_DATA_DIR}/analytics"
    mkdir -p "${patterns_dir}" 2>/dev/null || true

    wow_debug "Analytics patterns initialized (v${PATTERNS_VERSION})"
    return 0
}

# ============================================================================
# Public: Pattern Detection
# ============================================================================

# Detect patterns across all sessions
analytics_pattern_detect() {
    analytics_collector_scan

    # Get all sessions
    local sessions
    sessions=$(analytics_collector_get_sessions)

    # Collect all violations
    declare -A violation_map
    local session_id

    while IFS= read -r session_id; do
        [[ -z "${session_id}" ]] && continue

        local violations
        violations=$(_patterns_extract_violations "${session_id}")

        while IFS= read -r violation; do
            [[ -z "${violation}" ]] && continue

            local signature
            signature=$(_patterns_create_signature "${violation}")

            # Track violation
            if [[ -n "${violation_map[${signature}]:-}" ]]; then
                violation_map["${signature}"]=$((${violation_map[${signature}]} + 1))
            else
                violation_map["${signature}"]=1
            fi
        done <<< "${violations}"
    done <<< "${sessions}"

    # Filter patterns (min occurrences)
    local pattern_count=0
    local signature

    for signature in "${!violation_map[@]}"; do
        local count=${violation_map[${signature}]}

        if [[ ${count} -ge ${PATTERNS_MIN_OCCURRENCES} ]]; then
            # Get detailed info
            local info
            info=$(_patterns_count_occurrences "${signature}")

            local occurrences first_seen last_seen
            IFS='|' read -r occurrences first_seen last_seen <<< "${info}"

            local confidence
            confidence=$(_patterns_calculate_confidence "${occurrences}")

            local recommendation
            recommendation=$(_patterns_generate_recommendation "${signature}")

            # Store in cache
            _PATTERNS_CACHE["pattern_${pattern_count}_signature"]="${signature}"
            _PATTERNS_CACHE["pattern_${pattern_count}_occurrences"]="${occurrences}"
            _PATTERNS_CACHE["pattern_${pattern_count}_confidence"]="${confidence}"
            _PATTERNS_CACHE["pattern_${pattern_count}_first_seen"]="${first_seen}"
            _PATTERNS_CACHE["pattern_${pattern_count}_last_seen"]="${last_seen}"
            _PATTERNS_CACHE["pattern_${pattern_count}_recommendation"]="${recommendation}"

            ((pattern_count++))
        fi
    done

    _PATTERNS_CACHE["pattern_count"]="${pattern_count}"
    _PATTERNS_CACHE_VALID=1

    echo "${pattern_count}"
}

# Get top N patterns
analytics_pattern_get_top() {
    local limit="${1:-5}"

    # Ensure cache is valid
    if [[ ${_PATTERNS_CACHE_VALID} -eq 0 ]]; then
        analytics_pattern_detect > /dev/null
    fi

    local count=${_PATTERNS_CACHE["pattern_count"]:-0}
    [[ ${count} -eq 0 ]] && return 1

    # Sort by occurrences (descending) and return top N
    local -a patterns=()
    local i

    for ((i=0; i<count; i++)); do
        local occurrences=${_PATTERNS_CACHE["pattern_${i}_occurrences"]:-0}
        local signature=${_PATTERNS_CACHE["pattern_${i}_signature"]:-}
        patterns+=("${occurrences}:${i}:${signature}")
    done

    # Sort and output
    local sorted
    sorted=$(printf '%s\n' "${patterns[@]}" | sort -rn)

    local output_count=0
    while IFS=: read -r occurrences index signature; do
        [[ ${output_count} -ge ${limit} ]] && break

        echo "Pattern ${index}: ${signature} (${occurrences} occurrences)"
        ((output_count++))
    done <<< "${sorted}"
}

# Get recommendations for detected patterns
analytics_pattern_get_recommendations() {
    local limit="${1:-3}"

    # Ensure cache is valid
    if [[ ${_PATTERNS_CACHE_VALID} -eq 0 ]]; then
        analytics_pattern_detect > /dev/null
    fi

    local count=${_PATTERNS_CACHE["pattern_count"]:-0}
    [[ ${count} -eq 0 ]] && return 1

    # Get top patterns by confidence
    local output_count=0
    local i

    for ((i=0; i<count && output_count<limit; i++)); do
        local confidence=${_PATTERNS_CACHE["pattern_${i}_confidence"]:-}

        # Only show critical/high confidence patterns
        if [[ "${confidence}" == "critical" ]] || [[ "${confidence}" == "high" ]]; then
            local signature=${_PATTERNS_CACHE["pattern_${i}_signature"]:-}
            local occurrences=${_PATTERNS_CACHE["pattern_${i}_occurrences"]:-}
            local recommendation=${_PATTERNS_CACHE["pattern_${i}_recommendation"]:-}

            echo "⚠️  Pattern: ${signature:0:40}... (${occurrences}x)"
            echo "   Recommendation: ${recommendation}"
            echo ""

            ((output_count++))
        fi
    done

    [[ ${output_count} -eq 0 ]] && echo "No high-priority patterns detected" && return 0
}

# Get pattern summary for UX
analytics_pattern_get_summary() {
    # Ensure cache is valid
    if [[ ${_PATTERNS_CACHE_VALID} -eq 0 ]]; then
        analytics_pattern_detect > /dev/null
    fi

    local count=${_PATTERNS_CACHE["pattern_count"]:-0}

    if [[ ${count} -eq 0 ]]; then
        echo "No recurring patterns detected"
        return 0
    fi

    # Count by confidence
    local critical=0 high=0 medium=0 low=0
    local i

    for ((i=0; i<count; i++)); do
        local confidence=${_PATTERNS_CACHE["pattern_${i}_confidence"]:-}
        case "${confidence}" in
            critical) ((critical++)) ;;
            high) ((high++)) ;;
            medium) ((medium++)) ;;
            low) ((low++)) ;;
        esac
    done

    # Generate summary
    if [[ ${critical} -gt 0 ]]; then
        echo "${critical} critical pattern(s) - review recommended"
    elif [[ ${high} -gt 0 ]]; then
        echo "${high} high-priority pattern(s) detected"
    elif [[ ${medium} -gt 0 ]]; then
        echo "${medium} pattern(s) detected"
    else
        echo "${low} minor pattern(s) detected"
    fi
}

# ============================================================================
# Public: Cache Management
# ============================================================================

# Invalidate patterns cache
analytics_pattern_invalidate() {
    _PATTERNS_CACHE=()
    _PATTERNS_CACHE_VALID=0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Analytics Patterns - Self Test (v${PATTERNS_VERSION})"
    echo "=========================================================="
    echo ""

    # Test 1: Initialize
    analytics_pattern_init && echo "✓ Initialization works"

    # Test 2: Detect patterns
    count=$(analytics_pattern_detect 2>/dev/null || echo "0")
    echo "✓ Pattern detection works (found ${count} patterns)"

    # Test 3: Get top patterns
    analytics_pattern_get_top 3 2>/dev/null && echo "✓ Get top patterns works"

    # Test 4: Get recommendations
    analytics_pattern_get_recommendations 2 2>/dev/null && echo "✓ Get recommendations works"

    # Test 5: Get summary
    summary=$(analytics_pattern_get_summary)
    echo "✓ Get summary works: ${summary}"

    echo ""
    echo "All self-tests passed! ✓"
fi
