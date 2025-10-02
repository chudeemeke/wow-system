# WoW System API Reference

Version: 4.3.0

This document provides a complete API reference for all WoW System modules, functions, and interfaces.

---

## Table of Contents

1. [Core Modules](#core-modules)
2. [Handler Modules](#handler-modules)
3. [Engine Modules](#engine-modules)
4. [UI Modules](#ui-modules)
5. [Utility Modules](#utility-modules)
6. [Configuration](#configuration)
7. [Session State](#session-state)
8. [Return Codes](#return-codes)

---

## Core Modules

### orchestrator.sh

Central initialization facade for all WoW System modules.

#### Functions

##### `orchestrator_init [module_dir]`
Initialize the WoW System with all required modules.

**Parameters:**
- `module_dir` (optional): Directory containing modules. Defaults to auto-detected path.

**Returns:**
- `0`: Success
- `1`: Initialization failed

**Example:**
```bash
source orchestrator.sh
orchestrator_init "/path/to/wow-system"
```

##### `orchestrator_load_module <name> <path>`
Load an individual module into the system.

**Parameters:**
- `name`: Module name (for tracking)
- `path`: Path to module file

**Returns:**
- `0`: Module loaded successfully
- `1`: Module load failed

---

### handler-router.sh

Routes tool calls to appropriate security handlers using Strategy pattern.

#### Functions

##### `handler_register <tool_name> <handler_path>`
Register a security handler for a specific tool.

**Parameters:**
- `tool_name`: Name of Claude Code tool (e.g., "Bash", "Write")
- `handler_path`: Path to handler script

**Returns:**
- `0`: Handler registered successfully
- `1`: Registration failed

**Example:**
```bash
handler_register "Bash" "${handler_dir}/bash-handler.sh"
```

##### `handler_route <tool_name> <json_params>`
Route a tool call to its registered handler.

**Parameters:**
- `tool_name`: Name of tool being invoked
- `json_params`: JSON string with tool parameters

**Returns:**
- `0`: Operation allowed
- `1`: Operation blocked
- `2`: Warning issued (operation proceeds)

**Example:**
```bash
handler_route "Bash" '{"command": "ls -la"}'
```

##### `handler_list`
List all registered handlers.

**Returns:**
- Outputs list of registered tool handlers

---

## Handler Modules

All handlers follow a common interface pattern.

### Common Handler Interface

#### Required Function

##### `handle_<toolname> <json_params>`
Main entry point for each handler.

**Parameters:**
- `json_params`: JSON string containing tool-specific parameters

**Returns:**
- `0`: Operation allowed
- `1`: Operation blocked (sets `WOW_BLOCK_REASON`)
- `2`: Warning issued (sets `WOW_WARN_REASON`)

**Global Variables Set:**
- `WOW_BLOCK_REASON`: Explanation if blocked
- `WOW_WARN_REASON`: Explanation if warned
- `WOW_RISK_LEVEL`: Risk assessment (none/low/medium/high/critical)

---

### bash-handler.sh

Secures command execution via the Bash tool.

#### Functions

##### `handle_bash <json_params>`
Validate and secure bash command execution.

**JSON Parameters:**
```json
{
  "command": "string",
  "description": "string (optional)",
  "timeout": number (optional)
}
```

**Security Checks:**
- Dangerous commands (rm -rf /, sudo rm, dd, mkfs)
- Fork bombs (:(){ :|:& };:)
- Git commit auto-fixing (emoji removal, author addition)
- Heuristic safety analysis

**Example:**
```bash
handle_bash '{"command": "ls -la", "description": "List files"}'
# Returns: 0 (allowed)

handle_bash '{"command": "rm -rf /", "description": "Delete everything"}'
# Returns: 1 (blocked), WOW_BLOCK_REASON="Dangerous command: rm -rf /"
```

---

### write-handler.sh

Secures file creation via the Write tool.

#### Functions

##### `handle_write <json_params>`
Validate and secure file write operations.

**JSON Parameters:**
```json
{
  "file_path": "string",
  "content": "string"
}
```

**Security Checks:**
- System directory protection (/etc, /bin, /usr, /boot)
- Path traversal prevention
- Malicious content detection
- Credential detection (passwords, API keys, private keys)
- Binary file detection

**Example:**
```bash
handle_write '{"file_path": "/tmp/safe.txt", "content": "Hello World"}'
# Returns: 0 (allowed)

handle_write '{"file_path": "/etc/passwd", "content": "malicious"}'
# Returns: 1 (blocked), WOW_BLOCK_REASON="Cannot write to system directory: /etc"
```

---

### edit-handler.sh

Secures file modification via the Edit tool.

#### Functions

##### `handle_edit <json_params>`
Validate and secure file edit operations.

**JSON Parameters:**
```json
{
  "file_path": "string",
  "old_string": "string",
  "new_string": "string",
  "replace_all": boolean (optional)
}
```

**Security Checks:**
- System file protection
- Security code removal detection
- Dangerous replacement detection
- Edit validation

**Example:**
```bash
handle_edit '{"file_path": "/tmp/config.sh", "old_string": "DEBUG=0", "new_string": "DEBUG=1"}'
# Returns: 0 (allowed)

handle_edit '{"file_path": "/tmp/auth.sh", "old_string": "verify_password", "new_string": "# verify_password"}'
# Returns: 1 (blocked), WOW_BLOCK_REASON="Removing security code"
```

---

### read-handler.sh

Secures file reading via the Read tool.

#### Functions

##### `handle_read <json_params>`
Validate and secure file read operations.

**JSON Parameters:**
```json
{
  "file_path": "string",
  "offset": number (optional),
  "limit": number (optional)
}
```

**Security Checks:**
- Sensitive file blocking (/etc/shadow, SSH keys, AWS credentials)
- Cryptocurrency wallet protection
- Credential file warnings (.env, credentials.json)
- Browser data protection
- Anti-exfiltration (high read volume detection)

**Example:**
```bash
handle_read '{"file_path": "/tmp/data.txt"}'
# Returns: 0 (allowed)

handle_read '{"file_path": "/etc/shadow"}'
# Returns: 1 (blocked), WOW_BLOCK_REASON="Cannot read sensitive system file"
```

---

### glob-handler.sh

Secures file pattern matching via the Glob tool.

#### Functions

##### `handle_glob <json_params>`
Validate and secure glob operations.

**JSON Parameters:**
```json
{
  "pattern": "string",
  "path": "string (optional)"
}
```

**Security Checks:**
- Protected directory blocking (/etc, /root, /sys, ~/.ssh)
- Overly broad pattern detection (/**/* , **/* at root)
- Credential search warnings (**/.env, **/id_rsa)
- Path traversal detection

**Example:**
```bash
handle_glob '{"pattern": "*.txt", "path": "/tmp"}'
# Returns: 0 (allowed)

handle_glob '{"pattern": "**/*", "path": "/"}'
# Returns: 2 (warning), WOW_WARN_REASON="Overly broad glob pattern"
```

---

### grep-handler.sh

Secures content searching via the Grep tool.

#### Functions

##### `handle_grep <json_params>`
Validate and secure grep operations.

**JSON Parameters:**
```json
{
  "pattern": "string",
  "path": "string (optional)",
  "glob": "string (optional)",
  "type": "string (optional)",
  "output_mode": "string (optional)"
}
```

**Security Checks:**
- Sensitive directory protection (/etc, /root, ~/.ssh)
- Credential pattern detection (password, api_key, secret)
- Private key pattern detection (BEGIN.*PRIVATE KEY)
- PII protection (SSN, credit card numbers)

**Example:**
```bash
handle_grep '{"pattern": "TODO", "path": "./src"}'
# Returns: 0 (allowed)

handle_grep '{"pattern": "password.*=", "path": "/etc"}'
# Returns: 2 (warning), WOW_WARN_REASON="Searching for credential patterns"
```

---

### task-handler.sh

Monitors autonomous agent launches via the Task tool.

#### Functions

##### `handle_task <json_params>`
Monitor and validate Task tool invocations.

**JSON Parameters:**
```json
{
  "prompt": "string",
  "description": "string",
  "subagent_type": "string"
}
```

**Security Checks:**
- Dangerous pattern detection (infinite loops, recursive spawning)
- Credential harvesting detection
- Data exfiltration detection
- Network abuse detection
- Resource abuse prevention (rate limiting: 20/session, 5/minute)

**Example:**
```bash
handle_task '{"prompt": "Search for class definitions", "subagent_type": "general-purpose"}'
# Returns: 0 (allowed)

handle_task '{"prompt": "Launch 100 agents recursively", "subagent_type": "general-purpose"}'
# Returns: 2 (warning), WOW_WARN_REASON="Dangerous task pattern: recursive agent spawning"
```

---

### webfetch-handler.sh

Secures external URL access via the WebFetch tool.

#### Functions

##### `handle_webfetch <json_params>`
Validate and secure web fetch operations.

**JSON Parameters:**
```json
{
  "url": "string",
  "prompt": "string"
}
```

**Security Checks:**
- SSRF prevention (blocks private IPs: 192.168.x.x, 10.x.x.x, 127.x.x.x, etc.)
- Protocol security (blocks file://, ftp://)
- Credential protection (warns on URLs with embedded credentials)
- Suspicious domain detection (.tk, .ml, .ga TLDs)
- Data exfiltration prevention (pastebin, webhook endpoints)
- URL shortener detection

**Example:**
```bash
handle_webfetch '{"url": "https://docs.example.com", "prompt": "Get documentation"}'
# Returns: 0 (allowed)

handle_webfetch '{"url": "http://192.168.1.1/admin", "prompt": "Access internal"}'
# Returns: 1 (blocked), WOW_BLOCK_REASON="Private IP address detected (SSRF prevention)"
```

---

## Engine Modules

### scoring-engine.sh

Manages behavior scoring and assessment.

#### Functions

##### `score_init [initial_score]`
Initialize scoring for current session.

**Parameters:**
- `initial_score` (optional): Starting score (default: 100)

**Returns:**
- `0`: Success

##### `score_penalize <points> <reason>`
Apply penalty to current score.

**Parameters:**
- `points`: Points to deduct (positive number)
- `reason`: Explanation for penalty

**Returns:**
- `0`: Success

**Example:**
```bash
score_penalize 10 "Attempted dangerous operation"
```

##### `score_reward <points> <reason>`
Apply reward to current score.

**Parameters:**
- `points`: Points to add
- `reason`: Explanation for reward

**Returns:**
- `0`: Success

##### `score_decay`
Apply natural score decay (gradual improvement).

**Returns:**
- `0`: Success

##### `score_get`
Get current score.

**Returns:**
- Outputs current score (0-100)

##### `score_status`
Get status based on current score.

**Returns:**
- Outputs status: excellent/good/warn/critical/blocked

**Thresholds:**
- excellent: 80-100
- good: 50-79
- warn: 30-49
- critical: 10-29
- blocked: 0-9

##### `score_history [count]`
Get score history.

**Parameters:**
- `count` (optional): Number of recent entries (default: 10)

**Returns:**
- Outputs score history

---

### risk-assessor.sh

Multi-factor risk analysis engine.

#### Functions

##### `risk_assess <operation> <params_json>`
Perform comprehensive risk assessment.

**Parameters:**
- `operation`: Operation type (bash/write/edit/read/glob/grep/task/webfetch)
- `params_json`: JSON parameters for operation

**Returns:**
- Outputs risk level: none/low/medium/high/critical

**Assessment Factors:**
- Path risk (30%): Location sensitivity
- Content risk (25%): Data sensitivity
- Operation risk (20%): Action danger level
- Frequency risk (15%): Rate limiting
- Context risk (10%): Current WoW score

**Example:**
```bash
risk_level=$(risk_assess "write" '{"file_path": "/etc/passwd"}')
# Returns: "critical"
```

##### `risk_score_path <path>`
Assess path-based risk.

**Returns:**
- `0-100`: Risk score (higher = more risky)

##### `risk_score_content <content>`
Assess content-based risk.

**Returns:**
- `0-100`: Risk score

##### `risk_score_operation <operation>`
Assess operation-based risk.

**Returns:**
- `0-100`: Risk score

---

## UI Modules

### display.sh

Visual feedback and UI components.

#### Functions

##### `display_banner`
Show WoW System banner with current score.

**Returns:**
- Outputs formatted banner

##### `display_feedback <type> <message>`
Display feedback message to user.

**Parameters:**
- `type`: success/warning/error/blocked
- `message`: Message to display

**Returns:**
- Outputs colored, formatted message

**Example:**
```bash
display_feedback "warning" "This operation may be risky"
display_feedback "blocked" "Operation blocked: dangerous command"
```

##### `display_progress <message>`
Show progress indicator.

**Parameters:**
- `message`: Progress message

**Returns:**
- Outputs progress indicator

##### `display_score_gauge [score]`
Display visual score gauge.

**Parameters:**
- `score` (optional): Score to display (default: current score)

**Returns:**
- Outputs colored score gauge

##### `display_metrics`
Display session metrics.

**Returns:**
- Outputs metrics table

---

## Utility Modules

### utils.sh

Common utilities and helpers.

#### Functions

##### `log <level> <message>`
Log a message with level.

**Parameters:**
- `level`: DEBUG/INFO/WARN/ERROR
- `message`: Log message

**Returns:**
- Outputs to log file

**Example:**
```bash
log "INFO" "Handler initialized successfully"
log "ERROR" "Failed to load module"
```

##### `validate_path <path>`
Validate a file path.

**Parameters:**
- `path`: Path to validate

**Returns:**
- `0`: Valid path
- `1`: Invalid path

##### `validate_json <json_string>`
Validate JSON syntax.

**Parameters:**
- `json_string`: JSON to validate

**Returns:**
- `0`: Valid JSON
- `1`: Invalid JSON

##### `extract_json_value <json> <key>`
Extract value from JSON.

**Parameters:**
- `json`: JSON string
- `key`: Key to extract

**Returns:**
- Outputs value

**Example:**
```bash
command=$(extract_json_value "$params" "command")
```

##### `is_system_path <path>`
Check if path is a system path.

**Parameters:**
- `path`: Path to check

**Returns:**
- `0`: Is system path
- `1`: Not system path

**System paths:**
- `/etc`, `/bin`, `/usr`, `/boot`, `/sys`, `/proc`, `/dev`, `/root`

---

### file-storage.sh

Key-value persistent storage.

#### Functions

##### `storage_init [storage_dir]`
Initialize storage system.

**Parameters:**
- `storage_dir` (optional): Storage directory

**Returns:**
- `0`: Success
- `1`: Failed

##### `storage_set <namespace> <key> <value>`
Store a value.

**Parameters:**
- `namespace`: Storage namespace
- `key`: Storage key
- `value`: Value to store

**Returns:**
- `0`: Success
- `1`: Failed

**Example:**
```bash
storage_set "metrics" "violations" "5"
```

##### `storage_get <namespace> <key>`
Retrieve a value.

**Parameters:**
- `namespace`: Storage namespace
- `key`: Storage key

**Returns:**
- Outputs value (or empty if not found)

##### `storage_delete <namespace> <key>`
Delete a value.

**Parameters:**
- `namespace`: Storage namespace
- `key`: Storage key

**Returns:**
- `0`: Success

##### `storage_list <namespace>`
List all keys in namespace.

**Parameters:**
- `namespace`: Storage namespace

**Returns:**
- Outputs list of keys

---

### state-manager.sh

In-memory session state management.

#### Functions

##### `state_init`
Initialize state manager.

**Returns:**
- `0`: Success

##### `state_set <key> <value>`
Set state value.

**Parameters:**
- `key`: State key
- `value`: Value

**Returns:**
- `0`: Success

**Example:**
```bash
state_set "wow_score" "85"
```

##### `state_get <key>`
Get state value.

**Parameters:**
- `key`: State key

**Returns:**
- Outputs value (or empty if not found)

##### `state_increment <key> [amount]`
Increment numeric state value.

**Parameters:**
- `key`: State key
- `amount` (optional): Amount to increment (default: 1)

**Returns:**
- `0`: Success

##### `state_save`
Save state to persistent storage.

**Returns:**
- `0`: Success

##### `state_load`
Load state from persistent storage.

**Returns:**
- `0`: Success

---

### config-loader.sh

Configuration management.

#### Functions

##### `config_init [config_file]`
Initialize configuration.

**Parameters:**
- `config_file` (optional): Path to config JSON file

**Returns:**
- `0`: Success
- `1`: Failed

##### `config_get <key>`
Get configuration value.

**Parameters:**
- `key`: Config key (supports nested: "enforcement.strict_mode")

**Returns:**
- Outputs value

**Example:**
```bash
strict_mode=$(config_get "enforcement.strict_mode")
warn_threshold=$(config_get "scoring.warn_threshold")
```

##### `config_set <key> <value>`
Set configuration value (runtime only, not persisted).

**Parameters:**
- `key`: Config key
- `value`: Value

**Returns:**
- `0`: Success

---

### session-manager.sh

Session lifecycle orchestration.

#### Functions

##### `session_init`
Initialize new session.

**Returns:**
- `0`: Success

##### `session_start`
Start session tracking.

**Returns:**
- `0`: Success

##### `session_end`
End session and save state.

**Returns:**
- `0`: Success

##### `session_event <event_type> <details>`
Record session event.

**Parameters:**
- `event_type`: Event type (violation/warning/success)
- `details`: Event details

**Returns:**
- `0`: Success

**Example:**
```bash
session_event "violation" "Blocked dangerous command: rm -rf /"
```

##### `session_metric <metric_name> <value>`
Record session metric.

**Parameters:**
- `metric_name`: Metric name
- `value`: Metric value

**Returns:**
- `0`: Success

##### `session_get_stats`
Get session statistics.

**Returns:**
- Outputs session statistics as JSON

---

## Configuration

### Config File: config/wow-config.json

```json
{
  "version": "4.3.0",
  "enforcement": {
    "strict_mode": true,
    "block_on_violation": true,
    "warn_on_suspicious": true
  },
  "scoring": {
    "initial_score": 100,
    "warn_threshold": 50,
    "block_threshold": 30,
    "decay_rate": 1,
    "decay_interval": 300,
    "min_score": 0,
    "max_score": 100
  },
  "integration": {
    "claude_code": {
      "enabled": true,
      "hook_path": "~/.claude/hooks/user-prompt-submit.sh"
    }
  },
  "logging": {
    "level": "INFO",
    "file": "/tmp/wow-system.log"
  }
}
```

### Configuration Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enforcement.strict_mode` | boolean | true | Enable strict enforcement |
| `enforcement.block_on_violation` | boolean | true | Block operations on violations |
| `enforcement.warn_on_suspicious` | boolean | true | Warn on suspicious patterns |
| `scoring.initial_score` | number | 100 | Starting score for new sessions |
| `scoring.warn_threshold` | number | 50 | Score threshold for warnings |
| `scoring.block_threshold` | number | 30 | Score threshold for blocking |
| `scoring.decay_rate` | number | 1 | Points added per decay interval |
| `scoring.decay_interval` | number | 300 | Seconds between decay applications |
| `integration.claude_code.enabled` | boolean | true | Enable Claude Code integration |
| `logging.level` | string | INFO | Log level (DEBUG/INFO/WARN/ERROR) |

---

## Session State

### State Keys

| Key | Type | Description |
|-----|------|-------------|
| `wow_score` | number | Current WoW score (0-100) |
| `wow_status` | string | Current status (excellent/good/warn/critical/blocked) |
| `session_id` | string | Unique session identifier |
| `session_start` | timestamp | Session start time |
| `violations` | number | Total violations in session |
| `warnings` | number | Total warnings in session |
| `operations` | number | Total operations in session |
| `bash_count` | number | Bash operations count |
| `write_count` | number | Write operations count |
| `edit_count` | number | Edit operations count |
| `read_count` | number | Read operations count |
| `glob_count` | number | Glob operations count |
| `grep_count` | number | Grep operations count |
| `task_count` | number | Task operations count |
| `webfetch_count` | number | WebFetch operations count |

### Accessing State

```bash
# Get current score
current_score=$(state_get "wow_score")

# Get violations count
violations=$(state_get "violations")

# Increment operation count
state_increment "bash_count"
```

---

## Return Codes

### Standard Return Codes

| Code | Meaning | Description |
|------|---------|-------------|
| `0` | Success/Allowed | Operation completed successfully or is allowed to proceed |
| `1` | Error/Blocked | Operation failed or is blocked |
| `2` | Warning | Warning issued but operation proceeds |

### Handler-Specific Codes

All handlers follow the standard return code convention:
- `0`: Operation is allowed
- `1`: Operation is blocked (sets `WOW_BLOCK_REASON`)
- `2`: Warning issued (sets `WOW_WARN_REASON`)

---

## Global Variables

### Handler Output Variables

| Variable | Type | Description |
|----------|------|-------------|
| `WOW_BLOCK_REASON` | string | Explanation for blocking operation |
| `WOW_WARN_REASON` | string | Explanation for warning |
| `WOW_RISK_LEVEL` | string | Risk level (none/low/medium/high/critical) |
| `WOW_SCORE` | number | Current WoW score |
| `WOW_STATUS` | string | Current status |

### Example Usage

```bash
# Call handler
if handle_bash '{"command": "rm -rf /"}'; then
  echo "Operation allowed"
else
  echo "Operation blocked: $WOW_BLOCK_REASON"
  echo "Risk level: $WOW_RISK_LEVEL"
fi
```

---

## Error Handling

### Error Messages

All modules follow consistent error messaging:

```bash
# Success (silent)
return 0

# Error with message
log "ERROR" "Failed to initialize module: $module_name"
return 1

# Warning with message
log "WARN" "Suspicious pattern detected: $pattern"
return 2
```

### Error Codes by Module

| Module | Error Code | Meaning |
|--------|------------|---------|
| orchestrator | 1 | Module initialization failed |
| handler-router | 1 | Handler registration failed or routing failed |
| All handlers | 1 | Operation blocked |
| All handlers | 2 | Warning issued |
| scoring-engine | 1 | Scoring operation failed |
| risk-assessor | 1 | Risk assessment failed |

---

## Testing API

### Test Framework Functions

#### `assert_equals <expected> <actual> <message>`
Assert two values are equal.

#### `assert_not_equals <expected> <actual> <message>`
Assert two values are not equal.

#### `assert_contains <haystack> <needle> <message>`
Assert string contains substring.

#### `assert_success <command> <message>`
Assert command returns 0.

#### `assert_failure <command> <message>`
Assert command returns non-zero.

---

## Integration Examples

### Basic Handler Integration

```bash
#!/bin/bash

# Source orchestrator
source /path/to/wow-system/src/orchestrator.sh

# Initialize system
orchestrator_init

# Route a tool call
json_params='{"command": "ls -la", "description": "List files"}'
if handler_route "Bash" "$json_params"; then
  # Execute actual command
  ls -la
else
  echo "Operation blocked: $WOW_BLOCK_REASON"
  exit 1
fi
```

### Claude Code Hook Integration

```bash
#!/bin/bash

# In ~/.claude/hooks/user-prompt-submit.sh

source /path/to/wow-system/src/orchestrator.sh
orchestrator_init

# Extract tool and parameters from Claude Code
tool_name="$1"
json_params="$2"

# Route through handler
if ! handler_route "$tool_name" "$json_params"; then
  echo "WoW System blocked operation: $WOW_BLOCK_REASON"
  exit 1
fi

# Allow operation to proceed
exit 0
```

---

## Performance Considerations

### Overhead

- Handler routing: ~10-50ms per operation
- State persistence: ~5-20ms per save
- Risk assessment: ~5-15ms per assessment
- Total overhead: ~20-85ms per tool call

### Optimization Tips

1. **Minimize state saves**: Only save on important events
2. **Cache handler registrations**: Don't re-register on each call
3. **Batch risk assessments**: Assess multiple operations together
4. **Use selective logging**: Only log at appropriate levels

---

## Version History

- **v4.3.0**: Added Task and WebFetch handlers, complete API coverage
- **v4.2.0**: Added Read, Glob, Grep handlers
- **v4.1.0**: Initial release with core framework and Bash, Write, Edit handlers

---

## Support

For issues, questions, or contributions:
- **Author**: Chude <chude@emeke.org>
- **Repository**: (pending GitHub setup)

---

Last Updated: 2025-10-02
