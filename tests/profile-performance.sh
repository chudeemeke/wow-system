#!/bin/bash
# WoW System - Performance Profiling Script
# Measures handler latency and system overhead
# Author: Chude <chude@emeke.org>

set -euo pipefail

# Colors for output
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOW_ROOT="$(dirname "${SCRIPT_DIR}")"

echo "WoW System - Performance Profiling"
echo "==================================="
echo ""

# Initialize WoW system
export WOW_HOME="${WOW_ROOT}"
export WOW_DATA_DIR="/tmp/wow-profile-test"
mkdir -p "${WOW_DATA_DIR}"

# Source orchestrator
source "${WOW_ROOT}/src/core/orchestrator.sh"
wow_init

echo "✓ WoW System initialized"
echo ""

# Profiling function
profile_operation() {
    local operation_name="$1"
    local iterations="${2:-100}"

    local start_time=$(date +%s%N)

    for ((i=0; i<iterations; i++)); do
        eval "$3" > /dev/null 2>&1
    done

    local end_time=$(date +%s%N)
    local total_ns=$((end_time - start_time))
    local avg_ns=$((total_ns / iterations))
    local avg_ms=$(echo "scale=3; ${avg_ns} / 1000000" | bc)

    printf "${C_CYAN}%-40s${C_RESET} %8s ms/op (%d ops)\n" "${operation_name}" "${avg_ms}" "${iterations}"
}

# ============================================================================
# Handler Latency Tests
# ============================================================================

echo "${C_GREEN}Handler Performance:${C_RESET}"
echo "-------------------"

# Test bash handler with simple command
test_bash='source ${WOW_ROOT}/src/handlers/bash-handler.sh && handle_bash "{\"command\":\"echo test\"}"'
profile_operation "Bash Handler (simple command)" 100 "${test_bash}"

# Test write handler
test_write='source ${WOW_ROOT}/src/handlers/write-handler.sh && handle_write "{\"file_path\":\"/tmp/test.txt\",\"content\":\"test\"}"'
profile_operation "Write Handler (small file)" 100 "${test_write}"

# Test read handler with fast-path
test_read='source ${WOW_ROOT}/src/handlers/read-handler.sh && handle_read "{\"file_path\":\"${WOW_ROOT}/README.md\"}"'
profile_operation "Read Handler (fast-path)" 100 "${test_read}"

echo ""

# ============================================================================
# Analytics Performance Tests
# ============================================================================

echo "${C_GREEN}Analytics Performance:${C_RESET}"
echo "----------------------"

# Create test session data
mkdir -p "${WOW_DATA_DIR}/sessions/session-001"
cat > "${WOW_DATA_DIR}/sessions/session-001/metrics.json" <<EOF
{
  "session_id": "session-001",
  "wow_score": 85,
  "violations": 2,
  "bash_commands": 10
}
EOF

# Test collector scan
test_collector='source ${WOW_ROOT}/src/analytics/collector.sh && analytics_collector_init && analytics_collector_scan'
profile_operation "Analytics Collector (scan)" 100 "${test_collector}"

# Test aggregator
test_aggregator='source ${WOW_ROOT}/src/analytics/aggregator.sh && analytics_aggregate_init && analytics_aggregate_metrics "wow_score"'
profile_operation "Analytics Aggregator (calc)" 50 "${test_aggregator}"

# Test trends
test_trends='source ${WOW_ROOT}/src/analytics/trends.sh && analytics_trends_init && analytics_trends_calculate "wow_score"'
profile_operation "Analytics Trends (analysis)" 50 "${test_trends}"

echo ""

# ============================================================================
# Custom Rule Performance Tests
# ============================================================================

echo "${C_GREEN}Custom Rule Performance:${C_RESET}"
echo "------------------------"

# Create test rules file
cat > "/tmp/test-rules.conf" <<EOF
rule: Test rule
pattern: dangerous.*command
action: warn
severity: high
message: Test message
EOF

# Test rule DSL loading
test_dsl_load='source ${WOW_ROOT}/src/rules/dsl.sh && rule_dsl_init && rule_dsl_load_file "/tmp/test-rules.conf"'
profile_operation "Rule DSL (load file)" 100 "${test_dsl_load}"

# Test rule matching
test_dsl_match='source ${WOW_ROOT}/src/rules/dsl.sh && rule_dsl_init && rule_dsl_load_file "/tmp/test-rules.conf" > /dev/null && rule_dsl_match "safe command"'
profile_operation "Rule DSL (match miss)" 1000 "${test_dsl_match}"

test_dsl_match_hit='source ${WOW_ROOT}/src/rules/dsl.sh && rule_dsl_init && rule_dsl_load_file "/tmp/test-rules.conf" > /dev/null && rule_dsl_match "dangerous command"'
profile_operation "Rule DSL (match hit)" 1000 "${test_dsl_match_hit}"

echo ""

# ============================================================================
# End-to-End Flow Test
# ============================================================================

echo "${C_GREEN}End-to-End Performance:${C_RESET}"
echo "------------------------"

# Full handler flow with all checks
test_full_flow='source ${WOW_ROOT}/src/handlers/handler-router.sh && handler_init && handler_route "{\"tool\":\"Bash\",\"command\":\"echo test\"}"'
profile_operation "Full Handler Flow (E2E)" 100 "${test_full_flow}"

echo ""
echo "-------------------"
echo "${C_GREEN}Profiling Complete${C_RESET}"
echo ""
echo "Baseline Target: <20ms P95 latency"
echo "Phase E Baseline: 13ms P95 (exceptional)"

# Cleanup
rm -rf "${WOW_DATA_DIR}"
rm -f "/tmp/test-rules.conf"
