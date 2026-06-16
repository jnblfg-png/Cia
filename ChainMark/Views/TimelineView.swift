import SwiftUI
import AVFoundation

/// Chronological timeline of all locally captured evidence
/// Premium UX with refined card design, animations, and accessibility
struct TimelineView: View {
    @EnvironmentObject private var cameraViewModel: CameraViewModel
    @State private var selectedVideo: CapturedVideo?
    @State private var showDetail = false
    @State private var showCamera = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.edgesIgnoringSafeArea(.all)
                
                if cameraViewModel.recordedVideos.isEmpty {
                    emptyStateView
                } else {
                    videoList
                }
            }
            .navigationTitle("Evidence")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: AppSpacing.medium) {
                        sealStatusBadge
                        Button(action: { showCamera = true }) {
                            Image(systemName: "camera.fill")
                                .foregroundColor(AppColors.accent)
                                .font(.system(size: AppTypography.body))
                        }
                        .evidenceAction(label: "Open camera")
                    }
                }
            }
            .sheet(isPresented: $showDetail) {
                if let video = selectedVideo {
                    VideoDetailView(video: video)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accentColor(AppColors.accent)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.xlarge) {
            Image(systemName: "video.slash")
                .font(.system(size: 52))
                .foregroundColor(AppColors.tertiary)
            
            VStack(spacing: AppSpacing.xsmall) {
                Text("No Evidence")
                    .font(.system(size: AppTypography.title2, weight: .semibold))
                    .foregroundColor(AppColors.primary)
                Text("Record your first video evidence\nto see it here")
                    .font(.system(size: AppTypography.subheadline))
                    .foregroundColor(AppColors.tertiary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showCamera = true }) {
                Label("Open Camera", systemImage: "camera.fill")
                    .font(.system(size: AppTypography.body, weight: .semibold))
                    .padding(.horizontal, AppSpacing.xxlarge)
                    .padding(.vertical, AppSpacing.medium)
                    .background(AppColors.accent)
                    .foregroundColor(.black)
                    .cornerRadius(AppSpacing.radiusMedium)
            }
            .evidenceAction(label: "Open camera to capture evidence")
        }
        .padding(AppSpacing.paddingScreen)
    }
    
    // MARK: - Video List
    
    private var videoList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.small) {
                ForEach(cameraViewModel.recordedVideos) { video in
                    TimelineRow(video: video)
                        .onTapGesture {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            selectedVideo = video
                            showDetail = true
                        }
                        .contextMenu { contextMenu(for: video) }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(timelineAccessibilityLabel(for: video))
                        .accessibilityHint("Tap to view details and export")
                }
            }
            .padding(.horizontal, AppSpacing.paddingInline)
            .padding(.vertical, AppSpacing.small)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cameraViewModel.recordedVideos.count)
        }
    }
    
    @ViewBuilder
    private func contextMenu(for video: CapturedVideo) -> some View {
        Button(action: {
            selectedVideo = video
            showDetail = true
        }) {
            Label("View Details", systemImage: "info.circle")
        }
        
        Button(action: { quickExport(video) }) {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        
        if let hash = video.sha256Hash {
            Text("SHA-256: \(String(hash.prefix(16)))...")
        }
    }
    
    private func quickExport(_ video: CapturedVideo) {
        let storageManager = SecureStorageManager()
        let metaURL = storageManager.metadataURL(for: video.fileName)
        let metadataJSON = try? String(contentsOf: metaURL, encoding: .utf8)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            EvidenceExporter.presentShareSheet(
                for: video,
                presenting: rootVC,
                metadataJSON: metadataJSON
            )
        }
    }
    
    // MARK: - Seal Status Badge
    
    private var sealStatusBadge: some View {
        let total = cameraViewModel.recordedVideos.count
        let sealed = cameraViewModel.recordedVideos.filter { $0.isFullySealed }.count
        let hashed = cameraViewModel.recordedVideos.filter { $0.isHashed }.count
        
        return HStack(spacing: AppSpacing.xsmall) {
            Image(systemName: sealed == total ? "lock.fill" : "lock.open")
                .font(.system(size: AppTypography.caption))
            Text("\(hashed)/\(total)")
                .font(.system(size: AppTypography.caption2, weight: .medium))
        }
        .foregroundColor(sealed == total ? AppColors.success : AppColors.warning)
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xsmall)
        .background((sealed == total ? AppColors.success : AppColors.warning).opacity(0.15))
        .cornerRadius(AppSpacing.radiusSmall)
        .accessibilityLabel("\(hashed) of \(total) items sealed")
    }
    
    private func timelineAccessibilityLabel(for video: CapturedVideo) -> String {
        let sealStatus = video.isFullySealed ? "fully sealed and signed" :
                         video.isHashed ? "hashed" : "pending"
        return "Evidence from \(video.formattedDate), \(video.formattedDuration), \(sealStatus)"
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let video: CapturedVideo
    
    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            // Thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: AppSpacing.radiusSmall)
                    .fill(AppColors.surfaceElevated)
                    .frame(width: 72, height: 52)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accent)
            }
            
            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xsmall) {
                HStack {
                    Text(video.formattedDate)
                        .font(.system(size: AppTypography.subheadline, weight: .semibold))
                        .foregroundColor(AppColors.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    sealBadge
                }
                
                Text(video.formattedDuration)
                    .font(.system(size: AppTypography.footnote))
                    .foregroundColor(AppColors.tertiary)
                    .monospacedDigit()
                
                HStack(spacing: AppSpacing.xsmall) {
                    Image(systemName: "location.fill")
                        .font(.system(size: AppTypography.caption2))
                        .foregroundColor(AppColors.info)
                    
                    if let lat = video.gpsLatitude, let lng = video.gpsLongitude {
                        Text(String(format: "%.4f, %.4f", lat, lng))
                            .font(.system(size: AppTypography.caption, design: .monospaced))
                            .foregroundColor(AppColors.tertiary)
                            .lineLimit(1)
                    } else {
                        Text("No GPS")
                            .font(.system(size: AppTypography.caption))
                            .foregroundColor(AppColors.tertiary)
                    }
                    
                    if video.gpsWaypointCount > 0 {
                        Text("· \(video.gpsWaypointCount) pts")
                            .font(.system(size: AppTypography.caption2))
                            .foregroundColor(AppColors.tertiary)
                    }
                }
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.surface)
        .cornerRadius(AppSpacing.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.radiusMedium)
                .stroke(video.isFullySealed ? AppColors.success.opacity(0.2) : AppColors.border, lineWidth: video.isFullySealed ? 0.5 : 0.5)
        )
    }
    
    private var sealBadge: some View {
        HStack(spacing: AppSpacing.xxsmall) {
            Circle()
                .fill(video.isFullySealed ? AppColors.success : (video.isHashed ? AppColors.warning : AppColors.tertiary))
                .frame(width: 6, height: 6)
            
            Text(video.sealStatusString)
                .font(.system(size: AppTypography.caption2, weight: .semibold))
                .foregroundColor(video.isFullySealed ? AppColors.success : (video.isHashed ? AppColors.warning : AppColors.tertiary))
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xxsmall)
        .background((video.isFullySealed ? AppColors.success : (video.isHashed ? AppColors.warning : AppColors.tertiary)).opacity(0.15))
        .cornerRadius(AppSpacing.radiusSmall)
    }
}

// MARK: - Video Detail View

struct VideoDetailView: View {
    let video: CapturedVideo
    @Environment(\.dismiss) private var dismiss
    @State private var metadataJSON: String?
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    evidenceInfoCard
                    cryptoSealCard
                    gpsCard
                    metadataCard
                    exportButton
                }
                .padding()
            }
            .background(AppColors.background.edgesIgnoringSafeArea(.all))
            .navigationTitle("Evidence Detail")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        dismiss()
                    }
                    .foregroundColor(AppColors.accent)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { loadMetadata() }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
    }
    
    // MARK: - Evidence Info Card
    
    private var evidenceInfoCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: AppSpacing.radiusMedium)
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppColors.accent)
                }
                
                VStack(alignment: .leading, spacing: AppSpacing.xxsmall) {
                    Text(video.fileName)
                        .font(.system(size: AppTypography.subheadline, weight: .medium))
                        .foregroundColor(AppColors.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text(video.captureDate, style: .date)
                        .font(.system(size: AppTypography.footnote))
                        .foregroundColor(AppColors.tertiary)
                }
                
                Spacer()
            }
            
            Divider().background(AppColors.border)
            
            Group {
                detailRow(label: "Duration", value: video.formattedDuration)
                detailRow(label: "File Size", value: video.formattedFileSize)
                detailRow(label: "Captured", value: video.captureDate.formatted(date: .omitted, time: .complete))
            }
        }
        .cardStyle()
    }
    
    // MARK: - Crypto Seal Card
    
    private var cryptoSealCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Image(systemName: video.isFullySealed ? "lock.shield.fill" : "shield")
                    .font(.system(size: AppTypography.title3))
                    .foregroundColor(video.isFullySealed ? AppColors.success : AppColors.warning)
                
                VStack(alignment: .leading, spacing: AppSpacing.xxsmall) {
                    Text("Cryptographic Seal")
                        .font(.system(size: AppTypography.subheadline, weight: .semibold))
                        .foregroundColor(AppColors.primary)
                    Text(video.sealStatusString)
                        .font(.system(size: AppTypography.footnote))
                        .foregroundColor(video.isFullySealed ? AppColors.success : AppColors.warning)
                }
                
                Spacer()
                
                statusBadge(
                    color: video.isFullySealed ? AppColors.success : AppColors.warning,
                    text: video.isFullySealed ? "SEALED" : "PENDING"
                )
            }
            
            Divider().background(AppColors.border)
            
            if let hash = video.sha256Hash {
                VStack(alignment: .leading, spacing: AppSpacing.xsmall) {
                    Text("Combined Hash")
                        .font(.system(size: AppTypography.footnote))
                        .foregroundColor(AppColors.tertiary)
                    Text(hash)
                        .font(.system(size: AppTypography.monoSmall, design: .monospaced))
                        .foregroundColor(AppColors.success)
                        .textSelection(.enabled)
                        .padding(AppSpacing.small)
                        .background(AppColors.success.opacity(0.05))
                        .cornerRadius(AppSpacing.radiusSmall)
                }
                
                HStack(spacing: AppSpacing.small) {
                    Label("SHA-256 (CryptoKit)", systemImage: "cpu")
                        .font(.system(size: AppTypography.footnote))
                        .foregroundColor(AppColors.tertiary)
                    
                    if EnclaveManager.isAvailable {
                        Label("Secure Enclave", systemImage: "lock.fill")
                            .font(.system(size: AppTypography.footnote))
                            .foregroundColor(AppColors.success)
                    }
                }
                
                if let fingerprint = video.enclaveKeyFingerprint {
                    HStack(spacing: AppSpacing.xsmall) {
                        Text("Signing Key:")
                            .font(.system(size: AppTypography.footnote))
                            .foregroundColor(AppColors.tertiary)
                        Text(fingerprint)
                            .font(.system(size: AppTypography.monoSmall, design: .monospaced))
                            .foregroundColor(AppColors.signed)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(AppColors.warning)
                    Text("Seal pending — processing in progress")
                        .font(.system(size: AppTypography.subheadline))
                        .foregroundColor(AppColors.warning)
                }
            }
        }
        .cardStyle()
    }
    
    // MARK: - GPS Card
    
    private var gpsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: AppTypography.title3))
                    .foregroundColor(AppColors.info)
                Text("Location")
                    .font(.system(size: AppTypography.subheadline, weight: .semibold))
                    .foregroundColor(AppColors.primary)
                
                Spacer()
                
                if video.gpsWaypointCount > 0 {
                    statusBadge(color: AppColors.info, text: "\(video.gpsWaypointCount) waypoints")
                }
            }
            
            Divider().background(AppColors.border)
            
            if let lat = video.gpsLatitude, let lng = video.gpsLongitude {
                detailRow(label: "Latitude", value: String(format: "%.6f°", lat))
                detailRow(label: "Longitude", value: String(format: "%.6f°", lng))
                if let acc = video.gpsAccuracy {
                    detailRow(label: "Accuracy", value: String(format: "±%.0f m", acc))
                }
                
                Button(action: openInMaps) {
                    Label("View in Maps", systemImage: "map.fill")
                        .font(.system(size: AppTypography.footnote, weight: .medium))
                        .foregroundColor(AppColors.info)
                        .padding(.top, AppSpacing.xsmall)
                }
                .evidenceAction(label: "Open location in Maps")
            } else {
                HStack {
                    Image(systemName: "location.slash")
                        .foregroundColor(AppColors.tertiary)
                    Text("No GPS data recorded")
                        .font(.system(size: AppTypography.subheadline))
                        .foregroundColor(AppColors.tertiary)
                }
            }
        }
        .cardStyle()
    }
    
    // MARK: - Metadata Card
    
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: AppTypography.title3))
                    .foregroundColor(AppColors.tertiary)
                Text("Raw Metadata")
                    .font(.system(size: AppTypography.subheadline, weight: .semibold))
                    .foregroundColor(AppColors.primary)
                Spacer()
            }
            
            if let json = metadataJSON {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(json)
                        .font(.system(size: AppTypography.monoSmall, design: .monospaced))
                        .foregroundColor(AppColors.tertiary)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }
    
    // MARK: - Export Button
    
    private var exportButton: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            isExporting = true
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                EvidenceExporter.presentShareSheet(
                    for: video,
                    presenting: rootVC,
                    metadataJSON: metadataJSON
                )
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isExporting = false
            }
        }) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: isExporting ? "checkmark.circle.fill" : "square.and.arrow.up.fill")
                    .font(.system(size: AppTypography.body))
                Text(isExporting ? "Preparing Package…" : "Export Evidence Package")
                    .font(.system(size: AppTypography.body, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.large)
            .background(AppColors.accent)
            .foregroundColor(.black)
            .cornerRadius(AppSpacing.radiusMedium)
        }
        .disabled(isExporting)
        .evidenceAction(label: "Export evidence package", hint: "Shares video, metadata, and integrity report")
        .padding(.top, AppSpacing.small)
    }
    
    // MARK: - Helpers
    
    private func loadMetadata() {
        let storageManager = SecureStorageManager()
        let metaURL = storageManager.metadataURL(for: video.fileName)
        metadataJSON = try? String(contentsOf: metaURL, encoding: .utf8)
    }
    
    private func openInMaps() {
        guard let lat = video.gpsLatitude, let lng = video.gpsLongitude else { return }
        let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)")!
        UIApplication.shared.open(url)
    }
}