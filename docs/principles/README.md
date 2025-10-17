# WoW Principles & Philosophy

This directory contains the **why** behind WoW, not just the **how**.

---

## Current Documents

- **[PHILOSOPHY.md](./PHILOSOPHY.md)** - Core principles, axioms, and pet peeves
- Future: Version-specific deep dives and design decision logs

---

## Organization Strategy

### For Each Major Version

Create a folder: `docs/principles/v{VERSION}/`

Example structure:
```
docs/principles/
├── README.md (this file)
├── PHILOSOPHY.md (evergreen core principles)
├── v5.0/
│   ├── design-decisions.md (why we chose PreToolUse hooks)
│   ├── pet-peeves-addressed.md (specific frustrations solved)
│   └── lessons-learned.md (what worked, what didn't)
├── v6.0/
│   ├── design-decisions.md
│   ├── new-challenges.md
│   └── evolution-notes.md
```

---

## What to Document Here

### 1. Pet Peeves (The "Why")
- Specific frustrations that drove feature development
- Real examples of AI agent failures
- User pain points and their solutions

### 2. Design Decisions (The "How We Decided")
- Trade-offs considered
- Alternatives rejected and why
- Constraints that shaped the solution

### 3. Philosophy Evolution (The "Learning")
- How principles changed over time
- New insights from production use
- Feedback incorporation

### 4. Anti-Patterns (The "Don'ts")
- Mistakes made and corrected
- Design paths that didn't work
- Warnings for future maintainers

---

## Versioning Guidelines

### When to Create a New Version Folder

Create `v{X}.{Y}/` when:
- Major version bump (v5 → v6): Architectural changes
- Significant philosophy shift: New core principles added
- Major feature additions: New handlers, engines, or subsystems

### What Goes in Version Folders

- **design-decisions.md**: Why specific technical choices were made
- **pet-peeves-addressed.md**: Which frustrations this version solved
- **lessons-learned.md**: Retrospective after version stabilizes
- **examples/**: Real-world scenarios blocked or allowed

### What Stays in Root

- **PHILOSOPHY.md**: Evergreen core principles (updated, not replaced)
- **README.md**: This organizational guide

---

## Distillation Best Practices

### How to Distill Pet Peeves

1. **Start Specific**: Write down exact frustrations as they occur
2. **Find Patterns**: Group similar frustrations (5-10 → 2-3 themes)
3. **Extract Principle**: What's the underlying need? (Control? Transparency?)
4. **Make Actionable**: Turn feeling into testable criterion

Example:
```
Specific: "Claude deleted my config file without asking"
Pattern: Surprising autonomous actions
Principle: User sovereignty - explicit consent required
Actionable: Block file deletions in project directories without confirmation
```

### When to Distill

- **Immediate**: Capture raw frustration as it happens
- **Weekly**: Review and group patterns
- **Per Version**: Distill into core principles document
- **Annual**: Update PHILOSOPHY.md with refined insights

---

## Derivatives & Forks

If you create a derivative of WoW:

1. **Fork `docs/principles/`** - Preserve lineage and credit
2. **Create `derivatives/YOUR-NAME/`** - Document your specific adaptations
3. **Document divergence** - What changed and why
4. **Link back** - Reference original philosophy and what you kept/changed

Example:
```
docs/principles/derivatives/
├── corporate-wow/
│   ├── README.md (how this differs from base WoW)
│   ├── compliance-requirements.md
│   └── enterprise-constraints.md
├── research-wow/
│   ├── README.md
│   └── academic-use-cases.md
```

---

## Maintenance

### Monthly Review
- Read recent issue/PR discussions
- Update pet-peeves list with new frustrations
- Check if principles still align with behavior

### Per-Version Review
- Create version folder
- Write design-decisions.md while fresh
- Capture lessons-learned.md after 3 months of use

### Annual Review
- Distill PHILOSOPHY.md
- Remove outdated examples
- Refine core axioms based on evidence

---

## Questions to Ask

When documenting here, always answer:

1. **Why does this matter?** (Connect to user pain)
2. **What did we learn?** (Insights from implementation)
3. **Would future-me understand this?** (Clarity test)
4. **Can someone disagree productively?** (Is it specific enough?)

---

## Quick Start for New Contributors

1. Read **PHILOSOPHY.md** first (understand the "why")
2. Check latest version folder (see recent decisions)
3. When adding features, ask: "Which pet peeve does this solve?"
4. Document your reasoning in appropriate version folder

---

*Keep the philosophy alive. It's not just code; it's captured frustration turned into protection.*
