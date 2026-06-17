import SwiftUI
import AVFoundation

/// Chronological timeline of all locally captured evidence
/// Sorted newest-first with seal status indicators
struct TimelineView: View {
    @EnvironmentObject private var cameraViewModel: CameraViewModel
    @State private var selectedVideo: CapturedVideo?
    @State private var showDetail = false
    @State private var showDeleteAlert = false
    @State private var videoToDelete: CapturedVideo?
    @State private var showDeleteAllAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.edgesIgnoringSafeArea(.all)
                
                if cameraViewModel.recordedVideos.isEmpty {
                    emptyStateView
                } else {
                    videoList
                }
                
                // Capture confirmation toast
                if cameraViewModel.showCaptureConfirmation, let video = cameraViewModel.lastCompletedCapture {
                    captureConfirmationToast(video: video)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .navigationTitle("Evidence")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: AppSpacing.medium) {
                        sealStatusBadge
                        if !cameraViewModel.recordedVideos.isEmpty {
                            Menu {
                                Button(action: { showDeleteAllAlert = true }, role: .destructive) {
                                    Label("Delete All Evidence", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(AppColors.secondary)
                            }
                            .evidenceAction(label: "More options")
                        }
                    }
                }
            }
            .sheet(isPresented: $showDetail) {
                if let video = selectedVideo {
                    VideoDetailView(video: video)
                }
            }
            .alert("Delete Evidence", isPresented: $showDeleteAlert, presenting: videoToDelete) { video in
                Button("Cancel", role: .cancel) { }
                Button(deleteButtonLabel(for: video), role: .destructive) {
                    withAnimation { cameraViewModel.deleteEvidence(video) }
                }
            } message: { video in
                Text(deleteMessage(for: video))
            }
            .alert("Delete All Evidence", isPresented: $showDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    withAnimation { cameraViewModel.deleteAllEvidence() }
                }
            } message: {
                Text(deleteAllMessage)
            }
        }
        .preferredColorScheme(.dark)
        .accentColor(AppColors.accent)
    }
    
    // MARK: - Deletion Policy Helpers
    
    /// Delete button label adapts to sealed state
    private func deleteButtonLabel(for video: CapturedVideo) -> String {
        video.sha256Hash != nil ? "Withdraw" : "Delete"
    }
    
    /// Delete confirmation message adapts to sealed state
    private func deleteMessage(for video: CapturedVideo) -> String {
        if video.sha256Hash != nil {
            return "This evidence is SEALED. Withdrawing will record a withdrawal in the custody log and remove it from the active timeline. The integrity record (hash, signature, timestamp) is preserved."
        }
        return "This evidence is NOT sealed. It will be permanently deleted along with all metadata."
    }
    
    /// Delete All message explains both paths
    private var deleteAllMessage: String {
        let sealedCount = cameraViewModel.recordedVideos.filter { $0.sha256Hash != nil }.count
        let unsealedCount = cameraViewModel.recordedVideos.count - sealedCount
        
        var parts: [String] = []
        if sealedCount > 0 {
            parts.append("\(sealedCount) sealed item(s) will be withdrawn (custody log preserved)")
        }
        if unsealedCount > 0 {
            parts.append("\(unsealedCount) unsealed item(s) will be permanently deleted")
        }
        return parts.joined(separator: ". ") + "."
    }
    
    // MARK: - Capture Confirmation Toast
    
    @ViewBuilder
    private func captureConfirmationToast(video: CapturedVideo) -> some View {
        VStack(spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success)
                    .font(.system(size: AppTypography.title3))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence Captured")
                        .font(.system(size: AppTypography.subheadline, weight: .semibold))
                        .foregroundColor(AppColors.primary)
                    Text(video.formattedDuration + " · " + (video.isFullySealed ? "Sealed & Signed" : "Sealed"))
                        .font(.system(size: AppTypography.footnote))
                        .foregroundColor(AppColors.secondary)
                }
                
                Spacer()
                
                Button(action: { showDetail = true; selectedVideo = video }) {
                    Text("View")
                        .font(.system(size: AppTypography.subheadline, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
            .background(AppColors.surfaceDeep.opacity(0.95))
            .cornerRadius(AppSpacing.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.radiusMedium)
                    .stroke(AppColors.success.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: AppColors.shadowDark, radius: 10)
            .padding(.horizontal, AppSpacing.paddingInline)
            .padding(.top, AppSpacing.small)
            .transition(.move(edge: .top).combined(with: .opacity))
            
            Spacer()
        }
        .onTapGesture {
            withAnimation { cameraViewModel.showCaptureConfirmation = false }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Evidence Captured")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Record your first video evidence\nto see it here")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button(action: { showCamera = true }) {
                Label("Open Camera", systemImage: "camera.fill")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Video List
    
    private var videoList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(cameraViewModel.recordedVideos) { video in
                    TimelineRow(video: video)
                        .onTapGesture {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            selectedVideo = video
                            showDetail = true
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation { cameraViewModel.deleteEvidence(video) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(action: { quickExport(video) }) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(AppColors.accent)
                        }
                        .contextMenu {
                            Button(action: {
                                selectedVideo = video
                                showDetail = true
                            }) {
                                Label("View Details", systemImage: "info.circle")
                            }
                            
                            Button(action: {
                                // Quick export from context menu
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
                            }) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Seal Status Badge
    
    private var sealStatusBadge: some View {
        let totalVideos = cameraViewModel.recordedVideos.count
        let sealedCount = cameraViewModel.recordedVideos.filter { $0.sha256Hash != nil }.count
        
        return HStack(spacing: 4) {
            Image(systemName: sealedCount == totalVideos ? "lock.fill" : "lock.open")
                .font(.system(size: 10))
            Text("\(sealedCount)/\(totalVideos)")
                .font(.caption2)
        }
        .foregroundColor(sealedCount == totalVideos ? .green : .yellow)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(sealedCount == totalVideos ? Color.green.opacity(0.2) : Color.yellow.opacity(0.2))
        .cornerRadius(6)
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let video: CapturedVideo
    
    var body: some View {
        HStack(spacing: 12) {
            // Video thumbnail placeholder
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 64, height: 48)
                    .cornerRadius(6)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(video.formattedDate)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    sealBadge
                }
                
                Text(video.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                    
                    if let lat = video.gpsLatitude, let lng = video.gpsLongitude {
                        Text(String(format: "%.4f, %.4f", lat, lng))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    } else {
                        Text("No GPS")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    if video.gpsWaypointCount > 0 {
                        Text("· \(video.gpsWaypointCount) pts")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }
    
    private var sealBadge: some View {
        HStack(spacing: 3) {
            if video.sha256Hash != nil {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Sealed")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 6, height: 6)
                Text("Pending")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((video.sha256Hash != nil ? Color.green : Color.yellow).opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Video Detail View

struct VideoDetailView: View {
    let video: CapturedVideo
    @Environment(\.dismiss) private var dismiss
    @State private var metadataJSON: String?
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    videoInfoCard
                    videoPlayerCard
                    cryptoSealCard
                    gpsCard
                    metadataSection
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
                        player?.pause()
                        dismiss()
                    }
                    .foregroundColor(AppColors.accent)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { loadMetadata() }
            .onDisappear { player?.pause(); player = nil }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Video Player Card
    
    private var videoPlayerCard: some View {
        VStack(spacing: AppSpacing.medium) {
            // Video preview
            ZStack {
                if let player = player {
                    VideoPlayerView(player: player, isPlaying: $isPlaying)
                        .frame(height: 200)
                        .cornerRadius(AppSpacing.radiusMedium)
                } else {
                    RoundedRectangle(cornerRadius: AppSpacing.radiusMedium)
                        .fill(AppColors.surfaceDeep)
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: AppSpacing.small) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppColors.tertiary)
                                Text("Video preview unavailable")
                                    .font(.system(size: AppTypography.footnote))
                                    .foregroundColor(AppColors.tertiary)
                            }
                        }
                }
            }
            
            // Playback controls
            if player != nil {
                HStack(spacing: AppSpacing.large) {
                    Button(action: {
                        player?.seek(to: .zero)
                        player?.pause()
                        isPlaying = false
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: AppTypography.title3))
                    }
                    
                    Button(action: {
                        if isPlaying {
                            player?.pause()
                        } else {
                            player?.play()
                        }
                        isPlaying.toggle()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.accent)
                    }
                    
                    Button(action: {
                        player?.pause()
                        isPlaying = false
                        player?.seek(to: .zero)
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: AppTypography.title3))
                    }
                }
                .foregroundColor(AppColors.secondary)
            }
        }
        .cardStyle()
        .onAppear {
            let fileURL = URL(fileURLWithPath: video.filePath)
            player = VideoPlaybackManager.player(for: fileURL)
        }
    }
    
    // MARK: - Video Info Card
    
    private var videoInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(video.formattedDate)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            Divider().background(.gray.opacity(0.3))
            
            detailRow(label: "Duration", value: video.formattedDuration)
            detailRow(label: "File Size", value: video.formattedFileSize)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Crypto Seal Card
    
    private var cryptoSealCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                Text("Cryptographic Seal")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if video.sha256Hash != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("SEALED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                }
            }
            
            Divider().background(.gray.opacity(0.3))
            
            if let hash = video.sha256Hash {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Combined Hash")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(hash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                        .textSelection(.enabled)
                }
                
                HStack {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Sealed with CryptoKit SHA-256")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Secure Enclave status
                HStack {
                    Image(systemName: EnclaveManager.isAvailable ? "lock.fill" : "lock.slash")
                        .font(.caption)
                        .foregroundColor(EnclaveManager.isAvailable ? .green : .yellow)
                    Text(EnclaveManager.isAvailable ? "Secure Enclave available" : "Secure Enclave not available")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Hashing pending")
                        .foregroundColor(.yellow)
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - GPS Card
    
    private var gpsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                Text("GPS / Location")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if video.gpsWaypointCount > 0 {
                    Text("\(video.gpsWaypointCount) waypoints")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Divider().background(.gray.opacity(0.3))
            
            if let lat = video.gpsLatitude, let lng = video.gpsLongitude {
                detailRow(label: "Latitude", value: String(format: "%.6f", lat))
                detailRow(label: "Longitude", value: String(format: "%.6f", lng))
                if let acc = video.gpsAccuracy {
                    detailRow(label: "Accuracy", value: String(format: "±%.0f meters", acc))
                }
                
                // Apple Maps link
                Button(action: openInMaps) {
                    Label("View in Maps", systemImage: "map")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            } else {
                Text("No GPS data recorded")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                Text("Raw Metadata")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            if let json = metadataJSON {
                Text(json)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Export Button
    
    private var exportButton: some View {
        Button(action: {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                EvidenceExporter.presentShareSheet(for: video, presenting: rootVC, metadataJSON: metadataJSON)
            }
        }) {
            HStack {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 16))
                Text("Export Evidence Package")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helpers
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
        }
    }
    
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

#if DEBUG
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView()
            .environmentObject(CameraViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif