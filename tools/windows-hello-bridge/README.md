# WoW Windows Hello Bridge

A bridge that enables Windows Hello (fingerprint, face, PIN) authentication for WoW SuperAdmin mode in WSL2.

## Why This Exists

WSL2 runs as a Linux VM inside Windows and cannot directly access Windows hardware like fingerprint readers. This bridge allows WoW's SuperAdmin authentication to use Windows Hello by:

1. Receiving a verification request from WSL
2. Prompting Windows Hello for authentication (fingerprint/face/PIN)
3. Returning the verification result

See [DESIGN.md](DESIGN.md) for full architecture and decision rationale.

## Requirements

### Windows Side
- Windows 10 (1607+) or Windows 11
- Windows Hello configured (fingerprint, face, or PIN)
- .NET 9.0 SDK (for building)

### WSL Side
- WSL2 with any Linux distribution
- WoW System v7.0+

## Quick Start

### 1. Build the Bridge (Windows PowerShell)

```powershell
# Navigate to wow-system root
cd "C:\Users\<you>\Projects\wow-system"

# Build release version
dotnet publish "tools/windows-hello-bridge/src/WoWHelloBridge.csproj" -c Release -r win-x64 --self-contained -o "tools/windows-hello-bridge/build/"

# Verify the executable was created
dir "tools\windows-hello-bridge\build\WoWHelloBridge.exe"
```

### 2. Install the Bridge

```powershell
# Run the install script
.\tools\windows-hello-bridge\scripts\install.ps1

# Or manually:
mkdir "$env:LOCALAPPDATA\Programs\WoW" -Force
copy "tools\windows-hello-bridge\build\WoWHelloBridge.exe" "$env:LOCALAPPDATA\Programs\WoW\"
& "$env:LOCALAPPDATA\Programs\WoW\WoWHelloBridge.exe" --version
```

### 3. Configure Windows Hello

From WSL:

```bash
# Run setup (verifies Windows Hello is working)
wow superadmin setup --hello
```

This will:
1. Call WoWHelloBridge.exe with `--verify`
2. Prompt Windows Hello for verification
3. Store an enrollment marker in `~/.wow-data/superadmin/`

### 4. Test Authentication

```bash
# Unlock SuperAdmin with Windows Hello
wow superadmin unlock

# Should prompt for fingerprint/face/PIN on Windows side
```

## Usage

### Command Line Interface

```
WoWHelloBridge.exe <command>

Commands:
  --version, -v    Show version information
  --check, -c      Check if Windows Hello is available
  --verify, -V     Verify user identity with Windows Hello
  --help, -h       Show this help

Exit Codes:
  0  Success (verified)
  1  Authentication failed/canceled
  2  Windows Hello not available
  4  Invalid arguments
  5  Internal error
```

### Examples

```powershell
# Check Windows Hello availability
WoWHelloBridge.exe --check
# Output: AVAILABLE:WindowsHello

# Verify identity (prompts Windows Hello)
WoWHelloBridge.exe --verify
# Output: VERIFIED:OK
```

## Integration with WoW

The bridge is called by `superadmin-core.sh`:

```bash
# Location of Windows executable (from WSL perspective)
HELLO_BRIDGE="/mnt/c/Users/${WINDOWS_USER}/AppData/Local/Programs/WoW/WoWHelloBridge.exe"

# Verification flow
result=$("${HELLO_BRIDGE}" --verify)
if [[ "${result}" =~ ^VERIFIED: ]]; then
    # User identity confirmed
fi
```

## Security Model

### Authentication Flow

```
WSL                          Windows
 |                              |
 | 1. Request verification      |
 |                              |
 | 2. ───── --verify ─────────> |
 |                              |
 |    3. Windows Hello prompt   |
 |       (fingerprint/face/PIN) |
 |                              |
 |    4. Windows verifies       |
 |       user identity          |
 |                              |
 | <────── VERIFIED:OK ──────── |
 |                              |
 | 5. Create session token      |
 |    with HMAC verification    |
 |                              |
```

### Defense in Depth

| Layer | Protection |
|-------|------------|
| TTY Enforcement | AI/scripts cannot access /dev/tty |
| Windows Hello | Biometric/PIN verification in Windows subsystem |
| Short Timeouts | 15 min max, 5 min inactivity |
| HMAC Tokens | Prevents session forgery |

### Why This Is Secure

1. **Windows Hello handles verification**: Biometric check happens inside Windows security subsystem
2. **TTY enforcement in WSL**: Scripts/AI cannot trigger the verification
3. **Short token expiry**: Limits exposure window
4. **HMAC-verified sessions**: Cannot forge valid session tokens

## Troubleshooting

### "Windows Hello not available"

1. Check Windows Hello is configured: Settings > Accounts > Sign-in options
2. Ensure fingerprint/face/PIN is enrolled
3. Run `WoWHelloBridge.exe --check` from PowerShell

### "Bridge not found"

Run enrollment first:
```bash
wow superadmin setup --hello
```

### Bridge not found from WSL

Check the path matches your Windows username:
```bash
# Find your Windows username
cmd.exe /c "echo %USERNAME%"

# Verify bridge exists
ls -la "/mnt/c/Users/<username>/AppData/Local/Programs/WoW/WoWHelloBridge.exe"
```

## Development

### Project Structure

```
windows-hello-bridge/
├── DESIGN.md           # Architecture and decisions
├── README.md           # This file
├── src/
│   ├── WoWHelloBridge.csproj
│   └── Program.cs
├── build/              # Compiled output (gitignored)
└── scripts/
    └── install.ps1     # Windows installation script
```

### Code Audit

The entire implementation is ~240 lines in `src/Program.cs`.
Key security-relevant sections:

- `CheckAvailability()`: Checks Windows Hello is configured
- `Verify()`: Requests user verification via Windows Hello

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-12-24 | Initial release with KeyCredentialManager (MSIX required) |
| 1.1.0 | 2024-12-24 | Switched to UserConsentVerifier (no packaging required) |

## License

Same as WoW System (see project root LICENSE).

## Credits

Architecture inspired by [WSL-Hello-sudo](https://github.com/nullpo-head/WSL-Hello-sudo) by Takaya Saeki.
