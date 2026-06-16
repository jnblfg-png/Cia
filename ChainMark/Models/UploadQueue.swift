import Foundation

// MARK: - Upload Queue Item

/// Represents a single item in the local pending-upload queue
/// Evidence is captured and sealed offline, then queued for upload when connectivity is available
struct UploadQueueItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let localFilePath: String
    
    /// The case this evidence belongs to (set when available)
    var caseId: String?
    
    /// Current upload state
    var state: UploadState
    
    /// Number of retry attempts so far
    var retryCount: Int
    
    /// Timestamp when the item was first queued
    let createdAt: Date
    
    /// Timestamp of the last upload attempt
    var lastAttemptAt: Date?
    
    /// Error message from the last failed attempt
    var lastError: String?
    
    /// Pre-serialized registration request (ready to send)
    var registrationPayload: Data?
    
    /// The media type of the evidence
    var mediaType: String
    
    init(
        id: UUID = UUID(),
        fileName: String,
        localFilePath: String,
        caseId: String? = nil,
        mediaType: String = "video",
        registrationPayload: Data? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.localFilePath = localFilePath
        self.caseId = caseId
        self.state = .pending
        self.retryCount = 0
        self.createdAt = Date()
        self.mediaType = mediaType
        self.registrationPayload = registrationPayload
    }
    
    // MARK: - Upload States
    
    enum UploadState: String, Codable, Equatable, CaseIterable {
        /// Waiting to be uploaded (queued)
        case pending
        /// Currently uploading
        case uploading
        /// Upload succeeded
        case completed
        /// Upload failed — eligible for retry
        case failed
        /// Upload permanently failed after max retries
        case abandoned
    }
    
    // MARK: - Retry Logic
    
    /// Whether this item can be retried
    var isRetryable: Bool {
        state == .failed && retryCount < Configuration.maxUploadRetries
    }
    
    /// Calculate delay before next retry (exponential backoff)
    var retryDelay: TimeInterval {
        Configuration.retryBaseDelay * pow(2.0, Double(retryCount))
    }
    
    /// Mark as failed with error
    mutating func markFailed(error: String?) {
        state = .failed
        retryCount += 1
        lastAttemptAt = Date()
        lastError = error
        
        if retryCount >= Configuration.maxUploadRetries {
            state = .abandoned
        }
    }
    
    /// Mark as completed successfully
    mutating func markCompleted() {
        state = .completed
        lastAttemptAt = Date()
        lastError = nil
    }
    
    /// Mark as currently uploading
    mutating func markUploading() {
        state = .uploading
        lastAttemptAt = Date()
    }
    
    /// Reset for retry
    mutating func prepareForRetry() {
        if isRetryable {
            state = .pending
        }
    }
}

// MARK: - Upload Queue

/// A persistent, offline-first queue for evidence items awaiting upload
/// Automatically serializes to disk so items survive app restarts
final class UploadQueue: ObservableObject {
    
    // MARK: - Published State
    
    @Published var items: [UploadQueueItem] = []
    @Published var isProcessing = false
    
    /// Items ready for upload (pending or failed and retryable)
    var pendingItems: [UploadQueueItem] {
        items.filter { $0.state == .pending || ($0.state == .failed && $0.isRetryable) }
    }
    
    /// Items currently uploading
    var uploadingItems: [UploadQueueItem] {
        items.filter { $0.state == .uploading }
    }
    
    /// Completed items
    var completedItems: [UploadQueueItem] {
        items.filter { $0.state == .completed }
    }
    
    /// Failed items (not yet abandoned)
    var failedItems: [UploadQueueItem] {
        items.filter { $0.state == .failed && $0.isRetryable }
    }
    
    /// Abandoned items (exhausted retries)
    var abandonedItems: [UploadQueueItem] {
        items.filter { $0.state == .abandoned }
    }
    
    /// Total count
    var totalCount: Int { items.count }
    
    /// Count of items that have not yet succeeded
    var pendingCount: Int { items.filter { $0.state != .completed }.count }
    
    // MARK: - Persistence
    
    private let storageManager: SecureStorageManager
    private let queueURL: URL
    
    private let queueFileName = "upload_queue.json"
    
    // MARK: - Initialization
    
    init(storageManager: SecureStorageManager = SecureStorageManager()) {
        self.storageManager = storageManager
        
        // Queue file stored in the app-private ChainMarkEvidence directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.queueURL = documentsURL
            .appendingPathComponent("ChainMarkEvidence", isDirectory: true)
            .appendingPathComponent(queueFileName)
        
        loadFromDisk()
    }
    
    // MARK: - Queue Operations
    
    /// Enqueue a new evidence item for upload
    func enqueue(_ item: UploadQueueItem) {
        // Prevent duplicates by file path
        guard !items.contains(where: { $0.localFilePath == item.localFilePath && $0.state != .abandoned }) else {
            print("UploadQueue: Item already queued: \(item.fileName)")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.items.insert(item, at: 0)  // Newest first
            self?.saveToDisk()
        }
    }
    
    /// Remove an item from the queue
    func removeItem(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.items.removeAll { $0.id == id }
            self?.saveToDisk()
        }
    }
    
    /// Clear all completed items
    func clearCompleted() {
        DispatchQueue.main.async { [weak self] in
            self?.items.removeAll { $0.state == .completed || $0.state == .abandoned }
            self?.saveToDisk()
        }
    }
    
    /// Reset all failed items to pending for retry
    func resetFailedItems() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in self.items.indices where self.items[i].state == .failed && self.items[i].isRetryable {
                self.items[i].prepareForRetry()
            }
            self.saveToDisk()
        }
    }
    
    /// Update the state of a specific item
    func updateItem(_ id: UUID, update: (inout UploadQueueItem) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            update(&self.items[index])
            self.saveToDisk()
        }
    }
    
    /// Get the next batch of items ready for upload
    func nextBatch(limit: Int = Configuration.maxConcurrentUploads) -> [UploadQueueItem] {
        let readyItems = items.filter { item in
            item.state == .pending || (item.state == .failed && item.isRetryable)
        }
        return Array(readyItems.prefix(limit))
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(items)
            try data.write(to: queueURL, options: [.completeFileProtection, .atomic])
        } catch {
            print("UploadQueue: Failed to save queue: \(error.localizedDescription)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: queueURL.path) else {
            self.items = []
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let data = try Data(contentsOf: queueURL)
            let decoded = try decoder.decode([UploadQueueItem].self, from: data)
            self.items = decoded
        } catch {
            print("UploadQueue: Failed to load queue: \(error.localizedDescription)")
            self.items = []
        }
    }
}