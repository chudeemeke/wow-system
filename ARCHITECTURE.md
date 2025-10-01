# WoW System v4.1 - Architecture & Design

**Design Philosophy**: Anthropic Engineering (systematic, thorough, safety-first) + Apple Design (elegant, delightful, "just works")

---

## 🎯 System Overview

The WoW System is an **intelligence layer** that sits between Claude LLM and Claude Code's tool execution, enforcing development best practices through real-time interception, behavioral tracking, and intelligent guidance.

### Core Principle

> **"Guide with intelligence, block with wisdom, delight with feedback"**

---

## 🏗️ Architectural Layers

```
┌─────────────────────────────────────────────────────────────┐
│                      Claude Code v2.0.1                      │
│                    (User Interface Layer)                    │
└───────────────────────────────┬─────────────────────────────┘
                                │
                        Hooks Integration
                                │
┌───────────────────────────────┴─────────────────────────────┐
│                      WoW SYSTEM v4.1                         │
│                   (Intelligence Layer)                       │
│                                                              │
│  ┌────────────┐  ┌─────────────┐  ┌────────────────────┐  │
│  │   Hooks    │──│  Handlers   │──│    Strategies      │  │
│  │  (Entry)   │  │ (Intercept) │  │   (Intelligence)   │  │
│  └────────────┘  └─────────────┘  └────────────────────┘  │
│         │              │                      │             │
│         └──────────────┴──────────────────────┘             │
│                        │                                     │
│         ┌──────────────┴──────────────┐                    │
│         │                               │                    │
│    ┌────┴────┐                    ┌────┴────┐              │
│    │  Core   │                    │   UI    │              │
│    │ (State) │                    │(Feedback)│             │
│    └────┬────┘                    └────┬────┘              │
│         │                               │                    │
│    ┌────┴────┐                          │                    │
│    │ Storage │──────────────────────────┘                   │
│    │(Persist)│                                               │
│    └─────────┘                                               │
└─────────────────────────────────────────────────────────────┘
                                │
                        File System / State
```

---

## 📦 Component Architecture

### 1. **Hooks** (`src/hooks/`)

**Purpose**: Entry points triggered by Claude Code lifecycle events

**Components**:
- `session-start.sh` - Initialize WoW state, display welcome banner
- `user-prompt-submit.sh` - Show real-time metrics before each response
- `pre-tool-use.sh` - Route to appropriate handler based on tool type
- `post-tool-use.sh` - Record outcome, update metrics
- `session-stop.sh` - Generate and display session report

**Responsibilities**:
- Hook into Claude Code event system
- Route events to appropriate handlers
- Minimal logic (delegate to core/handlers)
- Fast execution (<50ms per hook)

**Claude Code v2.0.1 Integration**:
```json
{
  "hooks": {
    "SessionStart": [
      { "type": "command", "command": "/path/to/wow/hooks/session-start.sh" }
    ],
    "UserPromptSubmit": [...],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [...] },
      { "matcher": "Write", "hooks": [...] },
      { "matcher": "Edit", "hooks": [...] }
    ]
  }
}
```

---

### 2. **Handlers** (`src/handlers/`)

**Purpose**: Intercept and process specific tool invocations

**Components**:
- `bash-handler.sh` - Intercept Bash commands
  - Auto-fix git commits (remove emojis, add author)
  - Block dangerous commands (`rm -rf /`, `chmod 777`)
  - Sanitize sensitive operations

- `write-handler.sh` - Intercept Write tool
  - Check file location (root vs subdirectory)
  - Validate against dangerous paths
  - Warn or block based on risk level
  - Update ECR (Edit/Create Ratio)

- `edit-handler.sh` - Intercept Edit tool
  - Praise edit operations
  - Increment streak
  - Update ECR positively
  - Provide encouraging feedback

- `handler-router.sh` - Route PreToolUse to correct handler
  - Parse tool type from input
  - Dispatch to specialized handler
  - Aggregate results

**Responsibilities**:
- Tool-specific enforcement logic
- Risk assessment
- Decision: Allow/Warn/Block
- Update state via core API
- Return modified tool input (if applicable)

**Input/Output**:
```bash
# Input (from Claude Code hook):
{
  "tool": "Bash",
  "command": "git commit -m '🎉 Initial commit'",
  "args": {...}
}

# Output (back to Claude Code):
{
  "tool": "Bash",
  "command": "git commit -m 'Initial commit' --author='Chude <chude@emeke.org>'",
  "args": {...},
  "wow_status": "MODIFIED",
  "wow_message": "✅ AUTO-FIX: Removed emoji, added author"
}
```

---

### 3. **Strategies** (`src/strategies/`)

**Purpose**: Intelligent analysis and decision-making algorithms

**Components**:
- `scoring-engine.sh` - Calculate WoW score
  ```bash
  Base Score: 70
  + ECR Bonus: (edit_count / create_count) * 15  # max +30
  - Violation Penalty: (violations / total_ops) * 20  # max -20
  = Final Score: 0-100
  ```

- `pattern-detector.sh` - Analyze behavioral patterns
  - Recent vs historical trends
  - Time-weighted metrics
  - Streak detection
  - Improvement/degradation signals

- `risk-assessor.sh` - Evaluate operation risk level
  - **CRITICAL** (0): System files, destructive commands → BLOCK
  - **HIGH** (1-3): Root folder writes, risky operations → WARN
  - **MEDIUM** (4-6): Normal creates, acceptable patterns → ALLOW with reminder
  - **LOW** (7-10): Edits, compliant operations → PRAISE

- `feedback-generator.sh` - Create contextual feedback
  - Based on current score, trend, and operation
  - Actionable suggestions ("Need 2 more edits for grade A")
  - Encouraging messages for streaks
  - Warnings for risky behavior

**Responsibilities**:
- All "intelligence" lives here
- Stateless algorithms (read state, return decision)
- Extensible (new strategies can be added)
- Well-tested (critical business logic)

---

### 4. **Core** (`src/core/`)

**Purpose**: State management, session lifecycle, system coordination

**Components**:
- `state-manager.sh` - State CRUD operations
  ```bash
  wow_state_get "score"           # Read
  wow_state_set "score" 95        # Write
  wow_state_increment "streak"    # Atomic increment
  wow_state_append_audit "EDIT:SUCCESS"  # Log entry
  ```

- `session-manager.sh` - Session lifecycle
  - Initialize session state
  - Generate session ID
  - Session cleanup on exit
  - State migration between sessions

- `orchestrator.sh` - Coordinate components
  - Load all modules
  - Dependency injection
  - Error handling and recovery
  - Graceful degradation (if WoW fails, Claude Code continues)

- `config-loader.sh` - Load and validate configuration
  - Read `wow-config.json`
  - Environment variable resolution
  - Schema validation
  - Defaults for missing values

- `version-manager.sh` - Version compatibility
  - Check WoW system version
  - Check Claude Code version
  - Feature flags based on versions
  - Upgrade migrations

**Responsibilities**:
- System-wide coordination
- State consistency
- Error resilience
- Clean abstraction for other components

**API Design**:
```bash
# Simple, consistent API
wow::state::get <key>
wow::state::set <key> <value>
wow::session::init
wow::session::report
wow::config::load
wow::error::handle <code> <message>
```

---

### 5. **Storage** (`src/storage/`)

**Purpose**: Persistent state management

**Components**:
- `state-adapter.sh` - Abstract storage backend
  - File-based storage (default)
  - Future: Redis, SQLite support

- `migration.sh` - State schema migrations
  - Version upgrades
  - Backward compatibility

- `backup.sh` - Automatic state backups
  - Periodic snapshots
  - Recovery on corruption

**Storage Location**:
```bash
# Session state (ephemeral)
/tmp/.wow-session-<id>/
├── score
├── streak
├── trust
├── ecr
├── violation_rate
└── audit.log

# Persistent state (survives reboots)
~/.claude/wow-system/state/
├── historical_scores.jsonl
├── long_term_metrics.json
└── user_preferences.json
```

**Responsibilities**:
- Data persistence
- State recovery
- Migration management
- Backup/restore

---

### 6. **UI** (`src/ui/`)

**Purpose**: Visual feedback and user experience

**Components**:
- `banner.sh` - Session start welcome banner
  ```
  ╔══════════════════════════════════════════════════════════╗
  ║              🏆 WoW System v4.1 Active                   ║
  ║        Ways of Working Intelligence Enabled              ║
  ╠══════════════════════════════════════════════════════════╣
  ║  Score: 95/100 (A+) | Streak: 12 | Trust: HIGH          ║
  ║  Your coding excellence is being tracked ✨               ║
  ╚══════════════════════════════════════════════════════════╝
  ```

- `metrics-display.sh` - Real-time metrics bar
  ```
  ⚡ Score:88(B) | ECR:2.33 | VR:10.0% | Trend:↗ improving | Streak:6
  ```

- `feedback-renderer.sh` - Contextual feedback messages
  - Color-coded by severity
  - Icons for quick recognition
  - Concise, actionable text

- `report-generator.sh` - Session summary report
  ```
  ═══════════════════════════════════════════════════════════
  🏁 WOW SESSION REPORT
  ═══════════════════════════════════════════════════════════
  Final Score: 95/100 (A+)
  Total Operations: 23
  Edit/Create Ratio: 3.5:1 (Excellent!)
  Violation Rate: 4.3% (Low)
  Longest Streak: 15 consecutive compliant operations
  Trust Level: HIGH → MAXIMUM (upgraded!)

  🏆 OUTSTANDING SESSION!
  You demonstrated excellent WoW compliance.
  Keep up the great work!

  💡 Tip: Your ECR is excellent. Maintain this pattern.
  ═══════════════════════════════════════════════════════════
  ```

- `progress-bar.sh` - Visual progress indicators
  ```
  Grade Progress: [████████░░] 88/100 (B → A in 12 points)
  ```

**UX Design Principles** (Apple Philosophy):
1. **Instant Feedback**: Show metrics immediately, no waiting
2. **Clear Affordances**: Use icons, colors, formatting for quick scanning
3. **Progressive Disclosure**: Summary first, details on demand
4. **Delightful Interactions**: Celebrate success, gentle on failures
5. **Consistent Visual Language**: Same style everywhere
6. **Non-Intrusive**: Important but not overwhelming

**Color Coding**:
- 🟢 **Green**: Success, praise, high scores (A+, A)
- 🟡 **Yellow**: Warnings, reminders, medium scores (B, C)
- 🔴 **Red**: Blocks, violations, low scores (D, F)
- 🔵 **Blue**: Info, neutral feedback
- 🟣 **Purple**: Special achievements, milestones

---

## 🔒 Security Model

### Defense in Depth

**Layer 1: Input Validation**
- Sanitize all tool inputs
- Reject malformed data
- Validate against schema

**Layer 2: Risk Assessment**
- Every operation evaluated for risk
- Multi-factor risk scoring
- Conservative defaults

**Layer 3: Execution Control**
- Dangerous operations hard-blocked
- No escalation paths
- Audit trail of all decisions

**Layer 4: State Protection**
- State files protected (read-only where possible)
- Atomic writes (no partial state)
- Backup before mutations

### Threat Model

**What We Protect Against**:
1. ❌ Accidental destructive commands
2. ❌ Unauthorized file writes to system paths
3. ❌ State corruption
4. ❌ WoW system bypass attempts

**What We Don't Protect Against** (out of scope):
- Intentional user override (users can disable WoW)
- Network-based attacks
- OS-level vulnerabilities

### Fail-Safe Design

**Principle**: If WoW system fails, Claude Code must continue working

```bash
# Every hook wrapped in error handling
trap 'exit 0' ERR  # If WoW fails, return success (don't block Claude)

if ! wow_initialize; then
  echo "⚠️ WoW system initialization failed. Claude Code continues without WoW." >&2
  exit 0  # Don't block Claude Code
fi
```

---

## 📊 Data Flow

### 1. Session Start Flow

```
User launches Claude Code
        ↓
SessionStart hook triggered
        ↓
wow/hooks/session-start.sh
        ↓
wow/core/session-manager.sh → Initialize session state
        ↓
wow/storage/state-adapter.sh → Create state directory
        ↓
wow/ui/banner.sh → Display welcome
        ↓
Return to Claude Code
```

### 2. Tool Invocation Flow

```
User prompt → Claude decides to use Write tool
        ↓
PreToolUse hook triggered (matcher: "Write")
        ↓
wow/hooks/pre-tool-use.sh
        ↓
wow/handlers/handler-router.sh → Identify tool type
        ↓
wow/handlers/write-handler.sh
        ↓
wow/strategies/risk-assessor.sh → Evaluate risk
        ↓
Decision: ALLOW/WARN/BLOCK
        ↓
wow/core/state-manager.sh → Update metrics
        ↓
wow/strategies/scoring-engine.sh → Recalculate score
        ↓
wow/ui/feedback-renderer.sh → Generate feedback
        ↓
Return modified tool input + feedback to Claude Code
        ↓
Tool executes (or blocked)
```

### 3. User Prompt Submit Flow

```
User submits prompt
        ↓
UserPromptSubmit hook triggered
        ↓
wow/hooks/user-prompt-submit.sh
        ↓
wow/core/state-manager.sh → Read current state
        ↓
wow/strategies/pattern-detector.sh → Analyze trends
        ↓
wow/ui/metrics-display.sh → Render metrics bar
        ↓
Display: "⚡ Score:88(B) | ECR:2.33 | VR:10% | Trend:↗"
        ↓
Return to Claude Code (continue with response)
```

---

## 🔌 Extension Points

### Plugin Architecture

**Why**: Users may want custom rules, integrations, or behaviors

**How**: Plugin discovery and loading

```bash
# Plugins directory
~/.claude/wow-system/plugins/
├── my-custom-rule.sh
├── slack-integration.sh
└── advanced-metrics.sh

# Plugin API
wow::plugin::register "PreToolUse" "my_custom_check"
wow::plugin::register "SessionStop" "send_slack_notification"
```

**Plugin Contract**:
```bash
#!/bin/bash
# Plugin: my-custom-rule.sh
# Hook: PreToolUse
# Description: Custom validation for my workflow

my_custom_check() {
  local tool_type=$1
  local tool_input=$2

  # Custom logic here
  if [[ condition ]]; then
    echo "BLOCK:My custom reason"
    return 1
  fi

  echo "ALLOW"
  return 0
}

# Register with WoW system
wow::plugin::register "PreToolUse:Bash" "my_custom_check"
```

---

## 🛠️ Technology Stack

**Language**: Bash (v4.0+)
- Native to Linux/WSL2/Mac
- No external dependencies
- Fast execution
- Easy to read and modify

**Dependencies** (minimal):
- `jq` - JSON parsing (for settings.json, state files)
- `bc` - Floating-point arithmetic (for scoring calculations)
- Standard Unix utils (grep, sed, awk, cut)

**Claude Code Integration**: v2.0.1
- Hooks API (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop)
- settings.json configuration
- Tool input/output modification
- Matcher-based routing

**State Storage**:
- Primary: File-based (plain text, JSON)
- Future: Redis (for multi-session state), SQLite (for analytics)

---

## 📈 Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| Hook execution time | <50ms | Don't slow down Claude Code |
| State read | <5ms | Frequent operation, must be fast |
| State write | <10ms | Less frequent, can be slightly slower |
| Score calculation | <20ms | Complex but cached |
| Memory footprint | <10MB | Lightweight, no bloat |
| Startup time | <100ms | User shouldn't notice |

**Optimization Strategies**:
- Caching (score, metrics)
- Lazy loading (load modules only when needed)
- Async writes (don't block on audit log)
- Minimal disk I/O

---

## 🧪 Testing Strategy

### Unit Tests (`tests/unit/`)
- Test each function in isolation
- Mock state, filesystem
- Fast execution (<1s for all unit tests)

### Integration Tests (`tests/integration/`)
- Test component interactions
- Real state, real filesystem
- Verify hook chains work end-to-end

### End-to-End Tests (`tests/e2e/`)
- Full Claude Code simulation
- Real scenarios (edit file, commit, create file)
- Verify entire system behavior

### Test Coverage Target
- Core: 90%+
- Handlers: 80%+
- Strategies: 95%+ (critical business logic)
- Hooks: 70%+
- UI: 60%+ (mostly visual)

---

## 🚀 Deployment Model

### Development
```bash
# Work in Projects/wow-system/
cd /Projects/wow-system/
# Edit src/ files directly
vim src/core/state-manager.sh
```

### Deployment
```bash
# Run deploy script
./scripts/deploy.sh

# What it does:
# 1. Validate all scripts (syntax check)
# 2. Run tests
# 3. Create symlink: ~/.claude/wow-system → Projects/wow-system/src
# 4. Copy settings.json → ~/.claude/settings.json (merge with existing)
# 5. Verify deployment
# 6. Display success message
```

### Rollback
```bash
# Revert to previous version
./scripts/rollback.sh
```

---

## 📚 Documentation Strategy

1. **Code Comments**: Every function documented
2. **README.md**: Quick start, overview
3. **CONTEXT.md**: Background, history
4. **ARCHITECTURE.md** (this file): Deep dive into design
5. **IMPLEMENTATION-PLAN.md**: Step-by-step build guide
6. **API.md**: Public API reference
7. **CHANGELOG.md**: Version history

---

## 🎯 Success Metrics

**System Quality**:
- ✅ Hook execution <50ms (95th percentile)
- ✅ Zero crashes in normal operation
- ✅ Test coverage >80%
- ✅ Zero false positives (blocking valid operations)

**User Experience**:
- ✅ Users understand feedback instantly
- ✅ Actionable guidance provided
- ✅ Delightful interactions
- ✅ Non-intrusive operation

**Developer Experience**:
- ✅ Easy to extend (plugin system)
- ✅ Clear code organization
- ✅ Well-documented
- ✅ Simple deployment

---

**Next**: See `IMPLEMENTATION-PLAN.md` for the build roadmap.
