// WoW Windows Hello Bridge
// Windows Hello authentication for WoW SuperAdmin
// Author: Chude <chude@emeke.org>
//
// Security Model:
// - Uses UserConsentVerifier for Windows Hello authentication
// - Verifies user identity via fingerprint, face, or PIN
// - Works without MSIX packaging requirement
//
// Usage:
//   WoWHelloBridge.exe --check     Check Windows Hello availability
//   WoWHelloBridge.exe --verify    Verify user identity with Windows Hello

using System;
using System.Threading.Tasks;
using Windows.Security.Credentials.UI;

namespace WoWHelloBridge;

class Program
{
    private const string Version = "1.1.0";
    private const string VerificationMessage = "WoW SuperAdmin Authentication";

    // Exit codes
    private const int ExitSuccess = 0;
    private const int ExitAuthFailed = 1;
    private const int ExitNotAvailable = 2;
    private const int ExitInvalidArgs = 4;
    private const int ExitInternalError = 5;

    static async Task<int> Main(string[] args)
    {
        try
        {
            if (args.Length == 0 || args[0] == "--help" || args[0] == "-h")
            {
                PrintHelp();
                return ExitSuccess;
            }

            return args[0] switch
            {
                "--version" or "-v" => PrintVersion(),
                "--check" or "-c" => await CheckAvailability(),
                "--verify" or "-V" => await Verify(),
                // Legacy commands for compatibility
                "--enroll" or "-e" => await LegacyEnroll(),
                "--sign" or "-s" => await LegacySign(),
                _ => Error($"Unknown command: {args[0]}", ExitInvalidArgs)
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"ERROR:{ex.GetType().Name}: {ex.Message}");
            if (ex.InnerException != null)
            {
                Console.Error.WriteLine($"INNER:{ex.InnerException.GetType().Name}: {ex.InnerException.Message}");
            }
            return ExitInternalError;
        }
    }

    // ========================================================================
    // Commands
    // ========================================================================

    /// <summary>
    /// Check if Windows Hello is available
    /// </summary>
    private static async Task<int> CheckAvailability()
    {
        var availability = await UserConsentVerifier.CheckAvailabilityAsync();

        switch (availability)
        {
            case UserConsentVerifierAvailability.Available:
                Console.WriteLine("AVAILABLE:WindowsHello");
                return ExitSuccess;

            case UserConsentVerifierAvailability.DeviceNotPresent:
                Console.WriteLine("NOT_AVAILABLE:NoDevice");
                return ExitNotAvailable;

            case UserConsentVerifierAvailability.NotConfiguredForUser:
                Console.WriteLine("NOT_AVAILABLE:NotConfigured");
                return ExitNotAvailable;

            case UserConsentVerifierAvailability.DisabledByPolicy:
                Console.WriteLine("NOT_AVAILABLE:DisabledByPolicy");
                return ExitNotAvailable;

            case UserConsentVerifierAvailability.DeviceBusy:
                Console.WriteLine("NOT_AVAILABLE:DeviceBusy");
                return ExitNotAvailable;

            default:
                Console.WriteLine($"NOT_AVAILABLE:{availability}");
                return ExitNotAvailable;
        }
    }

    /// <summary>
    /// Verify user identity with Windows Hello
    /// </summary>
    private static async Task<int> Verify()
    {
        // First check availability
        var availability = await UserConsentVerifier.CheckAvailabilityAsync();
        if (availability != UserConsentVerifierAvailability.Available)
        {
            Console.Error.WriteLine($"Windows Hello not available: {availability}");
            return ExitNotAvailable;
        }

        // Request verification - this triggers Windows Hello prompt
        Console.Error.WriteLine("Requesting Windows Hello verification...");
        var result = await UserConsentVerifier.RequestVerificationAsync(VerificationMessage);

        switch (result)
        {
            case UserConsentVerificationResult.Verified:
                Console.WriteLine("VERIFIED:OK");
                return ExitSuccess;

            case UserConsentVerificationResult.Canceled:
                Console.Error.WriteLine("Verification canceled by user");
                return ExitAuthFailed;

            case UserConsentVerificationResult.DeviceNotPresent:
                Console.Error.WriteLine("Biometric device not present");
                return ExitNotAvailable;

            case UserConsentVerificationResult.NotConfiguredForUser:
                Console.Error.WriteLine("Windows Hello not configured for this user");
                return ExitNotAvailable;

            case UserConsentVerificationResult.DisabledByPolicy:
                Console.Error.WriteLine("Windows Hello disabled by policy");
                return ExitNotAvailable;

            case UserConsentVerificationResult.DeviceBusy:
                Console.Error.WriteLine("Biometric device is busy");
                return ExitAuthFailed;

            case UserConsentVerificationResult.RetriesExhausted:
                Console.Error.WriteLine("Too many failed attempts");
                return ExitAuthFailed;

            default:
                Console.Error.WriteLine($"Verification failed: {result}");
                return ExitInternalError;
        }
    }

    /// <summary>
    /// Legacy enroll command - redirect to verify
    /// </summary>
    private static async Task<int> LegacyEnroll()
    {
        Console.Error.WriteLine("Note: Enrollment not required. Using --verify instead.");
        var result = await Verify();
        if (result == ExitSuccess)
        {
            // For compatibility, output ENROLLED format
            Console.WriteLine("ENROLLED:WindowsHello");
        }
        return result;
    }

    /// <summary>
    /// Legacy sign command - redirect to verify
    /// </summary>
    private static async Task<int> LegacySign()
    {
        Console.Error.WriteLine("Note: Challenge signing not required. Using --verify instead.");
        var result = await Verify();
        if (result == ExitSuccess)
        {
            // For compatibility, output SIGNED format
            Console.WriteLine("SIGNED:OK");
        }
        return result;
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    private static int PrintVersion()
    {
        Console.WriteLine($"WoWHelloBridge {Version}");
        return ExitSuccess;
    }

    private static void PrintHelp()
    {
        Console.WriteLine($@"
WoW Windows Hello Bridge v{Version}
Windows Hello authentication for WoW SuperAdmin

USAGE:
    WoWHelloBridge.exe <command>

COMMANDS:
    --version, -v    Show version information
    --check, -c      Check if Windows Hello is available
    --verify, -V     Verify user identity with Windows Hello
    --help, -h       Show this help

EXIT CODES:
    0  Success (verified)
    1  Authentication failed or canceled
    2  Windows Hello not available
    4  Invalid arguments
    5  Internal error

EXAMPLES:
    # Check availability
    WoWHelloBridge.exe --check

    # Verify identity (triggers Windows Hello)
    WoWHelloBridge.exe --verify

SECURITY:
    - Uses Windows Hello (fingerprint, face, or PIN)
    - Identity verified by Windows security subsystem
    - No credentials stored by this tool
");
    }

    private static int Error(string message, int code)
    {
        Console.Error.WriteLine($"ERROR:{message}");
        return code;
    }
}
