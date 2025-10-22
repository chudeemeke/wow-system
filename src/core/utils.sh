#!/bin/bash
# WoW System - Core Utilities
# Provides: Logging, validation, error handling, and common functions
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_UTILS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_UTILS_LOADED=1

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly WOW_VERSION="5.4.0"
readonly WOW_HOME="${WOW_HOME:-${HOME}/.claude/wow-system}"
readonly WOW_LOG_DIR="${WOW_LOG_DIR:-${WOW_HOME}/logs}"
readonly WOW_DATA_DIR="${WOW_DATA_DIR:-${WOW_HOME}/data}"

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Current log level (default: INFO)
WOW_LOG_LEVEL="${WOW_LOG_LEVEL:-${LOG_LEVEL_INFO}}"

# Colors for output (if terminal supports it)
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    readonly COLOR_RESET=$(tput sgr0)
    readonly COLOR_RED=$(tput setaf 1)
    readonly COLOR_GREEN=$(tput setaf 2)
    readonly COLOR_YELLOW=$(tput setaf 3)
    readonly COLOR_BLUE=$(tput setaf 4)
    readonly COLOR_MAGENTA=$(tput setaf 5)
    readonly COLOR_CYAN=$(tput setaf 6)
    readonly COLOR_BOLD=$(tput bold)
else
    readonly COLOR_RESET=""
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_MAGENTA=""
    readonly COLOR_CYAN=""
    readonly COLOR_BOLD=""
fi

# ============================================================================
# Logging Functions
# ============================================================================

# Get timestamp in ISO 8601 format
wow_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

# Internal logging function
_wow_log() {
    local level="$1"
    local level_num="$2"
    local color="$3"
    shift 3
    local message="$*"

    # Check if we should log this level
    if [[ ${level_num} -lt ${WOW_LOG_LEVEL} ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(wow_timestamp)

    # Format: [TIMESTAMP] LEVEL: message
    local log_line="[${timestamp}] ${level}: ${message}"

    # Console output with color
    echo -e "${color}${log_line}${COLOR_RESET}" >&2

    # File output (if log directory exists)
    if [[ -d "${WOW_LOG_DIR}" ]]; then
        echo "${log_line}" >> "${WOW_LOG_DIR}/wow.log"
    fi
}

# Public logging functions
wow_debug() {
    _wow_log "DEBUG" "${LOG_LEVEL_DEBUG}" "${COLOR_CYAN}" "$@"
}

wow_info() {
    _wow_log "INFO" "${LOG_LEVEL_INFO}" "${COLOR_BLUE}" "$@"
}

wow_warn() {
    _wow_log "WARN" "${LOG_LEVEL_WARN}" "${COLOR_YELLOW}" "$@"
}

wow_error() {
    _wow_log "ERROR" "${LOG_LEVEL_ERROR}" "${COLOR_RED}" "$@"
}

wow_fatal() {
    _wow_log "FATAL" "${LOG_LEVEL_FATAL}" "${COLOR_RED}${COLOR_BOLD}" "$@"
    exit 1
}

wow_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*" >&2
}

# ============================================================================
# Validation Functions
# ============================================================================

# Check if a variable is set and not empty
wow_require_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"

    if [[ -z "${var_value}" ]]; then
        wow_fatal "Required variable '${var_name}' is not set or empty"
    fi
}

# Check if a file exists
wow_require_file() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        wow_fatal "Required file does not exist: ${file_path}"
    fi
}

# Check if a directory exists
wow_require_dir() {
    local dir_path="$1"

    if [[ ! -d "${dir_path}" ]]; then
        wow_fatal "Required directory does not exist: ${dir_path}"
    fi
}

# Check if a command exists
wow_require_command() {
    local cmd="$1"

    if ! command -v "${cmd}" &>/dev/null; then
        wow_fatal "Required command not found: ${cmd}"
    fi
}

# Validate that a value is a number
wow_is_number() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

# Validate that a value is a valid boolean
wow_is_boolean() {
    local value="$1"
    [[ "${value}" =~ ^(true|false|0|1|yes|no)$ ]]
}

# Normalize boolean value to "true" or "false"
wow_normalize_bool() {
    local value="$1"

    case "${value,,}" in
        true|1|yes) echo "true" ;;
        false|0|no) echo "false" ;;
        *) wow_fatal "Invalid boolean value: ${value}" ;;
    esac
}

# ============================================================================
# Error Handling
# ============================================================================

# Global error handler
wow_error_handler() {
    local exit_code=$?
    local line_no=$1

    wow_error "Command failed with exit code ${exit_code} at line ${line_no}"

    # Print stack trace if available
    if [[ ${#BASH_SOURCE[@]} -gt 1 ]]; then
        wow_error "Stack trace:"
        local i=0
        while [[ $i -lt ${#BASH_SOURCE[@]} ]]; do
            wow_error "  ${BASH_SOURCE[$i]}:${BASH_LINENO[$i]} in ${FUNCNAME[$i+1]:-main}"
            ((i++))
        done
    fi

    return ${exit_code}
}

# Set up error trap (call this in scripts that source utils.sh)
wow_setup_error_trap() {
    trap 'wow_error_handler ${LINENO}' ERR
}

# ============================================================================
# File System Utilities
# ============================================================================

# Ensure directory exists (create if needed)
wow_ensure_dir() {
    local dir_path="$1"

    if [[ ! -d "${dir_path}" ]]; then
        mkdir -p "${dir_path}" || wow_fatal "Failed to create directory: ${dir_path}"
        wow_debug "Created directory: ${dir_path}"
    fi
}

# Safe file write (atomic via temp file)
wow_safe_write() {
    local file_path="$1"
    local content="$2"

    local temp_file="${file_path}.tmp.$$"

    # Write to temp file
    echo "${content}" > "${temp_file}" || {
        rm -f "${temp_file}"
        wow_fatal "Failed to write to temp file: ${temp_file}"
    }

    # Atomic move
    mv "${temp_file}" "${file_path}" || {
        rm -f "${temp_file}"
        wow_fatal "Failed to move temp file to: ${file_path}"
    }

    wow_debug "Wrote to file: ${file_path}"
}

# Read file safely (with error handling)
wow_safe_read() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        wow_error "File does not exist: ${file_path}"
        return 1
    fi

    cat "${file_path}" || {
        wow_error "Failed to read file: ${file_path}"
        return 1
    }
}

# ============================================================================
# JSON Utilities (using jq)
# ============================================================================

# Check if jq is available
wow_has_jq() {
    command -v jq &>/dev/null
}

# Parse JSON safely
wow_json_get() {
    local json="$1"
    local path="$2"

    if ! wow_has_jq; then
        wow_error "jq is not installed - cannot parse JSON"
        return 1
    fi

    echo "${json}" | jq -r "${path}" 2>/dev/null || {
        wow_error "Failed to parse JSON at path: ${path}"
        return 1
    }
}

# Validate JSON
wow_json_validate() {
    local json="$1"

    if ! wow_has_jq; then
        wow_warn "jq is not installed - cannot validate JSON"
        return 0  # Don't fail if jq isn't available
    fi

    echo "${json}" | jq empty 2>/dev/null
}

# ============================================================================
# String Utilities
# ============================================================================

# Trim whitespace from string
wow_trim() {
    local str="$1"
    # Remove leading whitespace
    str="${str#"${str%%[![:space:]]*}"}"
    # Remove trailing whitespace
    str="${str%"${str##*[![:space:]]}"}"
    echo "${str}"
}

# Convert string to lowercase
wow_lowercase() {
    echo "${1,,}"
}

# Convert string to uppercase
wow_uppercase() {
    echo "${1^^}"
}

# ============================================================================
# Array Utilities
# ============================================================================

# Check if array contains element
wow_array_contains() {
    local element="$1"
    shift
    local array=("$@")

    for item in "${array[@]}"; do
        if [[ "${item}" == "${element}" ]]; then
            return 0
        fi
    done

    return 1
}

# Join array elements with delimiter
wow_array_join() {
    local delimiter="$1"
    shift
    local array=("$@")

    local result=""
    local first=true

    for item in "${array[@]}"; do
        if [[ "${first}" == "true" ]]; then
            result="${item}"
            first=false
        else
            result="${result}${delimiter}${item}"
        fi
    done

    echo "${result}"
}

# ============================================================================
# Enforcement Utilities
# ============================================================================

# Check if enforcement is enabled globally
wow_enforcement_enabled() {
    local enabled
    enabled=$(config_get "enforcement.enabled" "true" 2>/dev/null || echo "true")
    [[ "${enabled}" == "true" ]]
}

# Check if strict mode is enabled
wow_strict_mode_enabled() {
    local strict
    strict=$(config_get "enforcement.strict_mode" "false" 2>/dev/null || echo "false")
    [[ "${strict}" == "true" ]]
}

# Check if block_on_violation is enabled
wow_block_on_violation_enabled() {
    local block
    block=$(config_get "enforcement.block_on_violation" "false" 2>/dev/null || echo "false")
    [[ "${block}" == "true" ]]
}

# Determine if should block based on severity and config
# Usage: wow_should_block "warn|error|block"
# Returns: 0 (should block) or 1 (should allow)
wow_should_block() {
    local severity="$1"  # warn, error, block

    # Check if enforcement is globally disabled
    if ! wow_enforcement_enabled; then
        return 1  # Don't block
    fi

    # block_on_violation: any violation becomes a block
    if wow_block_on_violation_enabled; then
        if [[ "${severity}" == "warn" ]] || [[ "${severity}" == "error" ]] || [[ "${severity}" == "block" ]]; then
            return 0  # Block
        fi
    fi

    # strict_mode: warnings become blocks
    if wow_strict_mode_enabled; then
        if [[ "${severity}" == "warn" ]] || [[ "${severity}" == "error" ]] || [[ "${severity}" == "block" ]]; then
            return 0  # Block
        fi
    fi

    # Default behavior: only block on explicit "block" or "error"
    if [[ "${severity}" == "block" ]] || [[ "${severity}" == "error" ]]; then
        return 0  # Block
    fi

    return 1  # Allow (for "warn")
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize WoW system directories
wow_init_dirs() {
    wow_ensure_dir "${WOW_HOME}"
    wow_ensure_dir "${WOW_LOG_DIR}"
    wow_ensure_dir "${WOW_DATA_DIR}"
    wow_debug "WoW directories initialized"
}

# ============================================================================
# Self-test
# ============================================================================

# Run self-test if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Utils v${WOW_VERSION} - Self Test"
    echo "======================================"

    wow_debug "Debug message"
    wow_info "Info message"
    wow_warn "Warning message"
    wow_error "Error message (non-fatal)"
    wow_success "Success message"

    echo ""
    echo "Validation tests:"
    wow_is_number "123" && echo "✓ Number validation works"
    wow_is_boolean "true" && echo "✓ Boolean validation works"

    echo ""
    echo "String utilities:"
    echo "  Trim: '$(wow_trim "  hello  ")'"
    echo "  Lowercase: '$(wow_lowercase "HELLO")'"
    echo "  Uppercase: '$(wow_uppercase "hello")'"

    echo ""
    echo "Array utilities:"
    wow_array_contains "b" "a" "b" "c" && echo "✓ Array contains works"
    echo "  Join: '$(wow_array_join "," "a" "b" "c")'"

    echo ""
    echo "All tests passed! ✓"
fi
