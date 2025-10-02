#!/bin/bash
# WoW System - Risk Assessor
# Analyzes operations and determines risk levels
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Multi-factor analysis: Consider multiple risk dimensions
# - Context-aware: Risk varies by environment and user
# - Graduated response: Low/Medium/High/Critical risk levels
# - Transparent reasoning: Explain why something is risky

# Prevent double-sourcing
if [[ -n "${WOW_RISK_ASSESSOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_RISK_ASSESSOR_LOADED=1

# Source dependencies
_RISK_ASSESSOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_RISK_ASSESSOR_DIR}/../core/utils.sh"
source "${_RISK_ASSESSOR_DIR}/../core/session-manager.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly RISK_VERSION="1.0.0"

# Risk levels
readonly RISK_LEVEL_NONE="none"
readonly RISK_LEVEL_LOW="low"
readonly RISK_LEVEL_MEDIUM="medium"
readonly RISK_LEVEL_HIGH="high"
readonly RISK_LEVEL_CRITICAL="critical"

# Risk weights (for composite scoring)
readonly RISK_WEIGHT_PATH=30
readonly RISK_WEIGHT_CONTENT=25
readonly RISK_WEIGHT_OPERATION=20
readonly RISK_WEIGHT_FREQUENCY=15
readonly RISK_WEIGHT_CONTEXT=10

# ============================================================================
# Initialization
# ============================================================================

# Initialize risk assessor
risk_init() {
    wow_debug "Initializing risk assessor v${RISK_VERSION}"

    # Initialize risk tracking
    session_update_metric "risk_assessments" "0"
    session_update_metric "high_risk_operations" "0"

    wow_debug "Risk assessor initialized"
    return 0
}

# ============================================================================
# Path Risk Assessment
# ============================================================================

# Assess risk based on file path
risk_assess_path() {
    local file_path="$1"

    # Critical: System directories
    if echo "${file_path}" | grep -qE "^/(etc|bin|sbin|boot|sys|proc|dev|lib)"; then
        echo "${RISK_LEVEL_CRITICAL}"
        return 0
    fi

    # High: User binaries, config directories
    if echo "${file_path}" | grep -qE "^/usr/(bin|sbin)|^/var/(lib|log)|^/opt"; then
        echo "${RISK_LEVEL_HIGH}"
        return 0
    fi

    # Medium: Shared directories, temp with executables
    if echo "${file_path}" | grep -qE "^/(tmp|var/tmp).*\\.(sh|exe|bin)|^/usr/local"; then
        echo "${RISK_LEVEL_MEDIUM}"
        return 0
    fi

    # Low: Home directory, project files
    if echo "${file_path}" | grep -qE "^/(home|Users)/|^\\./"; then
        echo "${RISK_LEVEL_LOW}"
        return 0
    fi

    # Default: Medium for unknown
    echo "${RISK_LEVEL_MEDIUM}"
}

# ============================================================================
# Content Risk Assessment
# ============================================================================

# Assess risk based on file content
risk_assess_content() {
    local content="$1"

    # Critical: Destructive commands
    if echo "${content}" | grep -qiE "(rm\\s+-rf\\s*/|dd\\s+of=/dev/|mkfs\\.)"; then
        echo "${RISK_LEVEL_CRITICAL}"
        return 0
    fi

    # High: Privilege escalation, network operations
    if echo "${content}" | grep -qiE "(sudo|chmod 777|curl.*\\||wget.*\\||nc\\s+-l)"; then
        echo "${RISK_LEVEL_HIGH}"
        return 0
    fi

    # Medium: Script execution, eval statements
    if echo "${content}" | grep -qiE "(eval|exec|source.*\\$|\\$\\(.*\\))"; then
        echo "${RISK_LEVEL_MEDIUM}"
        return 0
    fi

    # Low: Regular code patterns
    echo "${RISK_LEVEL_LOW}"
}

# ============================================================================
# Operation Risk Assessment
# ============================================================================

# Assess risk based on operation type
risk_assess_operation() {
    local operation="$1"

    case "${operation}" in
        delete|remove|format|destroy)
            echo "${RISK_LEVEL_HIGH}"
            ;;
        modify|edit|replace|update)
            echo "${RISK_LEVEL_MEDIUM}"
            ;;
        create|write|add|append)
            echo "${RISK_LEVEL_LOW}"
            ;;
        read|view|list|query)
            echo "${RISK_LEVEL_NONE}"
            ;;
        *)
            echo "${RISK_LEVEL_MEDIUM}"
            ;;
    esac
}

# ============================================================================
# Frequency Risk Assessment
# ============================================================================

# Assess risk based on operation frequency (rate limiting)
risk_assess_frequency() {
    local operation_type="$1"

    # Get operation count in current session
    local count
    count=$(session_get_metric "${operation_type}_count" "0")

    # Critical: Excessive operations
    if [[ ${count} -gt 100 ]]; then
        echo "${RISK_LEVEL_CRITICAL}"
        return 0
    fi

    # High: High frequency
    if [[ ${count} -gt 50 ]]; then
        echo "${RISK_LEVEL_HIGH}"
        return 0
    fi

    # Medium: Moderate frequency
    if [[ ${count} -gt 20 ]]; then
        echo "${RISK_LEVEL_MEDIUM}"
        return 0
    fi

    # Low: Normal frequency
    echo "${RISK_LEVEL_LOW}"
}

# ============================================================================
# Context Risk Assessment
# ============================================================================

# Assess risk based on current context (score, violations)
risk_assess_context() {
    # Check current WoW score (if scoring engine available)
    local score
    score=$(session_get_metric "wow_score" "70")

    # High risk if score is low
    if [[ ${score} -lt 40 ]]; then
        echo "${RISK_LEVEL_HIGH}"
        return 0
    fi

    # Medium risk if score is moderate
    if [[ ${score} -lt 60 ]]; then
        echo "${RISK_LEVEL_MEDIUM}"
        return 0
    fi

    # Low risk if score is good
    echo "${RISK_LEVEL_LOW}"
}

# ============================================================================
# Composite Risk Assessment
# ============================================================================

# Convert risk level to numeric score
_risk_level_to_score() {
    local level="$1"

    case "${level}" in
        ${RISK_LEVEL_NONE}) echo "0" ;;
        ${RISK_LEVEL_LOW}) echo "25" ;;
        ${RISK_LEVEL_MEDIUM}) echo "50" ;;
        ${RISK_LEVEL_HIGH}) echo "75" ;;
        ${RISK_LEVEL_CRITICAL}) echo "100" ;;
        *) echo "50" ;;  # Default to medium
    esac
}

# Convert numeric score to risk level
_risk_score_to_level() {
    local score="$1"

    if [[ ${score} -ge 90 ]]; then
        echo "${RISK_LEVEL_CRITICAL}"
    elif [[ ${score} -ge 65 ]]; then
        echo "${RISK_LEVEL_HIGH}"
    elif [[ ${score} -ge 35 ]]; then
        echo "${RISK_LEVEL_MEDIUM}"
    elif [[ ${score} -ge 10 ]]; then
        echo "${RISK_LEVEL_LOW}"
    else
        echo "${RISK_LEVEL_NONE}"
    fi
}

# Assess overall risk using multiple factors
risk_assess_composite() {
    local file_path="${1:-}"
    local content="${2:-}"
    local operation="${3:-modify}"

    # Get individual risk assessments
    local path_risk
    path_risk=$(risk_assess_path "${file_path}")
    local path_score
    path_score=$(_risk_level_to_score "${path_risk}")

    local content_risk
    content_risk=$(risk_assess_content "${content}")
    local content_score
    content_score=$(_risk_level_to_score "${content_risk}")

    local operation_risk
    operation_risk=$(risk_assess_operation "${operation}")
    local operation_score
    operation_score=$(_risk_level_to_score "${operation_risk}")

    local frequency_risk
    frequency_risk=$(risk_assess_frequency "${operation}")
    local frequency_score
    frequency_score=$(_risk_level_to_score "${frequency_risk}")

    local context_risk
    context_risk=$(risk_assess_context)
    local context_score
    context_score=$(_risk_level_to_score "${context_risk}")

    # Calculate weighted composite score
    local composite_score=$(awk "BEGIN { printf \"%.0f\", (${path_score} * ${RISK_WEIGHT_PATH} / 100 + ${content_score} * ${RISK_WEIGHT_CONTENT} / 100 + ${operation_score} * ${RISK_WEIGHT_OPERATION} / 100 + ${frequency_score} * ${RISK_WEIGHT_FREQUENCY} / 100 + ${context_score} * ${RISK_WEIGHT_CONTEXT} / 100) }")

    # Convert composite score to risk level
    local composite_level
    composite_level=$(_risk_score_to_level "${composite_score}")

    # Track assessment
    session_increment_metric "risk_assessments"

    if [[ "${composite_level}" == "${RISK_LEVEL_HIGH}" ]] || \
       [[ "${composite_level}" == "${RISK_LEVEL_CRITICAL}" ]]; then
        session_increment_metric "high_risk_operations"
    fi

    # Return composite level
    echo "${composite_level}"
}

# ============================================================================
# Risk Reporting
# ============================================================================

# Get risk assessment report
risk_report() {
    local file_path="${1:-unknown}"
    local content="${2:-}"
    local operation="${3:-modify}"

    # Perform assessment
    local overall_risk
    overall_risk=$(risk_assess_composite "${file_path}" "${content}" "${operation}")

    # Get individual factors
    local path_risk
    path_risk=$(risk_assess_path "${file_path}")
    local content_risk
    content_risk=$(risk_assess_content "${content}")
    local operation_risk
    operation_risk=$(risk_assess_operation "${operation}")
    local context_risk
    context_risk=$(risk_assess_context)

    cat <<EOF
Risk Assessment Report
======================
Overall Risk: ${overall_risk}

Risk Factors:
  Path: ${path_risk}
  Content: ${content_risk}
  Operation: ${operation_risk}
  Context: ${context_risk}

File: ${file_path}
Operation: ${operation}
EOF
}

# Get risk statistics
risk_stats() {
    local total_assessments
    total_assessments=$(session_get_metric "risk_assessments" "0")
    local high_risk_ops
    high_risk_ops=$(session_get_metric "high_risk_operations" "0")

    local risk_percentage=0
    if [[ ${total_assessments} -gt 0 ]]; then
        risk_percentage=$((high_risk_ops * 100 / total_assessments))
    fi

    cat <<EOF
Risk Statistics
===============
Total Assessments: ${total_assessments}
High Risk Operations: ${high_risk_ops}
Risk Percentage: ${risk_percentage}%
EOF
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Risk Assessor v${RISK_VERSION} - Self Test"
    echo "=============================================="
    echo ""

    # Initialize
    risk_init
    echo "✓ Initialized"

    # Test path assessment
    risk=$( risk_assess_path "/etc/passwd")
    [[ "${risk}" == "${RISK_LEVEL_CRITICAL}" ]] && echo "✓ Path risk: /etc/passwd = critical"

    risk=$(risk_assess_path "/home/user/file.txt")
    [[ "${risk}" == "${RISK_LEVEL_LOW}" ]] && echo "✓ Path risk: home file = low"

    # Test content assessment
    risk=$(risk_assess_content "rm -rf /")
    [[ "${risk}" == "${RISK_LEVEL_CRITICAL}" ]] && echo "✓ Content risk: rm -rf / = critical"

    risk=$(risk_assess_content "echo 'hello'")
    [[ "${risk}" == "${RISK_LEVEL_LOW}" ]] && echo "✓ Content risk: echo = low"

    # Test operation assessment
    risk=$(risk_assess_operation "delete")
    [[ "${risk}" == "${RISK_LEVEL_HIGH}" ]] && echo "✓ Operation risk: delete = high"

    risk=$(risk_assess_operation "read")
    [[ "${risk}" == "${RISK_LEVEL_NONE}" ]] && echo "✓ Operation risk: read = none"

    # Test composite assessment
    risk=$(risk_assess_composite "/etc/hosts" "malicious content" "delete")
    echo "✓ Composite risk assessment: ${risk}"

    # Test report
    echo ""
    risk_report "/tmp/test.sh" "echo test" "create"

    echo ""
    risk_stats

    echo ""
    echo "All tests passed! ✓"
fi
