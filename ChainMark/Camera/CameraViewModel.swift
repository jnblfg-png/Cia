import SwiftUI
import AVFoundation
import CoreLocation

/// Represents a single captured video recording with its metadata
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
}

/// Errors from the camera capture system
enum CameraError: LocalizedError {
    case cameraUnavailable
    case micUnavailable
    case permissionDenied
    case captureFailed(String)
    case storageFailed(String)
    
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
        }
    }
}

/// Manages the AVCaptureSession for video recording with GPS metadata
final class CameraViewModel: NSObject, ObservableObject {
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isSessionRunning = false
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
        
        // Capture starting location
        recordingStartLocation = lastLocation
        
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
        
        withAnimation {
            isRecording = true
        }
    }
    
    /// Stop recording and save metadata
    func stopRecording() {
        guard let movieOutput = movieFileOutput, movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        
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
    
    // MARK: - Cleanup
    
    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
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
        
        // Get file attributes
        let fileSize: Int64
        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }
        
        // Get duration
        let duration = Date().timeIntervalSince(recordingStartDate ?? Date())
        
        // Record GPS at start
        let startLocation = recordingStartLocation ?? lastLocation
        
        // Create captured video entry
        let video = CapturedVideo(
            id: UUID(),
            fileName: outputFileURL.lastPathComponent,
            filePath: outputFileURL.path,
            duration: duration,
            captureDate: recordingStartDate ?? Date(),
            fileSize: fileSize,
            gpsLatitude: startLocation?.coordinate.latitude,
            gpsLongitude: startLocation?.coordinate.longitude,
            gpsAccuracy: startLocation?.horizontalAccuracy
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.recordedVideos.append(video)
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