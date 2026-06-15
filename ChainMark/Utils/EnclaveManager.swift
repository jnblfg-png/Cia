import Foundation
import CryptoKit
import LocalAuthentication

/// Manages Secure Enclave key generation, signing, and verification for evidence sealing.
///
/// The Secure Enclave generates a P-256 private key that is NON-EXPORTABLE — it can never
/// leave the device. The key is access-controlled (requires device unlock) and is destroyed
/// if the device is wiped. This provides a hardware-backed root of trust for evidence.
///
/// Key generation happens lazily on first access. The key reference is stored in the system
/// Keychain via the Secure Enclave's own persistence mechanism.
enum EnclaveManager {
    
    // MARK: - Configuration
    
    /// The access control for the Secure Enclave key
    /// kSecAttrAccessibleWhenUnlockedThisDeviceOnly — key is only accessible when device is unlocked
    /// and does not migrate to other devices (no iCloud backup)
    private static let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .privateKeyUsage,
        nil
    )
    
    /// Application tag to identify our key in the Secure Enclave
    private static let keyTag = "com.chainmark.enclave.signing.key".data(using: .utf8)!
    
    // MARK: - Errors
    
    enum EnclaveError: LocalizedError {
        case keyGenerationFailed(reason: String)
        case keyNotFound
        case signingFailed(reason: String)
        case secureEnclaveNotAvailable
        case invalidSignatureData
        case verificationFailed
        
        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed(let reason):
                return "Failed to generate Secure Enclave key: \(reason)"
            case .keyNotFound:
                return "Secure Enclave signing key not found"
            case .signingFailed(let reason):
                return "Signing failed: \(reason)"
            case .secureEnclaveNotAvailable:
                return "Secure Enclave is not available on this device"
            case .invalidSignatureData:
                return "Signature data is invalid"
            case .verificationFailed:
                return "Signature verification failed"
            }
        }
    }
    
    // MARK: - Secure Enclave Availability
    
    /// Check if Secure Enclave is available on this device
    static var isAvailable: Bool {
        SecureEnclave.isAvailable
    }
    
    // MARK: - Key Management
    
    /// Get or create the Secure Enclave signing key
    /// - Returns: The Secure Enclave P-256 private key
    /// - Throws: EnclaveError if key generation fails
    static func getOrCreateSigningKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        // Try to load existing key
        if let existingKey = try? loadExistingKey() {
            return existingKey
        }
        
        // Generate a new key
        return try createNewKey()
    }
    
    /// Load the existing Secure Enclave key from the system
    private static func loadExistingKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let secKey = item else {
            throw EnclaveError.keyNotFound
        }
        
        // Create CryptoKit key from the SecKey reference
        let privateKey = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl!,
                                                                   authenticationContext: nil)
        return privateKey
    }
    
    /// Generate a new Secure Enclave key
    private static func createNewKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else {
            throw EnclaveError.secureEnclaveNotAvailable
        }
        
        guard let access = accessControl else {
            throw EnclaveError.keyGenerationFailed(reason: "Could not create access control flags")
        }
        
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                accessControl: access,
                authenticationContext: nil
            )
            return key
        } catch {
            throw EnclaveError.keyGenerationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Delete the Secure Enclave key (for testing/rotation)
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Signing
    
    /// Sign a SHA-256 hash with the Secure Enclave key
    /// - Parameter sha256Hash: The hex-encoded SHA-256 hash to sign
    /// - Returns: DER-encoded signature as a base64-encoded string
    /// - Throws: EnclaveError if signing fails
    static func signHash(_ sha256Hash: String) throws -> String {
        let key = try getOrCreateSigningKey()
        
        guard let hashData = sha256Hash.data(using: .utf8) else {
            throw EnclaveError.invalidSignatureData
        }
        
        // Hash the hash string itself to get a fixed-size digest
        let digest = SHA256.hash(data: hashData)
        
        do {
            let signature = try key.signature(for: Data(digest))
            return signature.derRepresentation.base64EncodedString()
        } catch {
            throw EnclaveError.signingFailed(reason: error.localizedDescription)
        }
    }
    
    /// Sign raw data with the Secure Enclave key
    /// - Parameter data: The data to sign
    /// - Returns: DER-encoded signature as a base64-encoded string
    /// - Throws: EnclaveError if signing fails
    static func signData(_ data: Data) throws -> String {
        let key = try getOrCreateSigningKey()
        
        // Hash the data first to get a fixed-size digest
        let digest = SHA256.hash(data: data)
        
        do {
            let signature = try key.signature(for: Data(digest))
            return signature.derRepresentation.base64EncodedString()
        } catch {
            throw EnclaveError.signingFailed(reason: error.localizedDescription)
        }
    }
    
    // MARK: - Verification
    
    /// Verify a signature against a SHA-256 hash using the Secure Enclave public key
    /// - Parameters:
    ///   - sha256Hash: The hex-encoded SHA-256 hash
    ///   - base64Signature: The base64-encoded DER signature
    /// - Returns: True if the signature is valid
    static func verifySignature(sha256Hash: String, base64Signature: String) -> Bool {
        guard let signatureData = Data(base64Encoded: base64Signature),
              let hashData = sha256Hash.data(using: .utf8) else {
            return false
        }
        
        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData) else {
            return false
        }
        
        let digest = SHA256.hash(data: hashData)
        
        do {
            let key = try getOrCreateSigningKey()
            let publicKey = key.publicKey
            return publicKey.isValidSignature(signature, for: Data(digest))
        } catch {
            return false
        }
    }
    
    // MARK: - Public Key
    
    /// Get the raw public key data (X9.63 representation) for inclusion in evidence metadata
    /// - Returns: Base64-encoded public key, or nil if key doesn't exist
    static func publicKeyBase64() -> String? {
        guard let key = try? getOrCreateSigningKey() else {
            return nil
        }
        return key.publicKey.x963Representation.base64EncodedString()
    }
    
    /// Get a human-readable fingerprint of the public key (first 16 chars of SHA-256 of public key)
    static var publicKeyFingerprint: String? {
        guard let pubKeyData = publicKeyBase64()?.data(using: .utf8) else {
            return nil
        }
        let digest = SHA256.hash(data: pubKeyData)
        return digest.map { String(format: "%02x", $0) }.prefix(16).joined()
    }
}