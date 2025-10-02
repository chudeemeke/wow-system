#!/bin/bash
# WoW System - File Storage Adapter
# Provides: Key-value storage with namespaces, atomic writes, and error handling
# Author: Chude <chude@emeke.org>

# Source utilities
_FILE_STORAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_FILE_STORAGE_DIR}/../core/utils.sh"

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly STORAGE_VERSION="1.0.0"
readonly STORAGE_ROOT="${WOW_DATA_DIR}/storage"
readonly STORAGE_METADATA_DIR="${STORAGE_ROOT}/.metadata"

# ============================================================================
# Initialization
# ============================================================================

# Initialize storage system
storage_init() {
    wow_debug "Initializing file storage adapter v${STORAGE_VERSION}"

    wow_ensure_dir "${STORAGE_ROOT}"
    wow_ensure_dir "${STORAGE_METADATA_DIR}"

    wow_success "Storage adapter initialized"
}

# ============================================================================
# Namespace Management
# ============================================================================

# Get namespace directory path
_storage_namespace_dir() {
    local namespace="$1"
    echo "${STORAGE_ROOT}/${namespace}"
}

# Create namespace if it doesn't exist
storage_namespace_create() {
    local namespace="$1"

    if [[ -z "${namespace}" ]]; then
        wow_error "Namespace cannot be empty"
        return 1
    fi

    # Validate namespace (alphanumeric, dash, underscore only)
    if [[ ! "${namespace}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        wow_error "Invalid namespace: ${namespace} (use only alphanumeric, dash, underscore)"
        return 1
    fi

    local namespace_dir
    namespace_dir=$(_storage_namespace_dir "${namespace}")

    wow_ensure_dir "${namespace_dir}"
    wow_debug "Namespace '${namespace}' created/verified"
}

# Check if namespace exists
storage_namespace_exists() {
    local namespace="$1"
    local namespace_dir
    namespace_dir=$(_storage_namespace_dir "${namespace}")

    [[ -d "${namespace_dir}" ]]
}

# List all namespaces
storage_namespace_list() {
    if [[ ! -d "${STORAGE_ROOT}" ]]; then
        return 0
    fi

    find "${STORAGE_ROOT}" -mindepth 1 -maxdepth 1 -type d ! -name ".*" -exec basename {} \;
}

# Delete namespace and all its data
storage_namespace_delete() {
    local namespace="$1"

    if ! storage_namespace_exists "${namespace}"; then
        wow_warn "Namespace does not exist: ${namespace}"
        return 0
    fi

    local namespace_dir
    namespace_dir=$(_storage_namespace_dir "${namespace}")

    rm -rf "${namespace_dir}"
    wow_info "Namespace '${namespace}' deleted"
}

# ============================================================================
# Key-Value Operations
# ============================================================================

# Get file path for a key
_storage_key_path() {
    local namespace="$1"
    local key="$2"

    # Encode key to handle special characters (simple base64-like encoding)
    local encoded_key
    encoded_key=$(echo -n "${key}" | xxd -p | tr -d '\n')

    local namespace_dir
    namespace_dir=$(_storage_namespace_dir "${namespace}")

    echo "${namespace_dir}/${encoded_key}.data"
}

# Set a value (create or update)
storage_set() {
    local namespace="$1"
    local key="$2"
    local value="$3"

    if [[ -z "${namespace}" ]] || [[ -z "${key}" ]]; then
        wow_error "Namespace and key are required"
        return 1
    fi

    # Ensure namespace exists
    storage_namespace_create "${namespace}"

    # Encode key
    local encoded_key
    encoded_key=$(echo -n "${key}" | xxd -p | tr -d '\n')

    local key_path
    key_path=$(_storage_key_path "${namespace}" "${key}")

    # Atomic write using temp file
    local temp_file="${key_path}.tmp.$$"

    echo "${value}" > "${temp_file}" || {
        rm -f "${temp_file}"
        wow_error "Failed to write value for key: ${namespace}:${key}"
        return 1
    }

    mv "${temp_file}" "${key_path}" || {
        rm -f "${temp_file}"
        wow_error "Failed to commit value for key: ${namespace}:${key}"
        return 1
    }

    # Update metadata (timestamp)
    local metadata_file="${STORAGE_METADATA_DIR}/${namespace}_${encoded_key}.meta"
    echo "updated=$(wow_timestamp)" > "${metadata_file}"

    wow_debug "Set ${namespace}:${key}"
    return 0
}

# Get a value
storage_get() {
    local namespace="$1"
    local key="$2"
    local default="${3:-}"

    if [[ -z "${namespace}" ]] || [[ -z "${key}" ]]; then
        wow_error "Namespace and key are required"
        return 1
    fi

    local key_path
    key_path=$(_storage_key_path "${namespace}" "${key}")

    if [[ ! -f "${key_path}" ]]; then
        if [[ -n "${default}" ]]; then
            echo "${default}"
            return 0
        else
            wow_debug "Key not found: ${namespace}:${key}"
            return 1
        fi
    fi

    cat "${key_path}"
}

# Check if key exists
storage_exists() {
    local namespace="$1"
    local key="$2"

    local key_path
    key_path=$(_storage_key_path "${namespace}" "${key}")

    [[ -f "${key_path}" ]]
}

# Delete a key
storage_delete() {
    local namespace="$1"
    local key="$2"

    if [[ -z "${namespace}" ]] || [[ -z "${key}" ]]; then
        wow_error "Namespace and key are required"
        return 1
    fi

    local key_path
    key_path=$(_storage_key_path "${namespace}" "${key}")

    if [[ ! -f "${key_path}" ]]; then
        wow_debug "Key not found (already deleted): ${namespace}:${key}"
        return 0
    fi

    rm -f "${key_path}"

    # Remove metadata
    local encoded_key
    encoded_key=$(echo -n "${key}" | xxd -p | tr -d '\n')
    local metadata_file="${STORAGE_METADATA_DIR}/${namespace}_${encoded_key}.meta"
    rm -f "${metadata_file}"

    wow_debug "Deleted ${namespace}:${key}"
    return 0
}

# List all keys in a namespace
storage_keys() {
    local namespace="$1"

    if ! storage_namespace_exists "${namespace}"; then
        return 0
    fi

    local namespace_dir
    namespace_dir=$(_storage_namespace_dir "${namespace}")

    # Find all .data files and decode their names
    find "${namespace_dir}" -maxdepth 1 -type f -name "*.data" | while read -r file; do
        local basename
        basename=$(basename "${file}" .data)

        # Decode hex back to original key
        echo -n "${basename}" | xxd -r -p
        echo ""
    done
}

# Count keys in namespace
storage_count() {
    local namespace="$1"

    if ! storage_namespace_exists "${namespace}"; then
        echo "0"
        return 0
    fi

    local namespace_dir
    namespace_dir=$(_storage_namespace_dir "${namespace}")

    find "${namespace_dir}" -maxdepth 1 -type f -name "*.data" | wc -l
}

# ============================================================================
# Batch Operations
# ============================================================================

# Set multiple values at once (atomic)
storage_set_batch() {
    local namespace="$1"
    shift
    local -a operations=("$@")

    # Operations format: "key=value" pairs
    for op in "${operations[@]}"; do
        local key="${op%%=*}"
        local value="${op#*=}"

        storage_set "${namespace}" "${key}" "${value}" || {
            wow_error "Batch operation failed at key: ${key}"
            return 1
        }
    done

    wow_debug "Batch set complete: ${#operations[@]} keys in ${namespace}"
}

# Get multiple values at once
storage_get_batch() {
    local namespace="$1"
    shift
    local -a keys=("$@")

    for key in "${keys[@]}"; do
        local value
        value=$(storage_get "${namespace}" "${key}" "")
        echo "${key}=${value}"
    done
}

# ============================================================================
# Maintenance Operations
# ============================================================================

# Get storage statistics
storage_stats() {
    echo "Storage Statistics"
    echo "=================="
    echo "Root: ${STORAGE_ROOT}"
    echo ""

    if [[ ! -d "${STORAGE_ROOT}" ]]; then
        echo "Storage not initialized"
        return 0
    fi

    local total_namespaces
    total_namespaces=$(storage_namespace_list | wc -l)
    echo "Namespaces: ${total_namespaces}"

    storage_namespace_list | while read -r ns; do
        local count
        count=$(storage_count "${ns}")
        echo "  - ${ns}: ${count} keys"
    done

    echo ""
    local total_size
    total_size=$(du -sh "${STORAGE_ROOT}" 2>/dev/null | cut -f1)
    echo "Total size: ${total_size}"
}

# Compact storage (remove old temp files, optimize)
storage_compact() {
    wow_info "Compacting storage..."

    # Remove any leftover temp files
    find "${STORAGE_ROOT}" -name "*.tmp.*" -type f -mtime +1 -delete 2>/dev/null || true

    # Remove empty namespaces
    find "${STORAGE_ROOT}" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true

    wow_success "Storage compacted"
}

# Backup storage to a tar.gz file
storage_backup() {
    local backup_path="$1"

    if [[ -z "${backup_path}" ]]; then
        backup_path="${WOW_HOME}/backups/storage-$(date +%Y%m%d-%H%M%S).tar.gz"
    fi

    local backup_dir
    backup_dir=$(dirname "${backup_path}")
    wow_ensure_dir "${backup_dir}"

    tar -czf "${backup_path}" -C "$(dirname "${STORAGE_ROOT}")" "$(basename "${STORAGE_ROOT}")" 2>/dev/null || {
        wow_error "Failed to create backup"
        return 1
    }

    wow_success "Backup created: ${backup_path}"
    echo "${backup_path}"
}

# Restore storage from backup
storage_restore() {
    local backup_path="$1"

    if [[ ! -f "${backup_path}" ]]; then
        wow_error "Backup file not found: ${backup_path}"
        return 1
    fi

    # Create backup of current storage first
    local safety_backup
    safety_backup=$(storage_backup "${WOW_HOME}/backups/pre-restore-$(date +%Y%m%d-%H%M%S).tar.gz")
    wow_info "Current storage backed up to: ${safety_backup}"

    # Clear existing storage
    rm -rf "${STORAGE_ROOT}"

    # Extract backup
    tar -xzf "${backup_path}" -C "$(dirname "${STORAGE_ROOT}")" 2>/dev/null || {
        wow_error "Failed to restore backup"
        # Attempt to restore safety backup
        tar -xzf "${safety_backup}" -C "$(dirname "${STORAGE_ROOT}")" 2>/dev/null
        return 1
    }

    wow_success "Storage restored from: ${backup_path}"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW File Storage v${STORAGE_VERSION} - Self Test"
    echo "================================================"
    echo ""

    # Initialize
    storage_init

    # Test namespace operations
    echo "Testing namespaces..."
    storage_namespace_create "test"
    storage_namespace_exists "test" && echo "✓ Namespace creation works"

    # Test key-value operations
    echo ""
    echo "Testing key-value operations..."
    storage_set "test" "name" "WoW System"
    [[ "$(storage_get "test" "name")" == "WoW System" ]] && echo "✓ Set/Get works"

    storage_set "test" "version" "4.1.0"
    storage_exists "test" "version" && echo "✓ Exists check works"

    # Test default value
    default_value=$(storage_get "test" "nonexistent" "default")
    [[ "${default_value}" == "default" ]] && echo "✓ Default value works"

    # Test deletion
    storage_delete "test" "version"
    ! storage_exists "test" "version" && echo "✓ Delete works"

    # Test batch operations
    echo ""
    echo "Testing batch operations..."
    storage_set_batch "test" "key1=value1" "key2=value2" "key3=value3"
    [[ "$(storage_count "test")" == "4" ]] && echo "✓ Batch set works (4 keys total)"

    # Test listing keys
    echo ""
    echo "Keys in 'test' namespace:"
    storage_keys "test"

    # Statistics
    echo ""
    storage_stats

    # Cleanup
    echo ""
    echo "Cleaning up test data..."
    storage_namespace_delete "test"

    echo ""
    echo "All tests passed! ✓"
fi
