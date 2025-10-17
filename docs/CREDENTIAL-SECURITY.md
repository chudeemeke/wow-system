# WoW System - Credential Security Guide

## Quick Start

### 1. Basic Detection

```bash
source src/security/credential-detector.sh

# Test a string
if detect_in_string "GITHUB_TOKEN=ghp_abc123xyz..."; then
    echo "Credential detected!"
fi

# Scan a file
detect_in_file "config.env"

# Scan conversation history
detect_in_conversation "$HOME/.claude/history.jsonl"
```

### 2. Safe Redaction

```bash
source src/security/credential-redactor.sh

# Preview changes (no modification)
redact_preview_file "config.env"

# Redact with automatic backup (RECOMMENDED)
redact_with_backup "config.env"

# Restore if needed
redact_restore_latest "config.env"
```

### 3. Real-time Scanning

```bash
source src/security/credential-scanner.sh

# Scan command before execution
scanner_scan_command "export API_KEY=xyz..."

# Scan file with user alert
scanner_scan_file "secrets.txt"

# Scan conversation history
scanner_scan_conversation
```

## Integration with WoW Handlers

### Bash Handler Integration

Add credential scanning to bash commands:

```bash
# In src/handlers/bash-handler.sh

# 1. Source scanner (after line 20)
if [[ -f "${_BASH_HANDLER_DIR}/../security/credential-scanner.sh" ]]; then
    source "${_BASH_HANDLER_DIR}/../security/credential-scanner.sh"
    _CREDENTIAL_SCAN_ENABLED=true
else
    _CREDENTIAL_SCAN_ENABLED=false
fi

# 2. Add security check in handle_bash (after command extraction, ~line 220)
if [[ "${_CREDENTIAL_SCAN_ENABLED}" == "true" ]]; then
    if scanner_scan_command "${command}"; then
        # Credential detected and user alerted
        echo ""
        echo "Options:"
        echo "  1. Redact and continue"
        echo "  2. Block command"
        echo "  3. Continue anyway (NOT RECOMMENDED)"
        echo ""
        echo -n "Choice (1/2/3): "
        read -r choice

        case "$choice" in
            1)
                command=$(scanner_auto_redact "${command}")
                wow_info "Command redacted"
                ;;
            2)
                wow_error "Command blocked"
                return 2
                ;;
            3)
                wow_warn "Proceeding with credential in command"
                ;;
            *)
                wow_error "Invalid choice, blocking"
                return 2
                ;;
        esac
    fi
fi
```

### Write Handler Integration

Scan file content before writing:

```bash
# In src/handlers/write-handler.sh

# 1. Source scanner
if [[ -f "${_WRITE_HANDLER_DIR}/../security/credential-scanner.sh" ]]; then
    source "${_WRITE_HANDLER_DIR}/../security/credential-scanner.sh"
    _CREDENTIAL_SCAN_ENABLED=true
else
    _CREDENTIAL_SCAN_ENABLED=false
fi

# 2. Add check before writing file
if [[ "${_CREDENTIAL_SCAN_ENABLED}" == "true" ]]; then
    if scanner_has_credentials "${content}"; then
        wow_warn "Credentials detected in file content"

        echo ""
        echo "Options:"
        echo "  1. Redact and write"
        echo "  2. Cancel write"
        echo "  3. Write anyway (NOT RECOMMENDED)"
        echo ""
        echo -n "Choice (1/2/3): "
        read -r choice

        case "$choice" in
            1)
                content=$(scanner_auto_redact "${content}")
                wow_info "Content redacted"
                ;;
            2)
                wow_error "Write cancelled"
                return 2
                ;;
            3)
                wow_warn "Writing with credentials"
                ;;
            *)
                wow_error "Invalid choice, cancelling"
                return 2
                ;;
        esac
    fi
fi
```

## Credential Types Detected

### HIGH Severity (Immediate Alert)

| Type | Pattern Example | Service |
|------|----------------|---------|
| `github_pat` | `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx` | GitHub Personal Access Token |
| `github_oauth` | `gho_xxxxxxxxxxxxxxxxxxxxxxxxxxxx` | GitHub OAuth Token |
| `openai_api` | `sk-xxxxxxxxxxxxxxxxxxxxxxxx` | OpenAI API Key |
| `anthropic_api` | `sk-ant-xxxxxxxxxxxxxxxx` | Anthropic API Key |
| `aws_access_key` | `AKIAIOSFODNN7EXAMPLE` | AWS Access Key |
| `npm_token` | `npm_xxxxxxxxxxxxxxxxxxxxxxxx` | NPM Token |
| `slack_token` | `xoxb-xxxxxxxxxxxx-xxxxxxxxxxxx` | Slack Bot Token |
| `stripe_live` | `sk_live_xxxxxxxxxxxxxxxx` | Stripe Live Key |
| `jwt_token` | `eyJhbGc...` | JWT Token |

### MEDIUM Severity (Alert Required)

| Type | Pattern Example |
|------|----------------|
| `generic_api_key` | `api_key = xxxxxxxxxx` |
| `generic_token` | `token = xxxxxxxxxx` |
| `generic_secret` | `secret = xxxxxxxxxx` |
| `generic_password` | `password = xxxxxxxxxx` |
| `bearer_token` | `Bearer xxxxxxxxxx` |
| `basic_auth` | `Basic xxxxxxxxxx` |
| `connection_string` | `mongodb://user:pass@host` |
| `private_key_header` | `-----BEGIN PRIVATE KEY-----` |
| `ssh_key` | `ssh-rsa AAAAB3...` |

### LOW Severity (Manual Review)

- UUIDs (context-dependent)
- Hexadecimal keys (40+ chars)
- Base64 strings (60+ chars)

## Security Workflows

### 1. Pre-Commit Scan

```bash
# .git/hooks/pre-commit
#!/bin/bash
source "$(git rev-parse --show-toplevel)/src/security/credential-scanner.sh"

echo "Scanning staged files..."

git diff --cached --name-only | while read -r file; do
    if [[ -f "$file" ]]; then
        content=$(git show ":$file")
        if scanner_has_credentials "$content"; then
            echo "ERROR: Credentials in $file"
            exit 1
        fi
    fi
done

echo "No credentials detected."
```

### 2. Project-wide Scan

```bash
#!/bin/bash
source src/security/credential-scanner.sh

echo "Scanning project..."

find . -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" \) | while read -r file; do
    if scanner_has_credentials "$(<"$file")"; then
        scanner_scan_file "$file"
    fi
done
```

### 3. Conversation History Cleanup

```bash
#!/bin/bash
source src/security/credential-scanner.sh

# Scan
scanner_scan_conversation "$HOME/.claude/history.jsonl"

# Redact if credentials found
if [[ $? -eq 0 ]]; then
    echo ""
    echo "Redact conversation history? (y/n): "
    read -r choice

    if [[ "$choice" == "y" ]]; then
        redact_with_backup "$HOME/.claude/history.jsonl"
        echo "Redaction complete!"
    fi
fi
```

### 4. Configuration File Cleanup

```bash
#!/bin/bash
source src/security/credential-redactor.sh

# Preview
echo "=== Preview ==="
redact_preview_file "config.env"

# Ask user
echo ""
echo "Proceed with redaction? (y/n): "
read -r choice

if [[ "$choice" == "y" ]]; then
    redact_with_backup "config.env"
    echo "Done! Backup created."
    echo ""
    echo "To restore: redact_restore_latest config.env"
fi
```

## Statistics and Monitoring

### View Detection Statistics

```bash
source src/security/credential-detector.sh

# Get statistics
detect_get_stats

# Output:
# {
#   "total_scans": 150,
#   "total_detections": 12,
#   "high_severity": 8,
#   "medium_severity": 4,
#   "low_severity": 0,
#   "false_positives": 2
# }
```

### View Redaction Statistics

```bash
source src/security/credential-redactor.sh

# Get statistics
redact_get_stats

# View log
redact_view_log 50  # Last 50 entries
```

### View Scanner Statistics

```bash
source src/security/credential-scanner.sh

# Get statistics
scanner_get_stats

# View alerts
scanner_view_alerts 50
```

## Backup Management

### List Backups

```bash
redact_list_backups "config.env"

# Output:
# === BACKUPS FOR: config.env ===
# config.env.credential-backup.20250105_120000
# config.env.credential-backup.20250105_110000
# config.env.credential-backup.20250105_100000
```

### Restore from Backup

```bash
# Restore latest
redact_restore_latest "config.env"

# Restore specific
redact_restore_from "config.env" "config.env.credential-backup.20250105_120000"
```

### Cleanup Old Backups

```bash
# Keep only 5 most recent
redact_cleanup_backups "config.env" 5
```

## Testing

### Run Detector Tests (30+ samples)

```bash
bash tests/security/test-credential-detector.sh

# Output:
# === Testing GitHub Tokens ===
#   PASS: GitHub PAT
#   PASS: GitHub OAuth
#   ...
#
# Test Summary
# Total tests:  75
# Passed:       75
# Failed:       0
```

### Run Redactor Tests

```bash
bash tests/security/test-credential-redactor.sh

# Output:
# === Testing String Redaction (GitHub) ===
#   PASS: GitHub token redacted
#   ...
#
# Test Summary
# Total tests:  25
# Passed:       25
# Failed:       0
```

## API Reference

### credential-detector.sh

```bash
detect_init()                          # Initialize detector
detect_in_string(text)                 # Detect in string, returns JSON
detect_in_file(filepath)               # Detect in file, returns JSON array
detect_in_conversation(history_file)   # Detect in JSONL conversation
detect_get_severity(type)              # Get severity: HIGH/MEDIUM/LOW
detect_should_alert(type)              # Should trigger alert?
detect_get_stats()                     # Get detection statistics
detect_list_types()                    # List all credential types
detect_get_pattern(type)               # Get regex pattern for type
detect_version()                       # Get version
```

### credential-redactor.sh

```bash
redact_init()                          # Initialize redactor
redact_string(text, [pattern])         # Redact string
redact_preview(text)                   # Preview redaction
redact_file(filepath)                  # Redact file IN-PLACE
redact_with_backup(filepath)           # Redact with backup (SAFE)
redact_preview_file(filepath)          # Preview file redaction
redact_interactive(filepath)           # Interactive redaction
redact_list_backups(filepath)          # List backups
redact_restore_latest(filepath)        # Restore latest backup
redact_restore_from(filepath, backup)  # Restore specific backup
redact_cleanup_backups(filepath, n)    # Keep N most recent backups
redact_get_stats()                     # Get redaction statistics
redact_view_log([lines])               # View redaction log
redact_version()                       # Get version
```

### credential-scanner.sh

```bash
scanner_init()                         # Initialize scanner
scanner_scan_string(text, context)     # Scan with user alert
scanner_scan_command(command)          # Scan command
scanner_scan_tool_input(json, name)    # Scan tool input
scanner_scan_file(filepath)            # Scan file with alert
scanner_scan_conversation([file])      # Scan conversation history
scanner_auto_redact(text)              # Auto-redact for logging
scanner_has_credentials(text)          # Silent check (true/false)
scanner_get_stats()                    # Get scanner statistics
scanner_view_alerts([lines])           # View alert log
scanner_version()                      # Get version
```

## Files and Locations

```
src/security/
├── credential-detector.sh    # Core detection engine (416 LOC)
├── credential-redactor.sh    # Safe redaction (527 LOC)
├── credential-scanner.sh     # Integration layer (400 LOC)
└── README.md                 # Module documentation

tests/security/
├── test-credential-detector.sh  # 30+ test cases
└── test-credential-redactor.sh  # Redaction tests

examples/
└── credential-detection-integration.sh  # Integration examples

~/.wow/logs/
├── credential-alerts.log     # Alert log
└── redactions.log            # Redaction log

~/URGENT-REVOKE-TOKENS.txt   # Revocation reminder list
```

## Best Practices

1. **Always use backup**: Use `redact_with_backup()` instead of `redact_file()`
2. **Preview first**: Use `redact_preview_file()` before redacting
3. **Regular scans**: Scan conversation history periodically
4. **Pre-commit hooks**: Prevent credentials from being committed
5. **Immediate revocation**: Revoke detected credentials immediately
6. **False positives**: Mark false positives to improve accuracy
7. **Backup cleanup**: Regularly clean old backups

## Security Considerations

1. **Detection is not 100%**: Some obfuscated credentials may not be detected
2. **False positives**: Some legitimate strings may be flagged
3. **Context matters**: Review LOW severity detections manually
4. **Already committed?**: Scan git history for historical credentials
5. **Already pushed?**: Consider credentials compromised, revoke immediately
6. **Backup security**: Backup files still contain credentials, handle carefully

## Troubleshooting

### Detection not working?

```bash
# Check if module loaded
detect_version

# Test with known credential
echo "ghp_1234567890abcdefghijklmnopqrstuv123456" | detect_in_string

# Check statistics
detect_get_stats
```

### Redaction not working?

```bash
# Check if module loaded
redact_version

# Test with simple string
redact_string "API_KEY=test_key_1234567890abcdef"

# Check permissions
ls -la config.env
```

### False positives?

```bash
# Mark as false positive
detect_mark_false_positive

# Check safe context patterns in credential-detector.sh
# Add custom exclusions if needed
```

## Author

Chude <chude@emeke.org>

## Version

5.0.1

## License

Part of WoW System v5.0.1
