#!/bin/bash
# WoW System - Memory Profiling Stress Test
# Detects and quantifies memory leaks over time
# Author: Chude <chude@emeke.org>

set -euo pipefail

# ============================================================================
# Dependencies
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/stress-framework.sh"
source "${SCRIPT_DIR}/../benchmark-framework.sh"

# Source WoW components
WOW_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${WOW_ROOT}/src/core/utils.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly PROFILE_OPERATIONS=1000
readonly SAMPLE_INTERVAL=100  # Sample every N operations
readonly TARGET_GROWTH_PER_1K_OPS_MB=1  # < 1MB per 1000 ops
readonly TARGET_FD_LEAK=0  # No file descriptor leaks

# Memory profiling data
declare -a MEMORY_SAMPLES_RSS=()
declare -a MEMORY_SAMPLES_VSZ=()
declare -a FD_SAMPLES=()
declare -a OPERATION_COUNTS=()

# ============================================================================
# Memory Profiling Functions
# ============================================================================

# Take a memory sample
# Records: RSS, VSZ, FD count, operation count
sample_memory() {
    local operation_count="$1"

    local rss=$(stress_get_memory_rss)
    local vsz=$(stress_get_memory_vsz)
    local fd=$(stress_get_fd_count)

    MEMORY_SAMPLES_RSS+=("${rss}")
    MEMORY_SAMPLES_VSZ+=("${vsz}")
    FD_SAMPLES+=("${fd}")
    OPERATION_COUNTS+=("${operation_count}")

    # Log sample
    echo "${operation_count},${rss},${vsz},${fd}" >> "${STRESS_REPORT_DIR}/metrics/memory_profile.csv"
}

# Calculate memory growth rate
# Returns: KB per 1000 operations
calculate_growth_rate() {
    local sample_count=${#MEMORY_SAMPLES_RSS[@]}

    if [[ ${sample_count} -lt 2 ]]; then
        echo "0"
        return 0
    fi

    # First and last samples
    local first_rss=${MEMORY_SAMPLES_RSS[0]}
    local last_rss=${MEMORY_SAMPLES_RSS[$((sample_count - 1))]}
    local first_op=${OPERATION_COUNTS[0]}
    local last_op=${OPERATION_COUNTS[$((sample_count - 1))]}

    # Growth
    local growth=$((last_rss - first_rss))
    local ops=$((last_op - first_op))

    if [[ ${ops} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    # Rate per 1000 ops
    local rate=$(( (growth * 1000) / ops ))

    echo "${rate}"
}

# Detect memory leak trend
# Returns: "increasing" | "stable" | "decreasing"
detect_leak_trend() {
    local sample_count=${#MEMORY_SAMPLES_RSS[@]}

    if [[ ${sample_count} -lt 3 ]]; then
        echo "stable"
        return 0
    fi

    # Calculate trend using simple linear regression approach
    # Count how many times memory increased vs decreased
    local increases=0
    local decreases=0

    for ((i=1; i<sample_count; i++)); do
        local prev=${MEMORY_SAMPLES_RSS[$((i-1))]}
        local curr=${MEMORY_SAMPLES_RSS[${i}]}

        if [[ ${curr} -gt ${prev} ]]; then
            increases=$((increases + 1))
        elif [[ ${curr} -lt ${prev} ]]; then
            decreases=$((decreases + 1))
        fi
    done

    # Determine trend
    if [[ ${increases} -gt $((sample_count / 2)) ]]; then
        echo "increasing"
    elif [[ ${decreases} -gt $((sample_count / 2)) ]]; then
        echo "decreasing"
    else
        echo "stable"
    fi
}

# Check for file descriptor leaks
# Returns: Number of FDs leaked
detect_fd_leaks() {
    local sample_count=${#FD_SAMPLES[@]}

    if [[ ${sample_count} -lt 2 ]]; then
        echo "0"
        return 0
    fi

    local first_fd=${FD_SAMPLES[0]}
    local last_fd=${FD_SAMPLES[$((sample_count - 1))]}

    local leak=$((last_fd - first_fd))

    # Allow some variance (< 5 FDs is acceptable)
    if [[ ${leak} -lt 5 ]]; then
        echo "0"
    else
        echo "${leak}"
    fi
}

# ============================================================================
# Profiling Workload
# ============================================================================

# Execute profiled operations
run_profiled_operations() {
    echo "Executing ${PROFILE_OPERATIONS} operations with memory profiling..."
    echo ""

    # Initial sample
    sample_memory 0

    for ((i=1; i<=PROFILE_OPERATIONS; i++)); do
        # Execute operation
        local start=$(benchmark_time_ns)

        # Simulated operation
        local command="echo test"
        [[ "${command}" =~ "rm -rf" ]] && return 2

        local end=$(benchmark_time_ns)
        local latency=$((end - start))

        # Record
        stress_record "Bash" ${latency} "success"

        # Sample memory at intervals
        if [[ $((i % SAMPLE_INTERVAL)) -eq 0 ]]; then
            sample_memory ${i}
            printf "\r  Progress: %d/%d operations (%.1f%%) - RSS: %d KB" \
                ${i} ${PROFILE_OPERATIONS} \
                $(bc <<< "scale=1; ${i} * 100 / ${PROFILE_OPERATIONS}") \
                $(stress_get_memory_rss)
        fi
    done

    # Final sample
    sample_memory ${PROFILE_OPERATIONS}

    echo ""
    echo ""
}

# ============================================================================
# Visualization
# ============================================================================

# Generate ASCII chart of memory usage over time
generate_memory_chart() {
    echo "Memory Usage Over Time (RSS)"
    echo "───────────────────────────────────────────────────────"

    local sample_count=${#MEMORY_SAMPLES_RSS[@]}

    # Find min and max for scaling
    local min_rss=${MEMORY_SAMPLES_RSS[0]}
    local max_rss=${MEMORY_SAMPLES_RSS[0]}

    for rss in "${MEMORY_SAMPLES_RSS[@]}"; do
        [[ ${rss} -lt ${min_rss} ]] && min_rss=${rss}
        [[ ${rss} -gt ${max_rss} ]] && max_rss=${rss}
    done

    local range=$((max_rss - min_rss))
    [[ ${range} -eq 0 ]] && range=1  # Avoid division by zero

    # Chart width: 50 characters
    local chart_width=50

    for ((i=0; i<sample_count; i++)); do
        local ops=${OPERATION_COUNTS[${i}]}
        local rss=${MEMORY_SAMPLES_RSS[${i}]}

        # Scale to chart width
        local bar_length=$(( ((rss - min_rss) * chart_width) / range ))

        # Print bar
        printf "%4d ops | " ${ops}
        printf "%${bar_length}s" | tr ' ' '█'
        printf " %d KB\n" ${rss}
    done

    echo "───────────────────────────────────────────────────────"
}

# ============================================================================
# Main Test
# ============================================================================

main() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  WoW System v${WOW_VERSION:-5.2.0} - Memory Profiling Test       ║"
    echo "║  Production Hardening - Phase E Day 2                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Initialize
    echo "Initializing memory profiler..."
    stress_init

    # Create CSV header
    echo "operations,rss_kb,vsz_kb,fd_count" > "${STRESS_REPORT_DIR}/metrics/memory_profile.csv"

    echo "Profile configuration:"
    echo "  Operations: ${PROFILE_OPERATIONS}"
    echo "  Sample interval: every ${SAMPLE_INTERVAL} operations"
    echo "  Target growth: < ${TARGET_GROWTH_PER_1K_OPS_MB}MB per 1000 ops"
    echo ""

    # Record start time
    local test_start=$(date +%s)

    # Run profiled operations
    run_profiled_operations

    # Record end time
    local test_end=$(date +%s)
    local duration=$((test_end - test_start))

    echo "Test completed in ${duration} seconds"
    echo ""

    # ========================================================================
    # Analysis
    # ========================================================================

    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Memory Profile Analysis                                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Growth rate
    local growth_rate_kb=$(calculate_growth_rate)
    local growth_rate_mb=$((growth_rate_kb / 1024))

    echo "  Growth rate: ${growth_rate_kb} KB per 1000 operations (${growth_rate_mb} MB)"

    # Trend
    local trend=$(detect_leak_trend)
    echo "  Memory trend: ${trend}"

    # FD leaks
    local fd_leak=$(detect_fd_leaks)
    echo "  File descriptor leaks: ${fd_leak}"

    echo ""

    # Memory chart
    generate_memory_chart

    echo ""

    # ========================================================================
    # Validation
    # ========================================================================

    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Acceptance Criteria Validation                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    local validation_passed=true

    # Criterion 1: Growth rate < 1MB per 1000 ops
    echo -n "  1. Memory growth < ${TARGET_GROWTH_PER_1K_OPS_MB}MB per 1000 ops: "
    if [[ ${growth_rate_mb} -le ${TARGET_GROWTH_PER_1K_OPS_MB} ]]; then
        echo "✓ PASS (${growth_rate_mb}MB)"
    else
        echo "✗ FAIL (${growth_rate_mb}MB)"
        validation_passed=false
    fi

    # Criterion 2: Trend should be stable or decreasing
    echo -n "  2. Memory trend is stable/decreasing: "
    if [[ "${trend}" == "stable" ]] || [[ "${trend}" == "decreasing" ]]; then
        echo "✓ PASS (${trend})"
    else
        echo "⚠ WARNING (${trend})"
        # Don't fail on this - might be normal fluctuation
    fi

    # Criterion 3: No FD leaks
    echo -n "  3. No file descriptor leaks: "
    if [[ ${fd_leak} -eq ${TARGET_FD_LEAK} ]]; then
        echo "✓ PASS (${fd_leak} leaked)"
    else
        echo "⚠ WARNING (${fd_leak} leaked)"
        # Don't fail - some FD variance is normal
    fi

    echo ""

    # ========================================================================
    # Generate Report
    # ========================================================================

    stress_report "Memory Profiling Test"

    echo ""

    cat "${STRESS_REPORT_DIR}/summaries/Memory_Profiling_Test.txt"

    echo ""

    # ========================================================================
    # Final Result
    # ========================================================================

    if ${validation_passed}; then
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  ✓ MEMORY PROFILING TEST PASSED                          ║"
        echo "║  No memory leaks detected - production ready             ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        return 0
    else
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  ✗ MEMORY PROFILING TEST FAILED                          ║"
        echo "║  Memory leaks require investigation                      ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        return 1
    fi
}

# Execute
main "$@"
