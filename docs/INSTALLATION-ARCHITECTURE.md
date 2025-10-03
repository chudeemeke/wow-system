# WoW System v5.0 - Installation Architecture

## XDG Base Directory Compliance

The WoW System follows the XDG Base Directory Specification for proper separation of concerns and data resilience.

### Directory Structure

```
Source Repository:
  ~/Projects/wow-system/                    [Git repository - Development]
  ├── src/                                 [Source code]
  │   ├── core/                           [Core modules]
  │   ├── handlers/                       [Security handlers]
  │   ├── patterns/                       [Design pattern implementations]
  │   ├── factories/                      [Factory implementations]
  │   ├── decorators/                     [Decorator implementations]
  │   └── chains/                         [Chain of Responsibility]
  ├── tests/                              [Test suites]
  ├── scripts/                            [Installation scripts]
  └── config/                             [Default configuration templates]

Production Installation:
  $XDG_DATA_HOME/wow-system/              [~/.local/share/wow-system/]
  OR $HOME/.local/lib/wow-system/         [Alternative]
  ├── lib/                                [Core libraries - immutable]
  │   ├── core/
  │   ├── handlers/
  │   └── patterns/
  ├── bin/                                [Executable scripts]
  │   ├── wow-cli
  │   └── wow-health-check
  ├── VERSION                             [Version file]
  └── .manifest.json                      [Installation manifest]

User Configuration:
  $XDG_CONFIG_HOME/wow-system/            [~/.config/wow-system/]
  ├── wow-config.json                     [User configuration]
  ├── custom-handlers/                    [User-defined handlers]
  │   └── README.md                       [Handler development guide]
  ├── patterns/                           [User pattern overrides]
  └── backups/                            [Configuration backups]
      ├── pre-upgrade-v4.3.0/            [Before upgrade backups]
      └── pre-upgrade-v5.0.0/

Runtime Data:
  $XDG_DATA_HOME/wow-system/data/         [~/.local/share/wow-system/data/]
  ├── state/                              [Session state]
  │   └── session-*.json
  ├── storage/                            [Persistent storage]
  │   └── namespace/key/value
  ├── logs/                               [Log files]
  │   ├── wow-system.log
  │   └── wow-system.log.1
  ├── cache/                              [Temporary cache]
  └── metrics/                            [Historical metrics]
      └── metrics-YYYY-MM-DD.json

Claude Code Integration:
  ~/.claude/                              [Claude Code directory]
  ├── hooks/                              [Auto-regenerated hooks]
  │   └── user-prompt-submit.sh           [Main hook - symlink or copy]
  └── settings.json                       [Hook registration - managed]

Installation Backups:
  $XDG_CONFIG_HOME/wow-system/backups/    [Rollback capability]
  ├── installations/
  │   ├── v4.3.0/                        [Previous installation]
  │   └── v5.0.0/                        [Current installation]
  └── rollback.log                        [Rollback history]
```

## Installation Manifest

Location: `$INSTALL_DIR/.manifest.json`

```json
{
  "version": "5.0.0",
  "installed_at": "2025-10-03T12:00:00Z",
  "installed_from": "/path/to/source",
  "installation_method": "install-manager",
  "files": {
    "lib/core/orchestrator.sh": {
      "checksum": "sha256:abc123...",
      "size": 12345,
      "mode": "0644"
    },
    "lib/handlers/bash-handler.sh": {
      "checksum": "sha256:def456...",
      "size": 23456,
      "mode": "0644"
    }
  },
  "dependencies": {
    "bash": ">=4.0",
    "jq": ">=1.5"
  },
  "previous_version": "4.3.0",
  "rollback_available": true,
  "rollback_path": "~/.config/wow-system/backups/installations/v4.3.0"
}
```

## Installation Process

### 1. Pre-Installation Checks
- Verify bash >= 4.0
- Verify jq installed
- Check disk space
- Validate source integrity

### 2. Backup Phase
- Backup current installation to `~/.config/wow-system/backups/installations/v{version}/`
- Backup current configuration to `~/.config/wow-system/backups/pre-upgrade-v{version}/`
- Create rollback manifest

### 3. Installation Phase
- Create XDG directories if not exist
- Copy source to temporary staging directory
- Validate all files
- Atomic move: staging → production
- Set proper permissions

### 4. Configuration Phase
- Copy default config if user config doesn't exist
- Migrate configuration if needed
- Validate configuration

### 5. Integration Phase
- Detect Claude Code settings location
- Generate hooks in ~/.claude/hooks/
- Register hooks in ~/.claude/settings.json
- Verify hook registration

### 6. Post-Installation
- Create installation manifest
- Run health check
- Display installation summary
- Cleanup staging directory

### 7. Rollback on Failure
- If any step fails:
  - Restore previous installation
  - Restore previous configuration
  - Log failure reason
  - Exit with error

## Uninstallation Process

### Clean Uninstall
```bash
wow-uninstall --clean
```
- Remove installation directory
- Remove configuration directory
- Remove data directory
- Unregister hooks
- Remove all traces

### Preserve Data Uninstall
```bash
wow-uninstall --preserve-data
```
- Remove installation directory
- Preserve configuration directory
- Preserve data directory
- Unregister hooks

## Upgrade Process

### In-Place Upgrade
```bash
wow-upgrade /path/to/new/source
```
1. Verify new version > current version
2. Backup current installation
3. Run migration scripts (if any)
4. Install new version
5. Migrate configuration
6. Health check
7. Rollback if health check fails

### Migration Scripts
Location: `migrations/v{from}_to_v{to}.sh`

Example: `migrations/v4.3.0_to_v5.0.0.sh`
```bash
#!/bin/bash
# Migration from v4.3.0 to v5.0.0

migrate_config() {
    # Convert old config format to new format
    # Add new required fields
    # Remove deprecated fields
}

migrate_state() {
    # Update state format if changed
}

migrate_storage() {
    # Update storage format if changed
}
```

## Rollback Process

### Automatic Rollback
If installation or health check fails, automatic rollback:
1. Detect failure point
2. Stop installation
3. Restore from backup
4. Restore configuration
5. Re-register hooks
6. Log rollback event

### Manual Rollback
```bash
wow-rollback v4.3.0
```
1. Verify backup exists
2. Stop current system
3. Restore installation from backup
4. Restore configuration from backup
5. Re-register hooks
6. Health check
7. Update manifest

## Health Check System

### Installation Health Check
```bash
wow-health-check --full
```

Checks:
1. All required files present
2. File checksums match manifest
3. Proper permissions set
4. Dependencies available
5. Configuration valid
6. Hooks registered
7. Handlers loadable
8. State directories accessible

Exit codes:
- 0: All checks passed
- 1: Critical failure (system non-functional)
- 2: Warning (system functional but degraded)

### Runtime Health Check
```bash
wow-health-check --runtime
```

Checks:
1. Can initialize orchestrator
2. Can load all handlers
3. Can access state
4. Can access configuration
5. Hooks responding
6. No error accumulation

## Environment Variables

### Installation Paths
```bash
WOW_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/wow-system"
WOW_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wow-system"
WOW_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/wow-system/data"
WOW_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wow-system"
```

### Runtime Paths
```bash
WOW_HOME="${WOW_INSTALL_DIR}"
WOW_LIB_DIR="${WOW_INSTALL_DIR}/lib"
WOW_BIN_DIR="${WOW_INSTALL_DIR}/bin"
```

### Override (for development)
```bash
WOW_DEV_MODE=1
WOW_SOURCE_DIR="/path/to/dev/wow-system"
```

## Installation Methods

### Method 1: Standard User Install
```bash
cd /path/to/wow-system
bash scripts/install-manager.sh --user
```
Installs to `~/.local/share/wow-system/`

### Method 2: System-Wide Install (requires sudo)
```bash
cd /path/to/wow-system
sudo bash scripts/install-manager.sh --system
```
Installs to `/usr/local/lib/wow-system/`

### Method 3: Development Install
```bash
cd /path/to/wow-system
bash scripts/install-manager.sh --dev
```
Installs to development location with symlinks for active development

### Method 4: Custom Location
```bash
cd /path/to/wow-system
bash scripts/install-manager.sh --prefix /custom/path
```
Installs to `/custom/path/wow-system/`

## File Permissions

- Executables: 0755
- Libraries: 0644
- Configuration: 0600 (user-only access for security)
- Data directories: 0700 (user-only access)
- Hooks: 0755 (executable)

## Multi-Version Support

Can install multiple versions side-by-side:
```
~/.local/share/wow-system-v4.3.0/
~/.local/share/wow-system-v5.0.0/   [current]
~/.local/share/wow-system-v5.1.0/
```

Symlink points to active version:
```
~/.local/share/wow-system -> wow-system-v5.0.0
```

Switch versions:
```bash
wow-switch-version v4.3.0
```

## Configuration Migration

Configuration files are versioned. Migration is automatic:

```json
{
  "schema_version": "5.0",
  "migrated_from": "4.3",
  "migration_date": "2025-10-03T12:00:00Z",
  ...
}
```

If schema version mismatch detected, migration runs automatically.

## Resilience Features

1. **Atomic Installation**: All-or-nothing
2. **Automatic Backup**: Before every upgrade
3. **Automatic Rollback**: On failure
4. **Health Validation**: Before marking install complete
5. **Checksums**: Verify file integrity
6. **Permissions**: Proper security
7. **XDG Compliance**: Data survives .claude deletion

## Recovery Scenarios

### Scenario 1: .claude directory deleted
**Impact**: Hooks lost
**Recovery**: Auto-regenerate on next WoW operation
```bash
wow-hooks-regenerate
```

### Scenario 2: Installation corrupted
**Impact**: System non-functional
**Recovery**: Reinstall from source
```bash
wow-reinstall
```
OR rollback to previous version:
```bash
wow-rollback
```

### Scenario 3: Configuration corrupted
**Impact**: Uses defaults
**Recovery**: Restore from backup
```bash
wow-config-restore
```
OR regenerate defaults:
```bash
wow-config-reset
```

### Scenario 4: Data corruption
**Impact**: Metrics/state lost, but system functional
**Recovery**: Clear and reinitialize
```bash
wow-data-reset
```

---

Last Updated: 2025-10-03
Version: 5.0.0
