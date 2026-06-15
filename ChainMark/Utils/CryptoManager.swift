import Foundation
import CryptoKit

/// Cryptographic operations for evidence sealing.
/// Uses only Apple's CryptoKit — no hand-rolled crypto.
enum CryptoManager {
    
    // MARK: - SHA-256 Hashing
    
    /// Compute SHA-256 hash of a file at the given URL
    /// - Parameter fileURL: URL of the file to hash
    /// - Returns: Hex-encoded SHA-256 digest string, or nil on failure
    static func sha256HashOfFile(at fileURL: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            print("CryptoManager: Cannot open file for hashing: \(fileURL)")
            return nil
        }
        
        defer {
            try? fileHandle.close()
        }
        
        var hash = SHA256()
        
        // Read and hash in chunks to handle large video files
        let chunkSize = 1024 * 1024 * 16 // 16MB chunks
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: chunkSize)
            guard !data.isEmpty else { return false }
            hash.update(data: data)
            return true
        }) { }
        
        let digest = hash.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Compute SHA-256 hash of data
    /// - Parameter data: The data to hash
    /// - Returns: Hex-encoded SHA-256 digest string
    static func sha256HashOfData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Compute SHA-256 hash of a string
    /// - Parameter string: The string to hash
    /// - Returns: Hex-encoded SHA-256 digest string
    static func sha256HashOfString(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else {
            return ""
        }
        return sha256HashOfData(data)
    }
    
    // MARK: - Combined Evidence Hash
    
    /// Compute a combined hash that binds the video file with its metadata
    /// This creates a tamper-evident link: if either the video or metadata changes, the hash changes
    /// - Parameters:
    ///   - fileHash: SHA-256 of the video file
    ///   - metadataJSON: JSON-encoded metadata string
    /// - Returns: Combined SHA-256 hex string
    static func combinedEvidenceHash(fileHash: String, metadataJSON: String) -> String {
        let combined = "FILE_HASH:\(fileHash)\nMETADATA:\(metadataJSON)"
        return sha256HashOfString(combined)
    }
    
    // MARK: - Metadata JSON Builder
    
    /// Build a complete metadata dictionary with hashes included
    /// - Parameters:
    ///   - fileName: The video file name
    ///   - fileSize: File size in bytes
    ///   - sha256Hash: SHA-256 hash of the video file
    ///   - duration: Recording duration in seconds
    ///   - captureStartDate: When recording started
    ///   - gpsWaypoints: Array of GPS waypoints as dictionaries
    /// - Returns: Metadata dictionary ready for JSON serialization
    static func buildMetadataJSON(
        fileName: String,
        fileSize: Int64,
        sha256Hash: String,
        duration: TimeInterval,
        captureStartDate: Date,
        gpsWaypoints: [[String: Any]]
    ) -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let metadata: [String: Any] = [
            "fileName": fileName,
            "fileSizeBytes": fileSize,
            "sha256Hash": sha256Hash,
            "captureStartDate": dateFormatter.string(from: captureStartDate),
            "durationSeconds": duration,
            "gpsWaypoints": gpsWaypoints,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "deviceModel": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "createdAt": dateFormatter.string(from: Date()),
            "cryptoMethod": "SHA-256 (CryptoKit)"
        ]
        
        return metadata
    }
}