import Foundation
import AVFoundation
import UIKit
import CoreMedia

/// Post-processes recorded video to burn a visible timestamp overlay into the video frames.
/// The timestamp appears in the bottom-right corner of the video and is permanently part of the
/// video file itself — it will be visible when played on any device or media player.
///
/// This uses AVVideoComposition with a CoreAnimation layer tree overlay. The approach:
/// 1. Load the recorded video as an AVAsset
/// 2. Create an AVMutableVideoComposition with the same dimensions
/// 3. Build a CALayer tree with a CATextLayer for the timestamp
/// 4. Export using AVAssetExportSession with the custom video composition
enum VideoTimestampOverlay {
    
    /// Configuration for the timestamp overlay appearance
    enum Configuration {
        /// Font size relative to video height
        static let fontSizeRatio: CGFloat = 0.035
        /// Bottom-right padding relative to video width
        static let rightPaddingRatio: CGFloat = 0.02
        /// Bottom-right padding relative to video height
        static let bottomPaddingRatio: CGFloat = 0.02
        /// Background opacity behind text
        static let backgroundColorAlpha: CGFloat = 0.6
        /// Text color
        static let textColor = UIColor.white
        /// Background color
        static let backgroundColor = UIColor.black
    }
    
    /// Errors that can occur during timestamp overlay processing
    enum OverlayError: LocalizedError {
        case assetCreationFailed
        case noVideoTrack
        case exportFailed(String)
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .assetCreationFailed:
                return "Could not create video asset from recording"
            case .noVideoTrack:
                return "No video track found in recording"
            case .exportFailed(let reason):
                return "Timestamp overlay export failed: \(reason)"
            case .cancelled:
                return "Timestamp overlay was cancelled"
            }
        }
    }
    
    /// Result of the overlay operation
    struct OverlayResult {
        let outputURL: URL
        let duration: TimeInterval
    }
    
    /// Burn a timestamp overlay into a video file
    /// - Parameters:
    ///   - sourceURL: URL of the recorded video file
    ///   - startDate: The date/time when recording started (displayed as the timestamp)
    ///   - progressHandler: Optional callback for export progress (0.0 to 1.0)
    /// - Returns: Result with the output URL
    /// - Throws: OverlayError if processing fails
    static func burnTimestamp(
        sourceURL: URL,
        startDate: Date,
        progressHandler: ((Float) -> Void)? = nil
    ) async throws -> OverlayResult {
        
        // 1. Create asset from source
        let asset = AVAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw OverlayError.noVideoTrack
        }
        
        // 2. Get video dimensions and duration
        let videoSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0, videoSize.width > 0, videoSize.height > 0 else {
            throw OverlayError.assetCreationFailed
        }
        
        // 3. Create video composition
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OverlayError.assetCreationFailed
        }
        
        try await compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        
        // Add audio track if available
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw OverlayError.assetCreationFailed
            }
            try await compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }
        
        // 4. Create video composition instruction
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30fps composition
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // 5. Build the overlay layer tree
        let overlayLayer = buildTimestampLayer(
            videoSize: videoSize,
            startDate: startDate,
            duration: durationSeconds
        )
        
        // 6. Set up the animation tool
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        // 7. Export
        let outputURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("TMP_\(sourceURL.lastPathComponent)")
        
        // Remove any existing temp file
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw OverlayError.exportFailed("Could not create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        
        // Monitor progress if handler provided
        if progressHandler != nil {
            let progressQueue = DispatchQueue(label: "com.chainmark.timestamp-progress")
            let timer = DispatchSource.makeTimerSource(queue: progressQueue)
            timer.schedule(deadline: .now(), repeating: 0.5)
            timer.setEventHandler { [weak exportSession] in
                guard let session = exportSession else { return }
                Task { @MainActor in
                    progressHandler?(session.progress)
                }
            }
            timer.resume()
            
            // Cancel timer on completion
            defer { timer.cancel() }
        }
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            // Replace original with timestamped version
            try? FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.moveItem(at: outputURL, to: sourceURL)
            
            return OverlayResult(
                outputURL: sourceURL,
                duration: durationSeconds
            )
            
        case .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            throw OverlayError.cancelled
            
        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            try? FileManager.default.removeItem(at: outputURL)
            throw OverlayError.exportFailed(errorMsg)
            
        default:
            try? FileManager.default.removeItem(at: outputURL)
            throw OverlayError.exportFailed("Export ended with status: \(exportSession.status.rawValue)")
        }
    }
    
    /// Build the CALayer tree for the timestamp overlay
    /// - Parameters:
    ///   - videoSize: Size of the video frame
    ///   - startDate: Recording start date/time
    ///   - duration: Total recording duration in seconds
    /// - Returns: A CALayer that renders the timestamp overlay
    private static func buildTimestampLayer(
        videoSize: CGSize,
        startDate: Date,
        duration: TimeInterval
    ) -> CALayer {
        let fontSize = max(videoSize.height * fontSizeRatio, 14)
        let rightPadding = videoSize.width * rightPaddingRatio
        let bottomPadding = videoSize.height * bottomPaddingRatio
        
        // Format the timestamp display
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current
        let timestampStr = dateFormatter.string(from: startDate)
        
        // Show timezone
        let tzAbbreviation = TimeZone.current.abbreviation() ?? "UTC"
        let displayString = "ChainMark · \(timestampStr) \(tzAbbreviation)"
        
        // Format duration
        let durationStr = formatDuration(duration)
        let fullString = "\(displayString)\nDuration: \(durationStr)"
        
        // Calculate text size
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Configuration.textColor
        ]
        let textSize = (fullString as NSString).size(withAttributes: textAttributes)
        
        // Background padding
        let paddingH: CGFloat = 10
        let paddingV: CGFloat = 6
        let bgWidth = textSize.width + paddingH * 2
        let bgHeight = textSize.height + paddingV * 2
        
        // Position bottom-right
        let bgX = videoSize.width - bgWidth - rightPadding
        let bgY = videoSize.height - bgHeight - bottomPadding
        
        // Background layer
        let backgroundLayer = CALayer()
        backgroundLayer.frame = CGRect(x: bgX, y: bgY, width: bgWidth, height: bgHeight)
        backgroundLayer.backgroundColor = Configuration.backgroundColor.withAlphaComponent(
            Configuration.backgroundColorAlpha
        ).cgColor
        backgroundLayer.cornerRadius = 4
        backgroundLayer.masksToBounds = true
        
        // Text layer
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: paddingH, y: paddingV, width: textSize.width, height: textSize.height)
        textLayer.string = fullString
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = Configuration.textColor.cgColor
        textLayer.alignmentMode = .left
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = true
        
        backgroundLayer.addSublayer(textLayer)
        
        return backgroundLayer
    }
    
    /// Format seconds into a human-readable duration string
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
}