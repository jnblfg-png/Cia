import Foundation
import UIKit

/// Manages encrypted app-private storage for captured video evidence.
/// Files are stored in the app's Documents directory with complete file protection
/// (NSFileProtectionComplete), ensuring they are encrypted at rest and NOT accessible
/// via camera roll, iCloud, or external file sharing.
final class SecureStorageManager {
    
    // MARK: - Directory Structure
    
    /// Base URL for evidence storage within app-private Documents directory
    private let baseURL: URL
    
    /// Videos directory
    private let videosURL: URL
    
    /// Metadata directory
    private let metadataURL: URL
    
    // MARK: - Initialization
    
    init() {
        // Use app-private Documents directory (NOT camera roll, NOT iCloud)
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Cannot access app Documents directory — app-private storage unavailable")
        }
        
        self.baseURL = documentsURL.appendingPathComponent("ChainMarkEvidence", isDirectory: true)
        self.videosURL = baseURL.appendingPathComponent("Videos", isDirectory: true)
        self.metadataURL = baseURL.appendingPathComponent("Metadata", isDirectory: true)
        
        createDirectoryStructure()
        applyEncryptionProtection()
    }
    
    // MARK: - Directory Setup
    
    /// Create the directory hierarchy for evidence storage
    private func createDirectoryStructure() {
        let fileManager = FileManager.default
        
        for directory in [baseURL, videosURL, metadataURL] {
            if !fileManager.fileExists(atPath: directory.path) {
                do {
                    try fileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true,
                        attributes: [
                            .protectionKey: FileProtectionType.complete
                        ]
                    )
                } catch {
                    print("Failed to create storage directory: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Apply encryption protection to existing directories
    private func applyEncryptionProtection() {
        let fileManager = FileManager.default
        let directories = [baseURL, videosURL, metadataURL]
        
        for directory in directories {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true  // Exclude from iCloud backup
            do {
                try directory.setResourceValues(resourceValues)
            } catch {
                print("Failed to set resource values on \(directory): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - File URLs
    
    /// Generate an output URL for a new video recording
    /// - Parameter fileName: The desired file name (will be sanitized)
    /// - Returns: A URL in the app-private videos directory, or nil if storage is unavailable
    func outputURL(for fileName: String) -> URL? {
        let sanitized = sanitizeFileName(fileName)
        let fileURL = videosURL.appendingPathComponent(sanitized)
        
        // Ensure the videos directory exists
        if !FileManager.default.fileExists(atPath: videosURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: videosURL,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
            } catch {
                print("Failed to create videos directory: \(error.localizedDescription)")
                return nil
            }
        }
        
        return fileURL
    }
    
    /// Get the URL for a metadata file associated with a video
    func metadataURL(for videoFileName: String) -> URL {
        let metadataFileName = videoFileName.replacingOccurrences(
            of: ".mov",
            with: ".json"
        ).replacingOccurrences(
            of: ".mp4",
            with: ".json"
        )
        return metadataURL.appendingPathComponent(metadataFileName)
    }
    
    // MARK: - File Management
    
    /// Save metadata JSON alongside the video file
    func saveMetadata(_ metadata: [String: Any], for videoFileName: String) {
        let url = metadataURL(for: videoFileName)
        
        do {
            let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted])
            try data.write(to: url, options: [.completeFileProtection, .atomic])
        } catch {
            print("Failed to save metadata: \(error.localizedDescription)")
        }
    }
    
    /// List all recorded videos with their metadata
    func listRecordedVideos() -> [URL] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: videosURL.path) else { return [] }
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: videosURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter for video files only
            let videoExtensions: Set<String> = ["mov", "mp4"]
            return files.filter { url in
                videoExtensions.contains(url.pathExtension.lowercased())
            }.sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return dateA > dateB  // Newest first
            }
        } catch {
            print("Failed to list videos: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Delete a video and its associated metadata
    func deleteVideo(at url: URL) {
        let fileManager = FileManager.default
        let fileName = url.lastPathComponent
        
        // Delete video file
        do {
            try fileManager.removeItem(at: url)
        } catch {
            print("Failed to delete video: \(error.localizedDescription)")
        }
        
        // Delete associated metadata
        let metaURL = metadataURL(for: fileName)
        if fileManager.fileExists(atPath: metaURL.path) {
            do {
                try fileManager.removeItem(at: metaURL)
            } catch {
                print("Failed to delete metadata: \(error.localizedDescription)")
            }
        }
    }
    
    /// Get total storage used by evidence files
    var totalStorageUsed: Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: videosURL.path) else { return 0 }
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: videosURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            return files.reduce(0) { total, url in
                guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      let size = resources.fileSize else {
                    return total
                }
                return total + Int64(size)
            }
        } catch {
            return 0
        }
    }
    
    // MARK: - Helpers
    
    /// Sanitize a file name to prevent path traversal and ensure safe naming
    private func sanitizeFileName(_ name: String) -> String {
        // Remove path separators and null characters
        let sanitized = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "..", with: "_")
        
        // Limit length
        let maxLength = 255
        if sanitized.count > maxLength {
            let ext = (sanitized as NSString).pathExtension
            let nameOnly = (sanitized as NSString).deletingPathExtension
            let truncated = String(nameOnly.prefix(maxLength - ext.count - 1))
            return "\(truncated).\(ext)"
        }
        
        return sanitized
    }
}