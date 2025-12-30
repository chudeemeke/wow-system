#!/bin/bash
# WoW System - Duration Parser
# Parses human-friendly duration formats (1h, 30m, 2h30m) and plain minutes
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_DURATION_PARSER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_DURATION_PARSER_LOADED=1

# ============================================================================
# Duration Parsing (Human-Friendly -> Seconds)
# ============================================================================

# Parse duration string to seconds
# Supports: "1h", "30m", "2h30m", "1h 45m", or plain minutes "60"
# Returns: Number of seconds
# Exit code: 0=success, 1=error
duration_parse() {
    local input="$1"
    local hours=0
    local minutes=0
    local total_seconds=0

    # Handle empty input
    if [[ -z "${input}" ]]; then
        return 1
    fi

    # Normalize: lowercase, remove extra spaces
    input=$(echo "${input}" | tr '[:upper:]' '[:lower:]' | tr -s ' ')

    # Check for negative values
    if [[ "${input}" =~ ^- ]]; then
        return 1
    fi

    # Pattern 1: Combined hours and minutes (2h30m, 1h 45m)
    if [[ "${input}" =~ ^([0-9]+)h[[:space:]]*([0-9]+)m$ ]]; then
        hours="${BASH_REMATCH[1]}"
        minutes="${BASH_REMATCH[2]}"
        total_seconds=$(( (hours * 3600) + (minutes * 60) ))
        echo "${total_seconds}"
        return 0
    fi

    # Pattern 2: Hours only (1h, 4h)
    if [[ "${input}" =~ ^([0-9]+)h$ ]]; then
        hours="${BASH_REMATCH[1]}"
        total_seconds=$((hours * 3600))
        echo "${total_seconds}"
        return 0
    fi

    # Pattern 3: Minutes with suffix (30m, 120m)
    if [[ "${input}" =~ ^([0-9]+)m$ ]]; then
        minutes="${BASH_REMATCH[1]}"
        total_seconds=$((minutes * 60))
        echo "${total_seconds}"
        return 0
    fi

    # Pattern 4: Plain number (treated as minutes)
    if [[ "${input}" =~ ^[0-9]+$ ]]; then
        minutes="${input}"
        total_seconds=$((minutes * 60))
        echo "${total_seconds}"
        return 0
    fi

    # Invalid format
    return 1
}

# ============================================================================
# Duration Formatting (Seconds -> Human-Friendly)
# ============================================================================

# Format seconds to human-readable duration
# Input: Number of seconds
# Output: "2h 30m", "1h", "45m"
duration_format() {
    local seconds="$1"
    local hours=0
    local minutes=0
    local result=""

    # Handle zero/empty
    if [[ -z "${seconds}" ]] || [[ "${seconds}" -eq 0 ]]; then
        echo "0m"
        return 0
    fi

    # Calculate hours and remaining minutes
    hours=$((seconds / 3600))
    minutes=$(((seconds % 3600) / 60))

    # Build result string
    if [[ ${hours} -gt 0 ]] && [[ ${minutes} -gt 0 ]]; then
        result="${hours}h ${minutes}m"
    elif [[ ${hours} -gt 0 ]]; then
        result="${hours}h"
    else
        result="${minutes}m"
    fi

    echo "${result}"
}

# ============================================================================
# Validation Helpers
# ============================================================================

# Check if duration string is valid
# Returns: 0=valid, 1=invalid
duration_is_valid() {
    local input="$1"
    duration_parse "${input}" >/dev/null 2>&1
}

# Get default durations
duration_get_bypass_default() {
    echo "14400"  # 4 hours in seconds
}

duration_get_superadmin_default() {
    echo "1200"   # 20 minutes in seconds
}

# ============================================================================
# Self-Test
# ============================================================================

duration_self_test() {
    echo "Duration Parser Self-Test"
    echo "========================="

    local test_cases=(
        "1h:3600"
        "30m:1800"
        "2h30m:9000"
        "60:3600"
        "1h 45m:6300"
    )

    local passed=0
    local failed=0

    for tc in "${test_cases[@]}"; do
        local input="${tc%%:*}"
        local expected="${tc##*:}"
        local result
        result=$(duration_parse "${input}")

        if [[ "${result}" == "${expected}" ]]; then
            echo "[PASS] '${input}' -> ${result}"
            ((passed++))
        else
            echo "[FAIL] '${input}' -> ${result} (expected: ${expected})"
            ((failed++))
        fi
    done

    echo ""
    echo "Passed: ${passed}, Failed: ${failed}"

    return $((failed > 0 ? 1 : 0))
}
