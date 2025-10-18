#!/bin/bash
# WoW System - Fast Path Performance Benchmarks
# Measures performance improvement of fast path validation
# Author: Chude <chude@emeke.org>

set -uo pipefail

# Source benchmark framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/benchmark-framework.sh"

# Source dependencies
source "${SCRIPT_DIR}/../src/core/utils.sh"
source "${SCRIPT_DIR}/../src/core/fast-path-validator.sh"

# ============================================================================
# Constants
# ============================================================================

readonly ITERATIONS=100  # Number of iterations per benchmark
readonly EXPECTED_IMPROVEMENT=60  # Target: 60%+ improvement

# Test file paths
readonly TEST_FILE_CURRENT="/tmp/benchmark-test.js"
readonly TEST_FILE_PARENT="../config/wow-config.json"
readonly TEST_FILE_ABSOLUTE="/etc/passwd"
readonly TEST_FILE_SAFE_EXT="/tmp/test.md"

# ============================================================================
# Setup & Teardown
# ============================================================================

benchmark_setup() {
    # Create test files
    touch "${TEST_FILE_CURRENT}" 2>/dev/null || true
    touch "${TEST_FILE_SAFE_EXT}" 2>/dev/null || true
}

benchmark_teardown() {
    # Clean up test files
    rm -f "${TEST_FILE_CURRENT}" "${TEST_FILE_SAFE_EXT}" 2>/dev/null || true
}

# ============================================================================
# Baseline: Full Validation (Simulated)
# ============================================================================

# Simulate full handler validation (what would happen without fast path)
baseline_validate() {
    local file_path="$1"

    # Simulate expensive operations:
    # 1. Pattern matching
    # 2. File stat checks
    # 3. Content scanning preparation
    # 4. Permission checks

    # Check if file exists
    [[ -f "${file_path}" ]] || return 1

    # Simulate pattern matching (10 patterns)
    for pattern in "rm -rf" "sudo" "dd if" "mkfs" "fork" "bomb" "> /dev" "curl.*|.*sh" "wget.*|.*sh" "eval"; do
        [[ "${file_path}" =~ ${pattern} ]] && return 2
    done

    # Simulate path checks
    if [[ "${file_path}" =~ ^/etc ]] || [[ "${file_path}" =~ ^/bin ]] || [[ "${file_path}" =~ ^/usr ]]; then
        return 2
    fi

    # Simulate file stat
    stat "${file_path}" >/dev/null 2>&1

    return 0
}

# ============================================================================
# Benchmark 1: Current Directory File
# ============================================================================

benchmark_current_directory() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Benchmark 1: Current Directory File                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Baseline: Full validation
    echo "Running baseline (full validation)..."
    local -a baseline_times
    while IFS= read -r time; do
        baseline_times+=("${time}")
    done < <(benchmark_run ${ITERATIONS} "baseline_validate '${TEST_FILE_CURRENT}'")

    local baseline_mean=$(benchmark_mean "${baseline_times[@]}")
    local baseline_p95=$(benchmark_percentile 95 "${baseline_times[@]}")

    # Optimized: Fast path
    echo "Running optimized (fast path)..."
    local -a optimized_times
    while IFS= read -r time; do
        optimized_times+=("${time}")
    done < <(benchmark_run ${ITERATIONS} "fast_path_validate '${TEST_FILE_CURRENT}' 'read'")

    local optimized_mean=$(benchmark_mean "${optimized_times[@]}")
    local optimized_p95=$(benchmark_percentile 95 "${optimized_times[@]}")

    # Report
    benchmark_report "Current Directory File" \
        "${baseline_mean}" "${baseline_p95}" \
        "${optimized_mean}" "${optimized_p95}"

    local improvement=$(benchmark_improvement "${baseline_mean}" "${optimized_mean}")
    echo ""
    echo "Result: ${improvement}% faster"

    if [[ ${improvement} -ge ${EXPECTED_IMPROVEMENT} ]]; then
        echo "✓ Target achieved (${EXPECTED_IMPROVEMENT}%+ improvement)"
        return 0
    else
        echo "⚠  Below target (expected ${EXPECTED_IMPROVEMENT}%+, got ${improvement}%)"
        return 1
    fi
}

# ============================================================================
# Benchmark 2: Safe Extension File
# ============================================================================

benchmark_safe_extension() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Benchmark 2: Safe Extension File (.md)                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Baseline
    echo "Running baseline..."
    local -a baseline_times
    while IFS= read -r time; do
        baseline_times+=("${time}")
    done < <(benchmark_run ${ITERATIONS} "baseline_validate '${TEST_FILE_SAFE_EXT}'")

    local baseline_mean=$(benchmark_mean "${baseline_times[@]}")
    local baseline_p95=$(benchmark_percentile 95 "${baseline_times[@]}")

    # Optimized
    echo "Running optimized..."
    local -a optimized_times
    while IFS= read -r time; do
        optimized_times+=("${time}")
    done < <(benchmark_run ${ITERATIONS} "fast_path_validate '${TEST_FILE_SAFE_EXT}' 'read'")

    local optimized_mean=$(benchmark_mean "${optimized_times[@]}")
    local optimized_p95=$(benchmark_percentile 95 "${optimized_times[@]}")

    # Report
    benchmark_report "Safe Extension File (.md)" \
        "${baseline_mean}" "${baseline_p95}" \
        "${optimized_mean}" "${optimized_p95}"

    local improvement=$(benchmark_improvement "${baseline_mean}" "${optimized_mean}")
    echo ""
    echo "Result: ${improvement}% faster"

    if [[ ${improvement} -ge ${EXPECTED_IMPROVEMENT} ]]; then
        echo "✓ Target achieved"
        return 0
    else
        echo "⚠  Below target"
        return 1
    fi
}

# ============================================================================
# Benchmark 3: System Path (Should Block)
# ============================================================================

benchmark_system_path() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Benchmark 3: System Path (/etc/passwd)                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Baseline
    echo "Running baseline..."
    local -a baseline_times
    while IFS= read -r time; do
        baseline_times+=("${time}")
    done < <(benchmark_run ${ITERATIONS} "baseline_validate '${TEST_FILE_ABSOLUTE}'")

    local baseline_mean=$(benchmark_mean "${baseline_times[@]}")
    local baseline_p95=$(benchmark_percentile 95 "${baseline_times[@]}")

    # Optimized
    echo "Running optimized..."
    local -a optimized_times
    while IFS= read -r time; do
        optimized_times+=("${time}")
    done < <(benchmark_run ${ITERATIONS} "fast_path_validate '${TEST_FILE_ABSOLUTE}' 'read'")

    local optimized_mean=$(benchmark_mean "${optimized_times[@]}")
    local optimized_p95=$(benchmark_percentile 95 "${optimized_times[@]}")

    # Report
    benchmark_report "System Path (Block)" \
        "${baseline_mean}" "${baseline_p95}" \
        "${optimized_mean}" "${optimized_p95}"

    local improvement=$(benchmark_improvement "${baseline_mean}" "${optimized_mean}")
    echo ""
    echo "Result: ${improvement}% faster (early detection)"

    # System paths should be detected VERY fast (early exit)
    if [[ ${optimized_mean} -le 10 ]]; then
        echo "✓ System path detection is fast (<10ms)"
        return 0
    else
        echo "⚠  System path detection slower than expected"
        return 1
    fi
}

# ============================================================================
# Benchmark 4: Mixed Workload
# ============================================================================

benchmark_mixed_workload() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Benchmark 4: Mixed Workload (Real-World Simulation)     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Create array of test paths (realistic mix)
    local -a test_paths=(
        "${TEST_FILE_CURRENT}"      # 40% - current dir
        "${TEST_FILE_CURRENT}"
        "${TEST_FILE_CURRENT}"
        "${TEST_FILE_CURRENT}"
        "${TEST_FILE_SAFE_EXT}"     # 30% - safe extensions
        "${TEST_FILE_SAFE_EXT}"
        "${TEST_FILE_SAFE_EXT}"
        "${TEST_FILE_PARENT}"       # 20% - parent paths
        "${TEST_FILE_PARENT}"
        "${TEST_FILE_ABSOLUTE}"     # 10% - system paths
    )

    # Baseline
    echo "Running baseline (mixed)..."
    local baseline_total=0
    for path in "${test_paths[@]}"; do
        local time=$(benchmark_measure "baseline_validate '${path}'")
        baseline_total=$((baseline_total + time))
    done
    local baseline_mean=$((baseline_total / ${#test_paths[@]}))

    # Optimized
    echo "Running optimized (mixed)..."
    local optimized_total=0
    for path in "${test_paths[@]}"; do
        local time=$(benchmark_measure "fast_path_validate '${path}' 'read'")
        optimized_total=$((optimized_total + time))
    done
    local optimized_mean=$((optimized_total / ${#test_paths[@]}))

    # Report
    cat <<EOF

╔══════════════════════════════════════════════════════════╗
║  Mixed Workload Results                                  ║
╠══════════════════════════════════════════════════════════╣
║  Baseline:  ${baseline_mean}ms average per operation
║  Optimized: ${optimized_mean}ms average per operation
╚══════════════════════════════════════════════════════════╝
EOF

    local improvement=$(benchmark_improvement "${baseline_mean}" "${optimized_mean}")
    echo ""
    echo "Result: ${improvement}% overall improvement"

    if [[ ${improvement} -ge 70 ]]; then
        echo "✓ Excellent performance (70%+ improvement)"
        return 0
    elif [[ ${improvement} -ge 60 ]]; then
        echo "✓ Good performance (60%+ improvement)"
        return 0
    else
        echo "⚠  Below target (expected 60%+, got ${improvement}%)"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  WoW System v${WOW_VERSION:-5.2.0} - Fast Path Benchmarks          ║"
    echo "║  Performance Analysis & Optimization Validation          ║"
    echo "╚══════════════════════════════════════════════════════════╝"

    benchmark_setup

    local total=0
    local passed=0

    # Run benchmarks
    benchmark_current_directory && passed=$((passed + 1))
    total=$((total + 1))

    benchmark_safe_extension && passed=$((passed + 1))
    total=$((total + 1))

    benchmark_system_path && passed=$((passed + 1))
    total=$((total + 1))

    benchmark_mixed_workload && passed=$((passed + 1))
    total=$((total + 1))

    benchmark_teardown

    # Summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Benchmark Summary                                       ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  Benchmarks Passed: ${passed}/${total}                              ║"
    if [[ ${passed} -eq ${total} ]]; then
        echo "║  Status: ✓ ALL BENCHMARKS PASSED                        ║"
    else
        echo "║  Status: ⚠  SOME BENCHMARKS FAILED                      ║"
    fi
    echo "╚══════════════════════════════════════════════════════════╝"

    [[ ${passed} -eq ${total} ]]
}

main "$@"
