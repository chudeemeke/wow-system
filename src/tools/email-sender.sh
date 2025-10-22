#!/bin/bash
# WoW System - Secure Email Sender
# Provides: Email alerts with OS keychain integration
# Author: Chude <chude@emeke.org>
#
# Security Features:
# - Credentials stored in OS keychain (libsecret)
# - App-specific passwords only (no main passwords)
# - Retrieved on-demand (never stored in memory long-term)
# - Filtered from ALL logs (grep -v sensitive data)
# - Graceful fallback (file-based if not configured)
# - Rate limiting to prevent spam

# Prevent double-sourcing
if [[ -n "${WOW_EMAIL_SENDER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_EMAIL_SENDER_LOADED=1

# Source dependencies
_EMAIL_SENDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_EMAIL_SENDER_DIR}/../core/utils.sh"
source "${_EMAIL_SENDER_DIR}/../core/config-loader.sh"

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly EMAIL_KEYCHAIN_SERVICE="wow-email"
readonly EMAIL_KEYCHAIN_USERNAME="alerts"
readonly EMAIL_CONFIG_FILE="${WOW_DATA_DIR}/email-config.cache"
readonly EMAIL_RATE_LIMIT_FILE="${WOW_DATA_DIR}/email-rate-limit.txt"
readonly EMAIL_LOG_FILTER_PATTERN='(password|pass|credentials|secret|apikey|token|auth)'

# Priority levels
readonly EMAIL_PRIORITY_LOW="LOW"
readonly EMAIL_PRIORITY_NORMAL="NORMAL"
readonly EMAIL_PRIORITY_HIGH="HIGH"
readonly EMAIL_PRIORITY_CRITICAL="CRITICAL"

# ============================================================================
# Private: Security Functions
# ============================================================================

# Filter sensitive data from output
_email_filter_sensitive() {
    grep -v -iE "${EMAIL_LOG_FILTER_PATTERN}" || echo "(sensitive data filtered)"
}

# Clear sensitive variable from memory
_email_clear_var() {
    local var_name="$1"
    # Use declare instead of eval (safer, no code injection risk)
    declare -g "$var_name"='CLEARED'
    unset "$var_name"
}

# Detect operating system
_email_detect_os() {
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
        echo "WSL"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "MAC"
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "LINUX"
    else
        echo "UNKNOWN"
    fi
}

# ============================================================================
# Private: Keychain Functions
# ============================================================================

# Check if keychain tools are available
_email_has_keychain() {
    local os
    os=$(_email_detect_os)

    case "$os" in
        WSL|LINUX)
            command -v secret-tool &>/dev/null
            ;;
        MAC)
            command -v security &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Store credentials in keychain
_email_keychain_store() {
    local smtp_password="$1"
    local os
    os=$(_email_detect_os)

    case "$os" in
        WSL|LINUX)
            echo -n "$smtp_password" | secret-tool store \
                --label="WoW Email Alerts Password" \
                service "$EMAIL_KEYCHAIN_SERVICE" \
                username "$EMAIL_KEYCHAIN_USERNAME" 2>&1 | _email_filter_sensitive
            ;;
        MAC)
            security add-generic-password \
                -a "$EMAIL_KEYCHAIN_USERNAME" \
                -s "$EMAIL_KEYCHAIN_SERVICE" \
                -w "$smtp_password" \
                -U 2>&1 | _email_filter_sensitive
            ;;
        *)
            wow_error "Unsupported OS for keychain storage"
            return 1
            ;;
    esac

    local result=$?
    _email_clear_var smtp_password
    return $result
}

# Retrieve credentials from keychain
_email_keychain_retrieve() {
    local os
    os=$(_email_detect_os)

    local password=""

    case "$os" in
        WSL|LINUX)
            password=$(secret-tool lookup \
                service "$EMAIL_KEYCHAIN_SERVICE" \
                username "$EMAIL_KEYCHAIN_USERNAME" 2>/dev/null)
            ;;
        MAC)
            password=$(security find-generic-password \
                -a "$EMAIL_KEYCHAIN_USERNAME" \
                -s "$EMAIL_KEYCHAIN_SERVICE" \
                -w 2>/dev/null)
            ;;
        *)
            wow_error "Unsupported OS for keychain retrieval"
            return 1
            ;;
    esac

    if [[ -z "$password" ]]; then
        return 1
    fi

    echo "$password"
    return 0
}

# Delete credentials from keychain
_email_keychain_delete() {
    local os
    os=$(_email_detect_os)

    case "$os" in
        WSL|LINUX)
            secret-tool clear \
                service "$EMAIL_KEYCHAIN_SERVICE" \
                username "$EMAIL_KEYCHAIN_USERNAME" 2>&1 | _email_filter_sensitive
            ;;
        MAC)
            security delete-generic-password \
                -a "$EMAIL_KEYCHAIN_USERNAME" \
                -s "$EMAIL_KEYCHAIN_SERVICE" 2>&1 | _email_filter_sensitive
            ;;
        *)
            wow_error "Unsupported OS for keychain deletion"
            return 1
            ;;
    esac
}

# ============================================================================
# Private: Configuration Functions
# ============================================================================

# Get email configuration from config file
_email_get_config() {
    local key="$1"
    local default="${2:-}"

    config_get "capture.email_alerts.$key" "$default" 2>/dev/null || echo "$default"
}

# Check if email is enabled in config
_email_is_enabled() {
    local enabled
    enabled=$(_email_get_config "enabled" "false")
    [[ "$enabled" == "true" ]]
}

# Get SMTP configuration
_email_get_smtp_config() {
    local smtp_host smtp_port from_address to_address

    smtp_host=$(_email_get_config "smtp_host" "")
    smtp_port=$(_email_get_config "smtp_port" "587")
    from_address=$(_email_get_config "from_address" "")
    to_address=$(_email_get_config "to_address" "")

    if [[ -z "$smtp_host" ]] || [[ -z "$from_address" ]] || [[ -z "$to_address" ]]; then
        return 1
    fi

    echo "$smtp_host|$smtp_port|$from_address|$to_address"
    return 0
}

# ============================================================================
# Private: Rate Limiting
# ============================================================================

# Check rate limit
_email_check_rate_limit() {
    local rate_limit
    rate_limit=$(_email_get_config "rate_limit" "5")

    # 0 = no limit
    if [[ "$rate_limit" -eq 0 ]]; then
        return 0
    fi

    # Ensure rate limit file exists
    wow_ensure_dir "$WOW_DATA_DIR"
    touch "$EMAIL_RATE_LIMIT_FILE"

    # Count emails in last hour
    local cutoff_time
    cutoff_time=$(date -d '1 hour ago' +%s 2>/dev/null || date -v-1H +%s)

    local count=0
    while IFS= read -r line; do
        local timestamp=${line%%|*}
        if [[ "$timestamp" -ge "$cutoff_time" ]]; then
            ((count++))
        fi
    done < "$EMAIL_RATE_LIMIT_FILE"

    if [[ "$count" -ge "$rate_limit" ]]; then
        wow_warn "Email rate limit exceeded: $count emails in last hour (limit: $rate_limit)"
        return 1
    fi

    return 0
}

# Record email sent
_email_record_sent() {
    local subject="$1"
    local timestamp
    timestamp=$(date +%s)

    echo "$timestamp|$subject" >> "$EMAIL_RATE_LIMIT_FILE"

    # Clean old entries (older than 1 hour)
    local cutoff_time
    cutoff_time=$(date -d '1 hour ago' +%s 2>/dev/null || date -v-1H +%s)

    local temp_file="${EMAIL_RATE_LIMIT_FILE}.tmp"
    while IFS= read -r line; do
        local ts=${line%%|*}
        if [[ "$ts" -ge "$cutoff_time" ]]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$EMAIL_RATE_LIMIT_FILE"

    mv "$temp_file" "$EMAIL_RATE_LIMIT_FILE" 2>/dev/null || true
}

# ============================================================================
# Private: Email Sending
# ============================================================================

# Send email using sendemail (preferred) or mutt
_email_send_smtp() {
    local smtp_host="$1"
    local smtp_port="$2"
    local smtp_user="$3"
    local smtp_pass="$4"
    local from_addr="$5"
    local to_addr="$6"
    local subject="$7"
    local body="$8"

    # Try sendemail first (more reliable for SMTP)
    if command -v sendemail &>/dev/null; then
        sendemail \
            -f "$from_addr" \
            -t "$to_addr" \
            -u "$subject" \
            -m "$body" \
            -s "$smtp_host:$smtp_port" \
            -xu "$smtp_user" \
            -xp "$smtp_pass" \
            -o tls=yes \
            2>&1 | _email_filter_sensitive
        local result=$?
        _email_clear_var smtp_pass
        return $result
    fi

    # Fallback to mutt
    if command -v mutt &>/dev/null; then
        echo "$body" | mutt \
            -e "set smtp_url=smtp://$smtp_user:$smtp_pass@$smtp_host:$smtp_port" \
            -e "set ssl_starttls=yes" \
            -e "set from=$from_addr" \
            -s "$subject" \
            "$to_addr" \
            2>&1 | _email_filter_sensitive
        local result=$?
        _email_clear_var smtp_pass
        return $result
    fi

    # No email client available
    _email_clear_var smtp_pass
    wow_error "No email client available (sendemail or mutt required)"
    return 1
}

# ============================================================================
# Public API: Initialization
# ============================================================================

# Initialize email system
email_init() {
    wow_debug "Initializing email system..."

    # Ensure data directory exists
    wow_ensure_dir "$WOW_DATA_DIR"

    # Check if keychain tools are available
    if ! _email_has_keychain; then
        wow_warn "Keychain tools not available. Email functionality will be limited."
        wow_warn "Install libsecret-tools (Linux/WSL) for secure credential storage."
    fi

    # Check if email clients are available
    if ! command -v sendemail &>/dev/null && ! command -v mutt &>/dev/null; then
        wow_warn "No email client available. Install 'sendemail' or 'mutt' for email functionality."
    fi

    wow_debug "Email system initialized"
}

# ============================================================================
# Public API: Configuration Check
# ============================================================================

# Check if email is configured
email_is_configured() {
    # Check if enabled in config
    if ! _email_is_enabled; then
        return 1
    fi

    # Check if SMTP config is present
    if ! _email_get_smtp_config &>/dev/null; then
        return 1
    fi

    # Check if credentials are in keychain
    if ! _email_keychain_retrieve &>/dev/null; then
        wow_warn "Email enabled but credentials not found in keychain"
        return 1
    fi

    return 0
}

# ============================================================================
# Public API: Email Sending
# ============================================================================

# Send email with subject and body
# Usage: email_send "subject" "body" ["priority"]
email_send() {
    local subject="$1"
    local body="$2"
    local priority="${3:-$EMAIL_PRIORITY_NORMAL}"

    wow_debug "Attempting to send email: $subject"

    # Check if email is configured
    if ! email_is_configured; then
        wow_debug "Email not configured, falling back to file-based alert"
        email_fallback_to_file "$subject" "$body" "$priority"
        return 0
    fi

    # Check priority threshold
    local threshold
    threshold=$(_email_get_config "priority_threshold" "HIGH")

    case "$threshold" in
        LOW)
            # Send all emails
            ;;
        NORMAL)
            if [[ "$priority" == "$EMAIL_PRIORITY_LOW" ]]; then
                wow_debug "Email priority too low (threshold: $threshold)"
                return 0
            fi
            ;;
        HIGH)
            if [[ "$priority" == "$EMAIL_PRIORITY_LOW" ]] || [[ "$priority" == "$EMAIL_PRIORITY_NORMAL" ]]; then
                wow_debug "Email priority too low (threshold: $threshold)"
                return 0
            fi
            ;;
        CRITICAL)
            if [[ "$priority" != "$EMAIL_PRIORITY_CRITICAL" ]]; then
                wow_debug "Email priority too low (threshold: $threshold)"
                return 0
            fi
            ;;
    esac

    # Check rate limit
    if ! _email_check_rate_limit; then
        wow_warn "Email rate limit exceeded, skipping"
        email_fallback_to_file "$subject" "$body" "$priority"
        return 0
    fi

    # Get SMTP configuration
    local smtp_config
    smtp_config=$(_email_get_smtp_config)

    local smtp_host smtp_port from_address to_address
    IFS='|' read -r smtp_host smtp_port from_address to_address <<< "$smtp_config"

    # Get credentials from keychain
    local smtp_password
    smtp_password=$(_email_keychain_retrieve)

    if [[ -z "$smtp_password" ]]; then
        wow_error "Failed to retrieve credentials from keychain"
        email_fallback_to_file "$subject" "$body" "$priority"
        return 1
    fi

    # Add priority to subject
    local full_subject="[$priority] $subject"

    # Send email
    if _email_send_smtp "$smtp_host" "$smtp_port" "$from_address" "$smtp_password" \
                        "$from_address" "$to_address" "$full_subject" "$body"; then
        wow_success "Email sent: $subject"
        _email_record_sent "$subject"
        _email_clear_var smtp_password
        return 0
    else
        wow_error "Failed to send email"
        email_fallback_to_file "$subject" "$body" "$priority"
        _email_clear_var smtp_password
        return 1
    fi
}

# Send pre-formatted alert email
# Usage: email_send_alert "type" "message"
email_send_alert() {
    local alert_type="$1"
    local message="$2"

    local subject="WoW System Alert: $alert_type"
    local body="Alert Type: $alert_type
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
System: $(hostname)
User: $(whoami)

Message:
$message

---
WoW System v${WOW_VERSION}
Automated Alert System"

    # Determine priority based on alert type
    local priority="$EMAIL_PRIORITY_NORMAL"
    case "$alert_type" in
        CRITICAL|FATAL|SECURITY)
            priority="$EMAIL_PRIORITY_CRITICAL"
            ;;
        ERROR|WARNING)
            priority="$EMAIL_PRIORITY_HIGH"
            ;;
        INFO)
            priority="$EMAIL_PRIORITY_NORMAL"
            ;;
        DEBUG)
            priority="$EMAIL_PRIORITY_LOW"
            ;;
    esac

    email_send "$subject" "$body" "$priority"
}

# ============================================================================
# Public API: Fallback
# ============================================================================

# Fallback to file-based alert if email fails
email_fallback_to_file() {
    local subject="$1"
    local body="$2"
    local priority="$3"

    local alert_file="${WOW_DATA_DIR}/email-alerts.log"

    wow_debug "Writing alert to file: $alert_file"

    {
        echo "=========================================="
        echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "Priority: $priority"
        echo "Subject: $subject"
        echo "=========================================="
        echo "$body"
        echo ""
    } >> "$alert_file"

    wow_info "Alert saved to file: $alert_file"
}

# ============================================================================
# Public API: Testing
# ============================================================================

# Test SMTP connection
email_test_connection() {
    wow_info "Testing email connection..."

    if ! email_is_configured; then
        wow_error "Email is not configured"
        return 1
    fi

    local test_subject="WoW Email Test - $(date +%s)"
    local test_body="This is a test email from WoW System.

If you receive this, your email configuration is working correctly.

Test performed at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
System: $(hostname)
User: $(whoami)

WoW System v${WOW_VERSION}"

    if email_send "$test_subject" "$test_body" "$EMAIL_PRIORITY_NORMAL"; then
        wow_success "Email test successful! Check your inbox."
        return 0
    else
        wow_error "Email test failed"
        return 1
    fi
}

# ============================================================================
# Public API: Setup Wizard
# ============================================================================

# Interactive configuration wizard (calls external script)
email_setup_wizard() {
    local setup_script="${_EMAIL_SENDER_DIR}/../../bin/wow-email-setup"

    if [[ -f "$setup_script" ]]; then
        bash "$setup_script"
    else
        wow_error "Setup wizard not found: $setup_script"
        wow_info "Please install WoW System completely to use the email setup wizard"
        return 1
    fi
}

# ============================================================================
# Public API: Credential Management
# ============================================================================

# Get credentials status (without revealing them)
email_get_credentials_status() {
    if _email_keychain_retrieve &>/dev/null; then
        echo "CONFIGURED"
        return 0
    else
        echo "NOT_CONFIGURED"
        return 1
    fi
}

# Remove credentials from keychain
email_remove_credentials() {
    wow_info "Removing email credentials from keychain..."

    if _email_keychain_delete; then
        wow_success "Credentials removed from keychain"
        return 0
    else
        wow_error "Failed to remove credentials from keychain"
        return 1
    fi
}

# ============================================================================
# Self-test
# ============================================================================

# Run self-test if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Email Sender - Self Test"
    echo "=============================="

    email_init

    echo ""
    echo "System Information:"
    echo "  OS: $(_email_detect_os)"
    echo "  Keychain available: $(_email_has_keychain && echo "Yes" || echo "No")"
    echo "  sendemail available: $(command -v sendemail &>/dev/null && echo "Yes" || echo "No")"
    echo "  mutt available: $(command -v mutt &>/dev/null && echo "Yes" || echo "No")"

    echo ""
    echo "Configuration Status:"
    echo "  Email enabled: $(_email_is_enabled && echo "Yes" || echo "No")"
    echo "  Credentials status: $(email_get_credentials_status)"
    echo "  Fully configured: $(email_is_configured && echo "Yes" || echo "No")"

    echo ""
    echo "Self-test complete."
fi
