import Foundation
import Combine

/// Central Supabase client singleton that ties together auth, API, and upload queue
/// Provides a single entry point for all backend interactions
@MainActor
final class SupabaseClient: ObservableObject {
    
    // MARK: - Published State
    
    /// Whether the app is connected to a live backend
    @Published var isConnected: Bool = false
    
    /// Whether a health check is in progress
    @Published var isCheckingHealth: Bool = false
    
    // MARK: - Sub-Services
    
    let auth: AuthService
    let api: APIClientProtocol
    let uploadQueue: UploadQueue
    
    // MARK: - Singleton
    
    static let shared = SupabaseClient()
    
    // MARK: - Initialization
    
    /// Private init — use shared singleton
    /// Uses MockAPIClient by default; switch to real APIClient when backend is live
    private init() {
        // For development: use MockAuthProvider + MockAPIClient
        // Switch to real providers when backend is available:
        //   auth = AuthService(authProvider: SupabaseAuthProvider())
        //   api = APIClient(authTokenProvider: { ... })
        
        self.auth = AuthService(authProvider: MockAuthProvider())
        self.api = MockAPIClient()
        self.uploadQueue = UploadQueue()
        
        // Listen for auth state changes
        setupBindings()
    }
    
    /// Configure with live backend providers
    /// Called when the backend is ready for production use
    func configureForProduction() {
        // Would swap providers here:
        // let authProvider = SupabaseAuthProvider()
        // auth = AuthService(authProvider: authProvider)
        // api = APIClient(authTokenProvider: { /* get current token */ })
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // When auth state changes, re-check connection
        Task { [weak self] in
            for await _ in self?.auth.$authState.values ?? AsyncStream<AuthService.AuthState>.empty {
                if case .authenticated = self?.auth.authState {
                    self?.checkConnection()
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    /// Check connectivity to the backend
    func checkConnection() async {
        isCheckingHealth = true
        do {
            isConnected = try await api.healthCheck()
        } catch {
            isConnected = false
        }
        isCheckingHealth = false
    }
    
    /// Start processing the upload queue (uploads pending items)
    func processUploadQueue() async {
        guard !uploadQueue.isProcessing else { return }
        
        await MainActor.run { uploadQueue.isProcessing = true }
        
        let batch = uploadQueue.nextBatch()
        
        for var item in batch {
            await uploadQueue.updateItem(item.id) { $0.markUploading() }
            
            do {
                // Build registration request from the queued item's payload
                if let payloadData = item.registrationPayload {
                    let request = try JSONDecoder().decode(RegisterEvidenceRequest.self, from: payloadData)
                    let response = try await api.registerEvidence(request)
                    print("UploadQueue: Evidence registered: \(response.evidenceId)")
                    await uploadQueue.updateItem(item.id) { $0.markCompleted() }
                } else {
                    // No payload means we need to rebuild it from the file
                    await uploadQueue.updateItem(item.id) {
                        $0.markFailed(error: "No registration payload")
                    }
                }
            } catch {
                await uploadQueue.updateItem(item.id) {
                    $0.markFailed(error: error.localizedDescription)
                }
            }
        }
        
        await MainActor.run { uploadQueue.isProcessing = false }
    }
    
    // MARK: - Convenience Methods
    
    /// Sign in and check backend connectivity
    func signIn(email: String, password: String) async {
        await auth.signIn(email: email, password: password)
        if case .authenticated = auth.authState {
            await checkConnection()
        }
    }
    
    /// Sign out and clear connection state
    func signOut() async {
        await auth.signOut()
        isConnected = false
    }
    
    /// Queue evidence for upload after capture completes
    func queueEvidenceForUpload(
        fileName: String,
        localFilePath: String,
        caseId: String?,
        registrationRequest: RegisterEvidenceRequest?
    ) {
        var payloadData: Data?
        if let request = registrationRequest {
            payloadData = try? JSONEncoder().encode(request)
        }
        
        let item = UploadQueueItem(
            fileName: fileName,
            localFilePath: localFilePath,
            caseId: caseId,
            registrationPayload: payloadData
        )
        
        uploadQueue.enqueue(item)
    }
}