# WoW System: Core Philosophy

**Version**: 1.0 (WoW v5.0.0)
**Date**: 2025-10-04

---

## Why WoW Exists

WoW was created to solve a fundamental problem: **AI agents are powerful but dangerous**.

### The Core Pet Peeves

1. **Unchecked Autonomy** - Agents can execute any command without validation
2. **Lack of Transparency** - Operations happen in black boxes
3. **All-or-Nothing Trust** - Either full access or no delegation
4. **Surprising Behavior** - Unintended consequences from proactive actions
5. **Credential Exposure** - Agents can read sensitive secrets

---

## Guiding Principles

### 1. Defense in Depth
Multiple validation layers: path, content, operation, context

### 2. Fail-Safe Design
When uncertain, block and notify user

### 3. Transparency First
Clear explanations for every block

### 4. Intelligent, Not Paranoid
Context-aware security that doesn't cripple productivity

### 5. Extensible & Modular
Easy to add handlers and customize rules

### 6. User Sovereignty
User always has final control

---

## Core Axioms

1. **"Do what was asked; nothing more, nothing less"**
2. **"Explicit is better than implicit"**
3. **"Security is a journey, not a destination"**
4. **"Trust, but verify"**

---

## Success Criteria

-  Zero catastrophic operations execute
-  Zero false positives on normal workflows
-  Clear visibility into blocks
-  Easy to extend
-  Transparent until needed

---

## What WoW Is NOT

- Not a sandbox
- Not a replacement for judgment
- Not foolproof
- Not a bottleneck
- Not intrusive

---

## For Future Versions

Keep documentation of:
- Pet peeves that drove each feature
- Design decisions and trade-offs
- Examples of blocked vs allowed operations
- User feedback and iteration history

Store in versioned folders: `docs/principles/v5.0/`, `v6.0/`, etc.

---

*"AI agents are powerful tools, not trusted admins."*
