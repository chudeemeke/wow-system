#!/bin/bash
# WoW System - Scoring Engine
# Calculates and manages WoW scores based on behavior patterns
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Transparent scoring: Clear rules for score changes
# - Decay over time: Scores naturally improve
# - Threshold-based actions: Warn and block at configurable levels
# - History tracking: Monitor trends over time

# Prevent double-sourcing
if [[ -n "${WOW_SCORING_ENGINE_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_SCORING_ENGINE_LOADED=1

# Source dependencies
_SCORING_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCORING_ENGINE_DIR}/../core/utils.sh"
source "${_SCORING_ENGINE_DIR}/../core/session-manager.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly SCORE_VERSION="1.0.0"

# Default scoring parameters
readonly SCORE_DEFAULT=70
readonly SCORE_MIN=0
readonly SCORE_MAX=100

# Score adjustments
readonly SCORE_VIOLATION_PENALTY=10
readonly SCORE_GOOD_PRACTICE_REWARD=5
readonly SCORE_WARNING_REWARD=2

# Thresholds
readonly SCORE_THRESHOLD_EXCELLENT=90
readonly SCORE_THRESHOLD_GOOD=70
readonly SCORE_THRESHOLD_WARN=50
readonly SCORE_THRESHOLD_BLOCK=30

# Decay parameters
readonly SCORE_DECAY_RATE=0.95    # 5% improvement per period
readonly SCORE_DECAY_INTERVAL=300  # 5 minutes in seconds

# ============================================================================
# Initialization
# ============================================================================

# Initialize scoring engine
score_init() {
    wow_debug "Initializing scoring engine v${SCORE_VERSION}"

    # Initialize score if not set
    local current_score
    current_score=$(session_get_metric "wow_score" "")

    if [[ -z "${current_score}" ]]; then
        session_update_metric "wow_score" "${SCORE_DEFAULT}"
        session_update_metric "score_initialized_at" "$(wow_timestamp)"
        wow_debug "Initialized score to ${SCORE_DEFAULT}"
    fi

    # Initialize history
    session_update_metric "score_changes" "0"

    wow_debug "Scoring engine initialized"
    return 0
}

# ============================================================================
# Score Getters
# ============================================================================

# Get current score
score_get() {
    local score
    score=$(session_get_metric "wow_score" "${SCORE_DEFAULT}")
    echo "${score}"
}

# Get score status (excellent/good/warn/block)
score_get_status() {
    local score
    score=$(score_get)

    if [[ ${score} -ge ${SCORE_THRESHOLD_EXCELLENT} ]]; then
        echo "excellent"
    elif [[ ${score} -ge ${SCORE_THRESHOLD_GOOD} ]]; then
        echo "good"
    elif [[ ${score} -ge ${SCORE_THRESHOLD_WARN} ]]; then
        echo "warn"
    elif [[ ${score} -ge ${SCORE_THRESHOLD_BLOCK} ]]; then
        echo "critical"
    else
        echo "blocked"
    fi
}

# Check if score is in warning range
score_is_warning() {
    local score
    score=$(score_get)

    [[ ${score} -lt ${SCORE_THRESHOLD_GOOD} ]] && [[ ${score} -ge ${SCORE_THRESHOLD_WARN} ]]
}

# Check if score should trigger block
score_is_blocked() {
    local score
    score=$(score_get)

    [[ ${score} -lt ${SCORE_THRESHOLD_BLOCK} ]]
}

# ============================================================================
# Score Modifiers
# ============================================================================

# Apply score penalty for violation
score_penalty() {
    local penalty="${1:-${SCORE_VIOLATION_PENALTY}}"
    local reason="${2:-violation}"

    local current_score
    current_score=$(score_get)

    local new_score=$((current_score - penalty))

    # Enforce minimum
    if [[ ${new_score} -lt ${SCORE_MIN} ]]; then
        new_score=${SCORE_MIN}
    fi

    # Update score
    session_update_metric "wow_score" "${new_score}"

    # Track change
    _score_track_change "${current_score}" "${new_score}" "penalty" "${reason}"

    wow_warn "Score penalty: -${penalty} (${reason}). New score: ${new_score}"
    return 0
}

# Apply score reward for good practice
score_reward() {
    local reward="${1:-${SCORE_GOOD_PRACTICE_REWARD}}"
    local reason="${2:-good_practice}"

    local current_score
    current_score=$(score_get)

    local new_score=$((current_score + reward))

    # Enforce maximum
    if [[ ${new_score} -gt ${SCORE_MAX} ]]; then
        new_score=${SCORE_MAX}
    fi

    # Update score
    session_update_metric "wow_score" "${new_score}"

    # Track change
    _score_track_change "${current_score}" "${new_score}" "reward" "${reason}"

    wow_success "Score reward: +${reward} (${reason}). New score: ${new_score}"
    return 0
}

# Set score directly (with validation)
score_set() {
    local new_score="$1"
    local reason="${2:-manual_adjustment}"

    # Validate numeric
    if ! wow_is_number "${new_score}"; then
        wow_error "Invalid score: ${new_score}"
        return 1
    fi

    # Enforce bounds
    if [[ ${new_score} -lt ${SCORE_MIN} ]]; then
        new_score=${SCORE_MIN}
    elif [[ ${new_score} -gt ${SCORE_MAX} ]]; then
        new_score=${SCORE_MAX}
    fi

    local current_score
    current_score=$(score_get)

    # Update score
    session_update_metric "wow_score" "${new_score}"

    # Track change
    _score_track_change "${current_score}" "${new_score}" "set" "${reason}"

    wow_info "Score set: ${new_score} (${reason})"
    return 0
}

# Reset score to default
score_reset() {
    local reason="${1:-reset}"

    local current_score
    current_score=$(score_get)

    session_update_metric "wow_score" "${SCORE_DEFAULT}"

    # Track change
    _score_track_change "${current_score}" "${SCORE_DEFAULT}" "reset" "${reason}"

    wow_info "Score reset to ${SCORE_DEFAULT}"
    return 0
}

# ============================================================================
# Score Decay (Natural Improvement)
# ============================================================================

# Apply score decay (gradual improvement)
score_apply_decay() {
    local current_score
    current_score=$(score_get)

    # Only apply decay if score is below max
    if [[ ${current_score} -ge ${SCORE_MAX} ]]; then
        return 0
    fi

    # Check if decay interval has passed
    local last_decay
    last_decay=$(session_get_metric "last_decay_at" "0")
    local current_time
    current_time=$(date +%s)

    local time_diff=$((current_time - last_decay))

    if [[ ${time_diff} -lt ${SCORE_DECAY_INTERVAL} ]]; then
        return 0  # Not time for decay yet
    fi

    # Calculate improvement
    local deficit=$((SCORE_MAX - current_score))
    local improvement=$(awk "BEGIN {printf \"%.0f\", ${deficit} * (1 - ${SCORE_DECAY_RATE})}")

    # Ensure at least 1 point improvement if below max
    if [[ ${improvement} -lt 1 ]] && [[ ${current_score} -lt ${SCORE_MAX} ]]; then
        improvement=1
    fi

    local new_score=$((current_score + improvement))

    # Enforce maximum
    if [[ ${new_score} -gt ${SCORE_MAX} ]]; then
        new_score=${SCORE_MAX}
    fi

    # Update score
    session_update_metric "wow_score" "${new_score}"
    session_update_metric "last_decay_at" "${current_time}"

    # Track change
    _score_track_change "${current_score}" "${new_score}" "decay" "natural_improvement"

    wow_debug "Score decay applied: +${improvement}. New score: ${new_score}"
    return 0
}

# ============================================================================
# Score History & Trends
# ============================================================================

# Track score change (private)
_score_track_change() {
    local old_score="$1"
    local new_score="$2"
    local change_type="$3"
    local reason="$4"

    # Increment change counter
    session_increment_metric "score_changes"

    # Record change event
    local change_count
    change_count=$(session_get_metric "score_changes")

    local change_data="old=${old_score}|new=${new_score}|type=${change_type}|reason=${reason}"
    session_track_event "score_change_${change_count}" "${change_data}"

    return 0
}

# Get score trend (improving/stable/declining)
score_get_trend() {
    local changes
    changes=$(session_get_metric "score_changes" "0")

    if [[ ${changes} -lt 2 ]]; then
        echo "insufficient_data"
        return 0
    fi

    # Get last few changes
    local events
    events=$(session_get_events | grep "score_change" | tail -5)

    # Count improvements vs declines
    local improvements=0
    local declines=0

    while IFS= read -r event; do
        if echo "${event}" | grep -q "old=[0-9]*|new=[0-9]*"; then
            local old=$(echo "${event}" | grep -oP "old=\K[0-9]+")
            local new=$(echo "${event}" | grep -oP "new=\K[0-9]+")

            if [[ ${new} -gt ${old} ]]; then
                ((improvements++))
            elif [[ ${new} -lt ${old} ]]; then
                ((declines++))
            fi
        fi
    done <<< "${events}"

    # Determine trend
    if [[ ${improvements} -gt ${declines} ]]; then
        echo "improving"
    elif [[ ${declines} -gt ${improvements} ]]; then
        echo "declining"
    else
        echo "stable"
    fi
}

# ============================================================================
# Score Reporting
# ============================================================================

# Get score summary
score_summary() {
    local score
    score=$(score_get)
    local status
    status=$(score_get_status)
    local trend
    trend=$(score_get_trend)
    local changes
    changes=$(session_get_metric "score_changes" "0")

    cat <<EOF
WoW Score Summary
==================
Current Score: ${score}/100
Status: ${status}
Trend: ${trend}
Total Changes: ${changes}

Thresholds:
  Excellent: ${SCORE_THRESHOLD_EXCELLENT}+
  Good: ${SCORE_THRESHOLD_GOOD}+
  Warning: ${SCORE_THRESHOLD_WARN}+
  Critical: ${SCORE_THRESHOLD_BLOCK}+
  Blocked: <${SCORE_THRESHOLD_BLOCK}
EOF
}

# Get score as emoji indicator
score_get_emoji() {
    local status
    status=$(score_get_status)

    case "${status}" in
        excellent) echo "✨" ;;
        good) echo "✓" ;;
        warn) echo "⚠️" ;;
        critical) echo "🔴" ;;
        blocked) echo "☠️" ;;
        *) echo "?" ;;
    esac
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Scoring Engine v${SCORE_VERSION} - Self Test"
    echo "================================================="
    echo ""

    # Initialize
    score_init
    echo "✓ Initialized with default score: $(score_get)"

    # Apply penalty
    score_penalty 10 "test_violation"
    [[ "$(score_get)" == "60" ]] && echo "✓ Penalty applied correctly"

    # Apply reward
    score_reward 5 "test_good_practice"
    [[ "$(score_get)" == "65" ]] && echo "✓ Reward applied correctly"

    # Check status
    status=$(score_get_status)
    [[ "${status}" == "good" ]] && echo "✓ Status detection works: ${status}"

    # Check warning
    score_set 45 "test"
    score_is_warning && echo "✓ Warning detection works"

    # Check blocked
    score_set 25 "test"
    score_is_blocked && echo "✓ Block detection works"

    # Reset
    score_reset
    [[ "$(score_get)" == "${SCORE_DEFAULT}" ]] && echo "✓ Reset works"

    # Trend
    trend=$(score_get_trend)
    echo "✓ Trend calculation: ${trend}"

    echo ""
    score_summary

    echo ""
    echo "All tests passed! ✓"
fi
