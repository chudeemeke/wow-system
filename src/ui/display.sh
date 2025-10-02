#!/bin/bash
# WoW System - Display & UI Components
# Provides visual feedback, banners, and metrics display
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Clear visual hierarchy
# - Color-coded feedback
# - Minimal noise
# - Accessible information

# Prevent double-sourcing
if [[ -n "${WOW_DISPLAY_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_DISPLAY_LOADED=1

# Source dependencies
_DISPLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_DISPLAY_DIR}/../core/utils.sh"
source "${_DISPLAY_DIR}/../core/session-manager.sh"

set -uo pipefail

# ============================================================================
# Constants - Colors & Formatting
# ============================================================================

readonly DISPLAY_VERSION="1.0.0"

# ANSI Color codes (from utils.sh but define here for clarity)
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_MAGENTA='\033[0;35m'
readonly C_CYAN='\033[0;36m'
readonly C_GRAY='\033[0;90m'

readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'

# Box drawing characters
readonly BOX_TL="┌"
readonly BOX_TR="┐"
readonly BOX_BL="└"
readonly BOX_BR="┘"
readonly BOX_H="─"
readonly BOX_V="│"
readonly BOX_VR="├"
readonly BOX_VL="┤"

# ============================================================================
# Banner Display
# ============================================================================

# Display WoW System banner
display_banner() {
    local version="${1:-4.1.0}"
    local score="${2:-70}"
    local status="${3:-good}"

    # Color based on status
    local status_color="${C_GREEN}"
    case "${status}" in
        excellent) status_color="${C_CYAN}" ;;
        good) status_color="${C_GREEN}" ;;
        warn) status_color="${C_YELLOW}" ;;
        critical) status_color="${C_RED}" ;;
        blocked) status_color="${C_RED}${C_BOLD}" ;;
    esac

    cat <<EOF

${C_BOLD}${C_CYAN}${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${C_RESET}
${C_BOLD}${C_CYAN}${BOX_V}${C_RESET}   ${C_BOLD}WoW System v${version}${C_RESET}                ${C_BOLD}${C_CYAN}${BOX_V}${C_RESET}
${C_BOLD}${C_CYAN}${BOX_V}${C_RESET}   Ways of Working Enforcement       ${C_BOLD}${C_CYAN}${BOX_V}${C_RESET}
${C_BOLD}${C_CYAN}${BOX_VR}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_VL}${C_RESET}
${C_BOLD}${C_CYAN}${BOX_V}${C_RESET}   Score: ${status_color}${score}/100 (${status})${C_RESET}             ${C_BOLD}${C_CYAN}${BOX_V}${C_RESET}
${C_BOLD}${C_CYAN}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${C_RESET}

EOF
}

# Display minimal status line
display_statusline() {
    local score="${1:-70}"
    local violations="${2:-0}"
    local session_id="${3:-unknown}"

    echo -e "${C_BOLD}[WoW]${C_RESET} Score: ${C_GREEN}${score}${C_RESET} | Violations: ${C_YELLOW}${violations}${C_RESET} | Session: ${C_GRAY}${session_id}${C_RESET}"
}

# ============================================================================
# Feedback Messages
# ============================================================================

# Display operation feedback
display_feedback() {
    local operation="$1"
    local result="$2"
    local message="${3:-}"

    local icon=""
    local color=""

    case "${result}" in
        success)
            icon="✓"
            color="${C_GREEN}"
            ;;
        warning)
            icon="⚠️"
            color="${C_YELLOW}"
            ;;
        error)
            icon="✗"
            color="${C_RED}"
            ;;
        blocked)
            icon="☠️"
            color="${C_RED}${C_BOLD}"
            ;;
        info)
            icon="ℹ️"
            color="${C_BLUE}"
            ;;
        *)
            icon="•"
            color="${C_RESET}"
            ;;
    esac

    echo -e "${color}${icon} ${operation}${C_RESET}${message:+: ${message}}"
}

# Display progress indicator
display_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"

    local percentage=$((current * 100 / total))
    local filled=$((percentage / 5))  # 20 chars = 100%
    local empty=$((20 - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    echo -ne "\r${label}: [${C_CYAN}${bar}${C_RESET}] ${percentage}%"

    # Newline if complete
    if [[ ${current} -eq ${total} ]]; then
        echo ""
    fi
}

# ============================================================================
# Metrics Display
# ============================================================================

# Display session metrics
display_metrics() {
    local bash_count
    bash_count=$(session_get_metric "bash_commands" "0")
    local write_count
    write_count=$(session_get_metric "file_writes" "0")
    local edit_count
    edit_count=$(session_get_metric "file_edits" "0")
    local violations
    violations=$(session_get_metric "violations" "0")
    local score
    score=$(session_get_metric "wow_score" "70")

    cat <<EOF

${C_BOLD}Session Metrics${C_RESET}
${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}
Operations:
  ${BOX_V} Bash Commands:  ${bash_count}
  ${BOX_V} File Writes:    ${write_count}
  ${BOX_V} File Edits:     ${edit_count}

Score:
  ${BOX_V} Current:        ${score}/100
  ${BOX_V} Violations:     ${violations}

EOF
}

# Display detailed statistics table
display_stats_table() {
    cat <<EOF

${C_BOLD}${C_CYAN}Detailed Statistics${C_RESET}
${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}
${BOX_V} Metric              ${BOX_V} Value     ${BOX_V}
${BOX_VR}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_VL}
EOF

    # Get all metrics
    local metrics
    metrics=$(session_get_metrics)

    # Display each metric
    while IFS='=' read -r name value; do
        if [[ -n "${name}" ]]; then
            printf "${BOX_V} %-20s${BOX_V} %-10s${BOX_V}\n" "${name}" "${value}"
        fi
    done <<< "${metrics}"

    echo "${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}"
}

# ============================================================================
# Score Visualization
# ============================================================================

# Display score gauge
display_score_gauge() {
    local score="${1:-70}"

    local status="GOOD"
    local color="${C_GREEN}"

    if [[ ${score} -ge 90 ]]; then
        status="EXCELLENT"
        color="${C_CYAN}"
    elif [[ ${score} -ge 70 ]]; then
        status="GOOD"
        color="${C_GREEN}"
    elif [[ ${score} -ge 50 ]]; then
        status="WARNING"
        color="${C_YELLOW}"
    elif [[ ${score} -ge 30 ]]; then
        status="CRITICAL"
        color="${C_RED}"
    else
        status="BLOCKED"
        color="${C_RED}${C_BOLD}"
    fi

    # Create gauge
    local filled=$((score / 5))  # 20 chars = 100
    local empty=$((20 - filled))

    local gauge=""
    for ((i=0; i<filled; i++)); do
        gauge+="━"
    done
    for ((i=0; i<empty; i++)); do
        gauge+="─"
    done

    echo -e "\n${C_BOLD}WoW Score:${C_RESET} ${color}${score}/100${C_RESET}"
    echo -e "[${color}${gauge}${C_RESET}] ${color}${status}${C_RESET}\n"

    # Thresholds
    echo -e "${C_DIM}Thresholds: 90+ Excellent | 70+ Good | 50+ Warning | 30+ Critical | <30 Blocked${C_RESET}"
}

# ============================================================================
# Alert Display
# ============================================================================

# Display alert box
display_alert() {
    local level="$1"
    local title="$2"
    local message="$3"

    local icon=""
    local color=""

    case "${level}" in
        error)
            icon="✗"
            color="${C_RED}"
            ;;
        warning)
            icon="⚠️"
            color="${C_YELLOW}"
            ;;
        info)
            icon="ℹ️"
            color="${C_BLUE}"
            ;;
        success)
            icon="✓"
            color="${C_GREEN}"
            ;;
        *)
            icon="•"
            color="${C_RESET}"
            ;;
    esac

    cat <<EOF

${color}${C_BOLD}${BOX_TL}${BOX_H}${BOX_H}${BOX_H} ${icon} ${title} ${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${C_RESET}
${color}${BOX_V}${C_RESET} ${message}
${color}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${C_RESET}

EOF
}

# ============================================================================
# Helper Functions
# ============================================================================

# Center text in a given width
_display_center_text() {
    local text="$1"
    local width="${2:-40}"

    local text_len=${#text}
    local padding=$(( (width - text_len) / 2 ))

    printf "%*s%s%*s" ${padding} "" "${text}" ${padding} ""
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Display v${DISPLAY_VERSION} - Self Test"
    echo "==========================================="
    echo ""

    # Test banner
    display_banner "4.1.0" "85" "excellent"

    # Test statusline
    display_statusline "70" "3" "session_123"
    echo ""

    # Test feedback
    display_feedback "File Write" "success" "Created test.txt"
    display_feedback "Bash Command" "warning" "Suspicious pattern detected"
    display_feedback "Edit Operation" "error" "Permission denied"
    display_feedback "Delete Operation" "blocked" "Dangerous operation"
    echo ""

    # Test progress
    for i in {1..10}; do
        display_progress $i 10 "Processing"
        sleep 0.1
    done
    echo ""

    # Test score gauge
    display_score_gauge 75
    display_score_gauge 45
    display_score_gauge 95
    echo ""

    # Test alert
    display_alert "error" "Security Violation" "Attempted write to /etc/passwd blocked"
    display_alert "warning" "Score Warning" "Your WoW score has dropped below 50"
    display_alert "success" "Operation Complete" "All tests passed successfully"

    echo "All display tests completed! ✓"
fi
