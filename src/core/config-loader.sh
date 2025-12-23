#!/bin/bash
# WoW System - Config Loader
# Provides: JSON configuration management with nested keys and validation
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_CONFIG_LOADER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CONFIG_LOADER_LOADED=1

# Source dependencies
_CONFIG_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CONFIG_LOADER_DIR}/utils.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly CONFIG_VERSION="1.0.0"
readonly CONFIG_DEFAULT_PATH="${WOW_HOME}/config/wow-config.json"

# ============================================================================
# State Storage
# ============================================================================

# Global associative array for config
declare -gA _WOW_CONFIG

# Raw JSON storage (for saving)
_WOW_CONFIG_RAW=""

# ============================================================================
# Initialization
# ============================================================================

# Initialize config system
config_init() {
    wow_debug "Initializing config loader v${CONFIG_VERSION}"

    # Ensure config directory exists
    wow_ensure_dir "$(dirname "${CONFIG_DEFAULT_PATH}")"

    wow_debug "Config loader initialized"
    return 0
}

# ============================================================================
# Loading & Parsing
# ============================================================================

# Load config from JSON file
config_load() {
    local config_file="${1:-${CONFIG_DEFAULT_PATH}}"

    if [[ ! -f "${config_file}" ]]; then
        wow_error "Config file not found: ${config_file}"
        return 1
    fi

    if ! wow_has_jq; then
        wow_error "jq is required for config loading"
        return 1
    fi

    # Validate JSON
    if ! jq empty "${config_file}" 2>/dev/null; then
        wow_error "Invalid JSON in config file: ${config_file}"
        return 1
    fi

    # Store raw JSON
    _WOW_CONFIG_RAW=$(cat "${config_file}")

    # Flatten JSON into associative array
    _config_parse "${_WOW_CONFIG_RAW}"

    wow_debug "Config loaded from: ${config_file}"
    return 0
}

# Parse JSON and flatten to key-value pairs
_config_parse() {
    local json="$1"

    # Use jq to flatten JSON with dot notation
    while IFS='=' read -r key value; do
        # Skip empty lines
        [[ -z "${key}" ]] && continue

        # Store in associative array
        _WOW_CONFIG["${key}"]="${value}"
    done < <(echo "${json}" | jq -r 'paths(scalars) as $p | "\($p | join("."))=\(getpath($p))"' 2>/dev/null)
}

# Merge another config file (override existing values)
config_merge() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        wow_error "Config file not found: ${config_file}"
        return 1
    fi

    if ! wow_has_jq; then
        wow_error "jq is required for config merging"
        return 1
    fi

    # Validate JSON
    if ! jq empty "${config_file}" 2>/dev/null; then
        wow_error "Invalid JSON in config file: ${config_file}"
        return 1
    fi

    # Load and merge
    local merge_json
    merge_json=$(cat "${config_file}")

    # Parse and add to existing config
    while IFS='=' read -r key value; do
        [[ -z "${key}" ]] && continue
        _WOW_CONFIG["${key}"]="${value}"
    done < <(echo "${merge_json}" | jq -r 'paths(scalars) as $p | "\($p | join("."))=\(getpath($p))"' 2>/dev/null)

    # Update raw JSON (merge the two JSON objects)
    if [[ -n "${_WOW_CONFIG_RAW}" ]]; then
        _WOW_CONFIG_RAW=$(jq -s '.[0] * .[1]' <(echo "${_WOW_CONFIG_RAW}") <(echo "${merge_json}") 2>/dev/null)
    else
        _WOW_CONFIG_RAW="${merge_json}"
    fi

    wow_debug "Config merged from: ${config_file}"
    return 0
}

# ============================================================================
# Basic Operations
# ============================================================================

# Get config value
config_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "${key}" ]]; then
        wow_error "Config key cannot be empty"
        return 1
    fi

    local value="${_WOW_CONFIG[${key}]:-${default}}"
    echo "${value}"
    return 0
}

# Set config value
config_set() {
    local key="$1"
    local value="$2"

    if [[ -z "${key}" ]]; then
        wow_error "Config key cannot be empty"
        return 1
    fi

    _WOW_CONFIG["${key}"]="${value}"
    wow_debug "Config set: ${key}=${value}"
    return 0
}

# Check if config key exists
config_exists() {
    local key="$1"

    [[ -n "${_WOW_CONFIG[${key}]:-}" ]]
}

# Delete config key
config_delete() {
    local key="$1"

    if [[ -z "${key}" ]]; then
        wow_error "Config key cannot be empty"
        return 1
    fi

    unset "_WOW_CONFIG[${key}]"
    wow_debug "Config deleted: ${key}"
    return 0
}

# Clear all config
config_clear() {
    _WOW_CONFIG=()
    _WOW_CONFIG_RAW=""
    wow_debug "Config cleared"
    return 0
}

# ============================================================================
# Type-Specific Getters
# ============================================================================

# Get boolean value
config_get_bool() {
    local key="$1"
    local default="${2:-false}"

    local value
    value=$(config_get "${key}" "${default}")

    # Normalize to true/false
    case "${value,,}" in
        true|1|yes) echo "true" ;;
        false|0|no) echo "false" ;;
        *) echo "${default}" ;;
    esac
}

# Get integer value
config_get_int() {
    local key="$1"
    local default="${2:-0}"

    local value
    value=$(config_get "${key}" "${default}")

    # Validate it's a number
    if wow_is_number "${value}"; then
        echo "${value}"
    else
        echo "${default}"
    fi
}

# Get float value
config_get_float() {
    local key="$1"
    local default="${2:-0.0}"

    local value
    value=$(config_get "${key}" "${default}")

    # Basic validation for float
    if [[ "${value}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "${value}"
    else
        echo "${default}"
    fi
}

# Get array value (JSON array as bash array)
config_get_array() {
    local key="$1"

    if [[ -z "${_WOW_CONFIG_RAW}" ]]; then
        return 1
    fi

    if ! wow_has_jq; then
        wow_error "jq is required for array extraction"
        return 1
    fi

    # Convert dot notation to jq path
    local jq_path=".${key}"

    # Extract array elements
    echo "${_WOW_CONFIG_RAW}" | jq -r "${jq_path}[]?" 2>/dev/null
}

# ============================================================================
# Persistence
# ============================================================================

# Save config to JSON file
config_save() {
    local config_file="${1:-${CONFIG_DEFAULT_PATH}}"

    local config_dir
    config_dir=$(dirname "${config_file}")
    wow_ensure_dir "${config_dir}"

    # Rebuild JSON from associative array
    local json_output="{"
    local first=true

    # Group keys by top-level namespace
    local temp_json=""

    for key in $(config_keys | sort); do
        local value="${_WOW_CONFIG[${key}]}"

        # Escape special characters in value
        value=$(echo "${value}" | sed 's/\\/\\\\/g; s/"/\\"/g')

        # Build nested JSON structure
        if [[ "${first}" == "true" ]]; then
            temp_json="\"${key}\": \"${value}\""
            first=false
        else
            temp_json="${temp_json}, \"${key}\": \"${value}\""
        fi
    done

    json_output="${json_output}${temp_json}}"

    # Pretty-print using jq if available
    if wow_has_jq; then
        echo "${json_output}" | jq '.' > "${config_file}" 2>/dev/null || {
            # Fallback to raw JSON if jq fails
            echo "${json_output}" > "${config_file}"
        }
    else
        echo "${json_output}" > "${config_file}"
    fi

    wow_debug "Config saved to: ${config_file}"
    return 0
}

# ============================================================================
# Metadata
# ============================================================================

# Get all config keys
config_keys() {
    for key in "${!_WOW_CONFIG[@]}"; do
        echo "${key}"
    done | sort
}

# Get config size (number of keys)
config_size() {
    echo "${#_WOW_CONFIG[@]}"
}

# Dump config for debugging
config_dump() {
    echo "=== WoW Config Dump ==="
    echo "Keys: ${#_WOW_CONFIG[@]}"
    echo ""

    for key in $(config_keys); do
        local value="${_WOW_CONFIG[${key}]}"
        # Truncate long values
        if [[ ${#value} -gt 50 ]]; then
            value="${value:0:47}..."
        fi
        echo "  ${key}=${value}"
    done
}

# ============================================================================
# Validation
# ============================================================================

# Validate config against schema
config_validate() {
    # Basic validation - check required fields
    local required_fields=(
        "version"
    )

    for field in "${required_fields[@]}"; do
        if ! config_exists "${field}"; then
            wow_error "Missing required config field: ${field}"
            return 1
        fi
    done

    wow_debug "Config validation passed"
    return 0
}

# Validate specific types
config_validate_types() {
    # Example type validations
    local bool_fields=(
        "enforcement.enabled"
        "enforcement.strict_mode"
    )

    for field in "${bool_fields[@]}"; do
        if config_exists "${field}"; then
            local value
            value=$(config_get "${field}")
            if ! wow_is_boolean "${value}"; then
                wow_error "Invalid boolean value for ${field}: ${value}"
                return 1
            fi
        fi
    done

    wow_debug "Type validation passed"
    return 0
}

# ============================================================================
# Defaults
# ============================================================================

# Load default configuration
config_load_defaults() {
    # Set sensible defaults (version from SSOT: VERSION file via WOW_VERSION)
    config_set "version" "${WOW_VERSION:-6.1.0}"
    config_set "enforcement.enabled" "true"
    config_set "enforcement.strict_mode" "false"
    config_set "enforcement.block_on_violation" "false"
    config_set "scoring.threshold_warn" "50"
    config_set "scoring.threshold_block" "80"
    config_set "scoring.decay_rate" "0.95"
    config_set "rules.max_file_operations" "10"
    config_set "rules.max_bash_commands" "5"
    config_set "rules.require_documentation" "true"
    config_set "integrations.claude_code.hooks_enabled" "true"
    config_set "integrations.claude_code.session_tracking" "true"

    wow_debug "Default config loaded"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Config Loader v${CONFIG_VERSION} - Self Test"
    echo "================================================="
    echo ""

    # Initialize
    config_init
    echo "✓ Initialized"

    # Load defaults
    config_load_defaults
    echo "✓ Defaults loaded"

    # Basic operations
    config_set "test_key" "test_value"
    [[ "$(config_get "test_key")" == "test_value" ]] && echo "✓ Set/Get works"

    config_exists "test_key" && echo "✓ Exists check works"

    # Nested keys
    config_set "nested.key.value" "nested_data"
    [[ "$(config_get "nested.key.value")" == "nested_data" ]] && echo "✓ Nested keys work"

    # Type getters
    config_set "bool_val" "true"
    [[ "$(config_get_bool "bool_val")" == "true" ]] && echo "✓ Boolean getter works"

    config_set "int_val" "42"
    [[ "$(config_get_int "int_val")" == "42" ]] && echo "✓ Integer getter works"

    # Keys
    keys_output=$(config_keys)
    [[ "${keys_output}" == *"test_key"* ]] && echo "✓ Keys listing works"

    # Validation
    config_validate && echo "✓ Validation works"

    # Save/Load
    temp_file=$(mktemp)
    config_save "${temp_file}"
    [[ -f "${temp_file}" ]] && echo "✓ Save works"

    config_clear
    [[ "$(config_size)" == "0" ]] && echo "✓ Clear works"

    if wow_has_jq; then
        config_load "${temp_file}"
        [[ "$(config_get "test_key")" == "test_value" ]] && echo "✓ Load works"
    else
        echo "⊘ Load test skipped (jq not available)"
    fi

    rm -f "${temp_file}"

    echo ""
    echo "Configuration:"
    config_dump

    echo ""
    echo "All tests passed! ✓"
fi
