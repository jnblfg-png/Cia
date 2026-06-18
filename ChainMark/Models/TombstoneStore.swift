import Foundation

/// A lightweight audit record preserving integrity data for sealed evidence that has been withdrawn.
/// The tombstone ensures the chain-of-custody story is never destroyed — even when the video file
/// is removed from the active timeline.
struct EvidenceTombstone: Identifiable, Codable {
    let id: UUID
    let originalEvidenceId: UUID
    let fileName: String
    let sha256Hash: String?
    let secureEnclaveSignature: String?
    let enclaveKeyFingerprint: String?
    let captureDate: Date
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsAccuracy: Double?
    let duration: TimeInterval
    let withdrawnAt: Date
    let custodyEventType: String  // "withdrawn"
    
    init(from evidence: CapturedVideo) {
        self.id = UUID()
        self.originalEvidenceId = evidence.id
        self.fileName = evidence.fileName
        self.sha256Hash = evidence.sha256Hash
        self.secureEnclaveSignature = evidence.secureEnclaveSignature
        self.enclaveKeyFingerprint = evidence.enclaveKeyFingerprint
        self.captureDate = evidence.captureDate
        self.gpsLatitude = evidence.gpsLatitude
        self.gpsLongitude = evidence.gpsLongitude
        self.gpsAccuracy = evidence.gpsAccuracy
        self.duration = evidence.duration
        self.withdrawnAt = Date()
        self.custodyEventType = "withdrawn"
    }
}

/// Manages tombstone records for withdrawn sealed evidence.
/// Tombstones are persisted to disk so they survive app restarts.
final class TombstoneStore: ObservableObject {
    
    @Published var tombstones: [EvidenceTombstone] = []
    
    private let storeURL: URL
    
    init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storeURL = documentsURL
            .appendingPathComponent("ChainMarkEvidence", isDirectory: true)
            .appendingPathComponent("tombstones.json")
        load()
    }
    
    /// Add a tombstone for withdrawn sealed evidence
    func addTombstone(for evidence: CapturedVideo) {
        let tombstone = EvidenceTombstone(from: evidence)
        DispatchQueue.main.async { [weak self] in
            self?.tombstones.insert(tombstone, at: 0)  // newest first
            self?.save()
        }
    }
    
    /// Number of tombstones on record
    var count: Int { tombstones.count }
    
    // MARK: - Persistence
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(tombstones)
            try data.write(to: storeURL, options: [.completeFileProtection, .atomic])
        } catch {
            print("TombstoneStore: save failed: \(error.localizedDescription)")
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: storeURL)
            tombstones = try decoder.decode([EvidenceTombstone].self, from: data)
        } catch {
            print("TombstoneStore: load failed: \(error.localizedDescription)")
        }
    }
}