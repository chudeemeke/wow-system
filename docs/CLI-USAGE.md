# WoW Capture CLI - User Guide

**Version**: 1.0.0
**Author**: Chude <chude@emeke.org>

## Overview

`wow-capture` is a CLI tool for retroactive frustration analysis from Claude Code conversation history. It automatically detects patterns of frustration, security issues, and workflow problems, helping you capture insights that would otherwise be forgotten.

### Key Features

- **Automated Pattern Detection**: Identifies repeated errors, rapid-fire issues, path problems, and more
- **Credential Security Scanning**: Detects exposed credentials with immediate alerts
- **Confidence Scoring**: HIGH/MEDIUM/LOW confidence levels for intelligent filtering
- **Interactive Review**: User-controlled approval workflow
- **Auto-Approval Mode**: Automatically log HIGH confidence findings
- **Date Range Filtering**: Analyze specific time periods
- **Dry Run Mode**: Preview findings without making changes

## Installation

`wow-capture` is included with WoW System v5.0+. No additional installation needed.

### Prerequisites

- WoW System v5.0 or later
- `jq` (JSON processor)
- Bash 4.0+

### Verify Installation

```bash
wow-capture --version
```

Expected output:
```
wow-capture v1.0.0
WoW Capture Library v1.0.0
```

## Quick Start

### 1. Analyze Today's Conversations

```bash
wow-capture analyze
```

This will:
1. Scan today's conversation history
2. Detect frustration patterns
3. Launch interactive review
4. Log approved findings to `scratch.md`

### 2. Auto-Approve HIGH Confidence Findings

```bash
wow-capture analyze --auto-approve
```

All HIGH confidence findings (credentials, authority violations, repeated errors) are automatically logged.

### 3. Dry Run (Preview Only)

```bash
wow-capture analyze --dry-run
```

Shows what would be detected and logged, but doesn't modify any files.

## Commands

### `analyze`

Analyze conversation history for frustration patterns.

**Syntax**:
```bash
wow-capture analyze [options]
```

**Options**:
- `--from DATE` - Start date (YYYY-MM-DD)
- `--to DATE` - End date (YYYY-MM-DD)
- `--dry-run` - Preview without writing
- `--auto-approve` - Auto-log HIGH confidence findings
- `--output FILE` - Custom output file path

**Examples**:

```bash
# Analyze last week
wow-capture analyze --from 2025-09-28 --to 2025-10-05

# Analyze today with auto-approve
wow-capture analyze --auto-approve

# Preview tomorrow's analysis
wow-capture analyze --from 2025-10-06 --dry-run

# Save to custom file
wow-capture analyze --output ~/my-notes.md
```

### `review`

Interactive review of detected frustrations. Must run `analyze` first.

**Syntax**:
```bash
wow-capture review [options]
```

**Interactive Controls**:
- `y` - Log this finding to scratch.md
- `n` - Skip this finding
- `e` - Edit before logging (future feature)
- `q` - Quit review session

**Example Session**:

```
========================================
Finding #1
Type: credential
Confidence: HIGH
Evidence: Credential detected: anthropic_api
Context: Here's my API token: sk-ant-abc123...

Action [y/n/e/q]: y
✓ Logging to scratch.md...

========================================
Finding #2
Type: path_issue
Confidence: MEDIUM
Evidence: Path-related issue detected
Context: Path with spaces: /mnt/c/My Folder...

Action [y/n/e/q]: n
⚠ Skipped
```

### `report`

Generate summary statistics.

**Syntax**:
```bash
wow-capture report
```

**Example Output**:

```
Summary Statistics
==================
Total Entries Scanned:     127
Total Frustrations Found:  8

By Confidence:
  - HIGH:    2
  - MEDIUM:  4
  - LOW:     2

Credentials Detected:      1

User Decisions:
  - Approved:  5
  - Skipped:   3
```

### `config`

View current configuration and settings.

**Syntax**:
```bash
wow-capture config
```

**Example Output**:

```
Current Settings:
  - History File: /root/.claude/history.jsonl
  - Principles Dir: /path/to/wow-system/docs/principles
  - WoW Root: /path/to/wow-system
  - Debug Mode: 0

Detection Thresholds:
  - Repeated Errors: 3
  - Rapid Fire: 4
  - Time Window: 600s
```

### `help`

Show help information.

**Syntax**:
```bash
wow-capture help
# or
wow-capture --help
```

## Detection Patterns

`wow-capture` automatically detects these frustration patterns:

### 1. Credential Exposure (HIGH)

**What**: API keys, tokens, passwords in conversation
**Examples**:
- `sk-ant-...` (Anthropic)
- `ghp_...` (GitHub)
- `npm_...` (NPM)
- JWT tokens

**Action**: Immediate alert + rotation reminder

### 2. Authority Violations (HIGH)

**What**: AI acting without explicit user approval
**Examples**:
- "You did that without asking"
- "I NEED TO BE THE ONE that approves"
- "Why didn't you wait for confirmation"

**Lesson**: User control paramount

### 3. Repeated Errors (MEDIUM→HIGH)

**What**: Same error occurring 3+ times
**Examples**:
- Multiple "ERROR: ..." messages
- Repeated failure mentions
- Same exception multiple times

**Confidence**: MEDIUM (3x), HIGH (5+x)

### 4. Path Issues (MEDIUM)

**What**: Problems with file paths
**Examples**:
- Paths with spaces: `/mnt/c/My Folder`
- Quote issues
- "Path not found" errors
- WSL path problems

### 5. Restarts (LOW→MEDIUM)

**What**: Application/terminal restarts mentioned
**Examples**:
- "Need to restart Claude Code"
- "Reload required"
- "Restart terminal"

**Confidence**: LOW (1x), MEDIUM (3+x)

### 6. Workarounds (MEDIUM)

**What**: Manual fixes or temporary solutions
**Examples**:
- "Let me create a symlink"
- "Manual workaround"
- "Temporary fix"
- "Hack to make it work"

### 7. Frustration Language (LOW)

**What**: User expressing frustration
**Examples**:
- "This is annoying"
- "Why doesn't this work"
- "So frustrating"
- CAPS EMPHASIS

### 8. Rapid Fire (HIGH)

**What**: 4+ issues within 10 minutes
**Detection**: Timestamp analysis
**Indicates**: Severe workflow disruption

## Confidence Levels

### HIGH

**Criteria**:
- Credential detected
- Authority violation
- Repeated error (5+x)
- Rapid-fire pattern (4+ events in 10 min)

**Auto-approve**: Available with `--auto-approve`

**Action**: Should almost always be logged

### MEDIUM

**Criteria**:
- Repeated error (3-4x)
- Path issues
- Workarounds
- Multiple restarts (3+x)

**Auto-approve**: Not available

**Action**: Review and decide

### LOW

**Criteria**:
- Single restart
- Frustration language
- Isolated incidents

**Auto-approve**: Not available

**Action**: Review carefully, may be noise

## Output Format

Findings are logged to `docs/principles/v{VERSION}/scratch.md` in this format:

```markdown
---

## HIGH CONFIDENCE: credential

**Detected**: 2025-10-05 14:23:45
**Evidence**: Credential detected: anthropic_api

**Context**:
```
Here's my API token: sk-ant-[REDACTED]
Please use this for the deployment.
```
```

## Workflows

### Daily Review Workflow

End-of-day frustration capture:

```bash
# 1. Analyze today's session
wow-capture analyze --dry-run

# 2. Review findings
wow-capture analyze

# 3. Interactive approve/skip
# [y/n/e/q] for each finding

# 4. View summary
wow-capture report
```

### Weekly Retrospective

```bash
# Analyze past week
wow-capture analyze --from 2025-09-28 --to 2025-10-05

# Auto-approve critical issues
wow-capture analyze --from 2025-09-28 --to 2025-10-05 --auto-approve

# Generate report
wow-capture report
```

### Post-Incident Analysis

After a difficult debugging session:

```bash
# Immediate analysis
wow-capture analyze --auto-approve

# Check for credentials
grep -i "credential" docs/principles/v5.0/scratch.md

# Rotate if needed
# [manual rotation process]
```

### Monthly Cleanup

```bash
# Full month analysis
wow-capture analyze --from 2025-09-01 --to 2025-09-30 --dry-run

# Review patterns
wow-capture report

# Document recurring issues
# [manual documentation process]
```

## Configuration

### Environment Variables

- `WOW_DEBUG=1` - Enable debug output
- `WOW_SYSTEM_DIR` - Override WoW system location

**Example**:
```bash
WOW_DEBUG=1 wow-capture analyze
```

### Detection Thresholds

Currently hardcoded in `lib/wow-capture-lib.sh`:

```bash
THRESHOLD_REPEATED=3        # Errors to trigger detection
THRESHOLD_RAPID_FIRE=4      # Events for rapid-fire
THRESHOLD_TIME_WINDOW=600   # 10 minutes
```

To customize, edit the library file (configuration file support coming in v1.1).

## Security Considerations

### Credential Detection

`wow-capture` uses the WoW credential detector to scan all conversation content for:

- API tokens (Anthropic, OpenAI, GitHub, etc.)
- Passwords
- Private keys
- Connection strings

**When credentials are found**:
1. Immediate HIGH confidence alert
2. Content is marked for redaction
3. User is warned to rotate credentials
4. Finding is logged with `[REDACTED]` placeholder

### Privacy

`wow-capture` only reads from your local `~/.claude/history.jsonl` file. No data is sent to external services.

### Best Practices

1. **Never paste credentials in Claude Code conversations**
2. **Use environment variable references**: `$API_TOKEN` not the actual token
3. **Run analysis regularly** to catch exposures early
4. **Rotate immediately** if credentials are detected
5. **Review LOW confidence** findings to reduce false positives

## Troubleshooting

### "History file not found"

**Problem**: Can't locate `~/.claude/history.jsonl`

**Solutions**:
1. Verify file exists: `ls ~/.claude/history.jsonl`
2. Check alternate locations: `~/.config/claude/history.jsonl`
3. Set custom location: Edit `lib_find_history()` in library

### "jq: command not found"

**Problem**: JSON processor not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Fedora
sudo dnf install jq
```

### "Invalid JSONL format"

**Problem**: History file is corrupted or empty

**Solutions**:
1. Check file size: `ls -lh ~/.claude/history.jsonl`
2. Validate first line: `head -1 ~/.claude/history.jsonl | jq .`
3. If corrupted, restore from backup or start fresh

### "Permission denied"

**Problem**: Can't read history file or write to scratch.md

**Solutions**:
1. Check file permissions: `ls -l ~/.claude/history.jsonl`
2. Fix permissions: `chmod 644 ~/.claude/history.jsonl`
3. Check scratch.md directory: `ls -ld docs/principles/v5.0/`

### No patterns detected

**Problem**: Analysis shows 0 frustrations but you know there were issues

**Possible causes**:
1. **Wrong date range**: Check `--from` and `--to` dates
2. **Threshold too high**: Edit detection thresholds
3. **Patterns not recognized**: Pattern definitions may need expansion
4. **Empty history**: Verify conversation history exists

**Debug**:
```bash
# Enable debug mode
WOW_DEBUG=1 wow-capture analyze --dry-run

# Check history file
wc -l ~/.claude/history.jsonl
tail -5 ~/.claude/history.jsonl
```

## Examples

### Example 1: First-time User

```bash
# Show help
wow-capture --help

# Check configuration
wow-capture config

# Try dry run
wow-capture analyze --dry-run

# Real analysis
wow-capture analyze
```

### Example 2: Security Audit

```bash
# Scan entire history for credentials
wow-capture analyze --from 2025-01-01 --to 2025-12-31 --dry-run | grep -i credential

# Auto-log all credential exposures
wow-capture analyze --from 2025-01-01 --to 2025-12-31 --auto-approve

# Review findings
grep -i "HIGH CONFIDENCE: credential" docs/principles/v5.0/scratch.md
```

### Example 3: Pattern Analysis

```bash
# Analyze specific problematic day
wow-capture analyze --from 2025-10-03 --to 2025-10-03

# Generate report
wow-capture report

# Look for specific pattern
grep -i "path_issue" docs/principles/v5.0/scratch.md
```

## Advanced Usage

### Custom Output Location

```bash
# Save to custom file
wow-capture analyze --output ~/custom-notes.md

# Append to existing notes
wow-capture analyze --output ~/existing-notes.md
```

### Filtering by Confidence

Currently not directly supported, but can filter output:

```bash
# Show only HIGH confidence
wow-capture analyze --dry-run | grep "HIGH"

# Count MEDIUM confidence
wow-capture analyze --dry-run | grep -c "MEDIUM"
```

### Batch Processing

```bash
# Analyze multiple date ranges
for month in 01 02 03; do
    wow-capture analyze --from 2025-${month}-01 --to 2025-${month}-31 \
        --output ~/notes/2025-${month}.md
done
```

### Integration with Git

```bash
# Capture insights before committing
wow-capture analyze --auto-approve

# Add to commit
git add docs/principles/v5.0/scratch.md
git commit -m "Update: Captured session frustrations"
```

## Roadmap

### v1.1 (Planned)

- Configuration file support (`.wow-capture.conf`)
- Custom pattern definitions
- Export to JSON/CSV formats
- Email alerts for HIGH confidence findings
- Edit mode in interactive review

### v1.2 (Planned)

- Session filtering by ID
- Machine learning confidence scoring
- Pattern trend analysis
- Integration with WoW System dashboard

### v2.0 (Future)

- Real-time frustration capture (not just retroactive)
- Browser extension for web-based Claude
- Team collaboration features
- Pattern sharing/marketplace

## Contributing

Found a bug or have a feature request?

1. Document the issue in `scratch.md`
2. Run tests: `tests/test-wow-capture-cli.sh`
3. Submit via GitHub (coming soon)

## Support

For questions or issues:

- Check this guide first
- Review existing `scratch.md` entries for similar issues
- Enable debug mode: `WOW_DEBUG=1`
- Contact: chude@emeke.org

## License

Part of WoW System v5.0+
Author: Chude <chude@emeke.org>

---

**Remember**: The goal is to capture insights that would otherwise be lost. When in doubt, log it. Future you will thank present you.
