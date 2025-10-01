# WoW System v4.1

> **Ways of Working Intelligence Layer for Claude Code**
> Never compromise on development principles again.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status: In Development](https://img.shields.io/badge/Status-In%20Development-orange.svg)](IMPLEMENTATION-PLAN.md)

---

## 🎯 What Is This?

The **WoW (Ways of Working) System** is an advanced enforcement and intelligence layer for Claude Code that ensures adherence to development best practices through hooks, behavioral tracking, and intelligent guidance.

Think of it as a **real-time coach** that:
- ✅ Guides Claude LLM to follow your development principles
- 🛡️ Blocks dangerous operations before they execute
- 📊 Tracks compliance metrics and behavioral patterns
- 🎯 Provides actionable feedback for improvement
- 🏆 Rewards good practices with streaks and achievements

---

## 🚀 Quick Start

### Prerequisites
- Claude Code v2.0.1 or higher
- Bash 4.0+ (Linux, WSL2, macOS)
- `jq` (for JSON parsing)

### Installation

```bash
# Clone the repository
cd "/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects"
git clone <repository-url> wow-system
cd wow-system

# Deploy to Claude Code
./scripts/deploy.sh

# Launch Claude Code and see WoW in action!
claude
```

---

## ✨ Features

### Real-Time Enforcement
- **SessionStart**: Welcome banner with current status
- **UserPromptSubmit**: Live metrics bar before each response
- **PreToolUse**: Intercept and validate operations before execution
- **SessionStop**: Comprehensive session report

### Intelligent Scoring
```
Score = Base (70) + ECR Bonus (up to +30) - Violations (-20 max)
Where:
- ECR (Edit/Create Ratio): Reward editing over creating
- Violations: Penalize non-compliant behavior
```

### Selective Blocking
- 🔴 **Hard Block**: Dangerous operations (system files, destructive commands)
- 🟡 **Warning**: Risky actions (root folder writes, -3 points)
- 🟢 **Praise**: Good practices (edits, +2 points)

### Pattern Detection
- Trend analysis (improving/stable/degrading)
- Streak tracking (consecutive compliant operations)
- Trust level progression
- Actionable feedback ("Need 1 more edit for grade A")

---

## 📖 Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | This file - quick start and overview |
| [CONTEXT.md](CONTEXT.md) | Full background, history, what happened |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Deep technical design, UX/UI, security |
| [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) | Step-by-step build roadmap |

---

## 🏗️ Project Structure

```
wow-system/
├── .archive/                    # Historical versions for reference
│   ├── wow-system-v3.5/         # v3.5.0 implementation
│   ├── wow-system-v4.0/         # v4.0 design docs
│   ├── WOW-COMPLIANCE.md        # Organizational principles
│   └── broken-symlinks/         # v4.0.2 architecture reference
├── src/                         # Source code
│   ├── core/                    # State management, orchestration
│   ├── handlers/                # Tool interception (Bash, Write, Edit)
│   ├── hooks/                   # Claude Code hook implementations
│   ├── strategies/              # Intelligence (scoring, risk, patterns)
│   ├── storage/                 # Persistence layer
│   └── ui/                      # Visual feedback, reports
├── scripts/                     # Deployment, utilities
│   └── deploy.sh                # Deploy to Claude Code
├── tests/                       # Test suite
│   ├── unit/                    # Unit tests
│   ├── integration/             # Integration tests
│   └── e2e/                     # End-to-end tests
├── config/                      # Configuration files
│   ├── wow-config.json          # WoW system config
│   └── settings.json            # Claude Code settings template
├── docs/                        # Additional documentation
│   ├── architecture/            # Architecture diagrams
│   └── guides/                  # User and developer guides
└── examples/                    # Usage examples, plugins
```

---

## 🎨 Design Philosophy

**Anthropic Engineering** + **Apple Design**

| Principle | How We Apply It |
|-----------|----------------|
| **Systematic** | Every component has clear responsibility |
| **Thorough** | 80%+ test coverage, comprehensive error handling |
| **Safety-First** | Defensive design, fail-safe defaults |
| **Elegant** | Beautiful UI, delightful interactions |
| **Just Works** | Zero-config deployment, graceful degradation |

---

## 🔒 Security

### What We Protect Against
- ❌ Accidental destructive commands (`rm -rf /`, `chmod 777`)
- ❌ Unauthorized writes to system paths
- ❌ State corruption
- ❌ Git commit quality issues (emojis, wrong author)

### Fail-Safe Design
If WoW system fails, Claude Code continues working normally. **We never block Claude Code from functioning.**

---

## 📊 Example Output

### Session Start
```
╔══════════════════════════════════════════════════════════╗
║              🏆 WoW System v4.1 Active                   ║
║        Ways of Working Intelligence Enabled              ║
╠══════════════════════════════════════════════════════════╣
║  Score: 95/100 (A+) | Streak: 12 | Trust: HIGH          ║
║  Your coding excellence is being tracked ✨               ║
╚══════════════════════════════════════════════════════════╝
```

### Live Metrics
```
⚡ Score:88(B) | ECR:2.33 | VR:10.0% | Trend:↗ improving | Streak:6
```

### Session Report
```
═══════════════════════════════════════════════════════════
🏁 WOW SESSION REPORT
═══════════════════════════════════════════════════════════
Final Score: 95/100 (A+)
Total Operations: 23
Edit/Create Ratio: 3.5:1 (Excellent!)
Violation Rate: 4.3% (Low)
Longest Streak: 15 consecutive compliant operations

🏆 OUTSTANDING SESSION!
═══════════════════════════════════════════════════════════
```

---

## 🛠️ Development

### Running Tests
```bash
# Unit tests
./tests/run-unit-tests.sh

# Integration tests
./tests/run-integration-tests.sh

# All tests
./tests/run-all-tests.sh
```

### Building
```bash
# Validate all scripts
./scripts/validate.sh

# Run tests
./tests/run-all-tests.sh

# Deploy
./scripts/deploy.sh
```

---

## 🤝 Contributing

This is a personal project for enforcing my Ways of Working principles. However, if you're interested in adapting it for your own use:

1. Fork the repository
2. Customize `config/wow-config.json` with your principles
3. Modify handlers/strategies as needed
4. Deploy to your `.claude` folder

---

## 📈 Roadmap

See [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) for detailed roadmap.

**Current Phase**: Phase 0 - Foundation (Complete)
**Next Phase**: Phase 1 - Core & Storage

### Milestones
- [x] Phase 0: Foundation complete
- [ ] Phase 1: Core & Storage
- [ ] Phase 2: Hooks & Routing
- [ ] Phase 3: Handlers
- [ ] Phase 4: Strategies
- [ ] Phase 5: UI & UX
- [ ] Phase 6: Testing & Polish
- [ ] Phase 7: Extensions

---

## 📜 License

MIT License - See [LICENSE](LICENSE) for details

---

## 🙏 Acknowledgments

- Built for use with [Claude Code](https://claude.ai/code) by Anthropic
- Inspired by Anthropic's systematic engineering and Apple's design excellence
- Recovered and rebuilt after accidental deletion (September 30, 2025)

---

## 📞 Support

For questions, issues, or suggestions:
- Create an issue in this repository
- See [CONTEXT.md](CONTEXT.md) for background
- See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details

---

**Status**: 🚧 In Active Development
**Version**: 4.1.0-alpha
**Author**: Chude <chude@emeke.org>
**Last Updated**: October 1, 2025

---

> _"The code never lies, but the developer might forget. WoW remembers."_
