#!/usr/bin/env bash
# src/security/domain-validator.sh - Domain Validation Logic
# WoW System v6.0.0
#
# Three-Tier Validation System with Chain of Responsibility pattern
#
# Public API:
#   domain_validate(domain, context)      - Main validation (returns 0/1/2)
#   domain_is_safe(domain)                - Check if in any safe list
#   domain_is_blocked(domain)             - Check if in any block list
#   domain_add_custom(domain, list_type)  - Persist to config
#   domain_extract_from_url(url)          - Parse URL to domain
#   domain_prompt_user(domain)            - Interactive prompt (stub)

# Double-sourcing guard
if [[ -n "${WOW_DOMAIN_VALIDATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_DOMAIN_VALIDATOR_LOADED=1

#------------------------------------------------------------------------------
# Module Dependencies
#------------------------------------------------------------------------------

# Source domain-lists.sh (required dependency)
if [[ -f "${WOW_HOME:-}/src/security/domain-lists.sh" ]]; then
    source "${WOW_HOME}/src/security/domain-lists.sh"
elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/domain-lists.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/domain-lists.sh"
fi

# Source utils for logging if available
if [[ -f "${WOW_HOME:-}/src/core/utils.sh" ]]; then
    source "${WOW_HOME}/src/core/utils.sh"
fi

# Source security-constants for IP validation if available
if [[ -f "${WOW_HOME:-}/src/security/security-constants.sh" ]]; then
    source "${WOW_HOME}/src/security/security-constants.sh"
fi

#------------------------------------------------------------------------------
# Constants
#------------------------------------------------------------------------------

# DNS specification: max domain length is 253 characters
readonly DOMAIN_MAX_LENGTH=253

#------------------------------------------------------------------------------
# Helper Functions - Domain Normalization
#------------------------------------------------------------------------------

# Extract domain from URL
# Args: $1 = URL or domain
# Output: normalized domain
# Example: https://EXAMPLE.COM:8080/path → example.com
domain_extract_from_url() {
    local input="$1"
    local domain="$input"

    # Strip protocol (http://, https://, etc.)
    domain="${domain#*://}"

    # Strip path (everything after first /)
    domain="${domain%%/*}"

    # Strip port (everything after :)
    domain="${domain%%:*}"

    # Strip trailing dot (DNS format)
    domain="${domain%.}"

    # Convert to lowercase
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')

    # Trim whitespace
    domain=$(echo "$domain" | xargs 2>/dev/null || echo "$domain")

    echo "$domain"
}

# Normalize domain for validation
# Args: $1 = domain or URL
# Output: normalized domain
_domain_normalize_for_validation() {
    local input="$1"

    # Use domain_extract_from_url for full normalization
    domain_extract_from_url "$input"
}

# Validate domain format (basic checks)
# Args: $1 = domain
# Returns: 0 if valid format, 1 if invalid
_domain_is_valid_format() {
    local domain="$1"

    # Empty domain
    if [[ -z "$domain" ]]; then
        return 1
    fi

    # Too long (DNS spec: max 253 chars)
    if [[ ${#domain} -gt $DOMAIN_MAX_LENGTH ]]; then
        return 1
    fi

    # Check for whitespace
    if [[ "$domain" =~ [[:space:]] ]]; then
        return 1
    fi

    # Check for control characters
    if [[ "$domain" =~ [[:cntrl:]] ]]; then
        return 1
    fi

    # Very basic format check: should contain only valid DNS characters
    # Allow: a-z, 0-9, dot, hyphen, colon (for IPv6)
    # Note: We're being permissive here because IPv6 addresses contain colons
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.:*-]+$ ]]; then
        return 1
    fi

    return 0
}

# Check if domain is an IP address
# Args: $1 = domain
# Returns: 0 if IP address, 1 if not
_domain_is_ip_address() {
    local domain="$1"

    # IPv4 pattern (basic check)
    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi

    # IPv6 pattern (basic check - contains colons)
    if [[ "$domain" =~ : ]]; then
        return 0
    fi

    return 1
}

# Validate IP address using security-constants.sh if available
# Args: $1 = IP address
# Returns: 0 if safe, 2 if blocked
_domain_validate_ip() {
    local ip="$1"

    # Use security-constants.sh patterns if available
    if type -t wow_has_function >/dev/null 2>&1; then
        if wow_has_function "is_ssrf_pattern"; then
            if is_ssrf_pattern "$ip"; then
                return 2  # BLOCKED
            fi
        fi
    fi

    # Fallback: Block private IPs
    # IPv4 private ranges
    if [[ "$ip" =~ ^10\. ]] || \
       [[ "$ip" =~ ^192\.168\. ]] || \
       [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
       [[ "$ip" =~ ^127\. ]] || \
       [[ "$ip" =~ ^169\.254\. ]]; then
        return 2  # BLOCKED
    fi

    # IPv6 loopback and link-local
    if [[ "$ip" =~ ^::1$ ]] || \
       [[ "$ip" =~ ^fe80: ]] || \
       [[ "$ip" =~ ^::ffff:192\.168\. ]] || \
       [[ "$ip" =~ ^::ffff:10\. ]]; then
        return 2  # BLOCKED
    fi

    return 0  # ALLOWED
}

#------------------------------------------------------------------------------
# Public API - Query Functions
#------------------------------------------------------------------------------

# Check if domain is in any safe list (TIER 2 or TIER 3)
# Args: $1 = domain
# Returns: 0 if safe, 1 if not safe
domain_is_safe() {
    local domain="$1"

    # Normalize domain
    domain=$(_domain_normalize_for_validation "$domain")

    # Check TIER 2 system safe
    if domain_is_system_safe "$domain"; then
        return 0
    fi

    # Check TIER 3 user safe
    if domain_is_user_safe "$domain"; then
        return 0
    fi

    return 1
}

# Check if domain is in any block list (TIER 1 or TIER 3)
# Args: $1 = domain
# Returns: 0 if blocked, 1 if not blocked
domain_is_blocked() {
    local domain="$1"

    # Normalize domain
    domain=$(_domain_normalize_for_validation "$domain")

    # Check TIER 1 critical blocked (always checked first)
    if domain_is_critical_blocked "$domain"; then
        return 0
    fi

    # Check TIER 2 system blocked
    if type -t domain_is_system_blocked >/dev/null 2>&1; then
        if domain_is_system_blocked "$domain"; then
            return 0
        fi
    fi

    # Check TIER 3 user blocked
    if domain_is_user_blocked "$domain"; then
        return 0
    fi

    return 1
}

#------------------------------------------------------------------------------
# Public API - Config Persistence
#------------------------------------------------------------------------------

# Add domain to custom list (TIER 3)
# Args: $1 = domain, $2 = list type ("safe" or "blocked")
# Returns: 0 on success, 1 on error
domain_add_custom() {
    local domain="$1"
    local list_type="$2"

    # Normalize domain
    domain=$(_domain_normalize_for_validation "$domain")

    # Validate domain format
    if ! _domain_is_valid_format "$domain"; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "ERROR" "Invalid domain format: $domain"
        fi
        return 1
    fi

    # Determine config file
    local config_file=""
    if [[ "$list_type" == "safe" ]]; then
        config_file="${DOMAIN_CONFIG_DIR}/custom-safe-domains.conf"
    elif [[ "$list_type" == "blocked" ]]; then
        config_file="${DOMAIN_CONFIG_DIR}/custom-blocked-domains.conf"
    else
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "ERROR" "Invalid list type: $list_type (must be 'safe' or 'blocked')"
        fi
        return 1
    fi

    # Check if already in file
    if [[ -f "$config_file" ]] && grep -qx "$domain" "$config_file" 2>/dev/null; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "DEBUG" "Domain already in $list_type list: $domain"
        fi
        return 0
    fi

    # Append to config file (with file locking for concurrency)
    {
        flock -x 200 || {
            if type -t wow_log >/dev/null 2>&1; then
                wow_log "WARN" "Could not acquire lock for $config_file"
            fi
        }

        echo "$domain" >> "$config_file"

    } 200>"${config_file}.lock" 2>/dev/null

    # Remove lock file
    rm -f "${config_file}.lock" 2>/dev/null

    if type -t wow_log >/dev/null 2>&1; then
        wow_log "INFO" "Added domain to $list_type list: $domain"
    fi

    return 0
}

#------------------------------------------------------------------------------
# Public API - User Prompt (Stub for Phase 3)
#------------------------------------------------------------------------------

# Prompt user for unknown domain (stub for Phase 3)
# Args: $1 = domain, $2 = context
# Returns: 0=allow, 1=warn, 2=block
domain_prompt_user() {
    local domain="$1"
    local context="${2:-unknown}"

    # For Phase 1, this is a stub
    # Phase 3 will implement interactive prompts

    if type -t wow_log >/dev/null 2>&1; then
        wow_log "WARN" "Unknown domain: $domain (context: $context) - prompting not yet implemented"
    fi

    # Default behavior: WARN (return 1)
    return 1
}

#------------------------------------------------------------------------------
# Public API - Main Validation Function
#------------------------------------------------------------------------------

# Validate domain using three-tier system
# Args: $1 = domain or URL, $2 = context (e.g., "webfetch", "websearch")
# Returns: 0=ALLOW, 1=WARN, 2=BLOCK
domain_validate() {
    local input="$1"
    local context="${2:-unknown}"

    # Normalize domain
    local domain
    domain=$(_domain_normalize_for_validation "$input")

    # Step 1: Check format
    if ! _domain_is_valid_format "$domain"; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "WARN" "Invalid domain format: $input"
        fi
        return 2  # BLOCK
    fi

    # Step 2: Check if IP address
    if _domain_is_ip_address "$domain"; then
        _domain_validate_ip "$domain"
        return $?
    fi

    # Step 3: TIER 1 - Critical blocked (checked FIRST, immutable)
    if domain_is_critical_blocked "$domain"; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "BLOCK" "TIER 1 critical block: $domain"
        fi
        return 2  # BLOCK
    fi

    # Step 4: TIER 2 - System safe
    if domain_is_system_safe "$domain"; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "DEBUG" "TIER 2 system safe: $domain"
        fi
        return 0  # ALLOW
    fi

    # Step 5: TIER 3 - User safe
    if domain_is_user_safe "$domain"; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "DEBUG" "TIER 3 user safe: $domain"
        fi
        return 0  # ALLOW
    fi

    # Step 6: TIER 3 - User blocked
    if domain_is_user_blocked "$domain"; then
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "BLOCK" "TIER 3 user blocked: $domain"
        fi
        return 2  # BLOCK
    fi

    # Step 7: TIER 2 - System blocked
    if type -t domain_is_system_blocked >/dev/null 2>&1; then
        if domain_is_system_blocked "$domain"; then
            if type -t wow_log >/dev/null 2>&1; then
                wow_log "BLOCK" "TIER 2 system blocked: $domain"
            fi
            return 2  # BLOCK
        fi
    fi

    # Step 8: Unknown domain - prompt or warn
    # Check if interactive mode
    if [[ -n "${WOW_NON_INTERACTIVE:-}" ]] || [[ ! -t 0 ]]; then
        # Non-interactive: WARN
        if type -t wow_log >/dev/null 2>&1; then
            wow_log "WARN" "Unknown domain (non-interactive): $domain (context: $context)"
        fi
        return 1  # WARN
    else
        # Interactive: prompt user (stub for Phase 3)
        domain_prompt_user "$domain" "$context"
        return $?
    fi
}

#------------------------------------------------------------------------------
# Module Initialization Complete
#------------------------------------------------------------------------------

if type -t wow_log >/dev/null 2>&1; then
    wow_log "DEBUG" "domain-validator.sh loaded (v6.0.0)"
fi
