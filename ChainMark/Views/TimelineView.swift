import SwiftUI
import AVFoundation

/// Chronological timeline of all locally captured evidence
/// Sorted newest-first with seal status indicators
struct TimelineView: View {
    @EnvironmentObject private var cameraViewModel: CameraViewModel
    @State private var selectedVideo: CapturedVideo?
    @State private var showDetail = false
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if cameraViewModel.recordedVideos.isEmpty {
                    emptyStateView
                } else {
                    videoList
                }
            }
            .navigationTitle("Evidence Timeline")
            .navigationBarTitleTextColor(.white)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        sealStatusBadge
                        if !cameraViewModel.recordedVideos.isEmpty {
                            Button(action: { showCamera = true }) {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                            }
                        }
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
    }
    
    @State private var showCamera = false
    
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
                            selectedVideo = video
                            showDetail = true
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
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Video info card
                        videoInfoCard
                        
                        // Cryptographic seal card
                        cryptoSealCard
                        
                        // GPS data card
                        gpsCard
                        
                        // Metadata section
                        metadataSection
                        
                        // Export button
                        exportButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Evidence Detail")
            .navigationBarTitleTextColor(.white)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
            .onAppear {
                loadMetadata()
            }
        }
        .preferredColorScheme(.dark)
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