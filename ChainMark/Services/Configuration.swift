import Foundation

/// Environment configuration for the ChainMark backend
/// Values are loaded at runtime — either from a `.env` plist or build settings.
/// This keeps secrets out of source control and allows different environments (dev/staging/prod).
enum Configuration {
    
    // MARK: - Supabase Configuration
    
    /// Supabase project URL
    /// Load from Info.plist or environment; fallback to empty for safety
    static var supabaseURL: URL {
        #if DEBUG
        // Use local Supabase or staging in debug mode
        return URL(string: env("SUPABASE_URL") ?? "https://placeholder.supabase.co")!
        #else
        return URL(string: env("SUPABASE_URL") ?? "https://placeholder.supabase.co")!
        #endif
    }
    
    /// Supabase anonymous key (safe for client-side use, restricted by RLS)
    static var supabaseAnonKey: String {
        env("SUPABASE_ANON_KEY") ?? "placeholder-anon-key"
    }
    
    // MARK: - API Endpoints
    
    /// Base URL for Supabase Edge Functions
    static var edgeFunctionsURL: URL {
        supabaseURL.appendingPathComponent("functions/v1")
    }
    
    /// Edge Function: register_evidence
    static var registerEvidenceURL: URL {
        edgeFunctionsURL.appendingPathComponent("register_evidence")
    }
    
    /// Edge Function: generate_report
    static var generateReportURL: URL {
        edgeFunctionsURL.appendingPathComponent("generate_report")
    }
    
    /// Edge Function: finalize_report
    static var finalizeReportURL: URL {
        edgeFunctionsURL.appendingPathComponent("finalize_report")
    }
    
    // MARK: - App Configuration
    
    /// Maximum retry attempts for upload queue items
    static let maxUploadRetries: Int = 5
    
    /// Base delay for exponential backoff (seconds)
    static let retryBaseDelay: TimeInterval = 2.0
    
    /// Maximum number of concurrent uploads
    static let maxConcurrentUploads: Int = 3
    
    // MARK: - Helpers
    
    /// Read a value from Info.plist environment
    private static func env(_ key: String) -> String? {
        // Try ProcessInfo
        if let value = ProcessInfo.processInfo.environment[key] {
            return value
        }
        // Try Info.plist custom keys
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
            return value
        }
        return nil
    }
}