#!/bin/bash
# WoW System - Content Correlator
# Detects split attacks by correlating operations across a session
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Sliding Window: Track recent operations for correlation
# - Pattern Matching: Detect write-then-execute, download-then-execute
# - Risk Scoring: Graduated response based on pattern severity
# - Defense in Depth: Works with heuristic detector
#
# Attack Patterns Detected:
# 1. Write-then-Execute: Write script to temp, then run it
# 2. Download-then-Execute: Curl/wget file, then execute
# 3. Staged Building: Build dangerous command across operations
# 4. Config Poisoning: Write to shell configs, SSH configs

# Prevent double-sourcing
if [[ -n "${WOW_CORRELATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CORRELATOR_LOADED=1

# ============================================================================
# Configuration
# ============================================================================

# Window settings
readonly CORRELATOR_WINDOW_SIZE=50          # Max operations to track
readonly CORRELATOR_WINDOW_TTL=1800         # 30 minutes in seconds

# Risk thresholds
readonly CORRELATOR_THRESHOLD_BLOCK=70      # Block if risk >= this
readonly CORRELATOR_THRESHOLD_WARN=40       # Warn if risk >= this

# ============================================================================
# State Management
# ============================================================================

# Operation tracking (arrays for FIFO queue)
declare -ga _CORRELATOR_TOOLS=()
declare -ga _CORRELATOR_TARGETS=()
declare -ga _CORRELATOR_CONTENTS=()
declare -ga _CORRELATOR_TIMESTAMPS=()

# Detection state
declare -g _CORRELATOR_LAST_REASON=""
declare -g _CORRELATOR_LAST_RISK=0

# ============================================================================
# Dangerous Paths (SSOT)
# ============================================================================

# Temp/writable directories (high risk for write-then-execute)
readonly -a CORRELATOR_TEMP_PATHS=(
    '/tmp/'
    '/var/tmp/'
    '/dev/shm/'
    '/run/'
)

# Config files (config poisoning targets)
readonly -a CORRELATOR_CONFIG_PATTERNS=(
    '.bashrc'
    '.bash_profile'
    '.profile'
    '.zshrc'
    '.zprofile'
    '.ssh/config'
    '.ssh/authorized_keys'
    '.gitconfig'
    '.npmrc'
    '.pypirc'
)

# Download commands
readonly -a CORRELATOR_DOWNLOAD_CMDS=(
    'curl'
    'wget'
    'fetch'
    'aria2c'
)

# ============================================================================
# Initialization
# ============================================================================

correlator_init() {
    _CORRELATOR_TOOLS=()
    _CORRELATOR_TARGETS=()
    _CORRELATOR_CONTENTS=()
    _CORRELATOR_TIMESTAMPS=()
    _CORRELATOR_LAST_REASON=""
    _CORRELATOR_LAST_RISK=0
}

correlator_reset() {
    correlator_init
}

# ============================================================================
# Operation Tracking
# ============================================================================

# Track an operation for correlation
# Usage: correlator_track "Tool" "target_path_or_command" "content"
correlator_track() {
    local tool="$1"
    local target="$2"
    local content="${3:-}"
    local timestamp
    timestamp=$(date +%s)

    # If Bash command with redirect, also track as a Write
    if [[ "${tool}" == "Bash" ]] && [[ "${target}" =~ \>[[:space:]]*(/[^[:space:]]+) ]]; then
        local redirect_path="${BASH_REMATCH[1]}"
        _CORRELATOR_TOOLS+=("Write")
        _CORRELATOR_TARGETS+=("${redirect_path}")
        _CORRELATOR_CONTENTS+=("(redirect)")
        _CORRELATOR_TIMESTAMPS+=("${timestamp}")
    fi

    # Add to tracking arrays
    _CORRELATOR_TOOLS+=("${tool}")
    _CORRELATOR_TARGETS+=("${target}")
    _CORRELATOR_CONTENTS+=("${content}")
    _CORRELATOR_TIMESTAMPS+=("${timestamp}")

    # Enforce window size limit
    while [[ ${#_CORRELATOR_TOOLS[@]} -gt ${CORRELATOR_WINDOW_SIZE} ]]; do
        _CORRELATOR_TOOLS=("${_CORRELATOR_TOOLS[@]:1}")
        _CORRELATOR_TARGETS=("${_CORRELATOR_TARGETS[@]:1}")
        _CORRELATOR_CONTENTS=("${_CORRELATOR_CONTENTS[@]:1}")
        _CORRELATOR_TIMESTAMPS=("${_CORRELATOR_TIMESTAMPS[@]:1}")
    done
}

# Expire operations older than specified seconds
correlator_expire_old() {
    local max_age="${1:-${CORRELATOR_WINDOW_TTL}}"
    local now
    now=$(date +%s)
    local cutoff=$((now - max_age))

    local new_tools=()
    local new_targets=()
    local new_contents=()
    local new_timestamps=()

    for i in "${!_CORRELATOR_TIMESTAMPS[@]}"; do
        if [[ ${_CORRELATOR_TIMESTAMPS[$i]} -ge ${cutoff} ]]; then
            new_tools+=("${_CORRELATOR_TOOLS[$i]}")
            new_targets+=("${_CORRELATOR_TARGETS[$i]}")
            new_contents+=("${_CORRELATOR_CONTENTS[$i]}")
            new_timestamps+=("${_CORRELATOR_TIMESTAMPS[$i]}")
        fi
    done

    _CORRELATOR_TOOLS=("${new_tools[@]}")
    _CORRELATOR_TARGETS=("${new_targets[@]}")
    _CORRELATOR_CONTENTS=("${new_contents[@]}")
    _CORRELATOR_TIMESTAMPS=("${new_timestamps[@]}")
}

# Get current window size
correlator_get_window_size() {
    echo "${#_CORRELATOR_TOOLS[@]}"
}

# ============================================================================
# Path Utilities
# ============================================================================

# Check if path is in temp directory
_is_temp_path() {
    local path="$1"
    for temp in "${CORRELATOR_TEMP_PATHS[@]}"; do
        if [[ "${path}" == ${temp}* ]]; then
            return 0
        fi
    done
    return 1
}

# Check if path is a config file
_is_config_file() {
    local path="$1"
    for pattern in "${CORRELATOR_CONFIG_PATTERNS[@]}"; do
        if [[ "${path}" == *"${pattern}"* ]]; then
            return 0
        fi
    done
    return 1
}

# Extract path from command
_extract_path_from_command() {
    local cmd="$1"
    local path=""

    # source /path or . /path
    if [[ "${cmd}" =~ ^(source|\.)[[:space:]]+([^[:space:]]+) ]]; then
        path="${BASH_REMATCH[2]}"
    # bash /path or sh /path
    elif [[ "${cmd}" =~ ^(bash|sh)[[:space:]]+([^[:space:]]+) ]]; then
        path="${BASH_REMATCH[2]}"
    # chmod +x /path
    elif [[ "${cmd}" =~ chmod[[:space:]]+.*[[:space:]]+([^[:space:]]+)$ ]]; then
        path="${BASH_REMATCH[1]}"
    # Direct execution /path
    elif [[ "${cmd}" =~ ^(/[^[:space:]]+) ]]; then
        path="${BASH_REMATCH[1]}"
    # curl -o /path or wget -O /path
    elif [[ "${cmd}" =~ (-o|-O)[[:space:]]+([^[:space:]]+) ]]; then
        path="${BASH_REMATCH[2]}"
    # curl > /path
    elif [[ "${cmd}" =~ \>[[:space:]]*([^[:space:]]+) ]]; then
        path="${BASH_REMATCH[1]}"
    fi

    echo "${path}"
}

# Check if command is a download
_is_download_command() {
    local cmd="$1"
    for dl in "${CORRELATOR_DOWNLOAD_CMDS[@]}"; do
        if [[ "${cmd}" == ${dl}* ]] || [[ "${cmd}" == *" ${dl} "* ]]; then
            return 0
        fi
    done
    return 1
}

# ============================================================================
# Correlation Detection
# ============================================================================

# Check if current operation correlates with previous (dangerous pattern)
# Returns: 0 if safe, 1 if dangerous correlation detected
correlator_check() {
    local tool="$1"
    local operation="$2"

    _CORRELATOR_LAST_REASON=""
    _CORRELATOR_LAST_RISK=0

    # Extract target path from operation
    local target_path
    target_path=$(_extract_path_from_command "${operation}")

    # Check for write-then-execute pattern
    if _check_write_then_execute "${tool}" "${operation}" "${target_path}"; then
        return 1  # Dangerous
    fi

    # Check for download-then-execute pattern
    if _check_download_then_execute "${tool}" "${operation}" "${target_path}"; then
        return 1  # Dangerous
    fi

    # Check for staged variable building
    if _check_staged_building "${tool}" "${operation}"; then
        return 1  # Dangerous
    fi

    return 0  # Safe
}

# Check write-then-execute pattern
_check_write_then_execute() {
    local tool="$1"
    local operation="$2"
    local target_path="$3"

    # Only check execution operations
    if [[ "${tool}" != "Bash" ]]; then
        return 1
    fi

    # Check if this is an execution command
    local is_execution=false
    if [[ "${operation}" =~ ^(source|\.)[[:space:]] ]] || \
       [[ "${operation}" =~ ^(bash|sh)[[:space:]] ]] || \
       [[ "${operation}" =~ ^/ ]]; then
        is_execution=true
    fi

    if [[ "${is_execution}" != "true" ]]; then
        return 1
    fi

    # Check if target was recently written
    if [[ -z "${target_path}" ]]; then
        return 1
    fi

    for i in "${!_CORRELATOR_TOOLS[@]}"; do
        if [[ "${_CORRELATOR_TOOLS[$i]}" == "Write" ]]; then
            local written_path="${_CORRELATOR_TARGETS[$i]}"

            # Check for exact match or pattern match
            if [[ "${written_path}" == "${target_path}" ]]; then
                # Check if it's a temp path (high risk)
                if _is_temp_path "${written_path}"; then
                    _CORRELATOR_LAST_RISK=90
                    _CORRELATOR_LAST_REASON="Write-then-execute: Script written to ${written_path} is now being executed"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

# Check download-then-execute pattern
_check_download_then_execute() {
    local tool="$1"
    local operation="$2"
    local target_path="$3"

    # Only check Bash execution
    if [[ "${tool}" != "Bash" ]]; then
        return 1
    fi

    # Check if target was recently downloaded
    if [[ -z "${target_path}" ]]; then
        return 1
    fi

    for i in "${!_CORRELATOR_TOOLS[@]}"; do
        if [[ "${_CORRELATOR_TOOLS[$i]}" == "Bash" ]]; then
            local prev_cmd="${_CORRELATOR_TARGETS[$i]}"

            if _is_download_command "${prev_cmd}"; then
                # Extract download destination
                local download_path
                download_path=$(_extract_path_from_command "${prev_cmd}")

                if [[ -n "${download_path}" ]] && [[ "${download_path}" == "${target_path}" ]]; then
                    _CORRELATOR_LAST_RISK=95
                    _CORRELATOR_LAST_REASON="Download-then-execute: File downloaded to ${download_path} is now being executed"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

# Check staged variable building
_check_staged_building() {
    local tool="$1"
    local operation="$2"

    # Only check Bash operations with eval or array execution
    if [[ "${tool}" != "Bash" ]]; then
        return 1
    fi

    # Check for eval with variables
    if [[ "${operation}" =~ eval[[:space:]] ]]; then
        # Count recent variable assignments
        local var_count=0
        for i in "${!_CORRELATOR_TOOLS[@]}"; do
            if [[ "${_CORRELATOR_TOOLS[$i]}" == "Bash" ]]; then
                local prev_cmd="${_CORRELATOR_TARGETS[$i]}"
                # Check for variable assignment
                if [[ "${prev_cmd}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
                    ((var_count++))
                fi
            fi
        done

        if [[ ${var_count} -ge 3 ]]; then
            _CORRELATOR_LAST_RISK=75
            _CORRELATOR_LAST_REASON="Staged building: Multiple variable assignments followed by eval execution"
            return 0
        fi
    fi

    # Check for array execution
    if [[ "${operation}" =~ \"\$\{[a-zA-Z_]+\[@\]\}\" ]]; then
        # Count recent array operations
        local array_ops=0
        for i in "${!_CORRELATOR_TOOLS[@]}"; do
            if [[ "${_CORRELATOR_TOOLS[$i]}" == "Bash" ]]; then
                local prev_cmd="${_CORRELATOR_TARGETS[$i]}"
                if [[ "${prev_cmd}" =~ \+= ]] || [[ "${prev_cmd}" =~ =\(\) ]]; then
                    ((array_ops++))
                fi
            fi
        done

        if [[ ${array_ops} -ge 3 ]]; then
            _CORRELATOR_LAST_RISK=75
            _CORRELATOR_LAST_REASON="Staged building: Array built across operations then executed"
            return 0
        fi
    fi

    return 1
}

# ============================================================================
# Risk Assessment
# ============================================================================

# Get risk score for executing a specific path
correlator_get_execution_risk() {
    local path="$1"
    local risk=0

    # System binaries - low risk
    if [[ "${path}" == /usr/bin/* ]] || [[ "${path}" == /bin/* ]]; then
        echo "10"
        return
    fi

    # Check if recently written
    for i in "${!_CORRELATOR_TOOLS[@]}"; do
        if [[ "${_CORRELATOR_TOOLS[$i]}" == "Write" ]]; then
            if [[ "${_CORRELATOR_TARGETS[$i]}" == "${path}" ]]; then
                if _is_temp_path "${path}"; then
                    risk=90
                else
                    risk=60
                fi
                break
            fi
        fi
    done

    # Check if recently downloaded
    for i in "${!_CORRELATOR_TOOLS[@]}"; do
        if [[ "${_CORRELATOR_TOOLS[$i]}" == "Bash" ]]; then
            local prev_cmd="${_CORRELATOR_TARGETS[$i]}"
            if _is_download_command "${prev_cmd}"; then
                local download_path
                download_path=$(_extract_path_from_command "${prev_cmd}")
                if [[ "${download_path}" == "${path}" ]]; then
                    risk=95
                    break
                fi
            fi
        fi
    done

    echo "${risk}"
}

# Get risk assessment for a write operation (config poisoning)
correlator_get_risk() {
    local tool="$1"
    local target="$2"

    if [[ "${tool}" == "Write" ]] && _is_config_file "${target}"; then
        echo "config_poisoning:85:Modifying shell/SSH config file"
        return
    fi

    echo "none:0:No special risk"
}

# Get reason for last correlation detection
correlator_get_reason() {
    echo "${_CORRELATOR_LAST_REASON}"
}

# Get risk score for last correlation
correlator_get_risk_score() {
    echo "${_CORRELATOR_LAST_RISK}"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Content Correlator - Self Test"
    echo "==============================="
    echo ""

    correlator_init

    # Test 1: Write-then-execute detection
    echo "Test 1: Write-then-execute"
    correlator_track "Write" "/tmp/test.sh" "echo hello"
    if ! correlator_check "Bash" "bash /tmp/test.sh"; then
        echo "  PASS: Detected write-then-execute"
        echo "  Reason: $(correlator_get_reason)"
    else
        echo "  FAIL: Should have detected pattern"
    fi
    echo ""

    # Test 2: Safe execution
    correlator_reset
    echo "Test 2: Safe system binary"
    if correlator_check "Bash" "/usr/bin/ls"; then
        echo "  PASS: Allowed system binary"
    else
        echo "  FAIL: Should allow system binary"
    fi
    echo ""

    # Test 3: Config poisoning detection
    correlator_reset
    echo "Test 3: Config poisoning"
    result=$(correlator_get_risk "Write" "/home/user/.bashrc")
    if [[ "${result}" == *"config_poisoning"* ]]; then
        echo "  PASS: Detected config poisoning risk"
    else
        echo "  FAIL: Should detect config poisoning"
    fi
    echo ""

    echo "Self-test complete"
fi
