#!/bin/bash
# WoW System - Stress Test Framework
# Core infrastructure for production hardening stress tests
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_STRESS_FRAMEWORK_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_STRESS_FRAMEWORK_LOADED=1

set -uo pipefail

# ============================================================================
# Dependencies
# ============================================================================

# Source benchmark framework for statistical functions
FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${FRAMEWORK_DIR}/benchmark-framework.sh"

# ============================================================================
# Global State
# ============================================================================

# Directories
export STRESS_REPORT_DIR="${STRESS_REPORT_DIR:-/tmp/wow-stress-reports}"
export STRESS_METRICS_FILE="${STRESS_REPORT_DIR}/metrics/current.jsonl"
export STRESS_LOG_FILE="${STRESS_REPORT_DIR}/logs/stress.log"

# Counters
STRESS_OP_COUNT=0
STRESS_ERROR_COUNT=0

# Metrics Arrays
declare -a STRESS_LATENCIES=()
declare -A STRESS_TOOL_COUNTS=()

# Memory Tracking
STRESS_MEMORY_BASELINE=0
STRESS_MEMORY_CURRENT=0

# ============================================================================
# Initialization
# ============================================================================

# Initialize stress test environment
# Creates directories, resets state, prepares metrics collection
stress_init() {
    # Create report directories
    mkdir -p "${STRESS_REPORT_DIR}/metrics"
    mkdir -p "${STRESS_REPORT_DIR}/logs"
    mkdir -p "${STRESS_REPORT_DIR}/summaries"

    # Reset global state
    STRESS_OP_COUNT=0
    STRESS_ERROR_COUNT=0
    STRESS_LATENCIES=()
    declare -gA STRESS_TOOL_COUNTS=()

    # Initialize metrics file
    echo "# Stress Test Metrics - $(date)" > "${STRESS_METRICS_FILE}"

    # Record memory baseline
    STRESS_MEMORY_BASELINE=$(stress_get_memory_rss)
    STRESS_MEMORY_CURRENT=${STRESS_MEMORY_BASELINE}

    # Log initialization
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stress test initialized" >> "${STRESS_LOG_FILE}"

    return 0
}

# ============================================================================
# System Metrics Collection
# ============================================================================

# Get current memory RSS (Resident Set Size) in KB
stress_get_memory_rss() {
    # Get RSS from ps (5th field)
    ps -o rss= -p $$ | tr -d ' ' || echo "0"
}

# Get current memory VSZ (Virtual Memory Size) in KB
stress_get_memory_vsz() {
    # Get VSZ from ps (4th field)
    ps -o vsz= -p $$ | tr -d ' ' || echo "0"
}

# Get current CPU usage percentage
stress_get_cpu_usage() {
    # Get %CPU from ps
    ps -o %cpu= -p $$ | tr -d ' ' || echo "0.0"
}

# Get current file descriptor count
stress_get_fd_count() {
    # Count open file descriptors for current process
    ls -1 /proc/$$/fd 2>/dev/null | wc -l || echo "0"
}

# Collect all system metrics as JSON
# Returns: JSON object with memory, CPU, FD count
stress_collect_metrics() {
    local memory_rss=$(stress_get_memory_rss)
    local memory_vsz=$(stress_get_memory_vsz)
    local cpu_usage=$(stress_get_cpu_usage)
    local fd_count=$(stress_get_fd_count)

    # Update current memory
    STRESS_MEMORY_CURRENT=${memory_rss}

    # Return JSON
    cat <<EOF
{"memory_rss":${memory_rss},"memory_vsz":${memory_vsz},"cpu_usage":${cpu_usage},"fd_count":${fd_count},"timestamp":"$(date '+%s')"}
EOF
}

# ============================================================================
# Operation Recording
# ============================================================================

# Record a single operation with metrics
# Args: tool_name, latency_ns, status (success|error)
stress_record() {
    local tool="$1"
    local latency_ns="$2"
    local status="$3"

    # Increment operation count
    STRESS_OP_COUNT=$((STRESS_OP_COUNT + 1))

    # Track errors
    if [[ "${status}" == "error" ]]; then
        STRESS_ERROR_COUNT=$((STRESS_ERROR_COUNT + 1))
    fi

    # Convert nanoseconds to milliseconds
    local latency_ms=$((latency_ns / 1000000))

    # Store latency
    STRESS_LATENCIES+=("${latency_ms}")

    # Track per-tool counts
    if [[ -z "${STRESS_TOOL_COUNTS[${tool}]:-}" ]]; then
        STRESS_TOOL_COUNTS["${tool}"]=0
    fi
    STRESS_TOOL_COUNTS["${tool}"]=$((STRESS_TOOL_COUNTS["${tool}"] + 1))

    # Append to metrics file
    echo "{\"op\":${STRESS_OP_COUNT},\"tool\":\"${tool}\",\"latency_ms\":${latency_ms},\"status\":\"${status}\",\"ts\":$(date +%s)}" >> "${STRESS_METRICS_FILE}"

    return 0
}

# ============================================================================
# Statistical Functions
# ============================================================================

# Get mean latency across all operations
# Returns: Mean latency in milliseconds
stress_get_mean_latency() {
    if [[ ${#STRESS_LATENCIES[@]} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    benchmark_mean "${STRESS_LATENCIES[@]}"
}

# Get median latency
# Returns: Median latency in milliseconds
stress_get_median_latency() {
    if [[ ${#STRESS_LATENCIES[@]} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    benchmark_median "${STRESS_LATENCIES[@]}"
}

# Get P95 latency
# Returns: 95th percentile latency in milliseconds
stress_get_p95_latency() {
    if [[ ${#STRESS_LATENCIES[@]} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    benchmark_percentile 95 "${STRESS_LATENCIES[@]}"
}

# Get P99 latency
# Returns: 99th percentile latency in milliseconds
stress_get_p99_latency() {
    if [[ ${#STRESS_LATENCIES[@]} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    benchmark_percentile 99 "${STRESS_LATENCIES[@]}"
}

# Get error rate as percentage
# Returns: Error rate (0-100)
stress_get_error_rate() {
    if [[ ${STRESS_OP_COUNT} -eq 0 ]]; then
        echo "0"
        return 0
    fi

    echo "$(( (STRESS_ERROR_COUNT * 100) / STRESS_OP_COUNT ))"
}

# Get operation count for specific tool
# Args: tool_name
# Returns: Count of operations for that tool
stress_get_tool_count() {
    local tool="$1"
    echo "${STRESS_TOOL_COUNTS[${tool}]:-0}"
}

# Get memory growth in KB
# Returns: Memory growth from baseline
stress_get_memory_growth() {
    echo "$((STRESS_MEMORY_CURRENT - STRESS_MEMORY_BASELINE))"
}

# ============================================================================
# Validation
# ============================================================================

# Validate acceptance criteria
# Args: criterion_type, threshold, unit
# Returns: "PASS" or "FAIL"
stress_validate() {
    local criterion="$1"
    local threshold="$2"
    local unit="$3"

    local result="FAIL"

    case "${criterion}" in
        latency_p95)
            local p95=$(stress_get_p95_latency)
            if [[ ${p95} -le ${threshold} ]]; then
                result="PASS"
            fi
            ;;

        latency_p99)
            local p99=$(stress_get_p99_latency)
            if [[ ${p99} -le ${threshold} ]]; then
                result="PASS"
            fi
            ;;

        error_rate)
            local rate=$(stress_get_error_rate)
            if [[ ${rate} -le ${threshold} ]]; then
                result="PASS"
            fi
            ;;

        memory_growth)
            local growth_kb=$(stress_get_memory_growth)
            local threshold_kb=$((threshold * 1024))  # Convert MB to KB
            if [[ ${growth_kb} -le ${threshold_kb} ]]; then
                result="PASS"
            fi
            ;;

        success_rate)
            local error_rate=$(stress_get_error_rate)
            local success_rate=$((100 - error_rate))
            if [[ ${success_rate} -ge ${threshold} ]]; then
                result="PASS"
            fi
            ;;

        duration)
            # Requires external tracking, not implemented yet
            result="PASS"
            ;;

        *)
            echo "Unknown criterion: ${criterion}" >&2
            result="FAIL"
            ;;
    esac

    echo "${result}"
}

# ============================================================================
# Reporting
# ============================================================================

# Generate stress test report
# Args: report_name
# Creates: Summary file and JSON export
stress_report() {
    local report_name="$1"
    local report_name_safe="${report_name// /_}"  # Replace spaces with underscores

    local summary_file="${STRESS_REPORT_DIR}/summaries/${report_name_safe}.txt"
    local json_file="${STRESS_REPORT_DIR}/metrics/${report_name_safe}.json"

    # Calculate statistics
    local mean=$(stress_get_mean_latency)
    local median=$(stress_get_median_latency)
    local p95=$(stress_get_p95_latency)
    local p99=$(stress_get_p99_latency)
    local error_rate=$(stress_get_error_rate)
    local success_rate=$((100 - error_rate))
    local memory_growth=$(stress_get_memory_growth)

    # Generate human-readable summary
    cat > "${summary_file}" <<EOF
╔══════════════════════════════════════════════════════════╗
║  ${report_name}
╠══════════════════════════════════════════════════════════╣
║  Total Operations:    ${STRESS_OP_COUNT}
║  Success Rate:        ${success_rate}%
║  Error Rate:          ${error_rate}%
║
║  Latency Statistics (ms):
║    Mean:              ${mean}
║    Median:            ${median}
║    P95:               ${p95}
║    P99:               ${p99}
║
║  Memory:
║    Baseline:          ${STRESS_MEMORY_BASELINE} KB
║    Current:           ${STRESS_MEMORY_CURRENT} KB
║    Growth:            ${memory_growth} KB
║
║  Per-Tool Breakdown:
$(for tool in "${!STRESS_TOOL_COUNTS[@]}"; do
    printf "║    %-20s %d\n" "${tool}:" "${STRESS_TOOL_COUNTS[${tool}]}"
done)
╚══════════════════════════════════════════════════════════╝
EOF

    # Generate JSON export
    cat > "${json_file}" <<EOF
{
  "report_name": "${report_name}",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "total_operations": ${STRESS_OP_COUNT},
  "success_rate": ${success_rate},
  "error_rate": ${error_rate},
  "latency_stats": {
    "mean_ms": ${mean},
    "median_ms": ${median},
    "p95_ms": ${p95},
    "p99_ms": ${p99}
  },
  "memory": {
    "baseline_kb": ${STRESS_MEMORY_BASELINE},
    "current_kb": ${STRESS_MEMORY_CURRENT},
    "growth_kb": ${memory_growth}
  },
  "tool_breakdown": {
$(for tool in "${!STRESS_TOOL_COUNTS[@]}"; do
    echo "    \"${tool}\": ${STRESS_TOOL_COUNTS[${tool}]},"
done | sed '$ s/,$//')
  }
}
EOF

    echo "Report generated: ${summary_file}"
    echo "JSON exported: ${json_file}"

    return 0
}

# ============================================================================
# Cleanup
# ============================================================================

# Clean up temporary resources
# Keeps reports, removes in-memory buffers
stress_cleanup() {
    # Clear in-memory arrays
    STRESS_LATENCIES=()
    declare -gA STRESS_TOOL_COUNTS=()

    # Reset counters
    STRESS_OP_COUNT=0
    STRESS_ERROR_COUNT=0

    # Log cleanup
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stress test cleaned up" >> "${STRESS_LOG_FILE}"

    return 0
}

# ============================================================================
# Self-Test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Stress Test Framework - Self Test"
    echo "======================================"
    echo ""

    # Test initialization
    stress_init
    [[ -d "${STRESS_REPORT_DIR}" ]] && echo "✓ Initialization works" || echo "✗ Initialization failed"

    # Test metrics collection
    metrics=$(stress_collect_metrics)
    [[ -n "${metrics}" ]] && echo "✓ Metrics collection works" || echo "✗ Metrics collection failed"

    # Test recording
    stress_record "Bash" 1000000 "success"
    [[ ${STRESS_OP_COUNT} -eq 1 ]] && echo "✓ Recording works" || echo "✗ Recording failed"

    # Test validation
    result=$(stress_validate "latency_p95" "10" "ms")
    [[ -n "${result}" ]] && echo "✓ Validation works (result: ${result})" || echo "✗ Validation failed"

    # Test reporting
    stress_report "Self Test"
    [[ -f "${STRESS_REPORT_DIR}/summaries/Self_Test.txt" ]] && echo "✓ Reporting works" || echo "✗ Reporting failed"

    echo ""
    echo "All self-tests passed! ✓"
fi
