# WoW System - Credential Security Module

Real-time credential detection and redaction system for the WoW System v5.0.1.

## Components

### 1. credential-detector.sh
Pattern-based credential detection with 30+ credential types.

**Features:**
- High-precision pattern matching for tokens, API keys, secrets
- Three severity levels: HIGH, MEDIUM, LOW
- Context-aware detection (reduces false positives)
- Fast scanning for real-time use

**Supported Credential Types:**

**HIGH Severity:**
- GitHub tokens (PAT, OAuth, App, Refresh)
- NPM tokens
- GitLab tokens
- OpenAI API keys
- Anthropic API keys
- AWS access keys
- Slack tokens
- Google API keys
- Stripe keys (live/test)
- Twilio credentials
- SendGrid API keys
- Mailgun API keys
- JWT tokens
- PyPI tokens
- Docker tokens

**MEDIUM Severity:**
- Generic API keys
- Generic tokens
- Generic secrets
- Generic passwords
- Bearer tokens
- Basic auth
- Database connection strings
- Private key headers
- SSH keys

**LOW Severity:**
- UUIDs (context-dependent)
- Hexadecimal keys
- Base64 encoded strings

**Usage:**

```bash
source src/security/credential-detector.sh

# Initialize
detect_init

# Detect in string
if result=$(detect_in_string "GITHUB_TOKEN=ghp_abc123..."); then
    echo "Credential detected: $result"
fi

# Detect in file
if detections=$(detect_in_file "config.env"); then
    echo "Found credentials: $detections"
fi

# Detect in conversation history
if detections=$(detect_in_conversation "$HOME/.claude/history.jsonl"); then
    echo "Conversation contains credentials!"
fi

# Get severity
severity=$(detect_get_severity "github_pat")  # Returns: HIGH

# Should alert?
if detect_should_alert "github_pat"; then
    echo "Alert user immediately!"
fi

# Get statistics
detect_get_stats

# List all supported types
detect_list_types
```

### 2. credential-redactor.sh
Safe credential redaction with backup and preview.

**Features:**
- Automatic backup before redaction
- Preview mode (no modification)
- Type-specific redaction markers
- Backup management (list, restore, cleanup)
- Comprehensive statistics

**Safety Mechanisms:**
1. Always backup before modifying
2. Preview before applying changes
3. User confirmation for sensitive operations
4. Audit logging of all redactions
5. Reversible operations

**Usage:**

```bash
source src/security/credential-redactor.sh

# Initialize
redact_init

# Redact string
redacted=$(redact_string "API_KEY=abc123xyz...")
echo "$redacted"  # API_KEY=**REDACTED-API-KEY**

# Preview redaction (no changes)
redact_preview "GITHUB_TOKEN=ghp_abc123..."

# Redact file (IN-PLACE - use with caution!)
redact_file "config.env"

# Redact with automatic backup (RECOMMENDED)
redact_with_backup "config.env"

# Preview file redaction
redact_preview_file "config.env"

# Interactive redaction (prompts user)
redact_interactive "config.env"

# Backup management
redact_list_backups "config.env"
redact_restore_latest "config.env"
redact_restore_from "config.env" "config.env.credential-backup.20250105_120000"
redact_cleanup_backups "config.env" 5  # Keep 5 most recent

# Statistics
redact_get_stats
redact_view_log 50  # Last 50 redactions
```

### 3. credential-scanner.sh
Integration layer for real-time credential detection.

**Features:**
- User alerts with severity-based formatting
- Automatic revocation tracking
- Integration-ready for handlers
- Auto-redaction for logging
- Comprehensive statistics

**Usage:**

```bash
source src/security/credential-scanner.sh

# Initialize
scanner_init

# Scan string with user alert
scanner_scan_string "OPENAI_API_KEY=sk-abc..." "bash_command"

# Scan command
scanner_scan_command "export TOKEN=xyz..."

# Scan tool input (JSON)
scanner_scan_tool_input "$tool_input" "bash"

# Scan file
scanner_scan_file "config.env"

# Scan conversation history
scanner_scan_conversation "$HOME/.claude/history.jsonl"

# Auto-redact for safe logging
safe_output=$(scanner_auto_redact "$output")

# Silent check
if scanner_has_credentials "$text"; then
    echo "Contains credentials"
fi

# Statistics
scanner_get_stats
scanner_view_alerts 50
```

## Integration with Handlers

### Quick Integration Pattern

```bash
# In any handler (bash-handler.sh, write-handler.sh, etc.):

# 1. Source the scanner
if [[ -f "${HANDLER_DIR}/../security/credential-scanner.sh" ]]; then
    source "${HANDLER_DIR}/../security/credential-scanner.sh"
    _CREDENTIAL_SCAN_ENABLED=true
else
    _CREDENTIAL_SCAN_ENABLED=false
fi

# 2. Add security check in handler function
if [[ "${_CREDENTIAL_SCAN_ENABLED}" == "true" ]]; then
    if scanner_scan_command "${command}"; then
        # Credential detected, user was alerted
        # Decide: block, redact, or continue
    fi
fi
```

See `examples/credential-detection-integration.sh` for detailed integration examples.

## Testing

### Run Detector Tests (30+ credential samples)
```bash
bash tests/security/test-credential-detector.sh
```

### Run Redactor Tests
```bash
bash tests/security/test-credential-redactor.sh
```

### Test Coverage
- GitHub tokens (5 variants)
- NPM tokens
- GitLab tokens
- OpenAI API keys
- Anthropic API keys
- AWS keys
- Slack tokens
- Google API keys
- Stripe keys
- Twilio credentials
- SendGrid keys
- Mailgun keys
- JWT tokens
- PyPI tokens
- Docker tokens
- Generic API keys
- Generic tokens
- Generic secrets
- Generic passwords
- Bearer tokens
- Basic auth
- Database connection strings
- Private keys
- SSH keys
- False positive detection (10+ cases)

## Security Principles

1. **Defense in Depth**: Multiple pattern types, context awareness
2. **High Sensitivity**: Prefer false positives over false negatives
3. **Safety First**: Automatic backups, preview mode
4. **Audit Trail**: Comprehensive logging
5. **Reversible**: All operations can be undone
6. **User Control**: Interactive confirmations for critical actions

## Files Generated

- `~/.wow/logs/credential-alerts.log` - Alert log
- `~/.wow/logs/redactions.log` - Redaction log
- `~/URGENT-REVOKE-TOKENS.txt` - Revocation reminder list
- `*.credential-backup.*` - Backup files

## Example Workflows

### 1. Scan project for credentials
```bash
find . -type f -name "*.sh" | while read -r file; do
    if scanner_has_credentials "$(<"$file")"; then
        scanner_scan_file "$file"
    fi
done
```

### 2. Pre-commit hook
```bash
# In .git/hooks/pre-commit
source src/security/credential-scanner.sh

git diff --cached --name-only | while read -r file; do
    if scanner_has_credentials "$(git show ":$file")"; then
        echo "ERROR: Credentials in $file"
        exit 1
    fi
done
```

### 3. Clean up configuration file
```bash
# Preview first
redact_preview_file "config.env"

# Redact with backup
redact_with_backup "config.env"

# Verify
cat "config.env"

# Restore if needed
redact_restore_latest "config.env"
```

### 4. Scan and clean conversation history
```bash
# Scan
scanner_scan_conversation "$HOME/.claude/history.jsonl"

# Redact
redact_with_backup "$HOME/.claude/history.jsonl"

# Check stats
scanner_get_stats
```

## Performance

- String scanning: < 1ms per string
- File scanning: ~ 10-50ms per file (depends on size)
- Conversation scanning: ~ 100-500ms (depends on history size)
- Minimal overhead when no credentials detected

## Limitations

- English-language patterns only
- Base64/hex detection may have false positives
- Custom credential formats require adding new patterns
- No ML-based detection (pattern-based only)

## Future Enhancements

1. Machine learning-based detection
2. Custom pattern configuration
3. Email alerts for HIGH severity
4. Integration with secret vaults (1Password, etc.)
5. Automatic secret rotation
6. GitHub/GitLab API integration for token revocation

## Author

Chude <chude@emeke.org>

## Version

5.0.1

## License

Part of WoW System v5.0.1
