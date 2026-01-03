# WoW System - Email Alert Setup Guide

Complete guide for configuring secure email alerts with OS keychain integration.

## Table of Contents

1. [Overview](#overview)
2. [Security Features](#security-features)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Manual Configuration](#manual-configuration)
6. [Provider-Specific Instructions](#provider-specific-instructions)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)
9. [API Reference](#api-reference)

---

## Overview

WoW System v5.0.1+ includes secure email alerting capability with:

- **OS Keychain Integration**: Credentials stored in your system keychain (libsecret/macOS Keychain)
- **App-Specific Passwords**: Never use your main email password
- **On-Demand Retrieval**: Credentials retrieved only when needed
- **Log Filtering**: All sensitive data filtered from logs
- **Rate Limiting**: Prevent email spam
- **Priority Thresholds**: Only send important alerts
- **Graceful Fallback**: File-based alerts if email unavailable

---

## Security Features

### All Security Requirements Met

 **Credentials in OS Keychain**
- Linux/WSL: `libsecret-tools` (GNOME Keyring)
- macOS: Native Keychain via `security` command

 **App-Specific Passwords Only**
- Gmail: App Passwords (16 characters)
- Outlook: App Passwords or account password
- Custom: Application-specific credentials

 **Retrieved On-Demand**
- Credentials never stored in memory long-term
- Automatically cleared after use

 **Filtered from ALL Logs**
- Pattern: `(password|pass|credentials|secret|apikey|token|auth)`
- Applied to all log outputs

 **Graceful Fallback**
- File-based alerts if email not configured
- Saved to: `$WOW_DATA_DIR/email-alerts.log`

 **User Authentication Required**
- First-time setup requires user interaction
- Keychain may prompt for system password

---

## Prerequisites

### Required Dependencies

#### Linux/WSL

```bash
# Install libsecret-tools for keychain
sudo apt-get update
sudo apt-get install libsecret-tools

# Install email client (choose one)
sudo apt-get install sendemail  # Recommended
# OR
sudo apt-get install mutt       # Alternative

# Install jq for JSON parsing
sudo apt-get install jq
```

#### macOS

```bash
# Install email client via Homebrew
brew install sendemail  # Recommended
# OR
brew install mutt       # Alternative

# Install jq
brew install jq

# Note: macOS Keychain is built-in
```

### Verify Installation

```bash
# Check keychain tools
secret-tool --version    # Linux/WSL
security -h              # macOS

# Check email clients
sendemail --version
# OR
mutt -v

# Check jq
jq --version
```

---

## Quick Start

### Interactive Setup Wizard

The easiest way to configure email alerts:

```bash
cd /path/to/wow-system
bash bin/wow-email-setup
```

The wizard will guide you through:

1. **Dependency Check**: Verify all required tools are installed
2. **Provider Selection**: Choose Gmail, Outlook, or Custom SMTP
3. **Credential Input**: Enter email addresses and app-specific password
4. **Advanced Settings**: Configure priority threshold and rate limits
5. **Keychain Storage**: Securely store password in OS keychain
6. **Configuration Update**: Update `wow-config.json`
7. **Connection Test**: Send test email to verify setup

---

## Manual Configuration

### Step 1: Create App-Specific Password

See [Provider-Specific Instructions](#provider-specific-instructions) below.

### Step 2: Update Configuration

Edit `config/wow-config.json`:

```json
{
  "capture": {
    "email_alerts": {
      "enabled": true,
      "priority_threshold": "HIGH",
      "rate_limit": 5,
      "smtp_host": "smtp.gmail.com",
      "smtp_port": 587,
      "from_address": "your-email@gmail.com",
      "to_address": "alerts-recipient@example.com"
    }
  }
}
```

### Step 3: Store Credentials in Keychain

#### Linux/WSL

```bash
# Store password
echo -n "your-app-password" | secret-tool store \
    --label="WoW Email Alerts Password" \
    service "wow-email" \
    username "alerts"

# Verify storage
secret-tool lookup service "wow-email" username "alerts"
```

#### macOS

```bash
# Store password
security add-generic-password \
    -a "alerts" \
    -s "wow-email" \
    -w "your-app-password" \
    -U

# Verify storage
security find-generic-password \
    -a "alerts" \
    -s "wow-email" \
    -w
```

### Step 4: Test Configuration

```bash
cd /path/to/wow-system
source src/tools/email-sender.sh
email_init
email_test_connection
```

---

## Provider-Specific Instructions

### Gmail

#### Create App-Specific Password

1. Go to: https://myaccount.google.com/apppasswords
2. Sign in to your Google account
3. Click **"Select app"** → Choose **"Mail"**
4. Click **"Select device"** → Choose **"Other (Custom name)"**
5. Enter: **"WoW Email Alerts"**
6. Click **"Generate"**
7. Copy the **16-character password** (e.g., `abcd efgh ijkl mnop`)

#### Configuration

```json
{
  "capture": {
    "email_alerts": {
      "enabled": true,
      "smtp_host": "smtp.gmail.com",
      "smtp_port": 587,
      "from_address": "your-email@gmail.com",
      "to_address": "recipient@example.com"
    }
  }
}
```

**Note**: 2-Factor Authentication must be enabled to use App Passwords.

---

### Outlook/Office365

#### Create App Password

1. Go to: https://account.microsoft.com/security
2. Click **"Advanced security options"**
3. Under **"App passwords"**, click **"Create a new app password"**
4. Copy the generated password

**Alternative**: Some accounts can use the main password with "Allow less secure apps" enabled.

#### Configuration

```json
{
  "capture": {
    "email_alerts": {
      "enabled": true,
      "smtp_host": "smtp-mail.outlook.com",
      "smtp_port": 587,
      "from_address": "your-email@outlook.com",
      "to_address": "recipient@example.com"
    }
  }
}
```

---

### Custom SMTP Server

#### Configuration

```json
{
  "capture": {
    "email_alerts": {
      "enabled": true,
      "smtp_host": "smtp.yourserver.com",
      "smtp_port": 587,
      "from_address": "alerts@yourserver.com",
      "to_address": "recipient@example.com"
    }
  }
}
```

**Common Ports**:
- **587**: STARTTLS (recommended)
- **465**: SSL/TLS
- **25**: Plain (not recommended)

---

## Testing

### Run Self-Test

```bash
cd /path/to/wow-system
bash src/tools/email-sender.sh
```

**Expected Output**:
```
WoW Email Sender - Self Test
==============================

System Information:
  OS: WSL
  Keychain available: Yes
  sendemail available: Yes
  mutt available: No

Configuration Status:
  Email enabled: Yes
  Credentials status: CONFIGURED
  Fully configured: Yes

Self-test complete.
```

### Send Test Email

```bash
source src/tools/email-sender.sh
email_init
email_test_connection
```

### Check Fallback File

If email is not configured, alerts are saved to file:

```bash
cat ~/.claude/wow-system/data/email-alerts.log
```

---

## Troubleshooting

### Issue: "Keychain tools not available"

**Solution**:
```bash
# Linux/WSL
sudo apt-get install libsecret-tools

# macOS - built-in, check with:
security -h
```

### Issue: "No email client available"

**Solution**:
```bash
# Install sendemail (recommended)
sudo apt-get install sendemail

# Or mutt
sudo apt-get install mutt
```

### Issue: "Failed to retrieve credentials from keychain"

**Cause**: Password not stored in keychain.

**Solution**:
```bash
# Re-run setup wizard
bash bin/wow-email-setup

# Or manually store:
echo -n "your-password" | secret-tool store \
    --label="WoW Email Alerts Password" \
    service "wow-email" username "alerts"
```

### Issue: "Authentication failed" when sending email

**Causes**:
1. Incorrect app-specific password
2. App passwords not enabled (Gmail requires 2FA first)
3. "Less secure apps" not allowed (Outlook)

**Solution**:
1. Regenerate app-specific password
2. Enable 2-Factor Authentication (Gmail)
3. Allow less secure apps (Outlook) or use app password
4. Check SMTP host and port are correct

### Issue: "Email rate limit exceeded"

**Cause**: Too many emails sent in one hour.

**Solution**:
```json
{
  "capture": {
    "email_alerts": {
      "rate_limit": 0  // Disable rate limiting
      // OR
      "rate_limit": 10  // Increase limit
    }
  }
}
```

### Issue: Sensitive data appearing in logs

**This should never happen!** If you see passwords in logs:

1. Report as security issue
2. Check filter pattern in `src/tools/email-sender.sh`
3. Verify `_email_filter_sensitive()` is being called

---

## API Reference

### Initialization

```bash
email_init
```

Initialize email system (create directories, check dependencies).

### Configuration Check

```bash
email_is_configured
# Returns: 0 if configured, 1 if not
```

Check if email is fully configured and credentials are available.

### Send Email

```bash
email_send "subject" "body" "priority"
# priority: LOW, NORMAL, HIGH, CRITICAL (optional, default: NORMAL)
```

Send email with subject, body, and optional priority.

**Example**:
```bash
email_send "Test Alert" "This is a test message" "HIGH"
```

### Send Pre-Formatted Alert

```bash
email_send_alert "type" "message"
# type: CRITICAL, ERROR, WARNING, INFO, DEBUG
```

Send pre-formatted alert with timestamp and system info.

**Example**:
```bash
email_send_alert "CRITICAL" "System error detected"
```

### Test Connection

```bash
email_test_connection
# Returns: 0 if successful, 1 if failed
```

Send test email to verify configuration.

### Get Credentials Status

```bash
status=$(email_get_credentials_status)
# Returns: "CONFIGURED" or "NOT_CONFIGURED"
```

Check if credentials are stored in keychain (without revealing them).

### Remove Credentials

```bash
email_remove_credentials
```

Remove credentials from OS keychain.

### Fallback to File

```bash
email_fallback_to_file "subject" "body" "priority"
```

Save alert to file instead of sending email.

---

## Configuration Reference

### Priority Thresholds

```json
{
  "priority_threshold": "HIGH"
}
```

**Options**:
- `"LOW"`: Send all emails (LOW, NORMAL, HIGH, CRITICAL)
- `"NORMAL"`: Send NORMAL, HIGH, CRITICAL
- `"HIGH"`: Send only HIGH and CRITICAL
- `"CRITICAL"`: Send only CRITICAL

### Rate Limiting

```json
{
  "rate_limit": 5
}
```

**Options**:
- `0`: Unlimited emails
- `N`: Max N emails per hour

### SMTP Ports

```json
{
  "smtp_port": 587
}
```

**Common Ports**:
- `587`: STARTTLS (most common, recommended)
- `465`: SSL/TLS
- `25`: Plain (not recommended for security)

---

## Security Best Practices

1. **Never Commit Passwords**: Never add passwords to git or config files
2. **Use App Passwords**: Always use app-specific passwords, never main passwords
3. **Rotate Regularly**: Change app passwords periodically
4. **Limit Access**: Use `to_address` to limit who receives alerts
5. **Monitor Logs**: Check that sensitive data is filtered
6. **Rate Limit**: Use rate limiting to prevent spam
7. **Priority Threshold**: Set appropriate threshold to avoid noise

---

## File Locations

```
~/.claude/wow-system/
├── data/
│   ├── email-config.cache       # Cached SMTP config (no passwords)
│   ├── email-rate-limit.txt     # Rate limiting tracker
│   └── email-alerts.log         # Fallback alerts file
└── logs/
    └── wow.log                  # System logs (sensitive data filtered)

config/
└── wow-config.json              # Email configuration (no passwords)

src/tools/
└── email-sender.sh              # Email sender module

bin/
└── wow-email-setup              # Interactive setup wizard
```

---

## Example Usage

### Basic Usage

```bash
#!/bin/bash
source /path/to/wow-system/src/tools/email-sender.sh

email_init

# Send simple email
email_send "Test Subject" "Test body" "NORMAL"

# Send alert
email_send_alert "ERROR" "Something went wrong"
```

### Integration with Scripts

```bash
#!/bin/bash
source /path/to/wow-system/src/tools/email-sender.sh

email_init

# Run critical operation
if ! critical_operation; then
    email_send_alert "CRITICAL" "Critical operation failed: $?"
    exit 1
fi

# Send success notification
email_send_alert "INFO" "Critical operation completed successfully"
```

### Conditional Sending

```bash
# Only send if configured
if email_is_configured; then
    email_send "Alert" "System event occurred" "HIGH"
else
    echo "Email not configured, skipping notification"
fi
```

---

## Support

For issues or questions:

1. Check this guide and [Troubleshooting](#troubleshooting) section
2. Run self-test: `bash src/tools/email-sender.sh`
3. Check logs: `cat ~/.claude/wow-system/logs/wow.log`
4. Verify configuration: `cat config/wow-config.json`

---

## Version History

- **v5.0.1**: Initial email alert system with OS keychain integration
  - Secure credential storage
  - Rate limiting
  - Priority thresholds
  - Graceful fallback

---

**Author**: Chude <chude@emeke.org>

**License**: See LICENSE file in project root
