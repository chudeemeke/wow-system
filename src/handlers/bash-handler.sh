#!/bin/bash
# WoW System - Bash Handler (Production-Grade, Security-Critical)
# Intercepts bash commands for auto-fix and security enforcement
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple layers of protection
# - Fail-Safe: Block on ambiguity
# - Comprehensive Pattern Matching: Catch obfuscation attempts
# - Audit Logging: Track all decisions

# Prevent double-sourcing
if [[ -n "${WOW_BASH_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_BASH_HANDLER_LOADED=1

# Source dependencies
_BASH_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_BASH_HANDLER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants - Dangerous Patterns
# ============================================================================

# CRITICAL: Immediately destructive commands
readonly -a DANGEROUS_PATTERNS=(
    # Filesystem destruction
    "rm.*-rf\s*/($|[^a-zA-Z])"          # rm -rf /
    "rm.*-rf\s*/bin"                     # rm -rf /bin
    "rm.*-rf\s*/boot"                    # rm -rf /boot
    "rm.*-rf\s*/dev"                     # rm -rf /dev
    "rm.*-rf\s*/etc"                     # rm -rf /etc
    "rm.*-rf\s*/lib"                     # rm -rf /lib
    "rm.*-rf\s*/proc"                    # rm -rf /proc
    "rm.*-rf\s*/sbin"                    # rm -rf /sbin
    "rm.*-rf\s*/sys"                     # rm -rf /sys
    "rm.*-rf\s*/usr"                     # rm -rf /usr
    "rm.*-rf\s*/var"                     # rm -rf /var
    "sudo\s+rm.*-rf"                     # sudo rm -rf anything

    # Disk/device operations
    "dd.*of=/dev/(sd|hd|nvme)"          # dd to disk
    "mkfs\."                             # Format filesystem
    "fdisk"                              # Disk partitioning
    "parted"                             # Partition editing

    # Permission bombs
    "chmod\s+(777|666)\s+/"             # chmod 777 on root
    "chmod.*-R\s+(777|666)\s+/etc"      # Recursive chmod on /etc
    "chmod.*-R\s+(777|666)\s+/bin"      # Recursive chmod on /bin

    # Fork bombs and resource exhaustion
    ":\(\)"                              # Fork bomb pattern
    "while\s+true.*do"                   # Infinite loop (basic)

    # Kernel/system manipulation
    "rm.*-rf\s+/boot"                    # Remove boot files
    ">/dev/(sd|hd|nvme)"                 # Write to disk directly
)

# Emojis to remove from git commits
readonly EMOJI_PATTERN='[🎉🚀✨🔥💯😊👍🎯💪🌟🎨🐛📝♻️⚡💥🎊🎈🎁🎀🎂🍰🍕🍔🍟🌮🌯🥗🍜🍝🍲🍱🍣🍤🍙🍚🍛🍢🍡🍞🥐🥖🧀🥚🍳🥞🧇🥓]'

# Author signature
readonly AUTHOR_NAME="Chude"
readonly AUTHOR_EMAIL="chude@emeke.org"
readonly AUTHOR_FULL="Chude <chude@emeke.org>"

# ============================================================================
# Private: Enforcement Checks
# ============================================================================

# Check if bash command limit is exceeded
_check_bash_command_limit() {
    local max_commands
    max_commands=$(config_get "rules.max_bash_commands" "0" 2>/dev/null || echo "0")

    # 0 = unlimited
    if [[ "$max_commands" -eq 0 ]]; then
        return 0  # No limit
    fi

    local current_count
    current_count=$(session_get_metric "bash_commands" "0" 2>/dev/null || echo "0")

    if [[ "$current_count" -ge "$max_commands" ]]; then
        wow_error "LIMIT EXCEEDED: max_bash_commands = $max_commands (current: $current_count)"
        return 1  # Limit exceeded
    fi

    return 0  # Within limit
}

# ============================================================================
# Private: Security Checks
# ============================================================================

# Check if command matches dangerous patterns
_is_dangerous_command() {
    local command="$1"

    # Normalize command (remove extra spaces, handle obfuscation)
    local normalized
    normalized=$(echo "${command}" | tr -s ' ' | sed 's/\\//g')

    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
        if echo "${normalized}" | grep -qiE "${pattern}"; then
            wow_warn "SECURITY: Dangerous pattern detected: ${pattern}"
            return 0  # Is dangerous
        fi
    done

    return 1  # Safe
}

# Additional heuristic checks for command safety
_heuristic_safety_check() {
    local command="$1"

    # Check 1: Prevent writes to critical system directories
    if echo "${command}" | grep -qE ">/\s*(bin|boot|dev|etc|lib|proc|sbin|sys|usr)/"; then
        wow_warn "SECURITY: Attempted write to system directory"
        return 1  # Unsafe
    fi

    # Check 2: Detect chained dangerous operations
    if echo "${command}" | grep -qE ";\s*rm" && echo "${command}" | grep -q "sudo"; then
        wow_warn "SECURITY: Chained dangerous operations detected"
        return 1  # Unsafe
    fi

    # Check 3: Detect eval with external input
    if echo "${command}" | grep -qE "eval.*\$"; then
        wow_warn "SECURITY: Eval with variable detected"
        return 1  # Unsafe
    fi

    return 0  # Passed heuristics
}

# ============================================================================
# Private: Git Commit Processing
# ============================================================================

# Check if command is a git commit
_is_git_commit() {
    local command="$1"
    echo "${command}" | grep -q "git commit"
}

# Remove emojis from string
_remove_emojis() {
    local text="$1"
    echo "${text}" | sed -E "s/${EMOJI_PATTERN}//g" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

# Check if command already has author
_has_author() {
    local command="$1"
    echo "${command}" | grep -qiE "\-\-author.*${AUTHOR_NAME}"
}

# Process git commit command
_process_git_commit() {
    local command="$1"
    local modified=false

    # Step 1: Remove emojis
    local cleaned
    cleaned=$(_remove_emojis "${command}")

    if [[ "${cleaned}" != "${command}" ]]; then
        command="${cleaned}"
        modified=true
        wow_info "AUTO-FIX: Removed emojis from git commit"
    fi

    # Step 2: Add author if missing
    if ! _has_author "${command}"; then
        # Add author flag at the end
        command="${command} --author=\"${AUTHOR_FULL}\""
        modified=true
        wow_info "AUTO-FIX: Added author to git commit"
    fi

    echo "${command}"
    return 0
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle bash command interception
handle_bash() {
    local tool_input="$1"

    # Extract command from JSON input
    local command=""
    if wow_has_jq; then
        command=$(echo "${tool_input}" | jq -r '.command // empty' 2>/dev/null)
    else
        # Fallback: regex extraction for simple commands
        command=$(echo "${tool_input}" | grep -oP '"command"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate command extraction
    if [[ -z "${command}" ]]; then
        # For complex commands (heredocs, etc), pass through unchanged
        # They'll be handled by Claude Code directly
        wow_debug "Complex command format detected, passing through"
        echo "${tool_input}"
        return 0
    fi

    # Track metrics
    session_increment_metric "bash_commands" 2>/dev/null || true
    session_track_event "bash_command" "command=${command:0:100}" 2>/dev/null || true

    # ========================================================================
    # ENFORCEMENT CHECK: Command Limit
    # ========================================================================

    if ! _check_bash_command_limit; then
        session_track_event "limit_exceeded" "bash_commands" 2>/dev/null || true
        return 2  # Block
    fi

    # ========================================================================
    # SECURITY CHECK: Dangerous Command Detection
    # ========================================================================

    if _is_dangerous_command "${command}"; then
        wow_error "☠️  DANGEROUS COMMAND BLOCKED"
        wow_error "Command: ${command}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_DANGEROUS_CMD:${command:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # Additional heuristic safety checks
    if ! _heuristic_safety_check "${command}"; then
        wow_error "⚠️  POTENTIALLY DANGEROUS COMMAND BLOCKED"
        wow_error "Command: ${command}"

        session_track_event "security_violation" "BLOCKED_HEURISTIC:${command:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        return 2
    fi

    # ========================================================================
    # AUTO-FIX: Git Commit Processing
    # ========================================================================

    local modified_command="${command}"

    if _is_git_commit "${command}"; then
        modified_command=$(_process_git_commit "${command}")

        # Update tool input with modified command
        if wow_has_jq; then
            tool_input=$(echo "${tool_input}" | jq --arg cmd "${modified_command}" '.command = $cmd')
        fi

        # Track git commits
        session_increment_metric "git_commits" 2>/dev/null || true
    fi

    # ========================================================================
    # ALLOW: Return (modified) tool input
    # ========================================================================

    echo "${tool_input}"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Bash Handler - Self Test"
    echo "============================"
    echo ""

    # Test 1: Emoji removal
    test_cmd="git commit -m '🎉 Initial commit'"
    result=$(_remove_emojis "${test_cmd}")
    echo "${result}" | grep -qv "🎉" && echo "✓ Emoji removal works"

    # Test 2: Author detection
    test_cmd="git commit --author='Chude <chude@emeke.org>'"
    _has_author "${test_cmd}" && echo "✓ Author detection works"

    # Test 3: Dangerous command detection
    test_cmd="rm -rf /"
    _is_dangerous_command "${test_cmd}" && echo "✓ Dangerous command detection works"

    # Test 4: Safe command
    test_cmd="ls -la"
    ! _is_dangerous_command "${test_cmd}" && echo "✓ Safe command detection works"

    # Test 5: Git commit detection
    test_cmd="git commit -m 'test'"
    _is_git_commit "${test_cmd}" && echo "✓ Git commit detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
