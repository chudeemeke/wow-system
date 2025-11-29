# WoW System v6.0.0

**Ways of Working Enforcement for Claude Code**

Production-grade safety and behavior enforcement system that integrates with Claude Code to prevent dangerous operations, enforce best practices, and track quality metrics. Features multi-session analytics, pattern recognition, custom user-defined rules, and comprehensive security handlers for all Claude Code tools.

---

## Overview

The WoW (Ways of Working) System is a comprehensive security and quality enforcement framework designed to work seamlessly with Claude Code. It intercepts tool calls, validates operations, blocks dangerous commands, and maintains behavioral scoring to ensure safe and high-quality AI-assisted development.

### Key Features

#### Security & Enforcement (Phase E + B1)
- 🛡️ **10 Security Handlers**: Bash, Write, Edit, Read, Glob, Grep, Task, WebFetch, WebSearch, NotebookEdit
- 🚫 **Comprehensive Protection**: Blocks dangerous commands, system file access, SSRF attacks, code injection, PII exposure
- 🎯 **Three-Tier Security**: Critical (hard block), Sensitive (contextual), Tracked (monitored)
- 🔄 **Auto-Fixing**: Automatically adds author to git commits and removes emojis

#### Intelligence & Analytics (Phase B2 + B3)
- 📊 **Multi-Session Analytics**: Performance trends, percentile rankings, historical comparison
- 🔍 **Pattern Recognition**: Detects repeated violations and provides actionable recommendations
- ⚙️ **Custom Rule DSL**: User-defined security rules with allow/warn/block actions
- 📈 **Behavioral Scoring**: Adaptive 0-100 score with natural decay and reward system

#### User Experience
- 🎨 **Enhanced UX**: Real-time analytics insights, trend indicators (↑/→/↓), pattern summaries
- 📉 **Performance**: <10ms operation latency, aggressive caching, fast-path optimization
- 🎤 **Capture Engine**: Real-time frustration detection with intelligent pattern analysis
- 📧 **Email Alerts**: Secure email notifications with OS keychain credential storage

#### Security Features
- 🔐 **Credential Security**: Real-time detection, redaction, secure OS keychain storage
- 🛡️ **Defense in Depth**: Multiple validation layers across all tool operations
- 🔒 **Privacy-First**: No sensitive data exposure, secure storage, fail-safe design

#### Developer Experience
- 📚 **Documentation Automation**: Powered by docTruth - perpetually synchronized documentation
- ⚙️ **Highly Configurable**: Customizable thresholds, rules, and enforcement modes
- 🧪 **Comprehensive Testing**: 207+ tests across all modules (100% pass rate)

---

## Architecture

### Core Components

```
wow-system/
├── src/
│   ├── core/              # Foundation layer
│   │   ├── utils.sh           # Logging, validation, utilities
│   │   ├── file-storage.sh    # Persistent key-value storage
│   │   ├── state-manager.sh   # Session state management
│   │   ├── config-loader.sh   # JSON configuration
│   │   ├── session-manager.sh # Session lifecycle
│   │   └── orchestrator.sh    # Module loader (Facade)
│   │
│   ├── handlers/          # Tool interception (10 handlers)
│   │   ├── bash-handler.sh         # Bash command validation
│   │   ├── write-handler.sh        # File write safety
│   │   ├── edit-handler.sh         # File edit validation
│   │   ├── read-handler.sh         # File read protection
│   │   ├── glob-handler.sh         # File search safety
│   │   ├── grep-handler.sh         # Content search safety
│   │   ├── task-handler.sh         # Agent task validation
│   │   ├── webfetch-handler.sh     # Web fetch SSRF protection
│   │   ├── websearch-handler.sh    # Search query PII protection
│   │   ├── notebookedit-handler.sh # Jupyter notebook security
│   │   ├── custom-rule-helper.sh   # Custom rule integration
│   │   └── handler-router.sh       # Strategy pattern router
│   │
│   ├── analytics/         # Multi-session intelligence (v5.4.0)
│   │   ├── collector.sh       # Session data collection
│   │   ├── aggregator.sh      # Statistical calculations
│   │   ├── trends.sh          # Time-series trend analysis
│   │   ├── comparator.sh      # Historical performance comparison
│   │   └── patterns.sh        # Pattern recognition engine
│   │
│   ├── rules/             # Custom rule DSL (v5.4.0)
│   │   └── dsl.sh             # User-defined security rules
│   │
│   ├── engines/           # Analysis & scoring
│   │   ├── scoring-engine.sh  # Behavioral scoring
│   │   ├── risk-assessor.sh   # Multi-factor risk analysis
│   │   └── capture-engine.sh  # Frustration detection & doc automation
│   │
│   ├── security/          # Credential protection
│   │   ├── credential-detector.sh  # Real-time credential detection
│   │   └── credential-storage.sh   # Secure OS keychain integration
│   │
│   ├── tools/             # CLI utilities
│   │   ├── email-system.sh    # Secure email alerts
│   │   └── wow-capture.sh     # Manual frustration capture
│   │
│   └── ui/                # User interface
│       └── display.sh         # Banners, feedback, analytics insights
│
├── hooks/                 # Claude Code integration
│   └── user-prompt-submit.sh  # Main interception hook
│
├── tests/                 # Comprehensive test suites
│   ├── test-framework.sh      # Testing infrastructure
│   ├── test-bash-handler.sh   # 24 tests
│   ├── test-write-handler.sh  # 24 tests
│   └── test-edit-handler.sh   # 24 tests
│
├── config/                # Configuration
│   └── wow-config.json        # Default settings
│
└── install.sh             # Automated installer
```

### Design Patterns

- **Facade Pattern**: Orchestrator simplifies complex subsystem initialization
- **Strategy Pattern**: Handler router dynamically selects appropriate handler
- **Observer Pattern**: Event tracking and metrics collection
- **Template Method**: Extensible hooks for customization

### Design Principles

- **Single Responsibility**: Each module has one clear purpose
- **Open/Closed**: Extensible without modification
- **Dependency Inversion**: Modules depend on abstractions
- **Loose Coupling**: Components are independent but integrated
- **Defense in Depth**: Multiple layers of security validation

---

## Installation

### Quick Start

```bash
# Clone or navigate to wow-system directory
cd /path/to/wow-system

# Run installer
bash install.sh

# Follow the prompts for:
# - Dependency checking
# - Environment setup
# - Configuration generation
# - Self-test validation
```

### Manual Setup

1. **Set Environment Variables**:
```bash
export WOW_HOME="/path/to/wow-system"
export WOW_DATA_DIR="${HOME}/.wow-data"
```

2. **Configure Claude Code**:

Add to `~/.claude/config.json` or your project's `.claude/config.json`:

```json
{
  "hooks": {
    "user-prompt-submit": "/path/to/wow-system/hooks/user-prompt-submit.sh"
  }
}
```

3. **Verify Installation**:
```bash
bash install.sh  # Will run self-tests
```

---

## Usage

### Basic Operation

Once installed, the WoW System operates transparently in the background:

1. **Claude Code** prepares a tool call (Bash, Write, Edit, Read, Glob, Grep)
2. **WoW Hook** intercepts the call before execution
3. **Handler Router** routes to appropriate handler
4. **Handler** validates and potentially modifies the call
5. **Decision**:
   - ✅ **Allow**: Operation proceeds (possibly modified)
   - ⚠️ **Warn**: Operation proceeds with warning
   - ⛔ **Block**: Operation blocked, error returned

### What Gets Intercepted

#### Bash Handler
- ✅ Auto-fixes git commits (removes emojis, adds author)
- ⛔ Blocks: `rm -rf /`, `sudo rm -rf`, `dd of=/dev/`, `mkfs`, fork bombs
- ⚠️ Warns: Suspicious patterns, infinite loops

#### Write Handler
- ⛔ Blocks: Writes to `/etc`, `/bin`, `/usr`, `/boot`, `/sys`, `/proc`, `/dev`
- ⛔ Blocks: Path traversal (`../../etc/passwd`)
- ⛔ Blocks: Malicious content patterns
- ⚠️ Warns: Credentials detected, binary files

#### Edit Handler
- ⛔ Blocks: Edits to system files
- ⛔ Blocks: Dangerous replacements (security code removal)
- ⚠️ Warns: Missing documentation, validation bypass

#### Read Handler
- ⛔ Blocks: Reads of `/etc/shadow`, `/etc/passwd`, private SSH keys
- ⛔ Blocks: AWS/GCP credentials, cryptocurrency wallets
- ⛔ Blocks: Path traversal to sensitive files
- ⚠️ Warns: `.env` files, credential files, browser data
- ⚠️ Warns: High read volume (potential data exfiltration)

#### Glob Handler
- ⛔ Blocks: Globbing in `/etc`, `/root`, `/sys`, `~/.ssh`, `~/.aws`
- ⛔ Blocks: System security directories
- ⚠️ Warns: Overly broad patterns (`/**/*`, `**/*`)
- ⚠️ Warns: Credential file patterns (`**/.env`, `**/id_rsa`)
- ⚠️ Warns: Wallet searches (`**/wallet.dat`)

#### Grep Handler
- ⛔ Blocks: Searches in `/etc`, `/root`, `/sys`, `~/.ssh`, `~/.aws`
- ⛔ Blocks: Sensitive directory searches
- ⚠️ Warns: Credential pattern searches (password, api_key, secret, token)
- ⚠️ Warns: Private key pattern searches
- ⚠️ Warns: PII pattern searches (SSN, credit card numbers)

#### Task Handler
- ⚠️ Monitors: Autonomous agent launches and resource usage
- ⚠️ Warns: Dangerous task patterns (infinite loops, recursive spawning)
- ⚠️ Warns: Credential harvesting attempts
- ⚠️ Warns: Data exfiltration tasks
- ⚠️ Warns: Network abuse patterns (scanning, brute force)
- ⚠️ Warns: System modification attempts
- 📊 Tracks: Rate limiting (max 20 tasks/session, 5 tasks/minute)

#### WebFetch Handler
- ⛔ Blocks: Private IP addresses (SSRF prevention)
- ⛔ Blocks: Localhost and internal networks (127.0.0.1, 192.168.x.x, 10.x.x.x)
- ⛔ Blocks: `file://` protocol and other dangerous protocols
- ⚠️ Warns: URLs with embedded credentials
- ⚠️ Warns: Suspicious domains and TLDs (.tk, .ml, etc.)
- ⚠️ Warns: Data exfiltration endpoints (pastebin, etc.)
- ⚠️ Warns: URL shorteners (bit.ly, etc.)
- 📊 Tracks: External request rate limiting

### Scoring System

Your WoW Score (0-100) reflects code quality and safety:

- **90-100**: Excellent 🌟
- **70-89**: Good ✓
- **50-69**: Warning ⚠️
- **30-49**: Critical 🔴
- **0-29**: Blocked ☠️

**Score Changes**:
- Violation: -10 points
- Good practice: +5 points
- Natural decay: Gradual improvement over time (5% every 5 minutes)

### Configuration

Edit `config/wow-config.json`:

```json
{
  "version": "4.1.0",
  "enforcement": {
    "enabled": true,
    "strict_mode": false,
    "block_on_violation": false
  },
  "scoring": {
    "threshold_warn": 50,
    "threshold_block": 30,
    "decay_rate": 0.95
  },
  "rules": {
    "max_file_operations": 10,
    "max_bash_commands": 5,
    "require_documentation": true
  }
}
```

### Documentation Automation

WoW uses **docTruth** for automated documentation synchronization. docTruth captures the "truth" about your codebase by running commands and generating CURRENT_TRUTH.md.

**Features**:
- Auto-generates documentation from actual code state
- Runs validations to ensure accuracy
- Tracks metrics (LOC, test coverage, module count)
- Updates automatically on significant events

**Manual Update**:
```bash
# Generate/update CURRENT_TRUTH.md
doctruth

# Watch mode (auto-regenerate on file changes)
doctruth --watch

# Check if documentation is outdated
doctruth --check
```

**Automatic Updates**: The capture engine triggers docTruth on:
- Version bumps
- Feature additions
- Test suite completion
- Every 30 minutes during active sessions

**Configuration**: Edit `.doctruth.yml` to customize what gets documented.

---

## Testing

### Run All Tests

```bash
# Bash handler (24 tests)
bash tests/test-bash-handler.sh

# Write handler (24 tests)
bash tests/test-write-handler.sh

# Edit handler (24 tests)
bash tests/test-edit-handler.sh

# Read handler (24 tests)
bash tests/test-read-handler.sh

# Glob handler (24 tests)
bash tests/test-glob-handler.sh

# Grep handler (24 tests)
bash tests/test-grep-handler.sh

# Task handler (24 tests)
bash tests/test-task-handler.sh

# WebFetch handler (24 tests)
bash tests/test-webfetch-handler.sh

# Total: 192 tests, 100% passing
```

### Test Coverage

- ✅ **Git commit auto-fix**: Emoji removal, author addition
- ✅ **Dangerous commands**: rm -rf, sudo rm, dd, mkfs, fork bombs
- ✅ **Path validation**: System directories, path traversal
- ✅ **Content scanning**: Malicious patterns, credentials
- ✅ **Edge cases**: Empty inputs, long strings, special characters
- ✅ **Security scenarios**: Backdoors, validation bypass
- ✅ **Metrics tracking**: All operations logged and counted

---

## Security Features

### Multi-Layer Defense

1. **Path Validation**
   - Absolute path resolution
   - Protected directory detection
   - Path traversal prevention

2. **Content Scanning**
   - Pattern matching (20+ dangerous patterns)
   - Heuristic safety checks
   - Credential detection

3. **Operation Analysis**
   - Risk assessment (path, content, operation, frequency, context)
   - Composite scoring (weighted factors)
   - Context-aware decisions

4. **Behavioral Tracking**
   - Violation counting
   - Score-based thresholds
   - Trend analysis

### Dangerous Patterns Blocked

**Bash**:
- `rm -rf /` and variants
- `sudo rm -rf`
- `dd of=/dev/*`
- `mkfs.*`
- `chmod 777 /`
- Fork bombs: `:(){ :|:& };:`

**Write/Edit**:
- System directories: `/etc`, `/bin`, `/usr`, `/boot`, `/sys`, `/proc`, `/dev`
- Path traversal: `../..`
- Malicious content injection

---

## Development

### Adding a New Handler

1. Create handler file: `src/handlers/my-handler.sh`
2. Implement `handle_my_tool()` function
3. Register in `handler-router.sh`:
```bash
handler_register "MyTool" "${handler_dir}/my-handler.sh"
```
4. Create test suite: `tests/test-my-handler.sh`
5. Run tests and validate

### Extending Functionality

- **Custom Patterns**: Add to handler pattern arrays
- **New Metrics**: Use `session_update_metric()`
- **Risk Factors**: Extend `risk_assess_composite()`
- **UI Components**: Add to `src/ui/display.sh`

---

## Metrics & Analytics

### Session Metrics

Track per session:
- `bash_commands`: Total bash executions
- `file_writes`: File write operations
- `file_edits`: File edit operations
- `violations`: Security violations
- `wow_score`: Current behavioral score
- `score_changes`: Number of score adjustments

### Access Metrics

```bash
# From within WoW system
session_get_metric "bash_commands"
session_get_metrics  # All metrics

# View statistics
session_stats
session_info
```

---

## Troubleshooting

### WoW System Not Blocking

1. Check hook is configured in Claude Code config
2. Verify `WOW_HOME` environment variable
3. Ensure hook script is executable: `chmod +x hooks/user-prompt-submit.sh`
4. Check logs in `${WOW_DATA_DIR}` (if configured)

### Score Not Updating

1. Ensure session manager is initialized
2. Check `session_get_metric "wow_score"`
3. Verify config allows scoring: `enforcement.enabled: true`

### Tests Failing

1. Check dependencies: `bash`, `jq` (recommended)
2. Ensure all files are executable
3. Run installer to validate: `bash install.sh`

---

## Performance

- **Overhead**: ~10-50ms per tool call (negligible)
- **Memory**: ~5MB resident set size
- **Storage**: Session data ~100KB per session
- **Scalability**: Tested with 1000+ operations per session

---

## Roadmap

- [x] Additional handlers (Read, Glob, Grep) - **Completed v4.2.0**
- [x] High-priority handlers (Task, WebFetch) - **Completed v4.3.0**
- [x] Capture Engine with frustration detection - **Completed v5.0.0**
- [x] Email alerts with secure credential storage - **Completed v5.0.0**
- [x] Real-time credential detection and redaction - **Completed v5.0.0**
- [x] Documentation sync engine - **Completed v5.0.1**
- [ ] Medium-priority handlers (NotebookEdit, WebSearch)
- [ ] Machine learning-based anomaly detection
- [ ] Web dashboard for metrics visualization
- [ ] Multi-session analytics
- [ ] Team-based scoring and leaderboards
- [ ] Custom rule DSL

---

## Contributing

This is a personal project for AI-assisted development safety. Not currently accepting external contributions, but feedback is welcome!

---

## License

Copyright © 2025 Chude <chude@emeke.org>

This software is for personal use. All rights reserved.

---

## Credits

**Author**: Chude <chude@emeke.org>

**Built for**: Claude Code by Anthropic

**Design Philosophy**: Defense in depth, fail-safe defaults, transparent operations

---

## Support

For issues, questions, or feedback:
- Review this README
- Check `install.sh` output for diagnostics
- Run self-tests: `bash src/handlers/bash-handler.sh`

**Version**: 5.0.1
**Last Updated**: 2025-10-05
**Status**: Production Ready ✅
