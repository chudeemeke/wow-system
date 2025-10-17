# WoW System - Current Truth
Generated: 2025-10-05T09:24:45.345Z
Generation Time: 5.02s

## ⚠️ Warnings
- **validation**: Version consistency - Required validation failed
- **validation**: All handlers have tests - Required validation failed
- **validation**: Core modules present - Required validation failed
- **validation**: Config file exists - Required validation failed

## Status: 1/5 validations passed

## Project State

### Project

#### Version [ESSENTIAL]
```bash
$ grep 'readonly WOW_VERSION=' src/core/utils.sh | cut -d'"' -f2
5.0.1
```

#### Description [ESSENTIAL]
```bash
$ head -10 README.md | grep -A 2 '# WoW System' | tail -1 | sed 's/^> //'
**Ways of Working Enforcement for Claude Code**
```

#### License
```bash
$ grep '"license":' package.json 2>/dev/null | cut -d'"' -f4 || echo 'MIT'
```

#### Author [ESSENTIAL]
```bash
$ echo 'Chude <chude@emeke.org>'
Chude <chude@emeke.org>
```

### Architecture

#### Total Modules [ESSENTIAL]
```bash
$ find src -name '*.sh' -type f | wc -l
26
```

#### Core Modules
```bash
$ ls -1 src/core/*.sh | xargs -n1 basename | sed 's/.sh//'
config-loader
orchestrator
session-manager
state-manager
utils
```

#### Security Handlers [ESSENTIAL]
```bash
$ ls -1 src/handlers/*.sh | xargs -n1 basename | sed 's/-handler.sh//' | sed 's/.sh//'
b
edit
glob
grep
handler-router
read
task
webfetch
write
```

#### Engines
```bash
$ ls -1 src/engines/*.sh 2>/dev/null | xargs -n1 basename | sed 's/-engine.sh//' | sed 's/.sh//' || echo 'None'
capture
risk-assessor
scoring
```

#### Security Components
```bash
$ ls -1 src/security/*.sh 2>/dev/null | xargs -n1 basename | sed 's/.sh//' || echo 'None'
credential-detector
credential-redactor
credential-scanner
```

#### UI Components
```bash
$ ls -1 src/ui/*.sh 2>/dev/null | xargs -n1 basename | sed 's/.sh//' || echo 'None'
display
```

#### Design Patterns
```bash
$ ls -1 src/patterns/*.sh 2>/dev/null | xargs -n1 basename | sed 's/.sh//' || echo 'None'
di-container
event-bus
```

#### Tools & Utilities
```bash
$ ls -1 src/tools/*.sh 2>/dev/null | xargs -n1 basename | sed 's/.sh//' || echo 'None'
email-sender
```

#### CLI Commands
```bash
$ ls -1 bin/* 2>/dev/null | xargs -n1 basename | grep -v '\.sh$' || echo 'None'
wow-capture
wow-email-setup
```

### Testing

#### Total Tests [ESSENTIAL]
```bash
$ find tests -name 'test-*.sh' -type f | wc -l
23
```

#### Test Suites
```bash
$ ls -1 tests/test-*.sh | xargs -n1 basename | sed 's/test-//' | sed 's/.sh//'
b-handler.sh
capture-engine
config-loader
di-container
doc-sync
edit-handler
email-sender
event-bus
framework
glob-handler
grep-handler
handler-factory
install-manager
orchestrator
read-handler
session-manager
state-manager
task-handler
webfetch-handler
wow-capture-cli
write-handler
```

#### Test Coverage - Core
```bash
$ grep -h 'assert_' tests/test-*manager.sh tests/test-*loader.sh 2>/dev/null | wc -l
101
```

#### Test Coverage - Handlers
```bash
$ grep -h 'assert_' tests/test-*-handler.sh 2>/dev/null | wc -l
116
```

#### Test Coverage - Engines
```bash
$ grep -h 'assert_' tests/test-*-engine.sh 2>/dev/null | wc -l
53
```

### Features

#### Handler Count [ESSENTIAL]
```bash
$ ls -1 src/handlers/*-handler.sh 2>/dev/null | wc -l
8
```

#### Handlers List
```bash
$ ls -1 src/handlers/*.sh | xargs -n1 basename | sed 's/-handler.sh//' | tr '\n' ', ' | sed 's/, $//'
bash,edit,glob,grep,handler-router.sh,read,task,webfetch,write,
```

#### Capture Engine Status [ESSENTIAL]
```bash
$ [ -f src/engines/capture-engine.sh ] && echo 'Implemented (v5.0.1)' || echo 'Not implemented'
Implemented (v5.0.1)
```

#### Email Alert System [ESSENTIAL]
```bash
$ [ -f src/tools/email-sender.sh ] && echo 'Implemented with OS keychain' || echo 'Not implemented'
Implemented with OS keychain
```

#### Credential Security
```bash
$ [ -f src/security/credential-detector.sh ] && echo 'Implemented (30+ patterns)' || echo 'Not implemented'
Implemented (30+ patterns)
```

#### Documentation Automation [ESSENTIAL]
```bash
$ which doctruth >/dev/null 2>&1 && echo 'docTruth v'$(doctruth --version) || echo 'Not configured'
docTruth v1.0.2
```

### Metrics

#### Total Lines of Code
```bash
$ find src -name '*.sh' -type f -exec wc -l {} + | tail -1 | awk '{print $1}'
10582
```

#### Core Module LOC
```bash
$ find src/core -name '*.sh' -type f -exec wc -l {} + | tail -1 | awk '{print $1}'
2160
```

#### Handler LOC
```bash
$ find src/handlers -name '*.sh' -type f -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo '0'
3289
```

#### Test LOC
```bash
$ find tests -name '*.sh' -type f -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo '0'
9855
```

#### Public Functions
```bash
$ grep -rh '^[a-z_]*() {' src/ | wc -l
367
```

#### Documentation Files
```bash
$ find . -maxdepth 3 -name '*.md' -type f | grep -v node_modules | wc -l
33
```

### Configuration

#### Default Config Location
```bash
$ echo '~/.claude/wow-config.json or /root/wow-system/wow-config.json'
~/.claude/wow-config.json or /root/wow-system/wow-config.json
```

#### Enforcement Modes
```bash
$ echo 'strict, lenient, monitor (configurable)'
strict, lenient, monitor (configurable)
```

#### Hook Integration [ESSENTIAL]
```bash
$ [ -f hooks/user-prompt-submit.sh ] && echo 'PreToolUse hook implemented' || echo 'Not configured'
PreToolUse hook implemented
```

### Dependencies

#### System Dependencies
```bash
$ echo 'bash >= 4.0, jq, libsecret-tools (optional)'
bash >= 4.0, jq, libsecret-tools (optional)
```

#### Bash Version
```bash
$ bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
5.2.21
```

#### jq Available
```bash
$ which jq >/dev/null 2>&1 && echo 'Yes ('$(jq --version)')' || echo 'No'
Yes (jq-1.7)
```

#### libsecret Available
```bash
$ which secret-tool >/dev/null 2>&1 && echo 'Yes' || echo 'No (optional)'
Yes
```

## Validation Results

| Status | Validation | Result | Required |
|--------|------------|--------|----------|
| ❌ | Version consistency | ✗ Version mismatch: code=5.0.1, readme= | Yes |
| ❌ | All handlers have tests | ✗ Handler/test mismatch: 9 handlers, 8 tests | Yes |
| ❌ | Core modules present | ✗ Missing core modules: file-storage.sh | Yes |
| ✅ | Hook executable | ✓ Hook is executable | Yes |
| ❌ | Config file exists | ✗ No config | Yes |

## Working Examples

```bash
# Initialize WoW
source /root/wow-system/src/core/orchestrator.sh && wow_init

# Run all tests
for test in tests/test-*.sh; do bash $test; done

# Check handler status
source src/handlers/handler-router.sh && handler_router_list

# View session metrics
cat ~/.wow-data/sessions/latest/metrics.json

# Update documentation
doctruth

```

## Performance Metrics

| Metric | Value |
|--------|-------|
| Hook execution time | 0m0.519s |
| Total codebase size | 360K |
| Total test suite size | 340K |

## Environment

- **Operating System**: Linux
- **OS Version**: 6.6.87.2-microsoft-standard-WSL2
- **Shell**: /bin/bash
- **Installation Location**: /root/wow-system

---
*Generated by [DocTruth](https://github.com/yourusername/doctruth) - The Universal Documentation Truth System*
*Config: .doctruth.yml*