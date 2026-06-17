import Foundation
import AVFoundation
import UIKit

/// Manages local video playback for evidence review
final class VideoPlaybackManager {
    
    /// Play a local video file using AVPlayer
    /// - Parameter fileURL: URL of the local video file
    /// - Returns: AVPlayer configured for the video
    static func player(for fileURL: URL) -> AVPlayer? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return AVPlayer(url: fileURL)
    }
    
    /// Generate a thumbnail for a video file
    /// - Parameters:
    ///   - fileURL: URL of the video
    ///   - time: Time offset for the thumbnail (default: 0)
    /// - Returns: UIImage thumbnail, or nil
    static func thumbnail(for fileURL: URL, at time: CMTime = .zero) -> UIImage? {
        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 270)
        
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}