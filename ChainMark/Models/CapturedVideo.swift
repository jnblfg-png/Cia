import Foundation

/// Represents a single captured video recording with its full metadata
struct CapturedVideo: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let filePath: String
    let duration: TimeInterval
    let captureDate: Date
    let fileSize: Int64
    
    /// GPS location at start of recording
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsAccuracy: Double?
    
    /// SHA-256 hash of the video file (computed via CryptoKit)
    let sha256Hash: String?
    
    /// Number of GPS waypoints captured during recording
    let gpsWaypointCount: Int
    
    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        duration: TimeInterval,
        captureDate: Date,
        fileSize: Int64,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsAccuracy: Double? = nil,
        sha256Hash: String? = nil,
        gpsWaypointCount: Int = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.duration = duration
        self.captureDate = captureDate
        self.fileSize = fileSize
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsAccuracy = gpsAccuracy
        self.sha256Hash = sha256Hash
        self.gpsWaypointCount = gpsWaypointCount
    }
    
    // MARK: - Display Helpers
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: captureDate)
    }
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
    
    var formattedFileSize: String {
        let formatters = [
            (1_073_741_824, "GB"),
            (1_048_576, "MB"),
            (1_024, "KB")
        ]
        for (threshold, unit) in formatters {
            if fileSize >= threshold {
                let value = Double(fileSize) / Double(threshold)
                return String(format: "%.1f %@", value, unit)
            }
        }
        return "\(fileSize) B"
    }
    
    var formattedHash: String {
        guard let hash = sha256Hash else { return "Not computed" }
        return String(hash.prefix(16)) + "..."
    }
    
    var hashStatus: String {
        sha256Hash != nil ? "Sealed" : "Pending"
    }
}