import Foundation
import AuthenticationServices
import AppKit

// MARK: - Cloud Storage Protocol

/// Protocol that all cloud storage providers must implement
protocol CloudStorageProvider: AnyObject {
    var name: String { get }
    var isAuthenticated: Bool { get }
    var isUploading: Bool { get }
    var uploadProgress: Double { get }
    
    func authenticate() async throws
    func uploadFile(_ fileURL: URL, deleteAfterUpload: Bool) async throws -> CloudUploadResult
    func signOut()
}

// MARK: - Upload Result

struct CloudUploadResult {
    let fileID: String
    let shareURL: String?
    let provider: String
}

// MARK: - Unified Cloud Storage Manager

/// Central manager that coordinates multiple cloud storage providers
final class CloudStorageManager: ObservableObject {
    static let shared = CloudStorageManager()
    
    // Available providers
    private(set) lazy var googleDrive = GoogleDriveProvider()
    private(set) lazy var iCloudDrive = ICloudDriveProvider()
    
    // All providers
    private var allProviders: [CloudStorageProvider] {
        [googleDrive, iCloudDrive]
    }
    
    // Published state
    @Published var activeUploads: [String: Double] = [:] // provider name -> progress
    @Published var lastUploadError: String?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Upload to all enabled providers
    func uploadToEnabledProviders(_ fileURL: URL, settings: UploadSettings) async -> [CloudUploadResult] {
        var results: [CloudUploadResult] = []
        
        // Upload to Google Drive if enabled
        if settings.googleDriveEnabled && googleDrive.isAuthenticated {
            do {
                let result = try await googleDrive.uploadFile(fileURL, deleteAfterUpload: false)
                results.append(result)
            } catch {
                await handleUploadError("Google Drive", error)
            }
        }
        
        // Upload to iCloud if enabled (actually just moves the file)
        if settings.iCloudEnabled {
            do {
                let result = try await iCloudDrive.uploadFile(fileURL, deleteAfterUpload: settings.deleteAfterUpload)
                results.append(result)
            } catch {
                await handleUploadError("iCloud Drive", error)
            }
        }
        
        // Delete local file if requested and at least one upload succeeded
        if settings.deleteAfterUpload && !results.isEmpty && !settings.iCloudEnabled {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        return results
    }
    
    /// Upload to specific provider
    func upload(_ fileURL: URL, to provider: CloudProvider, deleteAfterUpload: Bool = false) async throws -> CloudUploadResult {
        let storageProvider: CloudStorageProvider
        
        switch provider {
        case .googleDrive:
            storageProvider = googleDrive
        case .iCloud:
            storageProvider = iCloudDrive
        }
        
        guard storageProvider.isAuthenticated else {
            throw CloudError.notAuthenticated(provider.rawValue)
        }
        
        return try await storageProvider.uploadFile(fileURL, deleteAfterUpload: deleteAfterUpload)
    }
    
    /// Get authentication status for a provider
    func isAuthenticated(_ provider: CloudProvider) -> Bool {
        switch provider {
        case .googleDrive:
            return googleDrive.isAuthenticated
        case .iCloud:
            return iCloudDrive.isAuthenticated
        }
    }
    
    /// Check if any uploads are in progress
    var isUploading: Bool {
        allProviders.contains { $0.isUploading }
    }
    
    // MARK: - Private Helpers
    
    private func handleUploadError(_ provider: String, _ error: Error) async {
        await MainActor.run {
            lastUploadError = "\(provider): \(error.localizedDescription)"
        }
    }
}

// MARK: - Upload Settings

struct UploadSettings {
    var googleDriveEnabled: Bool
    var iCloudEnabled: Bool
    var deleteAfterUpload: Bool
    var generateShareLinks: Bool
    
    static var `default`: UploadSettings {
        UploadSettings(
            googleDriveEnabled: false,
            iCloudEnabled: false,
            deleteAfterUpload: false,
            generateShareLinks: true
        )
    }
}

// MARK: - Cloud Provider Enum

enum CloudProvider: String, Codable, CaseIterable {
    case googleDrive = "Google Drive"
    case iCloud = "iCloud Drive"
    
    var icon: String {
        switch self {
        case .googleDrive: return "cloud.fill"
        case .iCloud: return "icloud.fill"
        }
    }
}

// MARK: - Cloud Errors

enum CloudError: LocalizedError {
    case notAuthenticated(String)
    case uploadFailed(String)
    case invalidURL
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated(let provider):
            return "Not authenticated with \(provider)"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .invalidURL:
            return "Invalid URL"
        case .fileNotFound:
            return "File not found"
        }
    }
}

// MARK: - Google Drive Provider

final class GoogleDriveProvider: NSObject, CloudStorageProvider, ObservableObject {
    let name = "Google Drive"
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isUploading = false
    @Published private(set) var uploadProgress: Double = 0.0
    
    private var accessToken: String?
    private var refreshToken: String?
    
    // Google OAuth Configuration
    // ⚠️ Replace these with your actual credentials from Google Cloud Console
    private let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    private let clientSecret = "YOUR_CLIENT_SECRET"
    private let redirectURI = "com.yourdomain.localloom:/oauth2callback"
    
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"
    
    override init() {
        super.init()
        loadStoredTokens()
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        let authURL = buildAuthURL()
        
        guard let url = URL(string: authURL) else {
            throw CloudError.invalidURL
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.yourdomain.localloom"
            ) { [weak self] callbackURL, error in
                guard let self = self else {
                    continuation.resume(throwing: CloudError.uploadFailed("Session ended"))
                    return
                }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: CloudError.invalidURL)
                    return
                }
                
                Task {
                    do {
                        try await self.handleAuthCallback(callbackURL)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    
    private func buildAuthURL() -> String {
        let scope = "https://www.googleapis.com/auth/drive.file"
        let params = [
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "response_type": "code",
            "scope": scope,
            "access_type": "offline",
            "prompt": "consent"
        ]
        
        let queryString = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        return "https://accounts.google.com/o/oauth2/v2/auth?\(queryString)"
    }
    
    private func handleAuthCallback(_ url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CloudError.uploadFailed("No authorization code")
        }
        
        try await exchangeCodeForToken(code)
    }
    
    private func exchangeCodeForToken(_ code: String) async throws {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        
        let bodyString = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = response.accessToken
            self.refreshToken = response.refreshToken
            self.isAuthenticated = true
            self.saveTokens()
        }
    }
    
    // MARK: - File Upload
    
    func uploadFile(_ fileURL: URL, deleteAfterUpload: Bool) async throws -> CloudUploadResult {
        guard let accessToken = accessToken else {
            throw CloudError.notAuthenticated("Google Drive")
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CloudError.fileNotFound
        }
        
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                isUploading = false
                uploadProgress = 0.0
            }
        }
        
        let fileName = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        
        // Update progress
        await MainActor.run { uploadProgress = 0.2 }
        
        // Create metadata
        let metadata: [String: Any] = [
            "name": fileName,
            "mimeType": "video/quicktime"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        
        // Build multipart request
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        await MainActor.run { uploadProgress = 0.5 }
        
        // Create request
        var request = URLRequest(url: URL(string: "\(uploadEndpoint)?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudError.uploadFailed("HTTP error")
        }
        
        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        
        await MainActor.run { uploadProgress = 0.8 }
        
        // Generate share link
        let shareURL = try await generateShareLink(uploadResponse.id)
        
        await MainActor.run { uploadProgress = 1.0 }
        
        // Delete local file if requested
        if deleteAfterUpload {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        return CloudUploadResult(
            fileID: uploadResponse.id,
            shareURL: shareURL,
            provider: name
        )
    }
    
    private func generateShareLink(_ fileID: String) async throws -> String {
        guard let accessToken = accessToken else {
            throw CloudError.notAuthenticated("Google Drive")
        }
        
        let permissionURL = "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions"
        var request = URLRequest(url: URL(string: permissionURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let permission = ["role": "reader", "type": "anyone"]
        request.httpBody = try JSONSerialization.data(withJSONObject: permission)
        
        _ = try await URLSession.shared.data(for: request)
        
        return "https://drive.google.com/file/d/\(fileID)/view"
    }
    
    // MARK: - Token Management
    
    private func saveTokens() {
        let keychain = KeychainHelper.shared
        if let accessToken = accessToken {
            keychain.save(accessToken, for: "drive.accessToken")
        }
        if let refreshToken = refreshToken {
            keychain.save(refreshToken, for: "drive.refreshToken")
        }
    }
    
    private func loadStoredTokens() {
        let keychain = KeychainHelper.shared
        accessToken = keychain.load(for: "drive.accessToken")
        refreshToken = keychain.load(for: "drive.refreshToken")
        isAuthenticated = accessToken != nil
    }
    
    func signOut() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        KeychainHelper.shared.delete(for: "drive.accessToken")
        KeychainHelper.shared.delete(for: "drive.refreshToken")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleDriveProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - iCloud Drive Provider

final class ICloudDriveProvider: CloudStorageProvider, ObservableObject {
    let name = "iCloud Drive"
    
    @Published private(set) var isAuthenticated = true // iCloud doesn't require auth
    @Published private(set) var isUploading = false
    @Published private(set) var uploadProgress: Double = 0.0
    
    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("LocalLoom")
    }
    
    func authenticate() async throws {
        // iCloud doesn't require authentication
        // Just verify container is available
        guard iCloudURL != nil else {
            throw CloudError.uploadFailed("iCloud Drive not available")
        }
    }
    
    func uploadFile(_ fileURL: URL, deleteAfterUpload: Bool) async throws -> CloudUploadResult {
        guard let iCloudURL = iCloudURL else {
            throw CloudError.uploadFailed("iCloud Drive not available")
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CloudError.fileNotFound
        }
        
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                isUploading = false
                uploadProgress = 0.0
            }
        }
        
        // Create directory if needed
        try FileManager.default.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
        
        await MainActor.run { uploadProgress = 0.3 }
        
        let fileName = fileURL.lastPathComponent
        let destinationURL = iCloudURL.appendingPathComponent(fileName)
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        await MainActor.run { uploadProgress = 0.5 }
        
        // Copy or move file to iCloud
        if deleteAfterUpload {
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
        } else {
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        }
        
        await MainActor.run { uploadProgress = 1.0 }
        
        // iCloud doesn't provide direct share URLs, but we can return the local path
        return CloudUploadResult(
            fileID: fileName,
            shareURL: nil,
            provider: name
        )
    }
    
    func signOut() {
        // iCloud doesn't have sign out
    }
}

// MARK: - Response Models

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct UploadResponse: Codable {
    let id: String
    let name: String
}

// MARK: - Keychain Helper

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    func save(_ value: String, for key: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
