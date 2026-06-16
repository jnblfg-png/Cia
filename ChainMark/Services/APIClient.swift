import Foundation

// MARK: - API Request/Response Models

/// Evidence registration request — sent after a video has been uploaded to Supabase Storage
struct RegisterEvidenceRequest: Codable {
    let caseId: String
    let mediaType: String          // "photo", "video", "audio"
    let filePath: String           // Path in Supabase Storage
    let fileHash: String           // SHA-256 of the file (computed client-side)
    let fileSize: Int64
    let mimeType: String
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsAccuracy: Double?
    let capturedAt: String         // ISO 8601 timestamp
    let deviceClockTime: String    // Device time at capture
    let secureEnclaveSignature: String?
    let metadata: [String: Any]?
    let custodyNotes: String?
    
    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case mediaType = "media_type"
        case filePath = "file_path"
        case fileHash = "file_hash"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case gpsLatitude = "gps_latitude"
        case gpsLongitude = "gps_longitude"
        case gpsAccuracy = "gps_accuracy"
        case capturedAt = "captured_at"
        case deviceClockTime = "device_clock_time"
        case secureEnclaveSignature = "secure_enclave_signature"
        case metadata
        case custodyNotes = "custody_notes"
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(caseId, forKey: .caseId)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(fileHash, forKey: .fileHash)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(gpsLatitude, forKey: .gpsLatitude)
        try container.encodeIfPresent(gpsLongitude, forKey: .gpsLongitude)
        try container.encodeIfPresent(gpsAccuracy, forKey: .gpsAccuracy)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(deviceClockTime, forKey: .deviceClockTime)
        try container.encodeIfPresent(secureEnclaveSignature, forKey: .secureEnclaveSignature)
        try container.encodeIfPresent(custodyNotes, forKey: .custodyNotes)
        // Metadata is encoded as JSON string for Supabase JSONB
        if let metadata = metadata, let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            try container.encode(jsonString, forKey: .metadata)
        }
    }
    
    init(caseId: String, mediaType: String, filePath: String, fileHash: String,
         fileSize: Int64, mimeType: String, gpsLatitude: Double? = nil,
         gpsLongitude: Double? = nil, gpsAccuracy: Double? = nil,
         capturedAt: String, deviceClockTime: String,
         secureEnclaveSignature: String? = nil, metadata: [String: Any]? = nil,
         custodyNotes: String? = nil) {
        self.caseId = caseId
        self.mediaType = mediaType
        self.filePath = filePath
        self.fileHash = fileHash
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsAccuracy = gpsAccuracy
        self.capturedAt = capturedAt
        self.deviceClockTime = deviceClockTime
        self.secureEnclaveSignature = secureEnclaveSignature
        self.metadata = metadata
        self.custodyNotes = custodyNotes
    }
}

/// Response from register_evidence edge function
struct RegisterEvidenceResponse: Codable {
    let evidenceId: String
    let custodyLogEntryId: Int
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case evidenceId = "evidence_id"
        case custodyLogEntryId = "custody_log_entry_id"
        case status
    }
}

/// Report generation request
struct GenerateReportRequest: Codable {
    let caseId: String
    let observationIds: [String]
    let evidenceIds: [String]
    let includeGPSSummary: Bool
    let customInstructions: String?
    
    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case observationIds = "observation_ids"
        case evidenceIds = "evidence_ids"
        case includeGPSSummary = "include_gps_summary"
        case customInstructions = "custom_instructions"
    }
}

/// Response from generate_report edge function
struct GenerateReportResponse: Codable {
    let reportId: String
    let title: String
    let content: String
    let status: String          // Always "draft" initially
    let aiModelUsed: String?
    let warning: String?        // Any AI warnings about gaps
    
    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case title
        case content
        case status
        case aiModelUsed = "ai_model_used"
        case warning
    }
}

/// Report finalization request
struct FinalizeReportRequest: Codable {
    let reportId: String
    let confirmHash: String     // SHA-256 of the report content the investigator confirms
    
    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case confirmHash = "confirm_hash"
    }
}

/// Response from finalize_report edge function
struct FinalizeReportResponse: Codable {
    let reportId: String
    let version: Int
    let status: String          // "finalized"
    let finalizedAt: String
    let hash: String
    
    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case version
        case status
        case finalizedAt = "finalized_at"
        case hash
    }
}

// MARK: - Error Types

/// Errors from the API client
enum APIError: LocalizedError {
    case invalidURL
    case requestFailed(Int, String)    // HTTP status + body
    case decodingFailed(String)
    case encodingFailed(String)
    case networkError(String)
    case unauthorized
    case notFound
    case serverError(String)
    case edgeFunctionUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .requestFailed(let code, let body): return "Request failed (\(code)): \(body)"
        case .decodingFailed(let reason): return "Response parsing failed: \(reason)"
        case .encodingFailed(let reason): return "Request encoding failed: \(reason)"
        case .networkError(let reason): return "Network error: \(reason)"
        case .unauthorized: return "Authentication required"
        case .notFound: return "Resource not found"
        case .serverError(let msg): return "Server error: \(msg)"
        case .edgeFunctionUnavailable(let name): return "Edge function '\(name)' unavailable"
        }
    }
}

// MARK: - API Client Protocol

/// Protocol defining all backend API endpoints
/// Enables mocking and testing without a live backend
protocol APIClientProtocol {
    /// Register a new evidence item on the backend
    func registerEvidence(_ request: RegisterEvidenceRequest) async throws -> RegisterEvidenceResponse
    
    /// Generate an AI report from observations and evidence
    func generateReport(_ request: GenerateReportRequest) async throws -> GenerateReportResponse
    
    /// Finalize a draft report
    func finalizeReport(_ request: FinalizeReportRequest) async throws -> FinalizeReportResponse
    
    /// Check if the API is reachable
    func healthCheck() async throws -> Bool
}

// MARK: - Concrete API Client (Supabase Edge Functions)

/// Real API client that calls Supabase Edge Functions
final class APIClient: APIClientProtocol {
    
    private let session: URLSession
    private let authTokenProvider: () -> String?
    
    init(authTokenProvider: @escaping () -> String?) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.authTokenProvider = authTokenProvider
    }
    
    func registerEvidence(_ request: RegisterEvidenceRequest) async throws -> RegisterEvidenceResponse {
        let url = Configuration.registerEvidenceURL
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth token
        if let token = authTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }
        
        return try await performRequest(urlRequest)
    }
    
    func generateReport(_ request: GenerateReportRequest) async throws -> GenerateReportResponse {
        let url = Configuration.generateReportURL
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }
        
        return try await performRequest(urlRequest)
    }
    
    func finalizeReport(_ request: FinalizeReportRequest) async throws -> FinalizeReportResponse {
        let url = Configuration.finalizeReportURL
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }
        
        return try await performRequest(urlRequest)
    }
    
    func healthCheck() async throws -> Bool {
        let url = Configuration.edgeFunctionsURL.appendingPathComponent("health")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 5
        
        do {
            let (_, response) = try await session.data(for: urlRequest)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Request Execution
    
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw APIError.networkError("No internet connection")
            }
            throw APIError.networkError(error.localizedDescription)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 500...599:
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.serverError(body)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(httpResponse.statusCode, body)
        }
    }
}

// MARK: - Mock API Client

/// Mock API client for development/testing
final class MockAPIClient: APIClientProtocol {
    
    var shouldFail: Bool = false
    var simulateDelay: TimeInterval = 0.3
    
    func registerEvidence(_ request: RegisterEvidenceRequest) async throws -> RegisterEvidenceResponse {
        if shouldFail { throw APIError.serverError("Mock failure") }
        try await Task.sleep(nanoseconds: UInt64(simulateDelay * 1_000_000_000))
        return RegisterEvidenceResponse(
            evidenceId: UUID().uuidString,
            custodyLogEntryId: Int.random(in: 1...1000),
            status: "registered"
        )
    }
    
    func generateReport(_ request: GenerateReportRequest) async throws -> GenerateReportResponse {
        if shouldFail { throw APIError.serverError("Mock failure") }
        try await Task.sleep(nanoseconds: UInt64(simulateDelay * 2 * 1_000_000_000))
        return GenerateReportResponse(
            reportId: UUID().uuidString,
            title: "Surveillance Report - \(ISO8601DateFormatter().string(from: Date()))",
            content: "# Surveillance Report\n\n## Observations\n- Subject observed at location at 14:30\n- Blue sedan arrived at 15:45\n\n## GAPS / NEEDS CONFIRMATION\n- License plate number not confirmed\n- Subject identity not independently verified",
            status: "draft",
            aiModelUsed: "claude-3-sonnet-mock",
            warning: "Some observations may need investigator confirmation"
        )
    }
    
    func finalizeReport(_ request: FinalizeReportRequest) async throws -> FinalizeReportResponse {
        if shouldFail { throw APIError.serverError("Mock failure") }
        try await Task.sleep(nanoseconds: UInt64(simulateDelay * 1_000_000_000))
        return FinalizeReportResponse(
            reportId: request.reportId,
            version: 1,
            status: "finalized",
            finalizedAt: ISO8601DateFormatter().string(from: Date()),
            hash: "sha256-mock-hash-\(UUID().uuidString.prefix(8))"
        )
    }
    
    func healthCheck() async throws -> Bool {
        return !shouldFail
    }
}