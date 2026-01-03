# WoW Structure Standard

**Version:** 1.0.0
**Compatible with:** wow-system >= 5.4.3
**Status:** Production Ready

---

## Overview

The **WoW (World of Wisdom) Structure Standard** is the **Single Source of Truth** for project folder organization across all development projects. It defines:

-  **Required folders**: src/, docs/, tests/
-  **Recommended folders**: scripts/, config/, assets/
-  **Optional folders**: public/, build/, dist/, lib/
-  **Root file whitelist**: What belongs in project root
-  **Framework exceptions**: Next.js, Python, Rust, Go, Node.js
-  **Migration rules**: How to classify and move files
-  **Validation rules**: Error vs warning severity

---

## Quick Start

### For Tool Developers

**Source the structure standard:**

```bash
# Resolution order:
# 1. $WOW_STRUCTURE_CONFIG env var
# 2. ~/Projects/wow-system/config/wow-structure-standard.json
# 3. Embedded fallback

WOW_STRUCTURE_CONFIG="${WOW_STRUCTURE_CONFIG:-$HOME/Projects/wow-system/config/wow-structure-standard.json}"

if [ -f "$WOW_STRUCTURE_CONFIG" ] && command -v jq &> /dev/null; then
    # Load config
    WOW_VERSION=$(jq -r '.version' "$WOW_STRUCTURE_CONFIG")

    # Get required folders
    REQUIRED_FOLDERS=$(jq -r '.structure.folders.required | keys[]' "$WOW_STRUCTURE_CONFIG")

    # Get allowed root files
    ALLOWED_ROOT_FILES=$(jq -r '.structure.root_files.allowed_by_category | to_entries[] | .value.files[]' "$WOW_STRUCTURE_CONFIG")
else
    # Fallback to embedded defaults
    WOW_VERSION="1.0.0"
    REQUIRED_FOLDERS=("src" "docs" "tests")
fi
```

### For Project Creators

**Create new project with WoW structure:**

```bash
# Use add-go-alias (auto-creates WoW structure)
add-go-alias myproject '~/Projects/my-project'
# Answer 'y' → Creates src/, docs/, tests/

# Or manually:
mkdir -p ~/Projects/my-project/{src,docs,tests,scripts,assets,config}
cat > ~/Projects/my-project/.project.jsonl << EOF
{"name":"my-project","created":"$(date +%Y-%m-%d)","wow_structure":true,"wow_version":"1.0.0"}
EOF
```

---

## Configuration File Location

**Primary source:**
```
~/Projects/wow-system/config/wow-structure-standard.json
```

**Override via environment variable:**
```bash
export WOW_STRUCTURE_CONFIG="/path/to/custom/wow-structure-standard.json"
```

**Check current config:**
```bash
jq '.version, .standard.name' ~/Projects/wow-system/config/wow-structure-standard.json
```

---

## Schema Structure

### Top-Level Sections

```json
{
  "version": "5.4.3",              // Tied to wow-system version
  "standard": { ... },              // Metadata about the standard
  "structure": { ... },             // Core structure definitions
  "framework_exceptions": { ... },  // Framework-specific overrides
  "migration": { ... },             // Migration rules
  "validation": { ... },            // Validation rules
  "_metadata": { ... },             // Schema metadata
  "_comments": { ... }              // Usage documentation
}
```

### Structure Definition

```json
"structure": {
  "folders": {
    "required": {
      "src": { "purpose": "...", "allowed_patterns": [...] },
      "docs": { ... },
      "tests": { ... }
    },
    "recommended": {
      "scripts": { ... },
      "config": { ... },
      "assets": { ... }
    },
    "optional": {
      "public": { ... },
      "build": { ... },
      "dist": { ... }
    }
  },
  "root_files": {
    "allowed_by_category": {
      "package_management": { "files": [...] },
      "build_config": { "files": [...] },
      "framework_config": { "files": [...] },
      ...
    }
  }
}
```

---

## Usage Examples

### Example 1: Validate Project Structure

```bash
# Check if project follows WoW standard
PROJECT_PATH="$HOME/Projects/my-project"

# Get required folders from config
REQUIRED=$(jq -r '.structure.folders.required | keys[]' "$WOW_STRUCTURE_CONFIG")

for folder in $REQUIRED; do
    if [ ! -d "$PROJECT_PATH/$folder" ]; then
        echo " Missing required folder: $folder"
    fi
done
```

### Example 2: Classify File for Migration

```bash
# Classify where a file should go
FILE="test-utils.js"

# Check if it's a test file
if [[ "$FILE" =~ ^test- ]] || [[ "$FILE" =~ \.(test|spec)\. ]]; then
    echo "tests/"
# Check if it's a source file
elif [[ "$FILE" =~ \.(js|jsx|ts|tsx|py)$ ]]; then
    # But exclude config files
    if [[ "$FILE" =~ \.config\. ]]; then
        echo "root"
    else
        echo "src/"
    fi
fi
```

### Example 3: Get Framework Exceptions

```bash
# Check if Next.js allows 'app/' folder in root
FRAMEWORK="nextjs"

ALLOWED_FOLDERS=$(jq -r ".framework_exceptions.${FRAMEWORK}.allowed_root_folders[]" "$WOW_STRUCTURE_CONFIG" 2>/dev/null)

if echo "$ALLOWED_FOLDERS" | grep -q "^app$"; then
    echo " Next.js allows app/ in root"
fi
```

---

## Framework Exceptions

The standard includes built-in exceptions for popular frameworks:

### Next.js (`nextjs`)
- **Allowed root folders**: app/, pages/, public/, styles/
- **Allowed root files**: next.config.*, middleware.ts, next-env.d.ts
- **Rationale**: Next.js 13+ App Router convention

### Python (`python`)
- **Allowed root folders**: venv/, .venv/, __pycache__/
- **Allowed root files**: pyproject.toml, setup.py, requirements.txt
- **Rationale**: Python virtual environment convention

### Node.js (`nodejs`)
- **Allowed root folders**: node_modules/, dist/, build/, out/
- **Allowed root files**: package.json, yarn.lock, pnpm-lock.yaml
- **Rationale**: npm/yarn/pnpm conventions

**See full list:** Query `.framework_exceptions` in the JSON config

---

## Migration Rules

The config defines classification priority:

1. **Whitelisted files** → Stay in root
2. **Security files** → Never move (warn user)
3. **Config files** → Stay in root
4. **Test files** → tests/
5. **Script files** → scripts/
6. **Documentation** → docs/
7. **Source files** → src/
8. **Asset files** → assets/
9. **Data files** → assets/

**Never move automatically:**
- `.env`, `.env.*`
- `*.key`, `*.pem`, `*.crt`, `*.p12`, `*.pfx`
- Files matching `*credentials*`, `*secret*`

---

## Validation Severity Levels

### Error (Blocks in strict mode)
- Source files in root (except whitelisted)
- Missing required folders (src/, docs/, tests/)

### Warning (Reports but doesn't block)
- Non-standard root files
- Missing recommended folders
- Scripts in root (except setup.sh, install.sh)
- Docs in root (except README.md, LICENSE, etc.)

### Info (Logs only)
- Missing optional folders
- Unusual file placement

---

## Versioning

**Structure standard version:** Independent from wow-system version but tied for compatibility

**Version file:**
```
~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION
```

**Compatibility:**
- Structure v1.0.0 requires wow-system >= 5.4.3
- Future versions will maintain backward compatibility
- Breaking changes will increment major version

**Version check in tools:**
```bash
STRUCTURE_VERSION=$(cat ~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION 2>/dev/null || echo "unknown")
REQUIRED_VERSION="1.0.0"

if [ "$STRUCTURE_VERSION" != "$REQUIRED_VERSION" ]; then
    echo "  Warning: Structure standard v$STRUCTURE_VERSION (expected v$REQUIRED_VERSION)"
fi
```

---

## Integration with Tools

### ai-dev-environment

**Tools that consume this config:**
- `validate-paths.sh` - Validates project structures
- `migrate-project.sh` - Migrates projects to WoW standard
- `add-go-alias` - Creates new projects with WoW structure

**Resolution path:**
1. Check `$WOW_STRUCTURE_CONFIG` env var
2. Check `~/Projects/wow-system/config/wow-structure-standard.json`
3. Fall back to embedded defaults

### Custom Tools

**Recommended integration:**

```bash
#!/bin/bash
# my-tool.sh

# Source WoW structure config
source ~/Projects/ai-dev-environment/lib/wow-config-loader.sh

# Load structure standard
wow_load_structure_config

# Get required folders
wow_get_required_folders

# Validate project
wow_validate_structure "$PROJECT_PATH"
```

---

## Best Practices

### For Tool Developers

1. **Always source from config** - Never hardcode structure rules
2. **Graceful fallback** - Provide embedded defaults if config missing
3. **Version compatibility** - Check config version matches requirements
4. **Cache config** - Load once per session, not per operation
5. **Validate config** - Use jq to validate JSON before parsing

### For Project Maintainers

1. **Follow required folders** - Always have src/, docs/, tests/
2. **Use recommended folders** - scripts/, config/, assets/ improve organization
3. **Respect root file whitelist** - Only config/meta files in root
4. **Document exceptions** - If framework requires non-standard structure
5. **Update .project.jsonl** - Track WoW compliance and version

### For Framework Users

1. **Check framework exceptions** - Your framework may allow root folders
2. **Don't fight conventions** - If Next.js needs app/ in root, allow it
3. **Document deviations** - Explain why you diverge from standard
4. **Use validation warnings** - Fix warnings when possible

---

## Troubleshooting

### Config not found

```bash
$ validate-paths
Error: WoW structure config not found

# Solution: Check config location
ls -la ~/Projects/wow-system/config/wow-structure-standard.json

# Or set override
export WOW_STRUCTURE_CONFIG="/path/to/config.json"
```

### Invalid JSON

```bash
$ jq empty ~/Projects/wow-system/config/wow-structure-standard.json
parse error: Invalid numeric literal at line 10, column 5

# Solution: Validate and fix JSON
jq . ~/Projects/wow-system/config/wow-structure-standard.json
```

### Version mismatch

```bash
$ migrate-project my-project
  Warning: Structure standard v2.0.0 (tool expects v1.0.0)

# Solution: Update tool or downgrade config
```

---

## Future Enhancements

### Planned for v1.1.0
- **Custom project templates** - Language-specific scaffolding
- **Auto-documentation generation** - Generate docs from config
- **Validation hooks** - Pre-commit validation
- **IDE integration** - Editor support for structure validation

### Planned for v2.0.0
- **Monorepo support** - Workspaces and package structures
- **Custom conventions** - Project-specific overrides
- **Dependency analysis** - Module coupling validation
- **Performance metrics** - Structure impact on build times

---

## References

- **Config file**: `~/Projects/wow-system/config/wow-structure-standard.json`
- **Version file**: `~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION`
- **CHANGELOG**: `~/Projects/wow-system/CHANGELOG.md`
- **wow-system README**: `~/Projects/wow-system/README.md`
- **ai-dev-environment**: `~/Projects/ai-dev-environment/`

---

## Contributing

To propose changes to the WoW Structure Standard:

1. Open issue in wow-system repository
2. Describe rationale for change
3. Provide examples from real projects
4. Consider backward compatibility
5. Update version and CHANGELOG

**Approval criteria:**
- Solves real-world problem
- Maintains simplicity
- Backward compatible (or justifies breaking change)
- Well-documented
- Tested across multiple project types

---

## License

MIT License - Same as wow-system

---

**Last updated:** 2025-11-02
**Maintained by:** Chude <chude@emeke.org>
