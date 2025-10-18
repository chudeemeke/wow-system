#!/bin/bash
# WoW System - Score Display Module
# Displays violation information and score feedback
# Author: Chude <chude@emeke.org>
#
# Design Patterns:
# - Observer Pattern: Subscribes to violation events
# - Facade Pattern: Simplifies display operations
#
# SOLID Principles:
# - SRP: Only handles score visualization
# - OCP: Extensible for new display modes
# - DIP: Depends on scoring-engine abstraction

# Prevent double-sourcing
if [[ -n "${WOW_SCORE_DISPLAY_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_SCORE_DISPLAY_LOADED=1

# Source dependencies
_SCORE_DISPLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCORE_DISPLAY_DIR}/../core/utils.sh"
source "${_SCORE_DISPLAY_DIR}/display.sh"
source "${_SCORE_DISPLAY_DIR}/../core/scoring-engine.sh" 2>/dev/null || true
source "${_SCORE_DISPLAY_DIR}/../core/session-manager.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly SCORE_DISPLAY_VERSION="1.0.0"

# Configuration (can be overridden by config)
SCORE_DISPLAY_ENABLED="${SCORE_DISPLAY_ENABLED:-true}"
SCORE_DISPLAY_SHOW_GAUGE="${SCORE_DISPLAY_SHOW_GAUGE:-true}"
SCORE_DISPLAY_SHOW_HISTORY="${SCORE_DISPLAY_SHOW_HISTORY:-true}"
SCORE_DISPLAY_MAX_HISTORY="${SCORE_DISPLAY_MAX_HISTORY:-3}"

# ============================================================================
# Main Display Function
# ============================================================================

# Display violation information with score
# Args: violation_type, path, handler
score_display_violation() {
    local violation_type="${1:-unknown}"
    local path="${2:-}"
    local handler="${3:-unknown}"

    # Check if display is enabled
    if [[ "${SCORE_DISPLAY_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Get current score (default 70 if scoring engine not available)
    local score=70
    if type scoring_get_score &>/dev/null; then
        score=$(scoring_get_score 2>/dev/null || echo "70")
    fi

    # Determine status and color based on score
    local status="GOOD"
    local status_emoji="✓"
    local color="${C_GREEN}"

    if [[ ${score} -ge 90 ]]; then
        status="EXCELLENT"
        status_emoji="✨"
        color="${C_CYAN}"
    elif [[ ${score} -ge 70 ]]; then
        status="GOOD"
        status_emoji="✓"
        color="${C_GREEN}"
    elif [[ ${score} -ge 50 ]]; then
        status="WARNING"
        status_emoji="⚠️"
        color="${C_YELLOW}"
    elif [[ ${score} -ge 30 ]]; then
        status="CRITICAL"
        status_emoji="⚠️"
        color="${C_RED}"
    else
        status="BLOCKED"
        status_emoji="🚫"
        color="${C_RED}${C_BOLD}"
    fi

    # Get recent violations count
    local violations_count=0
    if type session_get_metric &>/dev/null; then
        violations_count=$(session_get_metric "violations" "0" 2>/dev/null || echo "0")
    fi

    # Sanitize inputs for display
    violation_type=$(echo "${violation_type}" | tr -cd '[:alnum:]_ -' | cut -c1-50)
    path=$(echo "${path}" | cut -c1-60)  # Truncate long paths
    handler=$(echo "${handler}" | tr -cd '[:alnum:]_.-' | cut -c1-30)

    # Build the display
    cat <<EOF

${C_RED}${C_BOLD}╔══════════════════════════════════════════════════════╗${C_RESET}
${C_RED}${C_BOLD}║  ⚠️  SECURITY VIOLATION DETECTED                     ║${C_RESET}
${C_RED}${C_BOLD}╠══════════════════════════════════════════════════════╣${C_RESET}
${C_BOLD}║  WoW Score: ${color}${score}/100${C_RESET}                                  ${C_BOLD}║${C_RESET}
${C_BOLD}║  Status: ${status_emoji} ${color}${status}${C_RESET}                                   ${C_BOLD}║${C_RESET}
${C_BOLD}║                                                      ║${C_RESET}
EOF

    # Display score gauge if enabled
    if [[ "${SCORE_DISPLAY_SHOW_GAUGE}" == "true" ]]; then
        local filled=$((score / 5))  # 20 chars = 100
        local empty=$((20 - filled))

        local gauge=""
        for ((i=0; i<filled; i++)); do
            gauge+="█"
        done
        for ((i=0; i<empty; i++)); do
            gauge+="░"
        done

        cat <<EOF
${C_BOLD}║  Score Gauge:                                        ║${C_RESET}
${C_BOLD}║  [${color}${gauge}${C_RESET}${C_BOLD}] ${score}%                        ║${C_RESET}
${C_BOLD}║                                                      ║${C_RESET}
EOF
    fi

    # Display violation details
    cat <<EOF
${C_BOLD}║  Violation: ${C_RED}${violation_type}${C_RESET}                               ${C_BOLD}║${C_RESET}
${C_BOLD}║  Path: ${C_YELLOW}${path}${C_RESET}                                   ${C_BOLD}║${C_RESET}
${C_BOLD}║  Handler: ${C_CYAN}${handler}${C_RESET}                                 ${C_BOLD}║${C_RESET}
${C_BOLD}║                                                      ║${C_RESET}
EOF

    # Display recent violations history if enabled
    if [[ "${SCORE_DISPLAY_SHOW_HISTORY}" == "true" ]] && [[ ${violations_count} -gt 0 ]]; then
        cat <<EOF
${C_BOLD}║  Recent Violations: ${C_YELLOW}${violations_count}${C_RESET}${C_BOLD}                             ║${C_RESET}
EOF
    fi

    # Close the box
    cat <<EOF
${C_BOLD}╚══════════════════════════════════════════════════════╝${C_RESET}

EOF
}

# Display score summary (compact version)
score_display_summary() {
    local score="${1:-70}"

    # Determine status
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

    echo -e "${C_BOLD}WoW Score:${C_RESET} ${color}${score}/100 (${status})${C_RESET}"
}

# Display score change notification
score_display_change() {
    local old_score="${1:-70}"
    local new_score="${2:-70}"
    local reason="${3:-score changed}"

    local diff=$((new_score - old_score))
    local direction="→"
    local color="${C_RESET}"

    if [[ ${diff} -gt 0 ]]; then
        direction="▲"
        color="${C_GREEN}"
    elif [[ ${diff} -lt 0 ]]; then
        direction="▼"
        color="${C_RED}"
        diff=$((diff * -1))  # Make positive for display
    fi

    echo -e "${C_BOLD}Score Update:${C_RESET} ${old_score} ${color}${direction}${diff}${C_RESET} ${new_score} (${reason})"
}

# ============================================================================
# Configuration
# ============================================================================

# Load configuration from config file if available
score_display_load_config() {
    if type config_get &>/dev/null; then
        SCORE_DISPLAY_ENABLED=$(config_get "ui.score_display.enabled" "true")
        SCORE_DISPLAY_SHOW_GAUGE=$(config_get "ui.score_display.show_gauge" "true")
        SCORE_DISPLAY_SHOW_HISTORY=$(config_get "ui.score_display.show_history" "true")
        SCORE_DISPLAY_MAX_HISTORY=$(config_get "ui.score_display.max_history_items" "3")
    fi
}

# Initialize score display
score_display_init() {
    score_display_load_config 2>/dev/null || true
    wow_debug "Score display initialized (enabled: ${SCORE_DISPLAY_ENABLED})"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Score Display v${SCORE_DISPLAY_VERSION} - Self Test"
    echo "========================================================="
    echo ""

    # Test 1: Display violation with default score
    echo "Test 1: Basic violation display"
    score_display_violation "path_traversal" "/tmp/suspicious-file" "read-handler"

    # Test 2: Display with different scores
    echo "Test 2: Warning level"
    if type scoring_set_score &>/dev/null; then
        scoring_init 2>/dev/null || true
        scoring_set_score 55 2>/dev/null || true
    fi
    score_display_violation "command_injection" "/tmp/dangerous-script" "bash-handler"

    # Test 3: Critical level
    echo "Test 3: Critical level"
    if type scoring_set_score &>/dev/null; then
        scoring_set_score 35 2>/dev/null || true
    fi
    score_display_violation "credential_exposure" "/tmp/config-file" "read-handler"

    # Test 4: Summary display
    echo "Test 4: Score summary"
    score_display_summary 85
    score_display_summary 45
    score_display_summary 25

    # Test 5: Score change
    echo ""
    echo "Test 5: Score changes"
    score_display_change 70 60 "security violation"
    score_display_change 60 75 "good practice"
    score_display_change 75 75 "no change"

    echo ""
    echo "All self-tests completed! ✓"
fi
