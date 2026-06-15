import Foundation
import UIKit
import AVFoundation

/// Packages evidence (video + metadata + integrity report) for export via the iOS share sheet.
/// Export is a COPY — the original sealed evidence remains untouched on device.
final class EvidenceExporter {
    
    // MARK: - Errors
    
    enum ExportError: LocalizedError {
        case videoFileNotFound
        case metadataNotFound
        case tempDirectoryFailed
        case packagingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .videoFileNotFound:
                return "Video file not found at expected path"
            case .metadataNotFound:
                return "Metadata file not found"
            case .tempDirectoryFailed:
                return "Could not create temporary export directory"
            case .packagingFailed(let reason):
                return "Export packaging failed: \(reason)"
            }
        }
    }
    
    // MARK: - Export
    
    /// Export video evidence as a complete package (video + metadata + integrity report)
    /// - Parameters:
    ///   - video: The CapturedVideo to export
    ///   - metadataJSON: Optional pre-loaded metadata JSON string
    /// - Returns: URL to the temporary export directory containing all files
    /// - Throws: ExportError if packaging fails
    static func exportPackage(for video: CapturedVideo, metadataJSON: String? = nil) throws -> URL {
        // 1. Verify source video exists
        let videoURL = URL(fileURLWithPath: video.filePath)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ExportError.videoFileNotFound
        }
        
        // 2. Create temp export directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChainMark_Export_\(UUID().uuidString.prefix(8))", isDirectory: true)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 3. Copy video file
        let exportVideoURL = tempDir.appendingPathComponent(video.fileName)
        try FileManager.default.copyItem(at: videoURL, to: exportVideoURL)
        
        // 4. Write metadata JSON
        let exportMetadataURL = tempDir.appendingPathComponent(
            video.fileName.replacingOccurrences(of: ".mov", with: ".json")
                .replacingOccurrences(of: ".mp4", with: ".json")
        )
        
        let metadata: String
        if let existingJSON = metadataJSON {
            metadata = existingJSON
        } else {
            // Try to load from storage
            let storageManager = SecureStorageManager()
            let metaURL = storageManager.metadataURL(for: video.fileName)
            metadata = (try? String(contentsOf: metaURL, encoding: .utf8)) ?? "{}"
        }
        try metadata.write(to: exportMetadataURL, atomically: true, encoding: .utf8)
        
        // 5. Generate integrity summary report
        let reportURL = tempDir.appendingPathComponent("INTEGRITY_REPORT.txt")
        let report = generateIntegrityReport(for: video, metadataJSON: metadata)
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        
        return tempDir
    }
    
    /// Generate a human-readable integrity report for the evidence package
    /// - Parameters:
    ///   - video: The CapturedVideo to report on
    ///   - metadataJSON: The metadata JSON string
    /// - Returns: Formatted integrity report text
    static func generateIntegrityReport(for video: CapturedVideo, metadataJSON: String) -> String {
        let separator = String(repeating: "=", count: 60)
        let subSeparator = String(repeating: "-", count: 40)
        
        var report = ""
        report += "\(separator)\n"
        report += "  CHAINMARK EVIDENCE INTEGRITY REPORT\n"
        report += "\(separator)\n\n"
        
        report += "\(subSeparator)\n"
        report += "  FILE INFORMATION\n"
        report += "\(subSeparator)\n\n"
        report += "  File Name:       \(video.fileName)\n"
        report += "  Capture Date:    \(video.formattedDate)\n"
        report += "  Duration:        \(video.formattedDuration)\n"
        report += "  File Size:       \(video.formattedFileSize)\n\n"
        
        report += "\(subSeparator)\n"
        report += "  CRYPTOGRAPHIC SEAL\n"
        report += "\(subSeparator)\n\n"
        
        if let hash = video.sha256Hash {
            report += "  Combined Hash:   \(hash)\n"
            let shortHash = String(hash.prefix(16))
            report += "  Hash (short):    \(shortHash)...\n"
        } else {
            report += "  SHA-256:         NOT COMPUTED\n"
        }
        
        // Add Secure Enclave info
        let enclaveAvailable = EnclaveManager.isAvailable
        report += "  Secure Enclave:  \(enclaveAvailable ? "Available" : "Not Available on this device")\n"
        
        if let fingerprint = EnclaveManager.publicKeyFingerprint {
            report += "  Signing Key:     \(fingerprint)...\n"
        }
        
        report += "  Crypto Method:   SHA-256 (CryptoKit)\n\n"
        
        report += "\(subSeparator)\n"
        report += "  LOCATION\n"
        report += "\(subSeparator)\n\n"
        
        if let lat = video.gpsLatitude, let lng = video.gpsLongitude {
            report += String(format: "  GPS Coordinates: %.6f, %.6f\n", lat, lng)
            if let acc = video.gpsAccuracy {
                report += String(format: "  GPS Accuracy:    ±%.0f meters\n", acc)
            }
            report += "  GPS Waypoints:   \(video.gpsWaypointCount)\n"
        } else {
            report += "  GPS:             Not available\n"
        }
        
        report += "\n  GPS Source:      CoreLocation (device GPS)\n\n"
        
        report += "\(subSeparator)\n"
        report += "  VERIFICATION\n"
        report += "\(subSeparator)\n\n"
        report += "  To verify this evidence:\n"
        report += "  1. Compute SHA-256 of the video file\n"
        report += "  2. Compare against the hash in the metadata JSON\n"
        report += "  3. Verify the Secure Enclave signature\n"
        report += "  4. Check the chain-of-custody log (when connected to backend)\n\n"
        
        report += "\(separator)\n"
        report += "  Generated: \(ISO8601DateFormatter().string(from: Date()))\n"
        report += "  App: ChainMark v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")\n"
        report += "  Device: \(UIDevice.current.model) (\(UIDevice.current.systemVersion))\n"
        report += "\(separator)\n"
        
        return report
    }
    
    /// Present the iOS share sheet for an export package
    /// - Parameters:
    ///   - video: The CapturedVideo to export
    ///   - presentingViewController: The view controller to present from
    ///   - metadataJSON: Optional pre-loaded metadata JSON
    static func presentShareSheet(
        for video: CapturedVideo,
        presenting viewController: UIViewController,
        metadataJSON: String? = nil
    ) {
        do {
            let exportURL = try exportPackage(for: video, metadataJSON: metadataJSON)
            
            // Collect items to share
            let videoURL = exportURL.appendingPathComponent(video.fileName)
            let metadataURL = exportURL.appendingPathComponent(
                video.fileName.replacingOccurrences(of: ".mov", with: ".json")
                    .replacingOccurrences(of: ".mp4", with: ".json")
            )
            let reportURL = exportURL.appendingPathComponent("INTEGRITY_REPORT.txt")
            
            let activityItems: [Any] = [videoURL, metadataURL, reportURL]
            
            let activityVC = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
            
            // Clean up temp files after sharing completes
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: exportURL)
            }
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                            y: viewController.view.bounds.midY,
                                            width: 0, height: 0)
            }
            
            viewController.present(activityVC, animated: true)
            
        } catch {
            // Show error alert
            let alert = UIAlertController(
                title: "Export Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }
    }
}