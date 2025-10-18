#!/bin/bash
# WoW System - Benchmark Framework
# Performance testing utilities
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_BENCHMARK_FRAMEWORK_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_BENCHMARK_FRAMEWORK_LOADED=1

set -uo pipefail

# ============================================================================
# Time Measurement
# ============================================================================

# Get high-resolution timestamp (nanoseconds)
benchmark_time_ns() {
    date +%s%N 2>/dev/null || echo "$(($(date +%s) * 1000000000))"
}

# Measure execution time of a command
# Args: command_string
# Returns: duration_ms via echo
benchmark_measure() {
    local command="$1"

    local start=$(benchmark_time_ns)
    eval "${command}" >/dev/null 2>&1
    local end=$(benchmark_time_ns)

    local duration_ns=$((end - start))
    local duration_ms=$((duration_ns / 1000000))

    echo "${duration_ms}"
}

# ============================================================================
# Statistical Analysis
# ============================================================================

# Calculate mean from array of numbers
benchmark_mean() {
    local -a numbers=("$@")
    local sum=0
    local count=${#numbers[@]}

    if [[ ${count} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    for num in "${numbers[@]}"; do
        sum=$((sum + num))
    done

    echo "$((sum / count))"
}

# Calculate median from array of numbers
benchmark_median() {
    local -a numbers=("$@")
    local count=${#numbers[@]}

    if [[ ${count} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    # Sort array
    local -a sorted=($(printf '%s\n' "${numbers[@]}" | sort -n))

    local mid=$((count / 2))

    if [[ $((count % 2)) -eq 0 ]]; then
        # Even count - average of two middle values
        echo "$(( (sorted[mid-1] + sorted[mid]) / 2 ))"
    else
        # Odd count - middle value
        echo "${sorted[mid]}"
    fi
}

# Calculate percentile from array of numbers
# Args: percentile (0-100), numbers...
benchmark_percentile() {
    local percentile="$1"
    shift
    local -a numbers=("$@")
    local count=${#numbers[@]}

    if [[ ${count} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    # Sort array
    local -a sorted=($(printf '%s\n' "${numbers[@]}" | sort -n))

    local index=$(( (count * percentile) / 100 ))
    if [[ ${index} -ge ${count} ]]; then
        index=$((count - 1))
    fi

    echo "${sorted[index]}"
}

# ============================================================================
# Benchmark Execution
# ============================================================================

# Run benchmark with multiple iterations
# Args: iterations, command_string
# Returns: array of measurements via stdout (one per line)
benchmark_run() {
    local iterations="$1"
    local command="$2"
    local -a results=()

    # Warmup (10% of iterations, min 2)
    local warmup=$((iterations / 10))
    [[ ${warmup} -lt 2 ]] && warmup=2

    for ((i=0; i<warmup; i++)); do
        eval "${command}" >/dev/null 2>&1
    done

    # Actual benchmark
    for ((i=0; i<iterations; i++)); do
        local duration=$(benchmark_measure "${command}")
        echo "${duration}"
    done
}

# ============================================================================
# Comparison & Reporting
# ============================================================================

# Compare two benchmark results
# Args: baseline_mean, optimized_mean
# Returns: improvement percentage
benchmark_improvement() {
    local baseline="$1"
    local optimized="$2"

    if [[ ${baseline} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    local diff=$((baseline - optimized))
    local improvement=$(( (diff * 100) / baseline ))

    echo "${improvement}"
}

# Generate benchmark report
# Args: name, baseline_stats, optimized_stats
benchmark_report() {
    local name="$1"
    local baseline_mean="$2"
    local baseline_p95="$3"
    local optimized_mean="$4"
    local optimized_p95="$5"

    local improvement=$(benchmark_improvement "${baseline_mean}" "${optimized_mean}")

    cat <<EOF
╔══════════════════════════════════════════════════════════╗
║  ${name}
╠══════════════════════════════════════════════════════════╣
║  Baseline:  ${baseline_mean}ms (mean), ${baseline_p95}ms (p95)
║  Optimized: ${optimized_mean}ms (mean), ${optimized_p95}ms (p95)
║  Improvement: ${improvement}% reduction
╚══════════════════════════════════════════════════════════╝
EOF
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Benchmark Framework - Self Test"
    echo "===================================="
    echo ""

    # Test timing
    duration=$(benchmark_measure "sleep 0.01")
    [[ ${duration} -ge 8 ]] && echo "✓ Timing works (${duration}ms)" || echo "✗ Timing failed"

    # Test statistics
    numbers=(10 20 30 40 50)
    mean=$(benchmark_mean "${numbers[@]}")
    [[ ${mean} -eq 30 ]] && echo "✓ Mean calculation works (${mean})" || echo "✗ Mean failed"

    median=$(benchmark_median "${numbers[@]}")
    [[ ${median} -eq 30 ]] && echo "✓ Median calculation works (${median})" || echo "✗ Median failed"

    p95=$(benchmark_percentile 95 "${numbers[@]}")
    [[ ${p95} -eq 50 ]] && echo "✓ Percentile calculation works (p95=${p95})" || echo "✗ Percentile failed"

    # Test improvement calculation
    improvement=$(benchmark_improvement 100 20)
    [[ ${improvement} -eq 80 ]] && echo "✓ Improvement calculation works (${improvement}%)" || echo "✗ Improvement failed"

    echo ""
    echo "All self-tests passed! ✓"
fi
