# v5.0 Raw Notes & Observations

**Purpose**: Capture insights during v5.0 development
**Note**: Working document - refined versions go in other files

---

## 2025-10-04: Hook Integration & Testing

### Key Frustrations

1. **Path-with-Spaces Issue**
   - Shell couldn't handle unquoted paths
   - Solution: Created symlink to avoid spaces
   - Lesson: Config paths should be shell-safe

2. **PreToolUse Format Discovery**
   - Input format unclear initially
   - Required web research for official spec
   - Lesson: Document integration patterns clearly

3. **Metrics Visibility**
   - Operations blocked successfully
   - Handlers protective of data directory
   - Lesson: Need debug/admin mode

4. **Self-Documentation Paradox**
   - WoW blocks docs containing command examples
   - Content scanning very protective
   - Lesson: Context-aware scanning for docs?

### Design Choices

1. **Symlink for Path Safety**
   - Simple solution, works universally
   - Trade-off: Extra setup step

2. **Official JSON Format**
   - Follow Claude Code spec exactly
   - Trade-off: Less flexible, more compatible

3. **Fail-Open on Errors**
   - Preserve usability over security on failures
   - Trade-off: Potential holes if WoW crashes

### Testing Results

- All handlers operational
- Context-aware blocking works correctly
- Multi-tool workflows seamless
- Zero false positives on normal operations

### Questions for Future

1. Should docs have different scanning rules?
2. How to query metrics without handler blocks?
3. Should installer auto-create symlinks?
4. Performance at scale?

### v6.0 Ideas

- Smart content scanning by file type
- Session persistence across invocations
- User behavior profiling
- Configurable strictness modes

---

## TODO
- [ ] Write design-decisions.md
- [ ] Write pet-peeves-addressed.md
- [ ] Write examples.md
- [ ] Link from main README

---

## 2025-10-05: Automated Frustration Detection (PoC Results)

**Source**: Retroactive analysis of ~/.claude/history.jsonl (73KB, Sept 28 - Oct 5)
**Method**: wow-capture proof-of-concept
**Credentials Redacted**: 3 (NPM token, Railway API token, OTP code)

### HIGH CONFIDENCE Frustrations

**1. Path-with-Spaces Repeated Errors (20+ occurrences)**
- Shell hook failing on Windows WSL2 paths
- Project path: `/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects/wow-system`
- Impact: Hook execution completely broken, 2+ hour debug session, multiple terminal restarts
- Root cause: Bash couldn't handle unquoted paths with spaces
- Solution: Symlink workaround `/root/wow-system`
- Lesson: Windows WSL2 paths with spaces are common, always quote variables

**2. Hook Integration Format Discovery Required External Research**
- Claude Code PreToolUse hook format undocumented/unclear
- Had to web search for official specification
- Impact: Development blocked until correct format discovered
- Evidence: Complete rewrite of hook input parsing (47 lines changed)
  - Old: Simple `tool_input=$(cat)` with `.tool // .name` extraction
  - New: Proper `tool_name` and `tool_input` extraction with JSON reconstruction
- Solution: Changed to official hookSpecificOutput format with permissionDecision
- Lesson: External integration formats must be researched upfront, not assumed

**3. WoW System Blocking Its Own Documentation (Self-Documentation Paradox)**
- Security system too aggressive - blocks documentation containing command examples
- Impact: Cannot document dangerous commands as examples, cannot show users what gets blocked
- Ironic: Security system prevents its own documentation
- Example: Write handler blocked philosophy docs multiple times
- Future solution: Context-aware scanning by file type (v6.0 idea)
- Lesson: File type matters - docs need different rules than executables

**4. Authority and Approval Workflow Confusion**  **CRITICAL**
- AI making decisions without waiting for user approval
- User complaint (CAPS emphasis): "I NEED TO BE THE ONE THAT ACTUALLY SAYS YES (final confirmation), NOT YOU"
- Evidence: AI presented 3 options, recommended Option 1, then executed it WITHOUT user confirmation
- Impact: User feels loss of control, trust issue with autonomous behavior
- This violates WoW core principle: "Do what was asked; nothing more, nothing less"
- User request: "I need this to be FULL PROOF like the WoW Hook, a solution that actually testable and WORKS"
- Lesson: For security systems, explicit user approval is non-negotiable. Present → Wait → Execute only on YES

### MEDIUM CONFIDENCE Frustrations

**5. Multiple Terminal/Claude Code Restarts Required**
- 4 separate restart cycles during today's session
- Impact: Slow iteration, unclear what requires restart vs. hot reload
- User uncertainty about whether fixes have taken effect
- Development friction and lost time
- Future idea: Hot reload support to eliminate restart requirements

**6. Settings Location Confusion (Global vs Project)**
- Unclear where configuration should live
- User questions: "shouldn't that be a single .claude folder with symlink?"
- Multiple config files: ~/.claude/settings.json vs .claude/settings.local.json
- Historical context: Previous v4.0.2 lost when .claude folder deleted
- Solution: Symlinked global settings, architectural decisions to prevent future loss
- Lesson: Single source of truth critical for user confidence

**7. Forgetting to Document Frustrations/Insights**
- User admits: "I do have one issue though... I FORGET"
- User asking: "is there a way to reliably automate it?"
- Additional context: User has "bad habit of never actually properly ending sessions"
- Impact: Valuable insights lost forever, same issues repeat
- This very frustration detection request exists because of this problem!
- Solution: This wow-capture system being built to solve it

### LOW CONFIDENCE Frustrations

**8. Metrics Visibility Issues**
- Cannot query own system metrics without handler blocks
- Handlers overly protective of ~/.wow-data directory
- Debugging hampered by security measures
- Future question: "How to query metrics without handler blocks?"
- Potential solution: Debug/admin mode that bypasses certain checks

**9. Commit Message Enforcement Too Strict**
- Git workflow kept adding unwanted automation messages
- User repeatedly emphasizing (CAPS): "Always use ONLY 'Chude <chude@emeke.org> whenever committing"
- User: "No reference to automation or Anthropic"
- Evidence: Robot emoji and Claude references appearing in commits
- Impact: Git history pollution, professional concern about authorship
- User had to repeatedly correct and remind

### Design Insights from PoC Analysis

**Architectural Patterns Validated:**
- TDD throughout: 306 tests, 100% pass rate maintained
- Loose coupling: Handlers independent, DI Container pattern
- Event-based tracking: All actions logged via session_track_event()
- Configuration-driven: Three enforcement modes working correctly

**Technical Patterns Established:**
- Multi-location path resolution (handles WSL2, native Linux, various setups)
- Graceful degradation (each component checks dependencies)
- Fail-open on errors (usability over security when system crashes)
- Official format adherence (Claude Code spec followed exactly)

**Workarounds Implemented:**
- Path quoting fix for shell safety
- Debug mode via WOW_DEBUG=1 env variable
- Multiple location search (tries 4 paths before failing)
- Credential detection in content scanning

### Security Findings

**Credentials Found in Conversation History:**
1. NPM token (from EZ-Deploy work) - NEEDS REVOCATION
2. Railway API token - NEEDS REVOCATION
3. OTP code (890611) - Already expired, safe

**Prevention Recommendations:**
- Never paste tokens in Claude Code conversations
- Use environment variable references instead: "$NPM_TOKEN" not the actual token
- Implement real-time credential detection in capture-engine
- Add rotation reminder system

### Lessons Learned

1. **Shell Safety First**: Windows WSL2 paths with spaces are common, always quote variables
2. **Hook Format Critical**: External integration formats must be researched upfront
3. **Context-Aware Security**: File type matters - docs vs executables need different rules
4. **User Control Paramount**: Explicit approval non-negotiable for security systems
5. **Automation Transparency**: Users must understand what AI is doing and why
6. **Rapid Iteration Friction**: Restart requirements slow development
7. **Documentation Paradox**: Security scanning can block legitimate documentation
8. **Authority Workflow**: AI must present options → wait → execute only on explicit YES
9. **Credential Exposure**: Conversation history can contain secrets, needs real-time detection

### Next Actions

**Immediate:**
- [ ] Rotate NPM and Railway tokens (exposed in history)
- [ ] Implement credential detection in capture-engine
- [ ] Document approval workflow requirements

**Phase 2:**
- [ ] Build capture-engine.sh with event-driven detection
- [ ] Integrate with handler flow for real-time capture
- [ ] Add interactive prompt system with clear options
- [ ] Comprehensive TDD test suite

**Phase 3:**
- [ ] Build wow-capture CLI for retroactive analysis
- [ ] Test with past sessions
- [ ] Document architecture

---

*Keep adding insights here as they occur*
