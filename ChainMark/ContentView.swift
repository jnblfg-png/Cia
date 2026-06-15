import SwiftUI
import AVFoundation

/// Main content view for the ChainMark iOS app
/// Provides a live camera preview with recording controls and GPS status
struct ContentView: View {
    @EnvironmentObject private var cameraViewModel: CameraViewModel
    @State private var showPermissionAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            if cameraViewModel.isSessionRunning {
                // Camera preview
                cameraPreviewSection
                
                // Overlays
                VStack {
                    // GPS status bar at top
                    gpsStatusBar
                    
                    Spacer()
                    
                    // Recording controls at bottom
                    recordingControls
                    
                    // Recording indicator
                    if cameraViewModel.isRecording {
                        recordingIndicator
                            .padding(.bottom, 8)
                    }
                }
            } else if cameraViewModel.error != nil {
                // Error state
                errorStateView
            } else {
                // Loading state
                loadingStateView
            }
        }
        .onAppear {
            setupCamera()
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ChainMark needs camera and microphone access to record evidence. Please enable them in Settings.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Camera Preview
    
    private var cameraPreviewSection: some View {
        CameraPreviewView(cameraViewModel: cameraViewModel)
            .aspectRatio(3/4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 4)
    }
    
    // MARK: - GPS Status
    
    private var gpsStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: cameraViewModel.currentGPSAccuracy > 0 ? "location.fill" : "location.slash")
                .foregroundColor(gpsQualityColor)
                .font(.system(size: 12))
            
            if cameraViewModel.currentGPSAccuracy > 0 {
                Text(String(format: "%.4f, %.4f",
                      cameraViewModel.currentGPSLatitude,
                      cameraViewModel.currentGPSLongitude))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                
                Text("±\(Int(cameraViewModel.currentGPSAccuracy))m")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(gpsQualityColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(gpsQualityColor.opacity(0.2))
                    .cornerRadius(4)
            } else {
                Text("No GPS Fix")
                    .font(.system(size: 11))
                    .foregroundColor(.yellow)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var gpsQualityColor: Color {
        let accuracy = cameraViewModel.currentGPSAccuracy
        if accuracy <= 0 { return .yellow }
        if accuracy <= 10 { return .green }
        if accuracy <= 50 { return .orange }
        return .red
    }
    
    // MARK: - Recording Controls
    
    private var recordingControls: some View {
        VStack(spacing: 20) {
            // Recording button
            Button(action: {
                cameraViewModel.toggleRecording()
            }) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    if cameraViewModel.isRecording {
                        // Square stop button
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        // Circle record button
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!cameraViewModel.isSessionRunning)
            
            // Session status text
            Text(cameraViewModel.isRecording ? "Recording..." : "Tap to Record")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Recording Indicator
    
    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("REC")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }
    
    // MARK: - Loading State
    
    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text("Initializing Camera...")
                .foregroundColor(.white.opacity(0.7))
                .font(.subheadline)
        }
    }
    
    // MARK: - Error State
    
    private var errorStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            
            Text("Camera Unavailable")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(cameraViewModel.error?.errorDescription ?? "Unknown error")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                setupCamera()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Setup
    
    private func setupCamera() {
        Task {
            await cameraViewModel.requestPermissionsAndSetup()
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CameraViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif