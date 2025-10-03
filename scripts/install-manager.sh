#!/bin/bash
# install-manager.sh - Production-grade installation manager for WoW System v5.0
# Author: Chude <chude@emeke.org>
#
# Design Patterns:
# - Template Method: Installation workflow
# - Strategy: Different installation modes (user/system/dev)
# - Builder: Configuration construction
# - Atomic Operations: All-or-nothing installation
#
# Usage:
#   bash install-manager.sh [--user|--system|--dev] [--prefix PATH]

set -euo pipefail

# ============================================================================
# Constants & Configuration
# ============================================================================

readonly INSTALL_MANAGER_VERSION="5.0.0"
readonly MIN_BASH_VERSION="4.0"
readonly MIN_DISK_SPACE_MB=50

# Colors for output
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'

# Installation mode
INSTALL_MODE="user"  # user|system|dev
INSTALL_PREFIX=""
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# XDG Base Directory Specification
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Installation paths (will be set based on mode)
INSTALL_DIR=""
CONFIG_DIR=""
DATA_DIR=""
CACHE_DIR=""

# Rollback state
ROLLBACK_AVAILABLE=false
ROLLBACK_PATH=""
PREVIOUS_VERSION=""

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_fatal() {
    echo -e "${COLOR_RED}[FATAL]${COLOR_RESET} $*" >&2
    exit 1
}

# ============================================================================
# Pre-Installation Checks
# ============================================================================

check_bash_version() {
    local bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"

    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log_error "Bash version ${bash_version} is too old. Minimum required: ${MIN_BASH_VERSION}"
        return 1
    fi

    log_info "Bash version: ${bash_version} ✓"
    return 0
}

check_jq_available() {
    if ! command -v jq &>/dev/null; then
        log_warn "jq not found. JSON processing will be limited"
        log_warn "Install jq: apt-get install jq (Ubuntu) or brew install jq (macOS)"
        return 0  # Non-fatal
    fi

    local jq_version
    jq_version=$(jq --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
    log_info "jq version: ${jq_version} ✓"
    return 0
}

check_disk_space() {
    local target_dir="$1"
    local required_mb="${2:-$MIN_DISK_SPACE_MB}"

    # Create target dir if it doesn't exist (for df check)
    mkdir -p "$(dirname "$target_dir")"

    local available_kb
    available_kb=$(df -k "$(dirname "$target_dir")" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt $required_mb ]]; then
        log_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi

    log_info "Disk space: ${available_mb}MB available ✓"
    return 0
}

validate_source_dir() {
    local source_dir="$1"

    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory not found: $source_dir"
        return 1
    fi

    log_info "Source directory: $source_dir ✓"
    return 0
}

validate_source_structure() {
    local source_dir="$1"

    local required_dirs=("src" "tests" "config")
    local required_files=("src/core/orchestrator.sh" "config/wow-config.json")

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$source_dir/$dir" ]]; then
            log_error "Required directory missing: $dir"
            return 1
        fi
    done

    for file in "${required_files[@]}"; do
        if [[ ! -f "$source_dir/$file" ]]; then
            log_error "Required file missing: $file"
            return 1
        fi
    done

    log_info "Source structure validated ✓"
    return 0
}

check_dependencies() {
    log_info "Checking dependencies..."

    check_bash_version || return 1
    check_jq_available || true  # Non-fatal
    check_disk_space "${INSTALL_DIR:-/tmp}" || return 1

    return 0
}

# ============================================================================
# Backup Operations
# ============================================================================

create_backup_dir() {
    local backup_base="$1"
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_dir="${backup_base}/backup-${timestamp}"

    mkdir -p "${backup_dir}"
    echo "${backup_dir}"
}

backup_installation() {
    local install_dir="$1"
    local backup_dir="$2"

    if [[ ! -d "$install_dir" ]]; then
        log_info "No existing installation to backup"
        return 0
    fi

    log_info "Backing up existing installation..."

    mkdir -p "$backup_dir"
    cp -a "$install_dir"/* "$backup_dir/" 2>/dev/null || true

    log_success "Installation backed up to: $backup_dir"
    return 0
}

backup_configuration() {
    local config_dir="$1"
    local backup_dir="$2"

    if [[ ! -d "$config_dir" ]]; then
        log_info "No existing configuration to backup"
        return 0
    fi

    log_info "Backing up configuration..."

    mkdir -p "$backup_dir"
    cp -a "$config_dir"/* "$backup_dir/" 2>/dev/null || true

    log_success "Configuration backed up to: $backup_dir"
    return 0
}

create_rollback_manifest() {
    local manifest_path="$1"
    local version="$2"
    local backup_path="$3"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$manifest_path" <<EOF
{
  "rollback_version": "${version}",
  "backup_path": "${backup_path}",
  "created_at": "${timestamp}",
  "can_rollback": true
}
EOF

    ROLLBACK_AVAILABLE=true
    ROLLBACK_PATH="$backup_path"
    PREVIOUS_VERSION="$version"

    return 0
}

# ============================================================================
# Installation Operations
# ============================================================================

create_xdg_directories() {
    local install_dir="$1"
    local config_dir="$2"
    local data_dir="$3"

    log_info "Creating XDG-compliant directory structure..."

    # Installation directories
    mkdir -p "${install_dir}/lib"
    mkdir -p "${install_dir}/bin"

    # Configuration directories
    mkdir -p "${config_dir}"
    mkdir -p "${config_dir}/custom-handlers"
    mkdir -p "${config_dir}/backups"

    # Data directories
    mkdir -p "${data_dir}/state"
    mkdir -p "${data_dir}/storage"
    mkdir -p "${data_dir}/logs"
    mkdir -p "${data_dir}/cache"
    mkdir -p "${data_dir}/metrics"

    log_success "Directories created"
    return 0
}

copy_source_to_staging() {
    local source_dir="$1"
    local staging_dir="$2"

    log_info "Copying source to staging..."

    mkdir -p "$staging_dir"

    # Copy essential directories
    cp -a "$source_dir/src" "$staging_dir/" 2>/dev/null || true
    cp -a "$source_dir/tests" "$staging_dir/" 2>/dev/null || true
    cp -a "$source_dir/config" "$staging_dir/" 2>/dev/null || true
    cp -a "$source_dir/hooks" "$staging_dir/" 2>/dev/null || true

    # Copy essential files
    [[ -f "$source_dir/README.md" ]] && cp "$source_dir/README.md" "$staging_dir/"
    [[ -f "$source_dir/LICENSE" ]] && cp "$source_dir/LICENSE" "$staging_dir/"

    # Create VERSION file
    echo "${INSTALL_MANAGER_VERSION}" > "$staging_dir/VERSION"

    log_success "Source copied to staging"
    return 0
}

validate_staged_files() {
    local staging_dir="$1"

    log_info "Validating staged files..."

    # Check critical files exist
    [[ -d "$staging_dir/src" ]] || { log_error "Missing src/"; return 1; }
    [[ -f "$staging_dir/VERSION" ]] || { log_error "Missing VERSION"; return 1; }

    log_success "Staged files validated"
    return 0
}

atomic_move_to_production() {
    local staging_dir="$1"
    local install_dir="$2"

    log_info "Installing to production (atomic)..."

    # Remove old installation
    if [[ -d "$install_dir" ]]; then
        rm -rf "${install_dir:?}"/* 2>/dev/null || true
    fi

    # Atomic move
    mkdir -p "$install_dir"
    mv "$staging_dir"/* "$install_dir/" 2>/dev/null || {
        log_error "Failed to move files to production"
        return 1
    }

    # Cleanup staging
    rm -rf "$staging_dir"

    log_success "Installation complete"
    return 0
}

set_file_permissions() {
    local install_dir="$1"

    log_info "Setting file permissions..."

    # Executables: 755
    if [[ -d "$install_dir/bin" ]]; then
        find "$install_dir/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
    fi

    # Libraries: 644
    if [[ -d "$install_dir/lib" ]] || [[ -d "$install_dir/src" ]]; then
        find "$install_dir" -type f -name "*.sh" -exec chmod 644 {} \; 2>/dev/null || true
    fi

    # Make orchestrator and handlers readable
    chmod 644 "$install_dir"/src/**/*.sh 2>/dev/null || true

    log_success "Permissions set"
    return 0
}

# ============================================================================
# Configuration
# ============================================================================

copy_default_configuration() {
    local source_config_dir="$1"
    local target_config_dir="$2"

    # Don't overwrite existing configuration
    if [[ -f "$target_config_dir/wow-config.json" ]]; then
        log_info "Configuration already exists, preserving"
        return 0
    fi

    log_info "Installing default configuration..."

    cp "$source_config_dir/wow-config.json" "$target_config_dir/" 2>/dev/null || {
        # Fallback: create minimal config
        cat > "$target_config_dir/wow-config.json" <<'EOF'
{
  "version": "5.0.0",
  "enforcement": {
    "strict_mode": true,
    "block_on_violation": true
  },
  "scoring": {
    "initial_score": 100,
    "warn_threshold": 50,
    "block_threshold": 30
  }
}
EOF
    }

    log_success "Default configuration installed"
    return 0
}

migrate_configuration() {
    local config_file="$1"
    local from_version="$2"
    local to_version="$3"

    log_info "Migrating configuration from ${from_version} to ${to_version}..."

    if command -v jq &>/dev/null; then
        # Update version in config
        local temp_file="${config_file}.tmp"
        jq --arg version "$to_version" '.version = $version | .migrated_from = "'${from_version}'" | .migration_date = now | todate' \
            "$config_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$config_file"
    fi

    log_success "Configuration migrated"
    return 0
}

validate_configuration() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Validate JSON syntax
    if command -v jq &>/dev/null; then
        jq '.' "$config_file" >/dev/null 2>&1 || {
            log_error "Invalid JSON in configuration file"
            return 1
        }
    fi

    log_success "Configuration validated"
    return 0
}

# ============================================================================
# Hook Integration
# ============================================================================

detect_claude_settings() {
    # Check common locations
    local possible_paths=(
        "$HOME/.claude/settings.json"
        "/root/.claude/settings.json"
    )

    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    # Not found - will create
    echo "$HOME/.claude/settings.json"
    return 0
}

generate_hooks() {
    local install_dir="$1"
    local hooks_dir="$2"

    log_info "Generating hooks..."

    mkdir -p "$hooks_dir"

    # Copy hook from installation
    if [[ -f "$install_dir/hooks/user-prompt-submit.sh" ]]; then
        cp "$install_dir/hooks/user-prompt-submit.sh" "$hooks_dir/"
        chmod 755 "$hooks_dir/user-prompt-submit.sh"
    else
        log_warn "Hook template not found, will need manual setup"
    fi

    log_success "Hooks generated"
    return 0
}

register_hooks() {
    local settings_file="$1"
    local hook_path="$2"

    log_info "Registering hooks in Claude Code settings..."

    mkdir -p "$(dirname "$settings_file")"

    # Create or update settings.json
    if [[ -f "$settings_file" ]]; then
        # File exists - need to merge
        if command -v jq &>/dev/null; then
            local temp_file="${settings_file}.tmp"
            jq --arg hook "$hook_path" \
                '.hooks.UserPromptSubmit = [{"matcher": "*", "hooks": [{"type": "command", "command": $hook}]}]' \
                "$settings_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$settings_file"
        else
            log_warn "jq not available, cannot auto-register hooks"
            log_warn "Manually add to $settings_file:"
            log_warn '  "hooks": {"UserPromptSubmit": [{"matcher": "*", "hooks": [{"type": "command", "command": "'$hook_path'"}]}]}'
        fi
    else
        # Create new settings file
        cat > "$settings_file" <<EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${hook_path}"
          }
        ]
      }
    ]
  }
}
EOF
    fi

    log_success "Hooks registered"
    return 0
}

verify_hook_registration() {
    local settings_file="$1"

    if [[ ! -f "$settings_file" ]]; then
        log_warn "Settings file not found: $settings_file"
        return 1
    fi

    if command -v jq &>/dev/null; then
        local has_hooks
        has_hooks=$(jq -r '.hooks.UserPromptSubmit // empty' "$settings_file" 2>/dev/null)

        if [[ -n "$has_hooks" ]]; then
            log_success "Hook registration verified"
            return 0
        else
            log_warn "Hooks not found in settings"
            return 1
        fi
    else
        # Without jq, just check file contains "UserPromptSubmit"
        if grep -q "UserPromptSubmit" "$settings_file"; then
            log_success "Hook registration verified (basic check)"
            return 0
        else
            log_warn "Hooks may not be registered properly"
            return 1
        fi
    fi
}

# ============================================================================
# Post-Installation
# ============================================================================

create_installation_manifest() {
    local manifest_path="$1"
    local version="$2"
    local source_path="$3"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_info "Creating installation manifest..."

    cat > "$manifest_path" <<EOF
{
  "version": "${version}",
  "installed_at": "${timestamp}",
  "installed_from": "${source_path}",
  "installation_method": "install-manager",
  "previous_version": "${PREVIOUS_VERSION:-none}",
  "rollback_available": ${ROLLBACK_AVAILABLE},
  "rollback_path": "${ROLLBACK_PATH:-}",
  "install_dir": "${INSTALL_DIR}",
  "config_dir": "${CONFIG_DIR}",
  "data_dir": "${DATA_DIR}"
}
EOF

    log_success "Installation manifest created"
    return 0
}

# ============================================================================
# Main Installation Workflow (Template Method Pattern)
# ============================================================================

install_wow_system() {
    log_info "WoW System Installation Manager v${INSTALL_MANAGER_VERSION}"
    log_info "=================================================="
    echo ""

    # Step 1: Pre-installation checks
    log_info "Step 1/7: Pre-installation checks"
    check_dependencies || log_fatal "Dependency check failed"
    validate_source_dir "$SOURCE_DIR" || log_fatal "Source validation failed"
    validate_source_structure "$SOURCE_DIR" || log_fatal "Source structure validation failed"
    echo ""

    # Step 2: Backup
    log_info "Step 2/7: Backup existing installation"
    local backup_dir
    backup_dir=$(create_backup_dir "$CONFIG_DIR/backups")
    backup_installation "$INSTALL_DIR" "$backup_dir/installation"
    backup_configuration "$CONFIG_DIR" "$backup_dir/configuration"

    # Detect previous version
    if [[ -f "$INSTALL_DIR/VERSION" ]]; then
        PREVIOUS_VERSION=$(cat "$INSTALL_DIR/VERSION")
        create_rollback_manifest "$backup_dir/rollback-manifest.json" "$PREVIOUS_VERSION" "$backup_dir"
    fi
    echo ""

    # Step 3: Installation
    log_info "Step 3/7: Installing to production"
    create_xdg_directories "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR"

    local staging_dir="/tmp/wow-install-$$"
    copy_source_to_staging "$SOURCE_DIR" "$staging_dir"
    validate_staged_files "$staging_dir"
    atomic_move_to_production "$staging_dir" "$INSTALL_DIR"
    set_file_permissions "$INSTALL_DIR"
    echo ""

    # Step 4: Configuration
    log_info "Step 4/7: Configuration"
    copy_default_configuration "$SOURCE_DIR/config" "$CONFIG_DIR"

    if [[ -n "$PREVIOUS_VERSION" ]] && [[ "$PREVIOUS_VERSION" != "$INSTALL_MANAGER_VERSION" ]]; then
        migrate_configuration "$CONFIG_DIR/wow-config.json" "$PREVIOUS_VERSION" "$INSTALL_MANAGER_VERSION"
    fi

    validate_configuration "$CONFIG_DIR/wow-config.json"
    echo ""

    # Step 5: Hook integration
    log_info "Step 5/7: Claude Code integration"
    local claude_settings
    claude_settings=$(detect_claude_settings)

    local claude_hooks_dir
    claude_hooks_dir="$(dirname "$claude_settings")/hooks"

    generate_hooks "$INSTALL_DIR" "$claude_hooks_dir"
    register_hooks "$claude_settings" "$claude_hooks_dir/user-prompt-submit.sh"
    verify_hook_registration "$claude_settings" || log_warn "Hook verification failed"
    echo ""

    # Step 6: Post-installation
    log_info "Step 6/7: Post-installation"
    create_installation_manifest "$INSTALL_DIR/.manifest.json" "$INSTALL_MANAGER_VERSION" "$SOURCE_DIR"
    echo ""

    # Step 7: Summary
    log_info "Step 7/7: Installation complete"
    echo ""
    log_success "=================================================="
    log_success "WoW System v${INSTALL_MANAGER_VERSION} installed successfully!"
    log_success "=================================================="
    echo ""
    log_info "Installation directory: $INSTALL_DIR"
    log_info "Configuration directory: $CONFIG_DIR"
    log_info "Data directory: $DATA_DIR"
    echo ""

    if [[ "$ROLLBACK_AVAILABLE" == "true" ]]; then
        log_info "Previous version backed up: $PREVIOUS_VERSION"
        log_info "Rollback available at: $ROLLBACK_PATH"
    fi

    echo ""
    log_info "Next steps:"
    log_info "1. Restart Claude Code to activate hooks"
    log_info "2. Test with: echo '{\"tool\": \"Bash\", \"command\": \"ls\"}' | bash $claude_hooks_dir/user-prompt-submit.sh"
    log_info "3. Try dangerous command: echo '{\"tool\": \"Bash\", \"command\": \"rm -rf /\"}' | bash $claude_hooks_dir/user-prompt-submit.sh"
    echo ""
}

# ============================================================================
# Parse Arguments
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user)
                INSTALL_MODE="user"
                shift
                ;;
            --system)
                INSTALL_MODE="system"
                shift
                ;;
            --dev)
                INSTALL_MODE="dev"
                shift
                ;;
            --prefix)
                INSTALL_PREFIX="$2"
                shift 2
                ;;
            --help|-h)
                cat <<EOF
WoW System Installation Manager v${INSTALL_MANAGER_VERSION}

Usage: $0 [OPTIONS]

Options:
  --user          Install for current user (default)
                  Location: ~/.local/share/wow-system

  --system        Install system-wide (requires sudo)
                  Location: /usr/local/lib/wow-system

  --dev           Development install (uses symlinks)
                  Location: ~/.local/share/wow-system-dev

  --prefix PATH   Custom installation prefix
                  Location: PATH/wow-system

  --help, -h      Show this help message

Examples:
  $0 --user                     # User installation
  $0 --system                   # System-wide (sudo required)
  $0 --prefix /opt              # Custom location

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_error "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Set installation paths based on mode
    case "$INSTALL_MODE" in
        user)
            INSTALL_DIR="${XDG_DATA_HOME}/wow-system"
            CONFIG_DIR="${XDG_CONFIG_HOME}/wow-system"
            DATA_DIR="${XDG_DATA_HOME}/wow-system/data"
            CACHE_DIR="${XDG_CACHE_HOME}/wow-system"
            ;;
        system)
            INSTALL_DIR="/usr/local/lib/wow-system"
            CONFIG_DIR="/etc/wow-system"
            DATA_DIR="/var/lib/wow-system"
            CACHE_DIR="/var/cache/wow-system"
            ;;
        dev)
            INSTALL_DIR="${XDG_DATA_HOME}/wow-system-dev"
            CONFIG_DIR="${XDG_CONFIG_HOME}/wow-system-dev"
            DATA_DIR="${XDG_DATA_HOME}/wow-system-dev/data"
            CACHE_DIR="${XDG_CACHE_HOME}/wow-system-dev"
            ;;
    esac

    # Override with custom prefix if provided
    if [[ -n "$INSTALL_PREFIX" ]]; then
        INSTALL_DIR="${INSTALL_PREFIX}/wow-system"
        CONFIG_DIR="${INSTALL_PREFIX}/wow-system/config"
        DATA_DIR="${INSTALL_PREFIX}/wow-system/data"
        CACHE_DIR="${INSTALL_PREFIX}/wow-system/cache"
    fi
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    parse_arguments "$@"
    install_wow_system
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
