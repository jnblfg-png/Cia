import SwiftUI
import AVFoundation
import UIKit

/// Main content view for the ChainMark iOS app
/// Premium UX with haptic feedback, accessibility labels, and refined visual hierarchy
struct ContentView: View {
    @EnvironmentObject private var cameraViewModel: CameraViewModel
    @State private var showPermissionAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            AppColors.background.edgesIgnoringSafeArea(.all)
            
            if cameraViewModel.isSessionRunning {
                cameraPreviewSection
                    .overlay(alignment: .top) { gpsStatusBar }
                    .overlay(alignment: .bottom) { bottomControls }
                    .overlay(alignment: .top) {
                        if cameraViewModel.isRecording {
                            recordingIndicator
                                .padding(.top, AppSpacing.huge + 20)
                        }
                    }
            } else if cameraViewModel.error != nil {
                errorStateView
            } else {
                loadingStateView
            }
        }
        .onAppear { setupCamera() }
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
        .onChange(of: cameraViewModel.error?.errorDescription ?? "") { newValue in
            if !newValue.isEmpty {
                errorMessage = newValue
                showErrorAlert = true
            }
        }
    }
    
    // MARK: - Camera Preview
    
    private var cameraPreviewSection: some View {
        CameraPreviewView(cameraViewModel: cameraViewModel)
            .aspectRatio(3/4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.radiusLarge)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .shadow(color: AppColors.shadowDark, radius: 20, x: 0, y: 10)
            .padding(.horizontal, AppSpacing.paddingInline)
            .evidenceAction(label: "Camera preview", hint: "Live camera feed for recording evidence")
    }
    
    // MARK: - GPS Status
    
    private var gpsStatusBar: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: cameraViewModel.currentGPSAccuracy > 0 ? "location.fill" : "location.slash")
                .font(.system(size: AppTypography.footnote))
                .foregroundColor(.gpsQualityColor(accuracy: cameraViewModel.currentGPSAccuracy))
            
            if cameraViewModel.currentGPSAccuracy > 0 {
                Text(String(format: "%.4f, %.4f",
                      cameraViewModel.currentGPSLatitude,
                      cameraViewModel.currentGPSLongitude))
                    .font(.system(size: AppTypography.caption, design: .monospaced))
                    .foregroundColor(AppColors.secondary)
                
                Text("±\(Int(cameraViewModel.currentGPSAccuracy))m")
                    .font(.system(size: AppTypography.caption2, design: .monospaced, weight: .medium))
                    .foregroundColor(.gpsQualityColor(accuracy: cameraViewModel.currentGPSAccuracy))
                    .padding(.horizontal, AppSpacing.xsmall)
                    .padding(.vertical, AppSpacing.xxsmall)
                    .background(.gpsQualityColor(accuracy: cameraViewModel.currentGPSAccuracy).opacity(0.15))
                    .cornerRadius(AppSpacing.radiusSmall)
            } else {
                Text("Acquiring GPS...")
                    .font(.system(size: AppTypography.caption))
                    .foregroundColor(AppColors.warning)
            }
            
            Spacer()
        }
        .padding(.horizontal, AppSpacing.paddingScreen)
        .padding(.top, AppSpacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(gpsAccessibilityLabel)
    }
    
    private var gpsAccessibilityLabel: String {
        if cameraViewModel.currentGPSAccuracy > 0 {
            return "GPS location: \(String(format: "%.4f", cameraViewModel.currentGPSLatitude)), \(String(format: "%.4f", cameraViewModel.currentGPSLongitude)), accuracy \(Int(cameraViewModel.currentGPSAccuracy)) meters"
        }
        return "Acquiring GPS signal"
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: AppSpacing.xlarge) {
            // Post-processing overlay
            if cameraViewModel.isProcessingOverlay {
                processingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Recording button
            recordButton
            
            // Session status
            Text(recordingStatusText)
                .font(.system(size: AppTypography.subheadline))
                .foregroundColor(recordingStatusColor)
                .animation(.easeInOut(duration: 0.2), value: cameraViewModel.isRecording)
        }
        .padding(.bottom, AppSpacing.huge)
    }
    
    private var recordButton: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: cameraViewModel.isRecording ? .light : .heavy)
            impact.impactOccurred()
            cameraViewModel.toggleRecording()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(recordButtonRingColor, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(cameraViewModel.isRecording ? 1.1 : 1.0)
                
                if cameraViewModel.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.error)
                        .frame(width: 30, height: 30)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(AppColors.error)
                        .frame(width: 60, height: 60)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cameraViewModel.isRecording)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!cameraViewModel.isSessionRunning || cameraViewModel.isProcessingOverlay)
        .evidenceAction(
            label: cameraViewModel.isRecording ? "Stop recording" : "Start recording",
            hint: cameraViewModel.isRecording ? "Tap to stop recording evidence" : "Tap to begin recording video evidence"
        )
    }
    
    private var recordButtonRingColor: Color {
        if cameraViewModel.isRecording { return AppColors.error }
        if cameraViewModel.isProcessingOverlay { return AppColors.disabled }
        return AppColors.primary
    }
    
    private var recordingStatusText: String {
        if cameraViewModel.isProcessingOverlay { return "Sealing evidence..." }
        if cameraViewModel.isRecording { return "Recording" }
        return "Tap to Record"
    }
    
    private var recordingStatusColor: Color {
        if cameraViewModel.isProcessingOverlay { return AppColors.warning }
        if cameraViewModel.isRecording { return AppColors.error }
        return AppColors.tertiary
    }
    
    // MARK: - Post-Processing Overlay
    
    private var processingOverlay: some View {
        VStack(spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppColors.warning)
                    .font(.system(size: AppTypography.callout))
                Text("Sealing Evidence")
                    .font(.system(size: AppTypography.subheadline, weight: .semibold))
                    .foregroundColor(AppColors.primary)
            }
            
            ProgressView(value: cameraViewModel.overlayProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: AppColors.warning))
                .frame(width: 200)
            
            Text(processingStatusText)
                .font(.system(size: AppTypography.footnote))
                .foregroundColor(AppColors.tertiary)
                .animation(.none, value: cameraViewModel.overlayProgress)
        }
        .padding(.horizontal, AppSpacing.xxlarge)
        .padding(.vertical, AppSpacing.large)
        .background(AppColors.surfaceDeep.opacity(0.9))
        .cornerRadius(AppSpacing.radiusLarge)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.radiusLarge)
                .stroke(AppColors.warning.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.huge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sealing evidence: \(processingStatusText)")
    }
    
    private var processingStatusText: String {
        let progress = cameraViewModel.overlayProgress
        if progress < 0.7 { return "Applying timestamp..." }
        if progress < 0.9 { return "Computing SHA-256..." }
        if progress < 1.0 { return "Signing with Secure Enclave..." }
        return "Finalizing"
    }
    
    // MARK: - Recording Indicator
    
    private var recordingIndicator: some View {
        HStack(spacing: AppSpacing.xsmall) {
            Circle()
                .fill(AppColors.error)
                .frame(width: 8, height: 8)
                .opacity(cameraViewModel.isRecording ? 1 : 0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cameraViewModel.isRecording)
            
            Text("REC")
                .font(.system(size: AppTypography.footnote, weight: .bold))
                .foregroundColor(AppColors.error)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(AppColors.surfaceDeep.opacity(0.7))
        .cornerRadius(AppSpacing.radiusSmall)
        .accessibilityLabel("Recording in progress")
    }
    
    // MARK: - Loading State
    
    private var loadingStateView: some View {
        VStack(spacing: AppSpacing.large) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
                .scaleEffect(1.5)
            Text("Initializing Camera")
                .font(.system(size: AppTypography.subheadline))
                .foregroundColor(AppColors.secondary)
        }
        .accessibilityLabel("Camera initializing")
    }
    
    // MARK: - Error State
    
    private var errorStateView: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(AppColors.warning)
            
            Text("Camera Unavailable")
                .font(.system(size: AppTypography.title3, weight: .semibold))
                .foregroundColor(AppColors.primary)
            
            Text(cameraViewModel.error?.errorDescription ?? "Unknown error")
                .font(.system(size: AppTypography.subheadline))
                .foregroundColor(AppColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.huge)
            
            Button("Retry") {
                setupCamera()
            }
            .primaryButton(color: AppColors.accent)
            .padding(.horizontal, AppSpacing.xxxlarge)
            .padding(.top, AppSpacing.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera error: \(cameraViewModel.error?.errorDescription ?? "Unknown")")
    }
    
    // MARK: - Setup
    
    private func setupCamera() {
        Task { await cameraViewModel.requestPermissionsAndSetup() }
    }
}