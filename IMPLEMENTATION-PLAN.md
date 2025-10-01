# WoW System v4.1 - Implementation Plan

**Approach**: Incremental development with working system at each phase

---

## 🎯 Development Philosophy

**Build → Test → Deploy → Iterate**

- Each phase produces a working, deployable system
- Start simple, add complexity incrementally
- Test continuously
- Deploy early, deploy often

---

## 📋 Phase Overview

| Phase | Goal | Duration | Deliverable |
|-------|------|----------|-------------|
| **Phase 0** | Foundation | 1 session | Project setup, basic structure |
| **Phase 1** | Core & Storage | 2-3 sessions | State management working |
| **Phase 2** | Hooks & Routing | 2 sessions | Hook integration complete |
| **Phase 3** | Handlers | 3 sessions | Tool interception working |
| **Phase 4** | Strategies | 2-3 sessions | Intelligent scoring active |
| **Phase 5** | UI & UX | 2 sessions | Beautiful feedback system |
| **Phase 6** | Testing & Polish | 2 sessions | Production-ready |
| **Phase 7** | Extensions | 1-2 sessions | Plugin system, extras |

**Total Estimated**: 14-18 coding sessions

---

## Phase 0: Foundation

### Goals
- ✅ Project structure created
- ✅ Git repository initialized
- ✅ Basic deployment script working
- ✅ Minimal "Hello World" hook

### Tasks

**0.1. Project Setup** ✅ (Already Done)
- [x] Create directory structure
- [x] Migrate archive files
- [x] Create documentation (CONTEXT.md, ARCHITECTURE.md, this plan)

**0.2. Git Initialization**
```bash
# Initialize git
cd /Projects/wow-system
git init
git config user.name "Chude"
git config user.email "chude@emeke.org"

# Create .gitignore
cat > .gitignore << 'EOF'
.DS_Store
*.swp
*.bak
*~
.backup/
node_modules/
.vscode/
EOF

# Initial commit
git add .
git commit -m "Initial commit: WoW System v4.1 project structure

- Created modular architecture (core, handlers, hooks, strategies, storage, ui)
- Migrated v3.5 and v4.0 documentation to .archive
- Comprehensive documentation (CONTEXT, ARCHITECTURE, IMPLEMENTATION-PLAN)
- Clean separation from AI-Dev-Environment project

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"
```

**0.3. Basic Deployment Script**
```bash
# File: scripts/deploy.sh
#!/bin/bash
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-/mnt/c/Users/Destiny/.claude}"
WOW_SRC="$(cd "$(dirname "$0")/.." && pwd)/src"

echo "🚀 Deploying WoW System v4.1..."

# Create symlink
if [ -L "$CLAUDE_HOME/wow-system" ]; then
  rm "$CLAUDE_HOME/wow-system"
fi
ln -sf "$WOW_SRC" "$CLAUDE_HOME/wow-system"

echo "✅ Symlink created: $CLAUDE_HOME/wow-system → $WOW_SRC"
echo "🎉 Deployment complete!"
```

**0.4. Hello World Hook**
```bash
# File: src/hooks/session-start.sh
#!/bin/bash
echo "🏆 WoW System v4.1 - Hello World!"
echo "   System is active and monitoring your session."
exit 0
```

**0.5. Minimal settings.json**
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/mnt/c/Users/Destiny/.claude/wow-system/hooks/session-start.sh"
          }
        ]
      }
    ]
  }
}
```

**0.6. Test Deployment**
```bash
chmod +x scripts/deploy.sh src/hooks/session-start.sh
./scripts/deploy.sh
# Launch Claude Code, verify "Hello World" appears
```

### Success Criteria
- ✅ Git repository initialized
- ✅ Deploy script works
- ✅ Symlink created correctly
- ✅ Basic hook executes on SessionStart
- ✅ "Hello World" message appears

---

## Phase 1: Core & Storage

### Goals
- State management API working
- Storage backend functional
- Session lifecycle managed
- Configuration loaded

### Tasks

**1.1. State Manager** (`src/core/state-manager.sh`)
```bash
# API:
wow::state::init        # Initialize state directory
wow::state::get <key>   # Read state value
wow::state::set <key> <value>  # Write state value
wow::state::increment <key>    # Atomic increment
wow::state::append_audit <message>  # Append to audit log
```

**Implementation**:
- Create state directory structure
- File-based storage (simple, fast)
- Atomic operations (use mv for atomic writes)
- Error handling

**1.2. Storage Adapter** (`src/storage/state-adapter.sh`)
```bash
# Abstract storage interface
wow::storage::read <file>
wow::storage::write <file> <data>
wow::storage::exists <file>
wow::storage::backup <file>
```

**1.3. Session Manager** (`src/core/session-manager.sh`)
```bash
wow::session::init      # Create session state
wow::session::id        # Get current session ID
wow::session::cleanup   # Clean up on exit
```

**1.4. Config Loader** (`src/core/config-loader.sh`)
```bash
# File: config/wow-config.json
{
  "version": "4.1.0",
  "state_dir": "/tmp/.wow-session-{SESSION_ID}",
  "persistent_dir": "~/.claude/wow-system/state",
  "scoring": {
    "base_score": 70,
    "ecr_weight": 15,
    "violation_weight": 20
  },
  "thresholds": {
    "grade_a_plus": 95,
    "grade_a": 90,
    "grade_b": 80,
    "grade_c": 70
  }
}

# API:
wow::config::load
wow::config::get <key>
```

**1.5. Unit Tests**
```bash
# File: tests/unit/test-state-manager.sh
test_state_init() {
  wow::state::init
  assert_dir_exists "$WOW_STATE_DIR"
}

test_state_set_get() {
  wow::state::set "score" 95
  result=$(wow::state::get "score")
  assertEquals "95" "$result"
}

test_state_increment() {
  wow::state::set "streak" 5
  wow::state::increment "streak"
  result=$(wow::state::get "streak")
  assertEquals "6" "$result"
}
```

### Success Criteria
- ✅ State can be initialized
- ✅ Read/write operations work
- ✅ Session management functional
- ✅ Config loaded correctly
- ✅ All unit tests pass

---

## Phase 2: Hooks & Routing

### Goals
- All 5 hooks implemented
- Hook routing to handlers works
- Basic feedback displayed

### Tasks

**2.1. Session Start Hook** (`src/hooks/session-start.sh`)
```bash
#!/bin/bash
source "$(dirname "$0")/../core/orchestrator.sh"

wow::init  # Load all modules
wow::session::init
wow::ui::banner::display
exit 0
```

**2.2. User Prompt Submit Hook** (`src/hooks/user-prompt-submit.sh`)
```bash
#!/bin/bash
source "$(dirname "$0")/../core/orchestrator.sh"

wow::init
score=$(wow::state::get "score")
streak=$(wow::state::get "streak")
wow::ui::metrics::display "$score" "$streak"
exit 0
```

**2.3. Pre Tool Use Hook** (`src/hooks/pre-tool-use.sh`)
```bash
#!/bin/bash
source "$(dirname "$0")/../core/orchestrator.sh"

wow::init

# Read tool input from stdin
tool_input=$(cat)

# Route to appropriate handler
tool_type=$(echo "$tool_input" | jq -r '.tool')
wow::handlers::route "$tool_type" "$tool_input"

exit $?
```

**2.4. Session Stop Hook** (`src/hooks/session-stop.sh`)
```bash
#!/bin/bash
source "$(dirname "$0")/../core/orchestrator.sh"

wow::init
wow::ui::report::generate
wow::session::cleanup
exit 0
```

**2.5. Orchestrator** (`src/core/orchestrator.sh`)
```bash
# Central loader for all modules
wow::init() {
  source "$(dirname "$0")/state-manager.sh"
  source "$(dirname "$0")/session-manager.sh"
  source "$(dirname "$0")/config-loader.sh"
  source "$(dirname "$0")/../storage/state-adapter.sh"
  source "$(dirname "$0")/../handlers/handler-router.sh"
  source "$(dirname "$0")/../ui/banner.sh"
  source "$(dirname "$0")/../ui/metrics-display.sh"
  source "$(dirname "$0")/../ui/report-generator.sh"

  wow::config::load
  # More initialization as needed
}
```

**2.6. Handler Router** (`src/handlers/handler-router.sh`)
```bash
wow::handlers::route() {
  local tool_type=$1
  local tool_input=$2

  case "$tool_type" in
    "Bash")
      source "$(dirname "$0")/bash-handler.sh"
      wow::handlers::bash "$tool_input"
      ;;
    "Write")
      source "$(dirname "$0")/write-handler.sh"
      wow::handlers::write "$tool_input"
      ;;
    "Edit")
      source "$(dirname "$0")/edit-handler.sh"
      wow::handlers::edit "$tool_input"
      ;;
    *)
      # Pass through unknown tools
      echo "$tool_input"
      return 0
      ;;
  esac
}
```

### Success Criteria
- ✅ All hooks execute without errors
- ✅ Orchestrator loads all modules
- ✅ Handler routing works (even if handlers are stubs)
- ✅ Basic feedback displayed

---

## Phase 3: Handlers

### Goals
- Bash handler: Auto-fix git, block dangerous commands
- Write handler: Check locations, assess risk
- Edit handler: Praise, increment streak

### Tasks

**3.1. Bash Handler** (`src/handlers/bash-handler.sh`)
```bash
wow::handlers::bash() {
  local tool_input=$1
  local command=$(echo "$tool_input" | jq -r '.command')

  # Check for dangerous commands
  if echo "$command" | grep -qE "rm -rf /|sudo rm -rf|chmod 777"; then
    wow::ui::feedback "☠️ DANGEROUS COMMAND BLOCKED" "red"
    wow::state::append_audit "VIOLATION:DANGEROUS_CMD:$command"
    wow::state::set "score" $(($(wow::state::get "score") - 10))
    exit 2  # Block
  fi

  # Auto-fix git commits
  if echo "$command" | grep -q "git commit"; then
    # Remove emojis
    command=$(echo "$command" | sed 's/[🎉🚀✨🔥💯😊👍🎯💪🌟🎨🐛📝♻️⚡💥🎊🎈]//g')
    # Add author
    if ! echo "$command" | grep -q "author.*Chude"; then
      command="$command --author=\"Chude <chude@emeke.org>\""
    fi
    wow::ui::feedback "✅ AUTO-FIX: Git commit sanitized" "green"
    tool_input=$(echo "$tool_input" | jq ".command = \"$command\"")
  fi

  echo "$tool_input"
  return 0
}
```

**3.2. Write Handler** (`src/handlers/write-handler.sh`)
```bash
wow::handlers::write() {
  local tool_input=$1
  local file_path=$(echo "$tool_input" | jq -r '.file_path')

  # Assess risk
  risk=$(wow::strategies::risk::assess "write" "$file_path")

  if [ "$risk" -eq 0 ]; then
    # CRITICAL: Block
    wow::ui::feedback "🚫 BLOCKED: System file write" "red"
    exit 2
  elif [ "$risk" -le 3 ]; then
    # HIGH: Warn
    wow::ui::feedback "⚠️ WARNING: Root folder write (allowed, -3 points)" "yellow"
    wow::state::set "score" $(($(wow::state::get "score") - 3))
  else
    # MEDIUM/LOW: Gentle reminder
    wow::ui::feedback "📝 Creating file (consider editing existing)" "blue"
    wow::state::set "score" $(($(wow::state::get "score") - 1))
  fi

  # Update ECR
  wow::state::increment "create_count"

  echo "$tool_input"
  return 0
}
```

**3.3. Edit Handler** (`src/handlers/edit-handler.sh`)
```bash
wow::handlers::edit() {
  local tool_input=$1

  # Praise edit
  wow::state::increment "streak"
  wow::state::increment "edit_count"

  streak=$(wow::state::get "streak")
  badges=""
  [ "$streak" -ge 10 ] && badges="🏆 Master"
  [ "$streak" -ge 5 ] && [ "$streak" -lt 10 ] && badges="⭐ Streak"

  wow::ui::feedback "✅ Excellent! Edit #$streak (WoW compliant) $badges" "green"

  echo "$tool_input"
  return 0
}
```

### Success Criteria
- ✅ Dangerous bash commands blocked
- ✅ Git commits auto-fixed
- ✅ Write operations assessed and warned/blocked appropriately
- ✅ Edit operations praised
- ✅ Streak tracking works

---

## Phase 4: Strategies

### Goals
- Risk assessment working
- Scoring engine calculates correctly
- Pattern detection identifies trends

### Tasks

**4.1. Risk Assessor** (`src/strategies/risk-assessor.sh`)
```bash
wow::strategies::risk::assess() {
  local operation=$1
  local target=$2

  # Check for system paths
  if [[ "$target" =~ ^/etc/|^/sys/|^/proc/|^/dev/ ]]; then
    echo 0  # CRITICAL
    return
  fi

  # Check for root folder
  if [[ "$target" =~ ^\.?/[^/]+$ ]]; then
    echo 2  # HIGH
    return
  fi

  # Default: MEDIUM
  echo 5
}
```

**4.2. Scoring Engine** (`src/strategies/scoring-engine.sh`)
```bash
wow::strategies::score::calculate() {
  local edit_count=$(wow::state::get "edit_count" || echo 1)
  local create_count=$(wow::state::get "create_count" || echo 1)
  local total_ops=$((edit_count + create_count))
  local violations=$(grep -c VIOLATION "$WOW_STATE_DIR/audit.log" || echo 0)

  # ECR (Edit/Create Ratio)
  ecr=$(echo "scale=2; $edit_count / $create_count" | bc)

  # Violation Rate
  vr=$(echo "scale=2; ($violations / $total_ops) * 100" | bc)

  # Base score
  score=70

  # ECR bonus (max +30)
  ecr_bonus=$(echo "scale=0; $ecr * 15" | bc)
  [ "$ecr_bonus" -gt 30 ] && ecr_bonus=30
  score=$((score + ecr_bonus))

  # Violation penalty (max -20)
  vr_penalty=$(echo "scale=0; $vr / 5" | bc)
  [ "$vr_penalty" -gt 20 ] && vr_penalty=20
  score=$((score - vr_penalty))

  # Clamp to 0-100
  [ "$score" -lt 0 ] && score=0
  [ "$score" -gt 100 ] && score=100

  echo "$score"
}
```

**4.3. Pattern Detector** (`src/strategies/pattern-detector.sh`)
```bash
wow::strategies::pattern::trend() {
  # Analyze last 10 operations
  # Return: improving | stable | degrading
  # (Simple version: compare recent score to historical average)
  current=$(wow::state::get "score")
  historical=$(wow::storage::read "historical_avg_score" || echo 70)

  diff=$((current - historical))

  if [ "$diff" -gt 5 ]; then
    echo "improving"
  elif [ "$diff" -lt -5 ]; then
    echo "degrading"
  else
    echo "stable"
  fi
}
```

### Success Criteria
- ✅ Risk assessment returns correct levels
- ✅ Score calculation matches expected values
- ✅ ECR and VR calculated correctly
- ✅ Trend detection works

---

## Phase 5: UI & UX

### Goals
- Beautiful banner on SessionStart
- Real-time metrics bar
- Delightful feedback messages
- Comprehensive session report

### Tasks

**5.1. Banner** (`src/ui/banner.sh`)
```bash
wow::ui::banner::display() {
  local score=$(wow::state::get "score")
  local streak=$(wow::state::get "streak")

  cat << EOF
╔══════════════════════════════════════════════════════════╗
║              🏆 WoW System v4.1 Active                   ║
║        Ways of Working Intelligence Enabled              ║
╠══════════════════════════════════════════════════════════╣
║  Score: $score/100 | Streak: $streak | Trust: HIGH       ║
║  Your coding excellence is being tracked ✨               ║
╚══════════════════════════════════════════════════════════╝
EOF
}
```

**5.2. Metrics Display** (`src/ui/metrics-display.sh`)
```bash
wow::ui::metrics::display() {
  local score=$1
  local streak=$2
  local grade=$(wow::ui::grade "$score")
  local ecr=$(wow::strategies::ecr::calculate)
  local vr=$(wow::strategies::vr::calculate)
  local trend=$(wow::strategies::pattern::trend)

  echo "⚡ Score:${score}(${grade}) | ECR:${ecr} | VR:${vr}% | Trend:${trend} | Streak:${streak}"
}
```

**5.3. Feedback Renderer** (`src/ui/feedback-renderer.sh`)
```bash
wow::ui::feedback() {
  local message=$1
  local color=${2:-blue}

  case "$color" in
    green) echo -e "\033[32m${message}\033[0m" ;;
    yellow) echo -e "\033[33m${message}\033[0m" ;;
    red) echo -e "\033[31m${message}\033[0m" ;;
    blue) echo -e "\033[34m${message}\033[0m" ;;
    *) echo "$message" ;;
  esac
}
```

**5.4. Report Generator** (`src/ui/report-generator.sh`)
```bash
wow::ui::report::generate() {
  local score=$(wow::state::get "score")
  local grade=$(wow::ui::grade "$score")
  local edits=$(wow::state::get "edit_count")
  local creates=$(wow::state::get "create_count")
  local violations=$(grep -c VIOLATION "$WOW_STATE_DIR/audit.log" || echo 0)

  cat << EOF
═══════════════════════════════════════════════════════════
🏁 WOW SESSION REPORT
═══════════════════════════════════════════════════════════
Final Score: $score/100 ($grade)
Total Operations: $((edits + creates))
Edit/Create Ratio: $(echo "scale=1; $edits / $creates" | bc):1
Violations: $violations

$(wow::ui::grade_feedback "$grade")
═══════════════════════════════════════════════════════════
EOF
}
```

### Success Criteria
- ✅ Banner looks beautiful
- ✅ Metrics bar displays correctly
- ✅ Feedback is color-coded and clear
- ✅ Session report is comprehensive

---

## Phase 6: Testing & Polish

### Goals
- Comprehensive test suite
- Bug fixes
- Performance optimization
- Documentation complete

### Tasks

**6.1. Unit Tests**
- Test all core functions
- Test all handlers
- Test all strategies
- Target: 80%+ coverage

**6.2. Integration Tests**
- Test hook chains
- Test state persistence
- Test error handling

**6.3. End-to-End Tests**
- Simulate full Claude Code sessions
- Verify real scenarios
- Test deployment

**6.4. Performance Optimization**
- Profile hook execution time
- Optimize slow paths
- Add caching where beneficial

**6.5. Security Audit**
- Review dangerous command detection
- Test bypass attempts
- Verify state protection

**6.6. Documentation**
- API reference
- User guide
- Developer guide
- Troubleshooting guide

### Success Criteria
- ✅ All tests pass
- ✅ Hook execution <50ms
- ✅ No known bugs
- ✅ Documentation complete

---

## Phase 7: Extensions

### Goals
- Plugin system working
- Example plugins
- Advanced features

### Tasks

**7.1. Plugin API**
```bash
# File: src/core/plugin-manager.sh
wow::plugin::register() {
  local hook_point=$1
  local callback=$2
  # Register callback for hook point
}

wow::plugin::load_all() {
  # Discover and load plugins from ~/.claude/wow-system/plugins/
}
```

**7.2. Example Plugins**
- Slack notification on session end
- Custom project-specific rules
- Advanced analytics

**7.3. Advanced Features**
- Persistent metrics across sessions
- Historical trend analysis
- Achievement badges
- Leaderboards (if multiple users)

### Success Criteria
- ✅ Plugin system works
- ✅ Example plugins functional
- ✅ Advanced features enhance UX

---

## 🚀 Deployment Checklist

Before each deployment:
- [ ] All tests pass
- [ ] Code reviewed
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] Version bumped
- [ ] Git tag created
- [ ] Deployed to test environment
- [ ] Verified in Claude Code
- [ ] Deployed to production
- [ ] Pushed to GitHub

---

## 📊 Progress Tracking

Use this checklist as you build:

### Phase 0: Foundation
- [x] Project structure
- [ ] Git initialized
- [ ] Deploy script
- [ ] Hello World hook
- [ ] Verified in Claude Code

### Phase 1: Core & Storage
- [ ] State manager
- [ ] Storage adapter
- [ ] Session manager
- [ ] Config loader
- [ ] Unit tests

### Phase 2: Hooks & Routing
- [ ] SessionStart hook
- [ ] UserPromptSubmit hook
- [ ] PreToolUse hook
- [ ] SessionStop hook
- [ ] Orchestrator
- [ ] Handler router

### Phase 3: Handlers
- [ ] Bash handler
- [ ] Write handler
- [ ] Edit handler
- [ ] Integration tests

### Phase 4: Strategies
- [ ] Risk assessor
- [ ] Scoring engine
- [ ] Pattern detector
- [ ] Strategy tests

### Phase 5: UI & UX
- [ ] Banner
- [ ] Metrics display
- [ ] Feedback renderer
- [ ] Report generator

### Phase 6: Testing & Polish
- [ ] Comprehensive tests
- [ ] Performance optimization
- [ ] Security audit
- [ ] Documentation

### Phase 7: Extensions
- [ ] Plugin API
- [ ] Example plugins
- [ ] Advanced features

---

**Next**: Complete Phase 0 tasks, commit to git, then move to Phase 1 in new Claude Code session.
