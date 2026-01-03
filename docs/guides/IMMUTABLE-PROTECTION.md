# Immutable File Protection for WoW System

This guide explains how to use Linux's immutable file attribute to protect WoW's hook from being disabled by AI or accidental modification.

## Why This Matters

The WoW security hook can be bypassed if the hook file itself is moved, renamed, or deleted:

```bash
# Without protection, AI could do this:
mv ~/.claude/hooks/user-prompt-submit.sh ~/.claude/hooks/user-prompt-submit.sh.bak
# Now ALL WoW protection is disabled
```

The immutable attribute prevents this at the OS level.

## Quick Setup

```bash
# Protect the hook (requires sudo)
sudo chattr +i ~/.claude/hooks/user-prompt-submit.sh

# Verify protection
lsattr ~/.claude/hooks/user-prompt-submit.sh
# Output: ----i--------e-- /root/.claude/hooks/user-prompt-submit.sh
#              ^ immutable flag
```

## What Gets Protected

Once immutable, the file CANNOT be:
- Deleted (`rm`)
- Renamed (`mv`)
- Modified (`echo >> file`)
- Overwritten (`cp newfile oldfile`)
- Truncated

Even root cannot modify it without first removing the flag.

## Updating WoW

When you need to legitimately update the hook:

```bash
# 1. Remove immutable flag
sudo chattr -i ~/.claude/hooks/user-prompt-submit.sh

# 2. Make your changes (update WoW, etc.)
# ... do updates ...

# 3. Re-protect
sudo chattr +i ~/.claude/hooks/user-prompt-submit.sh
```

## Helper Commands

Add these to your `.bashrc` or `.zshrc` for convenience:

```bash
# Unlock WoW hook for updates
wow-unlock() {
    sudo chattr -i ~/.claude/hooks/user-prompt-submit.sh
    echo "WoW hook unlocked for editing"
}

# Lock WoW hook after updates
wow-lock() {
    sudo chattr +i ~/.claude/hooks/user-prompt-submit.sh
    echo "WoW hook locked (immutable)"
}

# Check WoW hook protection status
wow-lock-status() {
    local attrs=$(lsattr ~/.claude/hooks/user-prompt-submit.sh 2>/dev/null | cut -c5)
    if [[ "$attrs" == "i" ]]; then
        echo "WoW hook is PROTECTED (immutable)"
    else
        echo "WoW hook is UNPROTECTED"
    fi
}
```

## Full Protection Script

For comprehensive protection of all critical WoW files:

```bash
#!/bin/bash
# wow-protect-all.sh - Protect all critical WoW files

CRITICAL_FILES=(
    "$HOME/.claude/hooks/user-prompt-submit.sh"
)

protect() {
    echo "Protecting WoW critical files..."
    for file in "${CRITICAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            sudo chattr +i "$file"
            echo "  Protected: $file"
        fi
    done
    echo "Done. Files are now immutable."
}

unprotect() {
    echo "Unprotecting WoW critical files..."
    for file in "${CRITICAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            sudo chattr -i "$file"
            echo "  Unprotected: $file"
        fi
    done
    echo "Done. Files can now be modified."
}

status() {
    echo "WoW Protection Status:"
    for file in "${CRITICAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            local attrs=$(lsattr "$file" 2>/dev/null | cut -c5)
            if [[ "$attrs" == "i" ]]; then
                echo "  [LOCKED]   $file"
            else
                echo "  [UNLOCKED] $file"
            fi
        else
            echo "  [MISSING]  $file"
        fi
    done
}

case "${1:-status}" in
    protect|lock)     protect ;;
    unprotect|unlock) unprotect ;;
    status|*)         status ;;
esac
```

## WSL Considerations

On WSL2 (Windows Subsystem for Linux):

1. **Native Linux filesystem** (`/root`, `/home`): `chattr` works normally
2. **Mounted Windows filesystem** (`/mnt/c/...`): `chattr` may not work

Since the hook is at `~/.claude/hooks/` which typically resolves to Linux filesystem, this should work. Verify with:

```bash
df ~/.claude/hooks/
# Should show a Linux filesystem (ext4, etc.), not drvfs
```

If your `.claude` is on Windows filesystem, consider moving it:

```bash
# Move .claude to Linux filesystem
mv /mnt/c/Users/YourName/.claude ~/
ln -s ~/.claude /mnt/c/Users/YourName/.claude
```

## Security Trade-offs

| Aspect | Protected | Unprotected |
|--------|-----------|-------------|
| AI bypass | Prevented | Possible |
| Updates | Requires sudo | Easy |
| Accidents | Prevented | Possible |
| Recovery | Need sudo | Self-service |

## Recommended Workflow

1. **Development mode**: Keep unlocked, disable hook when needed
2. **Production mode**: Lock with `chattr +i`, unlock only for updates
3. **After WoW updates**: Always re-lock

## Verification

Test that protection works:

```bash
# Try to move (should fail)
mv ~/.claude/hooks/user-prompt-submit.sh /tmp/
# mv: cannot move: Operation not permitted

# Try to delete (should fail)
rm ~/.claude/hooks/user-prompt-submit.sh
# rm: cannot remove: Operation not permitted

# Try to modify (should fail)
echo "test" >> ~/.claude/hooks/user-prompt-submit.sh
# bash: cannot create: Operation not permitted
```

## Troubleshooting

**"Operation not permitted" when trying to unlock:**
```bash
# Make sure you're using sudo
sudo chattr -i ~/.claude/hooks/user-prompt-submit.sh
```

**"chattr: command not found":**
```bash
# Install e2fsprogs
sudo apt install e2fsprogs
```

**"Inappropriate ioctl for device":**
```bash
# Filesystem doesn't support chattr (likely NTFS/Windows mount)
# Move files to Linux filesystem (see WSL Considerations above)
```
