#!/usr/bin/env bash
# src/security/domain-lists.sh - Domain List Management
# WoW System v6.0.0
#
# Three-Tier Domain List System:
#   TIER 1: Critical Security (hardcoded, immutable)
#   TIER 2: System Defaults (config, append-only)
#   TIER 3: User Custom (config, fully editable)
#
# Public API:
#   domain_lists_init(config_dir)         - Load all lists
#   domain_lists_reload()                 - Reload config files
#   domain_is_critical_blocked(domain)    - TIER 1 check
#   domain_is_system_safe(domain)         - TIER 2 check
#   domain_is_user_safe(domain)           - TIER 3 safe check
#   domain_is_user_blocked(domain)        - TIER 3 block check

# Double-sourcing guard
if [[ -n "${WOW_DOMAIN_LISTS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_DOMAIN_LISTS_LOADED=1

#------------------------------------------------------------------------------
# Module Dependencies
#------------------------------------------------------------------------------

# Source utils for logging if available
if [[ -f "${WOW_HOME:-}/src/core/utils.sh" ]]; then
    source "${WOW_HOME}/src/core/utils.sh"
fi

#------------------------------------------------------------------------------
# Constants and Global State
#------------------------------------------------------------------------------

# Config directory (set by domain_lists_init)
DOMAIN_CONFIG_DIR=""

# TIER 1: Critical Security (Hardcoded - IMMUTABLE)
# These patterns protect against SSRF and metadata attacks
declare -a DOMAIN_TIER1_BLOCKED=(
    # Loopback
    "localhost"
    "127.0.0.1"
    "127.0.0.0/8"
    "::1"
    "0.0.0.0"

    # AWS Metadata
    "169.254.169.254"
    "169.254.169.253"
    "fd00:ec2::254"

    # GCP Metadata
    "metadata.google.internal"
    "metadata"

    # Azure Metadata
    "169.254.169.254"

    # Kubernetes
    "kubernetes.default"
    "kubernetes.default.svc"
    "kubernetes.default.svc.cluster.local"

    # Private IP ranges (will be matched as prefixes)
    "10.*"
    "192.168.*"
    "172.16.*"
    "172.17.*"
    "172.18.*"
    "172.19.*"
    "172.20.*"
    "172.21.*"
    "172.22.*"
    "172.23.*"
    "172.24.*"
    "172.25.*"
    "172.26.*"
    "172.27.*"
    "172.28.*"
    "172.29.*"
    "172.30.*"
    "172.31.*"

    # Link-local
    "169.254.*"
    "fe80:*"

    # Multicast
    "224.0.0.*"
    "ff00:*"
)

# TIER 2: System Defaults (Config - APPEND-ONLY)
declare -a DOMAIN_TIER2_SAFE=()
declare -a DOMAIN_TIER2_BLOCKED=()

# TIER 3: User Custom (Config - FULLY EDITABLE)
declare -a DOMAIN_TIER3_SAFE=()
declare -a DOMAIN_TIER3_BLOCKED=()

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

# Normalize domain for comparison
# Args: $1 = domain
# Output: normalized domain (lowercase, trimmed)
_domain_normalize() {
    local domain="$1"

    # Trim whitespace
    domain=$(echo "$domain" | xargs)

    # Convert to lowercase
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')

    echo "$domain"
}

# Check if domain matches pattern (supports wildcards)
# Args: $1 = domain, $2 = pattern
# Returns: 0 if match, 1 if no match
_domain_matches_pattern() {
    local domain="$1"
    local pattern="$2"

    # Normalize both
    domain=$(_domain_normalize "$domain")
    pattern=$(_domain_normalize "$pattern")

    # Exact match
    if [[ "$domain" == "$pattern" ]]; then
        return 0
    fi

    # Wildcard pattern: *.example.com
    if [[ "$pattern" == \*.* ]]; then
        # Remove leading *.
        local suffix="${pattern#\*.}"

        # Check if domain ends with suffix and has at least one subdomain
        if [[ "$domain" == *."$suffix" ]]; then
            return 0
        fi
    fi

    # Prefix wildcard pattern: 10.*
    if [[ "$pattern" == *\* ]]; then
        local prefix="${pattern%\*}"
        if [[ "$domain" == "$prefix"* ]]; then
            return 0
        fi
    fi

    return 1
}

# Check if domain is in list
# Args: $1 = domain, $2... = list array elements
# Returns: 0 if found, 1 if not found
_domain_in_list() {
    local domain="$1"
    shift
    local -a list=("$@")

    local pattern
    for pattern in "${list[@]}"; do
        if _domain_matches_pattern "$domain" "$pattern"; then
            return 0
        fi
    done

    return 1
}

# Parse config file and return domains
# Args: $1 = config file path
# Output: space-separated domains
_domain_parse_config() {
    local config_file="$1"

    # Check if file exists
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Check for symlinks (security)
    if [[ -L "$config_file" ]]; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "WARN" "Skipping symlink config file: $config_file"
        fi
        return 0
    fi

    local domains=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Strip inline comments (everything after #)
        line="${line%%#*}"

        # Trim whitespace
        line=$(echo "$line" | xargs)

        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi

        # Validate domain format (basic check)
        # Allow: a-z, 0-9, dot, hyphen, wildcard
        if [[ ! "$line" =~ ^[a-zA-Z0-9.*:-]+$ ]]; then
            if type -t wow_log >/dev/null 2>&1; then
                wow_log "WARN" "Skipping invalid domain in config: $line"
            fi
            continue
        fi

        # Check for directory traversal attempts
        if [[ "$line" =~ \.\. ]]; then
            if type -t wow_log >/dev/null 2>&1; then
                wow_log "WARN" "Skipping suspicious domain (traversal): $line"
            fi
            continue
        fi

        domains+=("$line")
    done < "$config_file"

    # Output as array elements
    printf '%s\n' "${domains[@]}"
}

#------------------------------------------------------------------------------
# Public API - Initialization
#------------------------------------------------------------------------------

# Initialize domain lists from config directory
# Args: $1 = config directory path (optional, defaults to ${WOW_HOME}/config/security)
# Returns: 0 on success, 1 on error
domain_lists_init() {
    local config_dir="${1:-${WOW_HOME}/config/security}"

    DOMAIN_CONFIG_DIR="$config_dir"

    # Clear existing lists (except TIER 1 which is hardcoded)
    DOMAIN_TIER2_SAFE=()
    DOMAIN_TIER2_BLOCKED=()
    DOMAIN_TIER3_SAFE=()
    DOMAIN_TIER3_BLOCKED=()

    # Load TIER 2 system safe domains
    local system_safe="${config_dir}/system-safe-domains.conf"
    if [[ -f "$system_safe" ]]; then
        local -a domains
        mapfile -t domains < <(_domain_parse_config "$system_safe")
        DOMAIN_TIER2_SAFE+=("${domains[@]}")
    fi

    # Load TIER 2 system blocked domains
    local system_blocked="${config_dir}/system-blocked-domains.conf"
    if [[ -f "$system_blocked" ]]; then
        local -a domains
        mapfile -t domains < <(_domain_parse_config "$system_blocked")
        DOMAIN_TIER2_BLOCKED+=("${domains[@]}")
    fi

    # Load TIER 3 custom safe domains
    local custom_safe="${config_dir}/custom-safe-domains.conf"
    if [[ -f "$custom_safe" ]]; then
        local -a domains
        mapfile -t domains < <(_domain_parse_config "$custom_safe")
        DOMAIN_TIER3_SAFE+=("${domains[@]}")
    fi

    # Load TIER 3 custom blocked domains
    local custom_blocked="${config_dir}/custom-blocked-domains.conf"
    if [[ -f "$custom_blocked" ]]; then
        local -a domains
        mapfile -t domains < <(_domain_parse_config "$custom_blocked")
        DOMAIN_TIER3_BLOCKED+=("${domains[@]}")
    fi

    if type -t wow_log >/dev/null 2>&1; then
        wow_log "DEBUG" "Domain lists loaded: TIER2_SAFE=${#DOMAIN_TIER2_SAFE[@]}, TIER3_SAFE=${#DOMAIN_TIER3_SAFE[@]}"
    fi

    return 0
}

# Reload domain lists from config files
# Returns: 0 on success
domain_lists_reload() {
    if [[ -z "$DOMAIN_CONFIG_DIR" ]]; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "WARN" "domain_lists_reload called before init, using default config dir"
        fi
        domain_lists_init "${WOW_HOME}/config/security"
    else
        domain_lists_init "$DOMAIN_CONFIG_DIR"
    fi

    return 0
}

#------------------------------------------------------------------------------
# Public API - Query Functions
#------------------------------------------------------------------------------

# Check if domain is in TIER 1 critical blocked list (hardcoded)
# Args: $1 = domain
# Returns: 0 if blocked, 1 if not blocked
domain_is_critical_blocked() {
    local domain="$1"

    _domain_in_list "$domain" "${DOMAIN_TIER1_BLOCKED[@]}"
}

# Check if domain is in TIER 2 system safe list
# Args: $1 = domain
# Returns: 0 if safe, 1 if not in list
domain_is_system_safe() {
    local domain="$1"

    _domain_in_list "$domain" "${DOMAIN_TIER2_SAFE[@]}"
}

# Check if domain is in TIER 2 system blocked list
# Args: $1 = domain
# Returns: 0 if blocked, 1 if not in list
domain_is_system_blocked() {
    local domain="$1"

    _domain_in_list "$domain" "${DOMAIN_TIER2_BLOCKED[@]}"
}

# Check if domain is in TIER 3 user safe list
# Args: $1 = domain
# Returns: 0 if safe, 1 if not in list
domain_is_user_safe() {
    local domain="$1"

    _domain_in_list "$domain" "${DOMAIN_TIER3_SAFE[@]}"
}

# Check if domain is in TIER 3 user blocked list
# Args: $1 = domain
# Returns: 0 if blocked, 1 if not in list
domain_is_user_blocked() {
    local domain="$1"

    _domain_in_list "$domain" "${DOMAIN_TIER3_BLOCKED[@]}"
}

#------------------------------------------------------------------------------
# Module Initialization Complete
#------------------------------------------------------------------------------

if type -t wow_log >/dev/null 2>&1; then
    wow_log "DEBUG" "domain-lists.sh loaded (v6.0.0)"
fi
