import SwiftUI
import AVFoundation
import CoreLocation

/// Errors from the camera capture system
enum CameraError: LocalizedError {
    case cameraUnavailable
    case micUnavailable
    case permissionDenied
    case captureFailed(String)
    case storageFailed(String)
    case overlayFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device"
        case .micUnavailable:
            return "Microphone is not available on this device"
        case .permissionDenied:
            return "Camera and microphone permissions are required"
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        case .storageFailed(let reason):
            return "Storage failed: \(reason)"
        case .overlayFailed(let reason):
            return "Timestamp overlay failed: \(reason)"
        }
    }
}

/// Manages the AVCaptureSession for video recording with:
/// - GPS capture at start, during (every 30s), and end
/// - Burned-in timestamp overlay on the video
/// - CryptoKit SHA-256 hashing on completion
final class CameraViewModel: NSObject, ObservableObject {
    
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isSessionRunning = false
    @Published var isProcessingOverlay = false
    @Published var overlayProgress: Float = 0
    @Published var error: CameraError?
    @Published var recordedVideos: [CapturedVideo] = []
    @Published var currentGPSAccuracy: Double = 0
    @Published var currentGPSLatitude: Double = 0
    @Published var currentGPSLongitude: Double = 0
    
    // MARK: - AVFoundation Properties
    let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    // Video output for preview
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    // Current recording file URL
    private var outputFileURL: URL?
    private var recordingStartDate: Date?
    
    // Start location at recording start
    private var recordingStartLocation: CLLocation?
    
    // MARK: - GPS Waypoint Tracking
    private let gpsCaptureInterval: TimeInterval = 30 // Every 30 seconds
    private var gpsWaypoints = GPSWaypointCollection()
    private var gpsTimer: DispatchSourceTimer?
    private var lastWaypointCaptureOffset: TimeInterval = 0
    
    // MARK: - Location
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    
    // MARK: - Storage
    private let storageManager: SecureStorageManager
    
    // MARK: - Initialization
    override init() {
        self.storageManager = SecureStorageManager()
        super.init()
        setupLocation()
    }
    
    // MARK: - Setup
    
    /// Request camera and microphone permissions, then configure the capture session
    func requestPermissionsAndSetup() async {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        // Request permissions if not yet determined
        switch cameraStatus {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            await MainActor.run { self.error = .permissionDenied }
            return
        default:
            break
        }
        
        switch micStatus {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            await MainActor.run { self.error = .permissionDenied }
            return
        default:
            break
        }
        
        await configureSession()
    }
    
    /// Configure the AVCaptureSession with video and audio inputs
    private func configureSession() async {
        await MainActor.run {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high
        }
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.external, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            await MainActor.run {
                self.error = .cameraUnavailable
                self.captureSession.commitConfiguration()
            }
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(videoInput) else {
                await MainActor.run {
                    self.error = .cameraUnavailable
                    self.captureSession.commitConfiguration()
                }
                return
            }
            captureSession.addInput(videoInput)
            self.videoDeviceInput = videoInput
            
            // Add video data output for preview layer
            self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
            if captureSession.canAddOutput(self.videoDataOutput) {
                captureSession.addOutput(self.videoDataOutput)
            }
        } catch {
            await MainActor.run {
                self.error = .captureFailed(error.localizedDescription)
                self.captureSession.commitConfiguration()
            }
            return
        }
        
        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                    self.audioDeviceInput = audioInput
                }
            } catch {
                // Audio is optional — continue without it
                print("Warning: Could not add audio input: \(error.localizedDescription)")
            }
        }
        
        // Add movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            self.movieFileOutput = movieOutput
        }
        
        await MainActor.run {
            self.captureSession.commitConfiguration()
        }
        
        // Start the session on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = true
            }
        }
    }
    
    // MARK: - Location Setup
    
    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - Recording Controls
    
    /// Start recording video to app-private encrypted storage
    func startRecording() {
        guard let movieOutput = movieFileOutput, !movieOutput.isRecording else { return }
        guard isSessionRunning else { return }
        
        // Reset GPS waypoints for this recording session
        gpsWaypoints = GPSWaypointCollection()
        lastWaypointCaptureOffset = 0
        
        // Capture starting location
        recordingStartLocation = lastLocation
        if let location = lastLocation {
            gpsWaypoints.addWaypoint(offset: 0, location: location)
        }
        
        // Generate output file URL in app-private storage
        let fileName = "CM_\(ISO8601DateFormatter().string(from: Date()))_\(UUID().uuidString.prefix(8)).mov"
        guard let outputURL = storageManager.outputURL(for: fileName) else {
            self.error = .storageFailed("Could not create output file URL")
            return
        }
        
        self.outputFileURL = outputURL
        self.recordingStartDate = Date()
        
        // Remove any existing file at that path
        try? FileManager.default.removeItem(at: outputURL)
        
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        // Start periodic GPS capture
        startGPSTimer()
        
        withAnimation {
            isRecording = true
        }
    }
    
    /// Stop recording and save metadata
    func stopRecording() {
        guard let movieOutput = movieFileOutput, movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        
        // Stop periodic GPS timer
        stopGPSTimer()
        
        // Capture final waypoint
        if let location = lastLocation {
            let offset = Date().timeIntervalSince(recordingStartDate ?? Date())
            gpsWaypoints.addWaypoint(offset: offset, location: location)
        }
        
        withAnimation {
            isRecording = false
        }
    }
    
    /// Toggle recording state
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    // MARK: - Periodic GPS Capture
    
    /// Start a timer that captures GPS waypoints every 30 seconds during recording
    private func startGPSTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + gpsCaptureInterval, repeating: gpsCaptureInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self,
                  let location = self.lastLocation,
                  let startDate = self.recordingStartDate else { return }
            
            let offset = Date().timeIntervalSince(startDate)
            
            // Only capture if enough time has passed since last capture
            guard offset - self.lastWaypointCaptureOffset >= self.gpsCaptureInterval - 1 else { return }
            
            self.gpsWaypoints.addWaypoint(offset: offset, location: location)
            self.lastWaypointCaptureOffset = offset
            
            DispatchQueue.main.async {
                // Update GPS display with latest waypoint info
                self.currentGPSLatitude = location.coordinate.latitude
                self.currentGPSLongitude = location.coordinate.longitude
                self.currentGPSAccuracy = location.horizontalAccuracy
            }
        }
        self.gpsTimer = timer
        timer.resume()
    }
    
    /// Stop the periodic GPS timer
    private func stopGPSTimer() {
        gpsTimer?.cancel()
        gpsTimer = nil
    }
    
    // MARK: - Post-Processing Pipeline (Timestamp Overlay + SHA-256)
    
    /// Process the recorded video: burn timestamp overlay and compute SHA-256 hash
    private func processRecordedVideo(at fileURL: URL, startDate: Date) async {
        await MainActor.run {
            self.isProcessingOverlay = true
            self.overlayProgress = 0
        }
        
        // Step 1: Burn timestamp overlay
        do {
            _ = try await VideoTimestampOverlay.burnTimestamp(
                sourceURL: fileURL,
                startDate: startDate,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.overlayProgress = progress * 0.7 // 70% of progress for overlay
                    }
                }
            )
        } catch {
            // Log the error but continue — timestamp overlay is important but non-fatal
            print("Warning: Timestamp overlay failed: \(error.localizedDescription)")
            // The raw video without overlay is still valid evidence
        }
        
        await MainActor.run {
            self.overlayProgress = 0.7
        }
        
        // Step 2: Compute SHA-256 hash
        let sha256Hash = CryptoManager.sha256HashOfFile(at: fileURL)
        
        await MainActor.run {
            self.overlayProgress = 0.9
        }
        
        // Step 3: Compute final hash
        let waypointsDict = gpsWaypoints.toDictionary()
        let metadata = CryptoManager.buildMetadataJSON(
            fileName: fileURL.lastPathComponent,
            fileSize: 0, // Will be updated below
            sha256Hash: sha256Hash ?? "ERROR",
            duration: Date().timeIntervalSince(startDate),
            captureStartDate: startDate,
            gpsWaypoints: waypointsDict
        )
        
        // Get actual file size
        let fileSize: Int64
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }
        
        // Add file size to metadata
        var finalMetadata = metadata
        finalMetadata["fileSizeBytes"] = fileSize
        
        // Step 4: Save metadata
        let metadataJSON: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: finalMetadata, options: .prettyPrinted),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            metadataJSON = jsonStr
            storageManager.saveMetadata(finalMetadata, for: fileURL.lastPathComponent)
        } else {
            metadataJSON = "{}"
        }
        
        // Step 5: Compute combined evidence hash (binds file + metadata)
        let combinedHash = sha256Hash.map { fileHash in
            CryptoManager.combinedEvidenceHash(fileHash: fileHash, metadataJSON: metadataJSON)
        }
        
        await MainActor.run {
            self.overlayProgress = 1.0
            
            // Get start location
            let startLocation = self.gpsWaypoints.startWaypoint
            
            // Create captured video entry with full metadata
            let duration = Date().timeIntervalSince(startDate)
            let video = CapturedVideo(
                id: UUID(),
                fileName: fileURL.lastPathComponent,
                filePath: fileURL.path,
                duration: duration,
                captureDate: startDate,
                fileSize: fileSize,
                gpsLatitude: startLocation?.latitude,
                gpsLongitude: startLocation?.longitude,
                gpsAccuracy: startLocation?.accuracy,
                sha256Hash: combinedHash,
                gpsWaypointCount: self.gpsWaypoints.count
            )
            
            self.recordedVideos.append(video)
            self.isProcessingOverlay = false
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        stopGPSTimer()
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started successfully
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil else {
            self.error = .captureFailed(error?.localizedDescription ?? "Unknown recording error")
            return
        }
        
        guard let startDate = recordingStartDate else { return }
        
        // Process the video asynchronously (timestamp overlay + SHA-256)
        Task {
            await processRecordedVideo(at: outputFileURL, startDate: startDate)
        }
        
        // Reset recording state
        recordingStartDate = nil
        recordingStartLocation = nil
    }
}

// MARK: - CLLocationManagerDelegate
extension CameraViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out invalid/simulated locations
        guard location.horizontalAccuracy >= 0 else { return }
        
        lastLocation = location
        
        DispatchQueue.main.async { [weak self] in
            self?.currentGPSLatitude = location.coordinate.latitude
            self?.currentGPSLongitude = location.coordinate.longitude
            self?.currentGPSAccuracy = location.horizontalAccuracy
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}