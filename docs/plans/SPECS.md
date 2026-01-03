# Michi (道) - Multi-Agent Orchestration System

**Version**: 1.0.0
**Status**: Specification Complete
**Last Updated**: 2026-01-02
**Author**: Chude

---

## Overview

**Michi** (道 - "The Way") is a multi-agent orchestration system with real-time dashboard, built on Claude Code's hook system. The system enables parallel agent execution, shared context/memory, agent-to-agent communication, and comprehensive observability.

The name reflects the Japanese concept of "道" (michi/dō) - the disciplined path followed in martial arts like Judo (柔道) and Bushido (武士道). Agents are "warriors" that follow your Ways of Working (WoW) with unwavering discipline.

**Core Philosophy**: Sequential workflows, functional isolation, and single-responsibility agents with non-overlapping tasks - ensuring clear boundaries and conflict avoidance by design.

---

## Functional Requirements

### Must Have (P0)

- [ ] **Multi-agent orchestration** - Spawn, monitor, and coordinate multiple Claude Code instances
- [ ] **Parallel execution** - Git worktrees + multiple CLI instances for true parallelism
- [ ] **Real-time dashboard** - Web-based monitoring of all agent activity
- [ ] **Cross-project learning system** - Memory that persists and transfers across projects
- [ ] **Audio notifications** - TTS announcements for task completion, errors, escalations (with toggle)
- [ ] **Conflict avoidance by design** - Orchestrator assigns non-overlapping tasks upfront
- [ ] **3-tier failure handling** - Retry → Reassign → Pause & Notify
- [ ] **Tiered approval for memory** - Routine updates auto-approve, significant require confirmation
- [ ] **WoW integration** - All agents follow user's Ways of Working rules

### Should Have (P1)

- [ ] **Task decomposition** - Intelligent breakdown of complex tasks
- [ ] **Dependency graph** - Visual representation of task dependencies
- [ ] **Cost tracking** - Monitor API usage across agents
- [ ] **Session replay** - Review what agents did
- [ ] **Mobile-responsive dashboard** - Works on phone/tablet
- [ ] **Dark/light theme toggle** - User preference

### Nice to Have (P2)

- [ ] **A2A protocol integration** - Future cross-platform agent communication
- [ ] **Pluggable auth** - Support various authentication methods
- [ ] **Export learning** - Share learned patterns across installations
- [ ] **Agent specialization profiles** - Pre-configured agent roles

---

## Technical Specifications

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          道場 DŌJŌ (Dashboard)                           │
│                     Web App (Vue 3 + Vite + Tailwind)                   │
│                    Mobile + Desktop Compatible                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ WebSocket (Socket.io)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        先生 SENSEI (Orchestrator)                        │
│                         Node.js + Express + SQLite                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ Task Queue  │  │ Agent Pool  │  │   Memory    │  │   Audio     │    │
│  │ (Decompose) │  │ (Lifecycle) │  │  (Learning) │  │   (TTS)     │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
          │                   │                    │
          │ Hook Events       │ Spawn/Monitor      │ Read/Write
          ▼                   ▼                    ▼
    ┌──────────┐        ┌──────────┐        ┌──────────────────┐
    │  武士 1  │        │  武士 2  │        │ 型/稽古 KATA/KEIKO │
    │ (Agent)  │◄──────►│ (Agent)  │◄──────►│ - patterns.md    │
    │ Worktree │  File  │ Worktree │        │ - learnings.json │
    │   /w1    │  Msgs  │   /w2    │        │ - context/       │
    └──────────┘        └──────────┘        └──────────────────┘
```

### Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Dashboard** | Vue 3 + Vite | Matches indydevtools pattern, reactive |
| **Styling** | Tailwind CSS | Rapid iteration, design system support |
| **Real-time** | Socket.io | Reliable WebSocket abstraction |
| **Backend** | Node.js + Express | Claude Code ecosystem consistency |
| **Database** | SQLite | Zero-config, file-based, portable |
| **TTS** | Web Speech API + fallback | Browser-native, no dependencies |
| **Memory** | Hybrid (Markdown + JSON index) | Human-readable + searchable |

### Hook Integration

Leverages all 8 Claude Code hook types:

| Hook | Michi Purpose |
|------|---------------|
| `SessionStart` | Register agent with orchestrator, load shared context |
| `UserPromptSubmit` | Route to task queue, validate agent assignment |
| `PreToolUse` | Security validation, conflict detection |
| `PostToolUse` | Log results, update shared memory |
| `Notification` | Agent status updates, completion signals, TTS triggers |
| `Stop` | Deregister agent, persist state |
| `SubagentStop` | Capture sub-agent results, handoff |
| `PreCompact` | Backup context before memory compaction |

### Parallel Execution Strategy

**Workaround for Claude Code's single-instance limitation:**

```bash
# Orchestrator creates worktrees
git worktree add ../project-bushi-1 -b bushi-1
git worktree add ../project-bushi-2 -b bushi-2

# Spawn agents in separate processes
cd ../project-bushi-1 && claude --agent-id=bushi-1 &
cd ../project-bushi-2 && claude --agent-id=bushi-2 &
```

**Orchestrator responsibilities:**
- Worktree creation/cleanup
- Branch management
- Merge coordination
- File ownership tracking (conflict avoidance)

### Three-Tier Memory Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ TIER 1: HOT CONTEXT (Per-Agent)                                 │
│ ├── .claude/AGENT_CONTEXT.md    # Agent-specific instructions   │
│ ├── Current task details                                        │
│ └── Recent decisions                                            │
├─────────────────────────────────────────────────────────────────┤
│ TIER 2: WARM CONTEXT (Shared - Project Level)                   │
│ ├── shared/context.json         # Task state, assignments       │
│ ├── shared/memory.json          # Project learnings             │
│ └── shared/results/             # Completed work                │
├─────────────────────────────────────────────────────────────────┤
│ TIER 3: COLD STORAGE (Persistent - Cross-Project)               │
│ ├── ~/.michi/global-memory.json # Cross-project learnings       │
│ ├── ~/.michi/patterns/          # Generalized patterns          │
│ └── ~/.michi/history.db         # SQLite: tasks, metrics        │
└─────────────────────────────────────────────────────────────────┘
```

### Learning System

**Memory Write Access Control:**

| Update Type | Approval | Example |
|-------------|----------|---------|
| Routine | Auto | Task completion, status changes |
| Significant | Prompt | New pattern detected, rule modification |
| Critical | Always prompt | Global memory changes, pattern deletion |

**Cross-Project Learning Flow:**

1. Agent completes task, generates local learning
2. Orchestrator evaluates confidence score
3. **High confidence** → Auto-promote to global memory
4. **Uncertain** → Keep local, tag for review
5. User can manually promote/demote learnings

**Generalization Tags:**
- `project-specific` - Stays in project
- `domain-specific` - Applicable to similar projects
- `universal` - Applies everywhere

### Failure Handling (3-Tier)

```
┌─────────────────────────────────────────────────────────────────┐
│ TIER 1: RETRY (Configurable N times, default: 3)                │
│ ├── Same agent retries with backoff                             │
│ ├── Captures error context for learning                         │
│ └── If fails N times → escalate to Tier 2                       │
├─────────────────────────────────────────────────────────────────┤
│ TIER 2: REASSIGN                                                │
│ ├── Task reassigned to different agent                          │
│ ├── Full context from previous agent included                   │
│ ├── May use different approach/worktree                         │
│ └── If fails → escalate to Tier 3                               │
├─────────────────────────────────────────────────────────────────┤
│ TIER 3: PAUSE & NOTIFY                                          │
│ ├── All related work paused                                     │
│ ├── Impact summary generated                                    │
│ ├── TTS notification (if enabled)                               │
│ ├── Dashboard alert with full context                           │
│ └── Awaits human intervention                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Conflict Avoidance by Design

**Principle**: Orchestrator ALWAYS ensures non-overlapping tasks upfront.

**Implementation:**
1. **Task decomposition** produces non-overlapping units
2. **File ownership registry** tracks which agent owns which files
3. **Pre-assignment validation** checks for conflicts before spawning
4. **Sequential fallback** - if conflict unavoidable, serialize those tasks

**Inspired by**: indydevtools approach - sequential workflows, functional isolation, single-responsibility agents.

---

## UI/UX Specifications

### Design Philosophy

- **Anthropic console style** - Warm, focused, professional
- **Apple/Airbnb level quality** - Polished, intuitive, delightful
- **Adaptive density** - Compact by default, expand on hover/click
- **No documentation required** - Interface should be self-explanatory

### Design Inspiration

| Source | Element to Borrow |
|--------|-------------------|
| **Claude.ai** | Warm color palette, typography, conversational feel |
| **Linear.app** | Task management, keyboard shortcuts, speed |
| **Notion/Obsidian** | Information density, markdown rendering |
| **Airbnb** | Visual polish, attention to detail |
| **Uber** | Real-time status, maps/visualization |
| **iCloud.com** | Minimal chrome, content-focused |
| **Apple.com** | Typography, whitespace, premium feel |

### Theme Support

- **Dark mode** (default for developers)
- **Light mode** (user toggle)
- **System preference detection**
- **Persistent preference storage**

### Dashboard Views

#### Main Dashboard

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Michi 道                                              [Dark] [Settings]│
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Active Agents                                               [+ Deploy] │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │ 武士 bushi-1    │  │ 武士 bushi-2    │  │ 武士 bushi-3    │         │
│  │ ● ACTIVE        │  │ ● ACTIVE        │  │ ○ IDLE          │         │
│  │                 │  │                 │  │                 │         │
│  │ auth-api        │  │ user-ui         │  │ Waiting...      │         │
│  │ ████████░░ 80%  │  │ █████░░░░░ 50%  │  │ ░░░░░░░░░░      │         │
│  │                 │  │                 │  │                 │         │
│  │ src/auth/       │  │ src/components/ │  │                 │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│                                                                         │
│  Event Stream                                          [Filter] [Audio]  │
│  ─────────────────────────────────────────────────────────────────────  │
│  10:32:15  bushi-1   Created src/auth/routes.ts                        │
│  10:32:18  bushi-2   Reading src/components/UserForm.tsx               │
│  10:32:21  bushi-1   Tool: Write completed                             │
│  10:32:25  sensei    Assigned test-auth to bushi-3                     │
│                                                                         │
│  Memory Updates                                          [View All]     │
│  ─────────────────────────────────────────────────────────────────────  │
│  [AUTO] Learned: JWT refresh pattern for this project                  │
│  [PENDING] New pattern detected: Error boundary in React - Approve?    │
│                                                                         │
│  Cost: $0.42 today | Tasks: 8 total, 3 done, 2 active, 3 queued        │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Audio Notifications

- **Task complete**: "Task auth-api complete. Bushi-1 is now idle."
- **Failure escalation**: "Alert. Task user-validation failed after 3 retries. Reassigning."
- **Human needed**: "Attention. Task database-migration requires your input."
- **Toggle**: Mute button in header, per-notification-type settings

### Multiple UI Designs

**Requirement**: Provide multiple UI design concepts for user selection.

| Design | Style | Best For |
|--------|-------|----------|
| **Dojo** | Japanese minimalism, lots of whitespace | Focus, meditation |
| **Command Center** | Dense, data-rich, multiple panels | Power users |
| **Conversational** | Chat-like, one task at a time | Beginners |

User selects preferred design during onboarding or in settings.

---

## Trade-offs & Decisions

| Decision | Choice Made | Rationale |
|----------|-------------|-----------|
| Parallelism approach | Git worktrees | Only proven method; file-based, no special tooling |
| Agent communication | File-based (start) | Simpler than A2A; migrate later when SDK matures |
| Memory format | Hybrid MD + JSON | Human-readable for debugging, searchable for queries |
| Memory writes | Orchestrator-only | Prevents conflicts, enables approval workflow |
| Dashboard tech | Web app (Vue) | Mobile + desktop, no installation, matches ecosystem |
| Conflict handling | Avoidance over resolution | Prevention is better than cure; simpler, more reliable |
| TTS | Web Speech API | Browser-native, zero dependencies, toggle-able |

---

## Success Criteria

- [ ] 2+ agents working simultaneously without file conflicts
- [ ] Dashboard shows real-time agent status (<1s latency)
- [ ] Learning persists across projects and sessions
- [ ] Audio notifications work with user toggle
- [ ] 3-tier failure handling operates correctly
- [ ] Memory approval workflow functions (auto vs prompted)
- [ ] Cost tracking accurate to $0.01
- [ ] Mobile-responsive dashboard
- [ ] Dark/light theme toggle works
- [ ] Apple/Anthropic-level design quality (user approval)
- [ ] Multiple UI designs available for selection

---

## Out of Scope (v1.0)

- **A2A protocol integration** - Future enhancement when SDK matures
- **Enterprise SSO** - Pluggable auth is P2
- **Multi-user collaboration** - Single user focus for v1
- **Cloud deployment** - Local-first, remote is optional
- **Custom LLM support** - Claude-only for v1
- **IDE integration** - CLI and dashboard only

---

## Open Questions

| Question | Status | Resolution |
|----------|--------|------------|
| Rate limiting across agents | Open | Need to implement token bucket per project |
| Cost budget caps | Open | UI for setting limits, hard stop or warn? |
| Rollback strategy | Open | Git-based rollback? Checkpoint system? |
| Agent specialization | Deferred | Start with generic, add profiles in v1.1 |

---

## CLI Commands (Proposed)

```bash
# Core
michi init                    # Initialize project
michi deploy <task>           # Deploy agents on task
michi status                  # System status
michi dojo                    # Open dashboard

# Agents
michi bushi list              # List agents
michi bushi spawn <n>         # Spawn n agents
michi bushi stop <id>         # Stop specific agent

# Learning
michi kata list               # List WoW patterns
michi kata teach <rule>       # Add WoW rule
michi keiko show              # Show learnings
michi keiko promote <id>      # Promote to global

# Configuration
michi config                  # Edit config
michi config set <key> <val>  # Set config value
```

---

## Integration with WoW System

Michi integrates with existing WoW v7.0.0 infrastructure:

| WoW Component | Michi Integration |
|---------------|-------------------|
| `handler-router.sh` | Route agent operations through handlers |
| `zone-validator.sh` | Validate agent file access by zone |
| `bypass-system` | Task-scoped bypass for trusted operations |
| `scoring-engine.sh` | Track agent behavior scores |
| `capture-engine.sh` | Log patterns across agents |

**Agent with WoW Enforcement:**
```bash
claude --agent-id=bushi-1 \
  --context="shared/AGENT_CONTEXT.md" \
  --wow-scope="task:auth-implementation"
```

---

## References

- [claude-flow](https://github.com/ruvnet/claude-flow) - Enterprise orchestration
- [claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) - Hook patterns
- [claude-squad](https://github.com/smtg-ai/claude-squad) - Terminal multi-agent
- [A2A Protocol](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/) - Future integration
- [Feature Request #3013](https://github.com/anthropics/claude-code/issues/3013) - Official parallel execution

---

## Appendix: Japanese Terminology

| Term | Kanji | Meaning | System Mapping |
|------|-------|---------|----------------|
| Michi | 道 | The Way | System name |
| Dōjō | 道場 | Place of the Way | Dashboard |
| Sensei | 先生 | Teacher/Master | Orchestrator |
| Bushi | 武士 | Warrior | Agent |
| Kata | 型 | Form/Pattern | WoW rules |
| Keiko | 稽古 | Practice/Training | Learning system |
