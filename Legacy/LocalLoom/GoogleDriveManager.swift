import Foundation
import AuthenticationServices
import AppKit

/// Manages Google Drive authentication and file uploads
final class GoogleDriveManager: NSObject, ObservableObject {
    static let shared = GoogleDriveManager()
    
    @Published var isAuthenticated = false
    @Published var uploadProgress: Double = 0.0
    @Published var isUploading = false
    
    private var accessToken: String?
    private var refreshToken: String?
    
    // Google OAuth Configuration
    // ⚠️ You need to create these in Google Cloud Console
    private let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    private let clientSecret = "YOUR_CLIENT_SECRET"
    private let redirectURI = "com.yourdomain.localloom:/oauth2callback"
    
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"
    
    private override init() {
        super.init()
        loadStoredTokens()
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        let authURL = buildAuthURL()
        
        // Open authentication in browser
        guard let url = URL(string: authURL) else {
            throw DriveError.invalidURL
        }
        
        // Use ASWebAuthenticationSession for OAuth
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.yourdomain.localloom"
            ) { [weak self] callbackURL, error in
                guard let self = self else {
                    continuation.resume(throwing: DriveError.invalidURL)
                    return
                }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: DriveError.noAuthCode)
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
            throw DriveError.noAuthCode
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
    
    func uploadFile(_ fileURL: URL, deleteAfterUpload: Bool = false) async throws -> String {
        guard let accessToken = accessToken else {
            throw DriveError.notAuthenticated
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
        
        // Create metadata
        let metadata: [String: Any] = [
            "name": fileName,
            "mimeType": "video/quicktime"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        
        // Build multipart request
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        // Add metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add file data part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Create request
        var request = URLRequest(url: URL(string: "\(uploadEndpoint)?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        // Upload with progress tracking
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DriveError.uploadFailed
        }
        
        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        
        // Delete local file if requested
        if deleteAfterUpload {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        await MainActor.run {
            uploadProgress = 1.0
        }
        
        return uploadResponse.id
    }
    
    func generateShareLink(_ fileID: String) async throws -> String {
        guard let accessToken = accessToken else {
            throw DriveError.notAuthenticated
        }
        
        // Make file publicly accessible
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
    
    // MARK: - Token Storage
    
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

extension GoogleDriveManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
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

// MARK: - Errors

enum DriveError: LocalizedError {
    case invalidURL
    case noAuthCode
    case notAuthenticated
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noAuthCode: return "No authorization code received"
        case .notAuthenticated: return "Not authenticated with Google Drive"
        case .uploadFailed: return "Upload to Google Drive failed"
        }
    }
}
