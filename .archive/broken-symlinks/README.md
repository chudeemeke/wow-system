# Broken Symlinks from AI-Dev-Environment

These files were symlinks in the AI-Dev-Environment project that pointed to the now-deleted `/mnt/c/Users/Destiny/.claude/wow-system/` directory.

They are preserved here for reference to understand the v4.0.2 architecture.

## Original Symlink Structure

All 19 files were symlinks pointing to:
`../wow-system/<subdirectory>/<filename>`

Where subdirectories were:
- `core/` - Core system files
- `handlers/` - Tool interception handlers
- `hooks/` - Hook implementations
- `strategies/` - Intelligence and scoring
- `storage/` - Persistence layer
- `ui/` - User interface components

See individual `.target` files for exact paths.
