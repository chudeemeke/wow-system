# WoW Email Alerts - Quick Reference Card

## Installation (One-Time Setup)

### 1. Install Dependencies

```bash
# Linux/WSL
sudo apt-get install libsecret-tools sendemail jq

# macOS
brew install sendemail jq
```

### 2. Run Setup Wizard

```bash
bash bin/wow-email-setup
```

Follow the prompts to configure email alerts.

---

## Common Operations

### Send Email Alert

```bash
source src/tools/email-sender.sh
email_init
email_send_alert "ERROR" "Your error message here"
```

### Test Connection

```bash
source src/tools/email-sender.sh
email_test_connection
```

### Check Configuration Status

```bash
source src/tools/email-sender.sh
email_is_configured && echo "Configured" || echo "Not configured"
```

### Remove Credentials

```bash
source src/tools/email-sender.sh
email_remove_credentials
```

---

## API Quick Reference

| Function | Usage | Description |
|----------|-------|-------------|
| `email_init` | `email_init` | Initialize email system |
| `email_send` | `email_send "subject" "body" "priority"` | Send email |
| `email_send_alert` | `email_send_alert "type" "message"` | Send pre-formatted alert |
| `email_test_connection` | `email_test_connection` | Test SMTP connection |
| `email_is_configured` | `email_is_configured` | Check if configured |
| `email_get_credentials_status` | `status=$(email_get_credentials_status)` | Get credentials status |
| `email_remove_credentials` | `email_remove_credentials` | Remove from keychain |

---

## Priority Levels

| Priority | Usage | When to Use |
|----------|-------|-------------|
| `LOW` | `email_send "..." "..." "LOW"` | Debug, info messages |
| `NORMAL` | `email_send "..." "..." "NORMAL"` | Regular notifications |
| `HIGH` | `email_send "..." "..." "HIGH"` | Important events |
| `CRITICAL` | `email_send "..." "..." "CRITICAL"` | System failures |

---

## Alert Types

| Type | Auto Priority | Usage |
|------|---------------|-------|
| `DEBUG` | LOW | `email_send_alert "DEBUG" "message"` |
| `INFO` | NORMAL | `email_send_alert "INFO" "message"` |
| `WARNING` | HIGH | `email_send_alert "WARNING" "message"` |
| `ERROR` | HIGH | `email_send_alert "ERROR" "message"` |
| `CRITICAL` | CRITICAL | `email_send_alert "CRITICAL" "message"` |
| `SECURITY` | CRITICAL | `email_send_alert "SECURITY" "message"` |

---

## Configuration (config/wow-config.json)

```json
{
  "capture": {
    "email_alerts": {
      "enabled": true,
      "priority_threshold": "HIGH",
      "rate_limit": 5,
      "smtp_host": "smtp.gmail.com",
      "smtp_port": 587,
      "from_address": "your@email.com",
      "to_address": "recipient@email.com"
    }
  }
}
```

---

## Gmail App Password

1. Visit: https://myaccount.google.com/apppasswords
2. Generate password for "Mail" → "Other (WoW Email)"
3. Copy 16-character password
4. Use in setup wizard or store manually

---

## Manual Credential Storage

### Linux/WSL

```bash
echo -n "app-password" | secret-tool store \
    --label="WoW Email Alerts Password" \
    service "wow-email" username "alerts"
```

### macOS

```bash
security add-generic-password \
    -a "alerts" -s "wow-email" \
    -w "app-password" -U
```

---

## Troubleshooting

| Issue | Quick Fix |
|-------|-----------|
| No email client | `sudo apt-get install sendemail` |
| No keychain tools | `sudo apt-get install libsecret-tools` |
| Auth failed | Regenerate app password, check SMTP settings |
| Rate limit exceeded | Increase `rate_limit` in config or set to `0` |
| Credentials not found | Re-run `bash bin/wow-email-setup` |

---

## File Locations

| File | Location |
|------|----------|
| Config | `config/wow-config.json` |
| Email module | `src/tools/email-sender.sh` |
| Setup wizard | `bin/wow-email-setup` |
| Fallback log | `~/.claude/wow-system/data/email-alerts.log` |
| Rate limit data | `~/.claude/wow-system/data/email-rate-limit.txt` |

---

## Security Checklist

-  Use app-specific passwords (never main password)
-  Credentials stored in OS keychain
-  Sensitive data filtered from logs
-  Rate limiting enabled
-  Priority threshold set appropriately
-  Regular password rotation

---

## Example: Integration in Script

```bash
#!/bin/bash
source /path/to/wow-system/src/tools/email-sender.sh

email_init

# Your script logic
if critical_operation; then
    email_send_alert "INFO" "Operation completed successfully"
else
    email_send_alert "CRITICAL" "Operation failed: $?"
    exit 1
fi
```

---

For detailed documentation, see: `docs/EMAIL-SETUP-GUIDE.md`
