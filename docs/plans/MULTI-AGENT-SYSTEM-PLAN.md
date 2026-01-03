# Multi-Agent Orchestration System Plan

**Version**: 1.0.0
**Status**: Planning
**Last Updated**: 2026-01-02

## Executive Summary

This document outlines the architecture and implementation plan for a multi-agent orchestration system with real-time dashboard, built on Claude Code's hook system. The system enables parallel agent execution, shared context/memory, agent-to-agent communication, and comprehensive observability.

---

## Research Findings

### Industry Landscape (January 2026)

| Solution | Approach | Parallelism | Memory | Dashboard |
|----------|----------|-------------|--------|-----------|
| [claude-flow](https://github.com/ruvnet/claude-flow) | MCP + Swarm | 2.8-4.4x via mesh topology | AgentDB (SQLite + Vector) | Flow Nexus Cloud |
| [claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) | Hook interception | None (sequential) | File-based + JSONL | Logs only |
| [claude-squad](https://github.com/smtg-ai/claude-squad) | Terminal multiplexing | Multiple CLI instances | Shared files | Terminal UI |
| [claude-code-heavy](https://github.com/gtrusler/claude-code-heavy) | Orchestrated research | 2-8 parallel agents | Session-based | None |
| [claude-launcher](https://crates.io/crates/claude-launcher) | Rust CLI | Multiple instances | Status files | Basic |

### Official Status

- **Feature Request #3013**: Parallel Agent Execution Mode - OPEN, no official response
- **A2A Protocol**: v0.3 available, 150+ org support including Anthropic, Linux Foundation governed
- **MCP Protocol**: Anthropic's tool/context protocol, complementary to A2A

### Key Technical Insights

1. **True parallelism workaround**: Git worktrees + multiple CLI instances
2. **Agent communication**: A2A protocol OR file-based message passing
3. **Shared memory**: SQLite/JSON files readable by all agents
4. **Context preservation**: CLAUDE.md files, session transcripts, JSONL logs

---

## Proposed Architecture

### High-Level Design

```
                    ┌─────────────────────────────────┐
                    │         Dashboard (Web)          │
                    │   Real-time agent monitoring     │
                    │   Task status, memory viewer     │
                    └─────────────────────────────────┘
                                    │
                                    │ WebSocket
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Orchestrator Service                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Task Queue  │  │ Agent Pool  │  │ Memory/Context Manager  │  │
│  │ (SQLite)    │  │ Lifecycle   │  │ (Shared State)          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          │                   │                    │
          │ Hook Events       │ Spawn/Monitor      │ Read/Write
          ▼                   ▼                    ▼
    ┌──────────┐        ┌──────────┐        ┌──────────────┐
    │  Agent 1 │        │  Agent 2 │        │ Shared Memory │
    │ (Worktree│◄──────►│ (Worktree│◄──────►│ - context.json│
    │   /w1)   │  A2A   │   /w2)   │        │ - tasks.json  │
    └──────────┘        └──────────┘        │ - results/    │
                                            └──────────────┘
```

### Component Breakdown

#### 1. Hook Layer (Claude Code Integration)

Leverages all 8 hook types from Claude Code:

| Hook | Purpose in Multi-Agent System |
|------|------------------------------|
| `SessionStart` | Register agent with orchestrator, load shared context |
| `UserPromptSubmit` | Route to task queue, validate agent assignment |
| `PreToolUse` | Security validation, conflict detection |
| `PostToolUse` | Log results, update shared memory |
| `Notification` | Agent status updates, completion signals |
| `Stop` | Deregister agent, persist state |
| `SubagentStop` | Capture sub-agent results, handoff |
| `PreCompact` | Backup context before memory compaction |

#### 2. Orchestrator Service

**Responsibilities:**
- Task decomposition and assignment
- Agent lifecycle management (spawn, monitor, terminate)
- Conflict detection (file ownership)
- Result aggregation

**Implementation Options:**
- Option A: Node.js service with Express + SQLite
- Option B: Python FastAPI + SQLite
- Option C: Rust CLI (like claude-launcher)

**Recommended**: Node.js for consistency with Claude Code ecosystem.

#### 3. Shared Memory System

**Three-Tier Memory Architecture:**

```
Tier 1: Hot Context (Per-Agent)
├── .claude/AGENT_CONTEXT.md    # Agent-specific instructions
├── Current task details
└── Recent decisions

Tier 2: Warm Context (Shared)
├── shared/context.json         # Task state, assignments
├── shared/memory.json          # Cross-agent learnings
└── shared/results/             # Completed work

Tier 3: Cold Storage (Persistent)
├── SQLite: tasks, history, metrics
└── JSONL: Full audit trail
```

**Memory Update Protocol:**
1. Agent reads `context.json` at session start
2. Agent writes to `results/{agent_id}/{task_id}.json`
3. Orchestrator aggregates and updates `context.json`
4. Next agent inherits updated context

#### 4. Agent-to-Agent Communication

**Approach A: File-Based Message Passing**

```json
// shared/messages/{from_agent}_{to_agent}_{timestamp}.json
{
  "from": "agent-1",
  "to": "agent-2",
  "type": "handoff",
  "payload": {
    "completed_task": "auth-routes",
    "artifacts": ["src/auth/routes.ts"],
    "notes": "JWT implementation complete, needs middleware"
  }
}
```

Agents poll `shared/messages/` or receive via hook notification.

**Approach B: A2A Protocol Integration**

```python
# Using A2A Python SDK (when available)
from a2a import Agent, Message

agent = Agent(id="coder-1", capabilities=["typescript", "testing"])
await agent.send(
    to="reviewer-1",
    message=Message(type="review_request", content={"files": [...]})
)
```

**Recommended**: Start with file-based (simpler), migrate to A2A when SDK matures.

#### 5. Dashboard (Observability)

**Technology Stack:**
- Frontend: Vue 3 + Vite (matches indydevtools pattern)
- Real-time: WebSocket (Socket.io)
- Backend: Same Node.js orchestrator
- Styling: Tailwind CSS

**Dashboard Views:**

```
┌─────────────────────────────────────────────────────────────┐
│  Multi-Agent Dashboard                          [Live] [5] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ Agent: coder-1  │  │ Agent: coder-2  │  │ Agent: test │ │
│  │ Status: ACTIVE  │  │ Status: ACTIVE  │  │ Status: IDLE│ │
│  │ Task: auth-api  │  │ Task: user-ui   │  │ Waiting...  │ │
│  │ Progress: 60%   │  │ Progress: 40%   │  │             │ │
│  │ ████████░░░░░░  │  │ █████░░░░░░░░░  │  │ ░░░░░░░░░░  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│                                                             │
│  Recent Events                                              │
│  ────────────────────────────────────────────────────────  │
│  [10:32:01] coder-1: Created src/auth/routes.ts            │
│  [10:32:05] coder-2: Reading src/components/UserForm.tsx   │
│  [10:32:08] coder-1: Tool: Write completed                 │
│  [10:32:12] orchestrator: Assigned test-auth to test-1     │
│                                                             │
│  Shared Memory                                [Refresh]     │
│  ────────────────────────────────────────────────────────  │
│  Tasks: 8 total | 3 complete | 2 in-progress | 3 pending   │
│  Context size: 4.2KB | Last update: 2s ago                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Key Features:**
- Real-time agent status (via WebSocket)
- Task dependency graph visualization
- Shared memory inspector
- Event timeline with filtering
- Decision log viewer

---

## Workarounds for Current Limitations

### Limitation 1: No True Parallel Execution in Claude Code

**Workaround**: Git Worktrees + Multiple CLI Instances

```bash
# Create worktrees for each agent
git worktree add ../project-agent-1 -b agent-1
git worktree add ../project-agent-2 -b agent-2

# Spawn agents in separate terminals/processes
cd ../project-agent-1 && claude --agent-id=1 &
cd ../project-agent-2 && claude --agent-id=2 &
```

**Orchestrator manages:**
- Worktree creation/cleanup
- Branch management
- Merge coordination
- Conflict resolution

### Limitation 2: No Native Agent-to-Agent Communication

**Workaround**: Shared Filesystem + Polling OR A2A Adapter

**Option A: File Watcher Pattern**
```javascript
// Each agent watches shared/messages/
const chokidar = require('chokidar');
chokidar.watch('shared/messages/*.json').on('add', (path) => {
  const message = JSON.parse(fs.readFileSync(path));
  if (message.to === MY_AGENT_ID) {
    handleMessage(message);
  }
});
```

**Option B: A2A Protocol Wrapper**
```python
# Create A2A-compatible wrapper for file-based messaging
class FileBasedA2AAdapter:
    def send(self, to: str, message: dict):
        path = f"shared/messages/{self.id}_{to}_{timestamp()}.json"
        write_json(path, message)

    def receive(self) -> list[dict]:
        return [m for m in read_messages() if m['to'] == self.id]
```

### Limitation 3: No Shared Memory Across Sessions

**Workaround**: Persistent Files + Session Injection

```markdown
<!-- shared/AGENT_CONTEXT.md - Read by every agent at SessionStart -->

## Current Project State

### Completed Tasks
- auth-routes: JWT authentication (agent-1)
- user-model: Database schema (agent-2)

### In-Progress
- auth-middleware: Token validation (agent-3)

### Pending
- auth-tests: Unit tests for auth module

### Key Decisions Made
- Using `jose` library for JWT (performance)
- Tokens expire in 1 hour with refresh

### Files Owned
| File | Owner | Status |
|------|-------|--------|
| src/auth/routes.ts | agent-1 | Complete |
| src/auth/middleware.ts | agent-3 | In-Progress |
```

**Hook injects this at SessionStart:**
```python
# hooks/session_start.py
def on_session_start(session_id):
    context = read_file("shared/AGENT_CONTEXT.md")
    inject_to_session(context)
```

### Limitation 4: No Approval Delegation

**Workaround**: Pre-Approved Task Scopes

```json
// shared/approvals.json
{
  "plan_id": "auth-implementation-v1",
  "approved_by": "user",
  "approved_at": "2026-01-02T10:00:00Z",
  "scope": {
    "files_allowed": ["src/auth/**", "tests/auth/**"],
    "operations_allowed": ["create", "modify"],
    "operations_forbidden": ["delete", "modify:package.json"]
  },
  "agents_authorized": ["coder-1", "coder-2", "test-1"]
}
```

**PreToolUse hook validates:**
```python
def pre_tool_use(tool_name, tool_input):
    approval = load_approval()
    if not is_within_scope(tool_input, approval.scope):
        return {"block": True, "reason": "Outside approved scope"}
    return {"allow": True}
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Deliverables:**
- [ ] Hook infrastructure (all 8 hooks)
- [ ] Basic orchestrator (task queue, agent registry)
- [ ] File-based shared memory (context.json, results/)
- [ ] Single-agent proof of concept

**Success Criteria:**
- Agent reads shared context at start
- Agent writes results on completion
- Orchestrator tracks agent lifecycle

### Phase 2: Multi-Agent Core (Week 3-4)

**Deliverables:**
- [ ] Git worktree management
- [ ] Multi-instance spawning
- [ ] File ownership / conflict prevention
- [ ] Basic agent-to-agent messaging

**Success Criteria:**
- 2+ agents work simultaneously
- No file conflicts
- Results aggregate correctly

### Phase 3: Dashboard MVP (Week 5-6)

**Deliverables:**
- [ ] WebSocket server integration
- [ ] Vue 3 dashboard frontend
- [ ] Agent status cards
- [ ] Event timeline
- [ ] Memory inspector

**Success Criteria:**
- Real-time agent visibility
- Event history viewable
- Shared memory browsable

### Phase 4: Intelligence Layer (Week 7-8)

**Deliverables:**
- [ ] Task decomposition logic
- [ ] Dependency graph management
- [ ] Smart agent assignment
- [ ] Conflict resolution automation

**Success Criteria:**
- Complex task auto-decomposes
- Dependencies respected
- Minimal human intervention needed

### Phase 5: A2A Integration (Future)

**Deliverables:**
- [ ] A2A protocol adapter
- [ ] Cross-platform agent support
- [ ] Enterprise features (audit, compliance)

---

## Integration with WoW System

This multi-agent system integrates with existing WoW infrastructure:

| WoW Component | Integration Point |
|---------------|-------------------|
| `handler-router.sh` | Route agent operations through handlers |
| `zone-validator.sh` | Validate agent file access by zone |
| `bypass-system` | Task-scoped bypass for agents |
| `scoring-engine.sh` | Track agent behavior scores |
| `capture-engine.sh` | Log frustration patterns across agents |

**Example: Agent with WoW Enforcement**

```bash
# Agent spawned with WoW context
claude --agent-id=coder-1 \
  --context="shared/AGENT_CONTEXT.md" \
  --wow-scope="task:auth-implementation"
```

WoW validates each operation:
1. Zone check (is path in DEVELOPMENT zone?)
2. Bypass check (is task-scope active?)
3. Handler routing (appropriate handler processes)
4. Scoring (track violations per agent)

---

## Open Questions

1. **Rate limiting**: How to manage API limits across many agents?
2. **Cost control**: Budget caps per task/session?
3. **Rollback strategy**: How to undo partial agent work?
4. **Human escalation**: When should agents request help?
5. **Agent specialization**: Pre-defined roles vs dynamic assignment?

---

## References

- [claude-flow](https://github.com/ruvnet/claude-flow) - Enterprise orchestration platform
- [claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) - Hook patterns
- [Feature Request #3013](https://github.com/anthropics/claude-code/issues/3013) - Official parallel execution request
- [A2A Protocol](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/) - Google's agent interoperability standard
- [claude-squad](https://github.com/smtg-ai/claude-squad) - Terminal-based multi-agent management

---

## Next Steps

1. **Decide on orchestrator language** (Node.js recommended)
2. **Set up project structure** (new repo or WoW extension?)
3. **Implement Phase 1 hooks**
4. **Create SPECS.md** via interview process (per specs-interview.md rule)
