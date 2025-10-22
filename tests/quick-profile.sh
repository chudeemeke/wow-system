#!/bin/bash
# Quick performance check - measures key operations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOW_ROOT="$(dirname "${SCRIPT_DIR}")"

export WOW_HOME="${WOW_ROOT}"
export WOW_DATA_DIR="/tmp/wow-quick-test"
mkdir -p "${WOW_DATA_DIR}"

echo "Quick Performance Check"
echo "======================="
echo ""

# Function to time an operation
time_op() {
    local name="$1"
    local iterations="${2:-10}"

    start=$(date +%s%N)
    for ((i=0; i<iterations; i++)); do
        eval "$3" >/dev/null 2>&1 || true
    done
    end=$(date +%s%N)

    elapsed_ns=$((end - start))
    avg_ns=$((elapsed_ns / iterations))
    avg_ms=$((avg_ns / 1000000))

    printf "%-45s %5d ms/op\n" "$name" "$avg_ms"
}

# Initialize
source "${WOW_ROOT}/src/core/orchestrator.sh" 2>/dev/null
wow_init 2>/dev/null

echo "Handler Latency:"
source "${WOW_ROOT}/src/handlers/bash-handler.sh" 2>/dev/null
time_op "  Bash handler (echo command)" 10 'handle_bash "{\"command\":\"echo test\"}"'

source "${WOW_ROOT}/src/handlers/read-handler.sh" 2>/dev/null
time_op "  Read handler (README)" 10 'handle_read "{\"file_path\":\"${WOW_ROOT}/README.md\"}"'

echo ""
echo "Analytics Overhead:"
source "${WOW_ROOT}/src/analytics/collector.sh" 2>/dev/null
analytics_collector_init 2>/dev/null
time_op "  Collector scan" 5 'analytics_collector_scan'

echo ""
echo "Custom Rules:"
source "${WOW_ROOT}/src/rules/dsl.sh" 2>/dev/null
rule_dsl_init 2>/dev/null
time_op "  DSL match (no rules)" 10 'rule_dsl_match "test command"'

echo ""
echo "Performance Status: $(if [ $avg_ms -lt 20 ]; then echo "GOOD (<20ms)"; else echo "NEEDS OPTIMIZATION"; fi)"

rm -rf "${WOW_DATA_DIR}"
