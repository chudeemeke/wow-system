# Capture Engine Integration Guide

## Overview

The Capture Engine is a real-time frustration detection and pattern analysis system for WoW v5.0.1. It monitors user interactions with handlers, detects frustration-worthy events, analyzes patterns, and intelligently decides when to prompt users for feedback.

**File:** `/src/engines/capture-engine.sh`
**Version:** 1.0.0
**Dependencies:** event-bus.sh, session-manager.sh, utils.sh

## Architecture

The Capture Engine follows WoW's design principles:

- **Event-driven**: Subscribes to event bus for real-time detection
- **Loosely coupled**: Integrates via well-defined event contracts
- **Tightly integrated**: Seamlessly works with existing WoW core
- **Pattern recognition**: Analyzes event sequences for intelligent prompting
- **User sovereignty**: Respects cooldown periods and user preferences

## Core Functions

### Initialization

```bash
capture_engine_init()
```

Initializes the capture engine:
- Creates session state for tracking frustrations
- Subscribes to event bus events
- Sets up default metrics

**Example:**
```bash
source src/core/orchestrator.sh
source src/engines/capture-engine.sh

wow_init
capture_engine_init

# Engine is now listening for events
```

### Event Detection

```bash
capture_detect_event(event_type, context, details)
```

Detects and records a frustration-worthy event.

**Parameters:**
- `event_type`: Type of event (handler.blocked, handler.error, etc.)
- `context`: Context where event occurred (handler name, path, etc.)
- `details`: Additional details about the event

**Returns:** Frustration ID

**Example:**
```bash
# Detect a blocked operation
frust_id=$(capture_detect_event "handler.blocked" "Bash" "operation=rm_rf|path=/data")

# Detect an error
frust_id=$(capture_detect_event "handler.error" "Write" "error=EACCES|path=/etc/config")

# Detect path issue
frust_id=$(capture_detect_event "path.issue" "/path with spaces/file.txt" "space_in_path")
```

### Pattern Analysis

```bash
capture_analyze_pattern()
```

Analyzes recent frustrations to detect patterns.

**Returns:** Pattern type (repeated_error, rapid_fire, workaround_attempt, path_pattern, none)

**Example:**
```bash
pattern=$(capture_analyze_pattern)

case "$pattern" in
    repeated_error)
        echo "User is hitting the same error repeatedly"
        ;;
    rapid_fire)
        echo "Multiple events in quick succession"
        ;;
    workaround_attempt)
        echo "User tried a workaround after being blocked"
        ;;
    path_pattern)
        echo "Multiple path-related issues detected"
        ;;
    none)
        echo "No clear pattern yet"
        ;;
esac
```

### Prompting Decision

```bash
capture_should_prompt()
```

Determines if user should be prompted for feedback.

**Returns:** "true" or "false"

**Considers:**
- Number of frustrations (threshold: 3+)
- Recent prompt cooldown (5 minutes)
- Critical patterns (security issues = immediate prompt)
- Pattern confidence level

**Example:**
```bash
if [[ "$(capture_should_prompt)" == "true" ]]; then
    echo "Time to prompt user for feedback"
    # Trigger email/prompt system

    # Mark that we prompted (starts cooldown)
    capture_mark_prompted
fi
```

### Confidence Scoring

```bash
capture_get_confidence()
```

Rates confidence level for current frustration state.

**Returns:** CRITICAL, HIGH, MEDIUM, LOW

**Example:**
```bash
confidence=$(capture_get_confidence)

case "$confidence" in
    CRITICAL)
        echo "Immediate action required (security issue)"
        ;;
    HIGH)
        echo "Clear pattern detected - high confidence"
        ;;
    MEDIUM)
        echo "Multiple events - moderate confidence"
        ;;
    LOW)
        echo "Single event - low confidence"
        ;;
esac
```

## Event Types

The Capture Engine listens for these event types:

| Event Type | Description | Example Context |
|------------|-------------|----------------|
| `handler.blocked` | Dangerous operation blocked | handler=Bash, operation=rm_rf |
| `handler.error` | Handler operation failed | handler=Write, error=EACCES |
| `handler.retry` | Operation retried | handler=Edit, reason=file_locked |
| `path.issue` | Path-related problem | /path with spaces/file.txt |
| `security.credential` | Credential exposure detected | API_KEY=secret123 |
| `workaround.detected` | Manual workaround attempted | symlink_created |

## Integration Examples

### Example 1: Event Bus Integration

The Capture Engine automatically subscribes to event bus events during initialization:

```bash
# In your handler code
source src/patterns/event-bus.sh
source src/engines/capture-engine.sh

# Initialize
event_bus_init
capture_engine_init

# Handler publishes events - capture engine automatically detects them
event_bus_publish "handler.blocked" "handler=Bash|operation=rm_rf|path=/data"
event_bus_publish "handler.error" "handler=Write|error=EACCES|path=/etc/test"

# Check if we should prompt
if [[ "$(capture_should_prompt)" == "true" ]]; then
    # Trigger feedback system
    echo "User needs assistance!"
fi
```

### Example 2: Manual Detection with Analysis

```bash
# Detect events manually
capture_detect_event "handler.blocked" "Bash" "dangerous_operation"
sleep 1
capture_detect_event "handler.error" "Write" "permission_denied"
sleep 1
capture_detect_event "handler.blocked" "Bash" "dangerous_operation"

# Analyze what's happening
pattern=$(capture_analyze_pattern)
confidence=$(capture_get_confidence)

echo "Pattern: $pattern"
echo "Confidence: $confidence"

# Get summary
capture_summary
```

### Example 3: Real-time Monitoring

```bash
#!/bin/bash
# Real-time frustration monitor

source src/core/orchestrator.sh
source src/engines/capture-engine.sh

wow_init
capture_engine_init

echo "Monitoring for frustrations..."

# Events come in via event bus from handlers
# Check periodically for prompting
while true; do
    sleep 30  # Check every 30 seconds

    if [[ "$(capture_should_prompt)" == "true" ]]; then
        echo "=== FRUSTRATION DETECTED ==="
        capture_summary
        echo ""

        # Trigger email/notification
        # (integrate with email system here)

        # Mark prompted to start cooldown
        capture_mark_prompted
    fi
done
```

### Example 4: Frustration Report Generation

```bash
# Generate detailed frustration report

echo "=== Frustration Analysis Report ==="
echo ""

# Get current state
count=$(session_get_metric "frustration_count" "0")
total=$(session_get_metric "total_frustrations_captured" "0")

echo "Active Frustrations: $count"
echo "Total Captured (this session): $total"
echo ""

# Pattern analysis
pattern=$(capture_analyze_pattern)
echo "Pattern Detected: $pattern"

# Confidence
confidence=$(capture_get_confidence)
echo "Confidence Level: $confidence"
echo ""

# List recent frustrations
echo "Recent Frustrations:"
capture_get_all_frustrations | tail -5 | while IFS= read -r line; do
    frust_id="${line%%=*}"
    frust_id="${frust_id#frustration:}"
    value="${line#*=}"

    event=$(echo "$value" | grep -oP 'event=\K[^|]+')
    context=$(echo "$value" | grep -oP 'context=\K[^|]+')
    timestamp=$(echo "$value" | grep -oP 'timestamp=\K[^|]+')

    date_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")

    echo "  [$date_str] $event - $context"
done
```

## Pattern Detection Logic

### Repeated Error Pattern

Triggered when the same error occurs 3+ times in the recency window (5 minutes).

```bash
# Same error 3 times
capture_detect_event "handler.error" "Bash" "error=ENOENT|file=test.txt"
capture_detect_event "handler.error" "Bash" "error=ENOENT|file=test.txt"
capture_detect_event "handler.error" "Bash" "error=ENOENT|file=test.txt"

pattern=$(capture_analyze_pattern)
# Returns: "repeated_error"
```

### Rapid-Fire Pattern

Triggered when 4+ events occur within 60 seconds.

```bash
# Multiple events in quick succession
capture_detect_event "handler.blocked" "Bash" "op1"
capture_detect_event "handler.blocked" "Bash" "op2"
capture_detect_event "handler.blocked" "Bash" "op3"
capture_detect_event "handler.blocked" "Bash" "op4"

pattern=$(capture_analyze_pattern)
# Returns: "rapid_fire"
```

### Workaround Pattern

Triggered when user attempts workarounds after being blocked.

```bash
# User blocked -> tries workaround -> blocked again
capture_detect_event "handler.blocked" "Bash" "operation"
capture_detect_event "workaround.detected" "symlink_created" "manual_fix"
capture_detect_event "handler.blocked" "Bash" "operation"

pattern=$(capture_analyze_pattern)
# Returns: "workaround_attempt"
```

### Path Pattern

Triggered when multiple path issues occur.

```bash
# Multiple path issues
capture_detect_event "path.issue" "/path with spaces/file1.txt" "space"
capture_detect_event "path.issue" "/another path/file2.txt" "space"

pattern=$(capture_analyze_pattern)
# Returns: "path_pattern"
```

## Configuration

### Thresholds (constants in capture-engine.sh)

```bash
FRUSTRATION_THRESHOLD=3           # Prompt after N frustrations
RAPID_FIRE_THRESHOLD=4            # N events = rapid-fire
RAPID_FIRE_WINDOW=60              # Seconds for rapid-fire detection
PROMPT_COOLDOWN=300               # 5 minutes between prompts
EVENT_RECENCY_WINDOW=300          # Only consider recent events
```

To customize, modify these constants in `src/engines/capture-engine.sh`.

## API Reference

### Management Functions

**capture_clear_frustrations()**
- Clears all frustration data
- Resets counters to zero
- Useful for testing or manual reset

**capture_engine_reset()**
- Unsubscribes from all events
- Clears all frustration data
- Full engine shutdown

**capture_mark_prompted()**
- Records that user was prompted
- Starts cooldown period
- Prevents prompt spam

### Retrieval Functions

**capture_get_frustration(frustration_id)**
- Returns details of specific frustration
- Format: "event=X|context=Y|details=Z|timestamp=T"

**capture_get_all_frustrations()**
- Lists all recorded frustrations
- One per line
- Format: frustration:frust_ID=details

**capture_summary()**
- Generates complete summary report
- Includes pattern analysis
- Shows confidence level
- Lists recent frustrations

## Testing

To manually test the capture engine:

```bash
# Run self-test
bash src/engines/capture-engine.sh

# Or use the comprehensive test suite
bash tests/test-capture-engine.sh
```

Test coverage includes:
- Initialization (4 tests)
- Event detection (8 tests)
- Pattern analysis (6 tests)
- Prompting decision (5 tests)
- Confidence scoring (5 tests)
- Event bus integration (3 tests)
- Storage/retrieval (3 tests)
- Edge cases (5 tests)
- Reporting (3 tests)
- Reset/cleanup (2 tests)

**Total: 44 test cases**

## Best Practices

1. **Initialize early**: Call `capture_engine_init()` after `wow_init()`

2. **Use event bus**: Let handlers publish events rather than calling detect directly

3. **Respect cooldowns**: Always check `capture_should_prompt()` before prompting

4. **Mark prompts**: Call `capture_mark_prompted()` after showing prompt

5. **Monitor patterns**: Use `capture_analyze_pattern()` to understand user struggles

6. **Check confidence**: Higher confidence = more reliable frustration signal

7. **Clean up**: Call `capture_engine_reset()` when shutting down

## Troubleshooting

**Issue:** Events not being detected

**Solution:** Ensure event bus is initialized before capture engine:
```bash
event_bus_init
capture_engine_init  # Must come after event_bus_init
```

**Issue:** Prompts not triggering

**Solution:** Check frustration threshold and recent prompts:
```bash
count=$(session_get_metric "frustration_count")
last_prompt=$(session_get_metric "last_prompt_at")
current_time=$(date +%s)
cooldown=$((current_time - last_prompt))

echo "Count: $count (threshold: 3)"
echo "Cooldown: $cooldown seconds (minimum: 300)"
```

**Issue:** Pattern always returns "none"

**Solution:** Check event recency window:
```bash
# Events older than 5 minutes are ignored
# Generate fresh events for testing
capture_detect_event "handler.error" "Bash" "test"
capture_detect_event "handler.error" "Bash" "test"
capture_detect_event "handler.error" "Bash" "test"

pattern=$(capture_analyze_pattern)  # Should now detect pattern
```

## Integration with Email System

```bash
# Pseudo-code for email integration

# In your main loop or handler
if [[ "$(capture_should_prompt)" == "true" ]]; then
    # Generate report
    report=$(capture_summary)
    pattern=$(capture_analyze_pattern)
    confidence=$(capture_get_confidence)

    # Compose email
    subject="WoW Frustration Detected: $pattern (Confidence: $confidence)"
    body="$report"

    # Send email (use your email system)
    send_email_to_user "$subject" "$body"

    # Mark prompted
    capture_mark_prompted
fi
```

## Performance Considerations

- **Memory**: Stores all frustrations in session state (RAM)
- **CPU**: Pattern analysis scans all recent frustrations (O(n))
- **Recency window**: Old events auto-expire after 5 minutes
- **Session boundary**: New session = clean slate

For long-running sessions with many frustrations, consider periodic cleanup:

```bash
# Periodic cleanup (every hour)
if [[ $(($(date +%s) % 3600)) -eq 0 ]]; then
    # Archive old frustrations
    # (implement custom archival logic if needed)
fi
```

## Version History

- **v1.0.0** (2025-10-05): Initial release
  - Core frustration detection
  - Pattern analysis (4 patterns)
  - Confidence scoring
  - Event bus integration
  - 44 test cases

## See Also

- [Event Bus Documentation](event-bus.md)
- [Session Manager Documentation](session-manager.md)
- [Handler Integration Guide](handler-integration.md)
- [WoW Architecture Overview](architecture.md)
