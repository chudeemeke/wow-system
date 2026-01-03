# For Future Claude Instances

**Purpose:** Guide for AI assistants working with the WoW Structure Standard
**Audience:** Claude Code, GitHub Copilot, or any AI coding assistant
**Last Updated:** 2025-11-02

---

## Quick Context

You're working with the **WoW (World of Wisdom) System**, specifically the **Structure Standard** module. This is the **Single Source of Truth** for project folder organization across all development projects.

**Key principle:** NEVER hardcode structure rules. ALWAYS source from the config file.

---

## File Locations

### Primary Config (SSOT)
```
~/Projects/wow-system/config/wow-structure-standard.json
```
**This is THE authoritative source**. All tools should read from here.

### Version File
```
~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION
```
Current version: `1.0.0`

### Documentation
```
~/Projects/wow-system/docs/STRUCTURE_STANDARD.md
```
Complete usage guide and API reference.

---

## What This Config Defines

### 1. Required Folders (MUST exist)
- `src/` - Source code
- `docs/` - Documentation
- `tests/` - Test files

### 2. Recommended Folders (SHOULD exist)
- `scripts/` - Build and deployment scripts
- `config/` - Environment configurations
- `assets/` - Static files (images, fonts, etc.)

### 3. Optional Folders (MAY exist)
- `public/` - Web server static files
- `build/` - Build output (gitignored)
- `dist/` - Distribution files (gitignored)
- `lib/` - Library output

### 4. Root File Whitelist
Only these categories allowed in project root:
- Package management (package.json, requirements.txt, etc.)
- Build configs (vite.config.js, webpack.config.js, etc.)
- Framework configs (next.config.js, etc.)
- Linting/formatting (.eslintrc.js, .prettierrc, etc.)
- Testing (jest.config.js, etc.)
- Deployment (Dockerfile, etc.)
- Documentation (README.md, LICENSE, etc.)
- Project meta (.project.jsonl, CLAUDE.md, etc.)

### 5. Framework Exceptions
Special rules for:
- Next.js (allows `app/`, `pages/` in root)
- Python (allows `venv/`, `.venv/` in root)
- Rust (allows `target/` in root)
- Go (allows `go.mod`, `go.sum` in root)
- Node.js (allows `node_modules/`, `dist/` in root)

### 6. Migration Rules
How to classify files for migration:
1. Whitelisted → root
2. Security files → NEVER move
3. Config files → root
4. Test files → tests/
5. Scripts → scripts/
6. Docs → docs/
7. Source → src/
8. Assets → assets/

### 7. Validation Levels
- **Error**: Source files in root, missing required folders
- **Warning**: Scripts/docs in root, missing recommended folders
- **Info**: Missing optional folders

---

## How to Use This Config

### Method 1: Direct jq Queries (Quick)

```bash
# Get required folders
jq -r '.structure.folders.required | keys[]' ~/Projects/wow-system/config/wow-structure-standard.json

# Get allowed root files
jq -r '.structure.root_files.allowed_by_category | to_entries[] | .value.files[]' ~/Projects/wow-system/config/wow-structure-standard.json

# Check framework exceptions
jq -r '.framework_exceptions.nextjs.allowed_root_folders[]' ~/Projects/wow-system/config/wow-structure-standard.json
```

### Method 2: Load via Config Loader (Recommended)

```bash
# Source the wow-system config loader
source ~/Projects/wow-system/src/core/config-loader.sh

# Load structure config
config_load ~/Projects/wow-system/config/wow-structure-standard.json

# Get value
config_get "structure.folders.required.src.purpose"
# Returns: "Source code and primary application logic"
```

### Method 3: Use ai-dev-environment Helper (Best for Tools)

```bash
# ai-dev-environment provides a wrapper
source ~/Projects/ai-dev-environment/lib/wow-config-loader.sh

wow_load_structure_config
wow_get_required_folders
wow_validate_structure "$PROJECT_PATH"
```

---

## When to Update This Config

###  DO Update When:
1. **New framework convention** discovered (e.g., SvelteKit needs `routes/` in root)
2. **New file type** becomes standard (e.g., `.astro` files)
3. **Validation rules** need adjustment based on real-world feedback
4. **Security patterns** identified (new file types that shouldn't be moved)

###  DON'T Update For:
1. **Project-specific preferences** - Use `.project.jsonl` for overrides
2. **Temporary exceptions** - Document in project CLAUDE.md instead
3. **Experimental features** - Wait until widely adopted
4. **Personal preferences** - The standard serves all projects

---

## Update Process (IMPORTANT)

If you need to modify the structure standard:

### 1. Validate the Change

```bash
# Test the updated JSON is valid
jq empty ~/Projects/wow-system/config/wow-structure-standard.json

# Verify no breaking changes
diff <(jq -S '.' old-version.json) <(jq -S '.' new-version.json)
```

### 2. Update Version Files

```bash
# If backward compatible (minor change)
echo "1.1.0" > ~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION

# If breaking change (major change)
echo "2.0.0" > ~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION

# Update version in JSON
jq '.version = "1.1.0"' config/wow-structure-standard.json > tmp && mv tmp config/wow-structure-standard.json
```

### 3. Update CHANGELOG

```bash
# Add entry to ~/Projects/wow-system/CHANGELOG.md
## [Unreleased]

### Changed - Structure Standard v1.1.0
- **Framework Exceptions**: Added SvelteKit support
  - Allowed root folders: `routes/`, `lib/`, `static/`
  - Rationale: SvelteKit convention from official documentation
```

### 4. Update Documentation

Update `~/Projects/wow-system/docs/STRUCTURE_STANDARD.md` with:
- New examples
- New framework exceptions
- Migration guide if breaking change

### 5. Test Impact

```bash
# Test validation still works
cd ~/Projects/ai-dev-environment
bash scripts/validate-paths.sh --check

# Test migration still works
bash scripts/migrate-project.sh test-project --dry-run
```

### 6. Commit Changes

```bash
cd ~/Projects/wow-system
git add config/wow-structure-standard.json config/STRUCTURE_STANDARD_VERSION docs/STRUCTURE_STANDARD.md CHANGELOG.md
git commit -m "feat(structure): add SvelteKit framework exceptions

- Add routes/, lib/, static/ as allowed root folders
- Update validation to recognize .svelte files
- Version: 1.0.0 → 1.1.0

Rationale: SvelteKit uses unconventional structure by design
Reference: https://kit.svelte.dev/docs/project-structure"
```

---

## Common Tasks

### Task 1: Add New Framework Exception

```json
// In wow-structure-standard.json
"framework_exceptions": {
  "sveltekit": {
    "description": "SvelteKit project structure",
    "allowed_root_folders": ["routes", "lib", "static"],
    "allowed_root_files": ["svelte.config.js"],
    "notes": "SvelteKit uses routes/ in root by convention"
  }
}
```

### Task 2: Add New File Extension

```json
// In structure.folders.required.src
"allowed_patterns": [
  "*.js", "*.jsx", "*.ts", "*.tsx",
  "*.py", "*.go", "*.rs",
  "*.svelte", // ADD HERE
  "*.astro"
]
```

### Task 3: Update Validation Rule

```json
// In validation.severity_levels.error
"error": {
  "violations": [
    "source_files_in_root",
    "missing_required_folders",
    "credentials_in_version_control" // ADD NEW RULE
  ]
}
```

---

## Integration Points

### Tools That Use This Config

1. **validate-paths.sh** (ai-dev-environment)
   - Validates project structures
   - Checks against whitelist
   - Reports violations

2. **migrate-project.sh** (ai-dev-environment)
   - Migrates projects to WoW standard
   - Uses classification rules
   - Respects framework exceptions

3. **add-go-alias** (ai-dev-environment)
   - Creates new projects
   - Auto-generates WoW structure
   - Updates .project.jsonl

4. **discover-projects.sh** (ai-dev-environment)
   - Analyzes project compliance
   - Detects framework types
   - Suggests migrations

### Future Integrations

- **Pre-commit hooks** - Block commits with violations
- **CI/CD pipelines** - Validate structure in automation
- **IDE extensions** - Real-time structure validation
- **Project scaffolding** - Template generation

---

## Troubleshooting Guide

### Problem: Config not loading

```bash
# Check file exists
ls -la ~/Projects/wow-system/config/wow-structure-standard.json

# Check valid JSON
jq empty ~/Projects/wow-system/config/wow-structure-standard.json

# Check jq installed
command -v jq || echo "jq not installed"
```

### Problem: Wrong values returned

```bash
# Check config version
jq -r '.version' ~/Projects/wow-system/config/wow-structure-standard.json

# Check structure standard version
cat ~/Projects/wow-system/config/STRUCTURE_STANDARD_VERSION

# Reload config (clear cache)
unset _WOW_CONFIG
source ~/Projects/ai-dev-environment/lib/wow-config-loader.sh
```

### Problem: Framework exception not working

```bash
# Check framework is defined
jq -r '.framework_exceptions | keys[]' ~/Projects/wow-system/config/wow-structure-standard.json

# Check specific exception
jq -r '.framework_exceptions.nextjs' ~/Projects/wow-system/config/wow-structure-standard.json
```

---

## Design Principles (Critical to Understand)

### 1. Single Source of Truth (SSOT)
**Never duplicate structure rules.** Always source from config.

 **Wrong:**
```bash
# Hardcoded in script
REQUIRED_FOLDERS=("src" "docs" "tests")
```

 **Correct:**
```bash
# Load from config
REQUIRED_FOLDERS=$(jq -r '.structure.folders.required | keys[]' "$WOW_CONFIG")
```

### 2. Graceful Degradation
**Always provide fallback.** Don't fail if config missing.

 **Correct:**
```bash
if [ -f "$WOW_CONFIG" ] && command -v jq &> /dev/null; then
    # Load from config
    REQUIRED=$(jq -r '...' "$WOW_CONFIG")
else
    # Embedded fallback
    REQUIRED=("src" "docs" "tests")
    echo "  Using embedded defaults (config not found)"
fi
```

### 3. Version Compatibility
**Check versions match.** Warn on mismatch.

 **Correct:**
```bash
CONFIG_VERSION=$(jq -r '.version' "$WOW_CONFIG")
TOOL_VERSION="1.0.0"

if [ "$CONFIG_VERSION" != "$TOOL_VERSION" ]; then
    echo "  Version mismatch: config v$CONFIG_VERSION, tool expects v$TOOL_VERSION"
fi
```

### 4. Extensibility
**Framework exceptions, not hardcoded special cases.**

 **Wrong:**
```bash
if [ "$FRAMEWORK" = "nextjs" ]; then
    # Allow app/ folder
fi
```

 **Correct:**
```bash
ALLOWED_FOLDERS=$(jq -r ".framework_exceptions.${FRAMEWORK}.allowed_root_folders[]" "$WOW_CONFIG")
```

---

## Critical Files (Don't Delete!)

```
~/Projects/wow-system/
├── config/
│   ├── wow-structure-standard.json    # THE source of truth
│   └── STRUCTURE_STANDARD_VERSION     # Version tracking
├── docs/
│   ├── STRUCTURE_STANDARD.md          # Complete documentation
│   └── FOR_FUTURE_CLAUDE.md          # This file (your guide)
└── CHANGELOG.md                        # Version history
```

---

## Questions to Ask Yourself

Before making changes:

1. **Is this a framework convention or personal preference?**
   - Framework convention → Add to config
   - Personal preference → Don't add to standard

2. **Is this widely adopted or experimental?**
   - Widely adopted (Next.js, React) → Add
   - Experimental → Wait

3. **Does this break backward compatibility?**
   - Yes → Major version bump
   - No → Minor version bump

4. **Have I tested against real projects?**
   - Yes → Proceed
   - No → Test first

5. **Have I documented the rationale?**
   - Yes → Good
   - No → Add to comments or docs

---

## Getting Help

If you're unsure about a change:

1. **Read existing patterns** - Check similar frameworks
2. **Check CHANGELOG** - See how past changes were made
3. **Test extensively** - Run against 5-10 real projects
4. **Document rationale** - Explain WHY in commit message

---

## Success Criteria

You've successfully worked with the structure standard if:

 No hardcoded structure rules in tools
 All tools source from config file
 Framework exceptions properly defined
 Version tracked and documented
 CHANGELOG updated
 Tests pass
 Documentation updated

---

**Remember:** This config affects every project. Changes should be well-reasoned, tested, and documented. When in doubt, be conservative.

**Good luck!** 

---

**Maintained by:** Chude <chude@emeke.org>
**Last updated:** 2025-11-02
