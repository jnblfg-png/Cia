import Foundation
import Combine

// MARK: - Auth User Model

/// Represents the authenticated user within the app
struct AuthUser: Codable, Equatable {
    let id: String
    let email: String
    let agencyId: String?
    let role: String?
    let fullName: String?
    
    /// Whether this user has a fully configured profile (agency + role assigned)
    var isActive: Bool {
        agencyId != nil && role != nil
    }
}

// MARK: - Auth State

/// Observable authentication state for the app
@MainActor
final class AuthService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentUser: AuthUser?
    @Published var authState: AuthState = .unknown
    @Published var authError: AuthError?
    
    // MARK: - Enums
    
    enum AuthState: Equatable {
        case unknown
        case authenticated(AuthUser)
        case unauthenticated
        case loading
    }
    
    enum AuthError: LocalizedError, Equatable {
        case signInFailed(String)
        case signUpFailed(String)
        case signOutFailed(String)
        case sessionExpired
        case networkError
        case profileNotFound
        case invalidCredentials
        
        var errorDescription: String? {
            switch self {
            case .signInFailed(let reason): return "Sign in failed: \(reason)"
            case .signUpFailed(let reason): return "Sign up failed: \(reason)"
            case .signOutFailed(let reason): return "Sign out failed: \(reason)"
            case .sessionExpired: return "Session expired. Please sign in again."
            case .networkError: return "Network error. Check your connection."
            case .profileNotFound: return "User profile not found. Contact your agency owner."
            case .invalidCredentials: return "Invalid email or password."
            }
        }
    }
    
    // MARK: - Auth Provider Protocol
    
    /// Abstract auth provider — allows mocking for development and testing
    protocol AuthProvider {
        func signIn(email: String, password: String) async throws -> AuthUser
        func signUp(email: String, password: String, fullName: String) async throws -> AuthUser
        func signOut() async throws
        func restoreSession() async throws -> AuthUser?
        func refreshSession() async throws -> AuthUser?
    }
    
    // MARK: - Properties
    
    private let authProvider: AuthProvider
    
    // MARK: - Initialization
    
    /// Create with a specific auth provider (defaults to SupabaseAuthProvider)
    init(authProvider: AuthProvider? = nil) {
        self.authProvider = authProvider ?? SupabaseAuthProvider()
    }
    
    // MARK: - Public API
    
    /// Attempt to restore a previous session on app launch
    func restoreSession() async {
        authState = .loading
        do {
            if let user = try await authProvider.restoreSession() {
                self.currentUser = user
                authState = .authenticated(user)
            } else {
                authState = .unauthenticated
            }
        } catch {
            authState = .unauthenticated
            authError = .sessionExpired
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        authState = .loading
        authError = nil
        do {
            let user = try await authProvider.signIn(email: email, password: password)
            self.currentUser = user
            authState = .authenticated(user)
        } catch {
            authState = .unauthenticated
            authError = .signInFailed(error.localizedDescription)
        }
    }
    
    /// Sign up a new user (creates auth user and triggers profile creation)
    func signUp(email: String, password: String, fullName: String) async {
        authState = .loading
        authError = nil
        do {
            let user = try await authProvider.signUp(email: email, password: password, fullName: fullName)
            self.currentUser = user
            authState = .authenticated(user)
        } catch {
            authState = .unauthenticated
            authError = .signUpFailed(error.localizedDescription)
        }
    }
    
    /// Sign out the current user
    func signOut() async {
        do {
            try await authProvider.signOut()
            self.currentUser = nil
            authState = .unauthenticated
            authError = nil
        } catch {
            authError = .signOutFailed(error.localizedDescription)
        }
    }
    
    /// Refresh the current session token
    func refreshSession() async {
        guard case .authenticated = authState else { return }
        do {
            if let user = try await authProvider.refreshSession() {
                self.currentUser = user
                authState = .authenticated(user)
            }
        } catch {
            // Session refresh failed — user may need to re-authenticate
            authState = .unauthenticated
            currentUser = nil
            authError = .sessionExpired
        }
    }
}

// MARK: - Supabase Auth Provider

/// Real Supabase auth provider using URLSession
/// Wraps the Supabase Auth REST API directly (avoids external SDK dependency until C1 is live)
struct SupabaseAuthProvider: AuthService.AuthProvider {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "apikey": Configuration.supabaseAnonKey,
            "Content-Type": "application/json"
        ]
        return URLSession(configuration: config)
    }()
    
    private let authBaseURL: URL = {
        Configuration.supabaseURL.appendingPathComponent("auth/v1")
    }()
    
    func signIn(email: String, password: String) async throws -> AuthUser {
        let url = authBaseURL.appendingPathComponent("token")
            .appendingPathComponent("grant")
            .appendingPathComponent("password")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthService.AuthError.invalidCredentials
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let userId = json?["user"] as? [String: Any]
        let id = userId?["id"] as? String ?? ""
        
        return AuthUser(
            id: id,
            email: email,
            agencyId: nil,  // Fetched from profile
            role: nil,
            fullName: nil
        )
    }
    
    func signUp(email: String, password: String, fullName: String) async throws -> AuthUser {
        let url = authBaseURL.appendingPathComponent("signup")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "data": ["full_name": fullName]
        ])
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthService.AuthError.signUpFailed("Could not create account")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let userId = json?["id"] as? String ?? ""
        
        return AuthUser(
            id: userId,
            email: email,
            agencyId: nil,
            role: nil,
            fullName: fullName
        )
    }
    
    func signOut() async throws {
        let url = authBaseURL.appendingPathComponent("logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, _) = try await session.data(for: request)
    }
    
    func restoreSession() async throws -> AuthUser? {
        // Session restoration requires a stored refresh token
        // Placeholder — will be implemented with Keychain storage
        return nil
    }
    
    func refreshSession() async throws -> AuthUser? {
        // Token refresh requires stored refresh token
        return nil
    }
}

// MARK: - Mock Auth Provider

/// Mock auth provider for development/testing without a live backend
struct MockAuthProvider: AuthService.AuthProvider {
    func signIn(email: String, password: String) async throws -> AuthUser {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        
        guard password.count >= 6 else {
            throw AuthService.AuthError.invalidCredentials
        }
        
        return AuthUser(
            id: "mock-user-id",
            email: email,
            agencyId: "mock-agency-id",
            role: "investigator",
            fullName: email.components(separatedBy: "@").first ?? "User"
        )
    }
    
    func signUp(email: String, password: String, fullName: String) async throws -> AuthUser {
        try await Task.sleep(nanoseconds: 500_000_000)
        return AuthUser(
            id: "mock-user-id",
            email: email,
            agencyId: nil,
            role: "owner",
            fullName: fullName
        )
    }
    
    func signOut() async throws {
        // No-op in mock
    }
    
    func restoreSession() async throws -> AuthUser? {
        return AuthUser(
            id: "mock-session-user",
            email: "mock@chainmark.test",
            agencyId: "mock-agency-id",
            role: "investigator",
            fullName: "Mock User"
        )
    }
    
    func refreshSession() async throws -> AuthUser? {
        return try await restoreSession()
    }
}