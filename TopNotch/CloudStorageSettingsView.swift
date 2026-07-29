import SwiftUI

/// Cloud storage settings UI component
struct CloudStorageSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var cloudManager = CloudStorageManager.shared
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        GroupBox("Cloud Storage") {
            VStack(alignment: .leading, spacing: 12) {
                // Auto-upload toggle
                Toggle("Auto-upload after recording", isOn: $settings.autoUploadEnabled)
                    .font(.headline)
                
                if settings.autoUploadEnabled {
                    Divider()
                    
                    // Provider selection
                    VStack(alignment: .leading, spacing: 16) {
                        // Google Drive Section
                        googleDriveSection
                        
                        Divider()
                        
                        // iCloud Drive Section
                        iCloudDriveSection
                        
                        // Show error if no providers enabled
                        if settings.autoUploadEnabled && !settings.googleDriveEnabled && !settings.iCloudEnabled {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Enable at least one cloud provider")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Upload options
                        if settings.googleDriveEnabled || settings.iCloudEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Upload Options")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Toggle("Delete local copy after upload", isOn: $settings.deleteAfterUpload)
                                
                                if settings.googleDriveEnabled {
                                    Toggle("Generate shareable links", isOn: $settings.generateShareLinks)
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }
                
                // Upload status
                if cloudManager.isUploading {
                    Divider()
                    uploadStatusSection
                }
            }
        }
        .alert("Cloud Storage Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Google Drive Section
    
    private var googleDriveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.blue)
                Text("Google Drive")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                if cloudManager.googleDrive.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .help("Connected")
                }
            }
            
            if cloudManager.googleDrive.isAuthenticated {
                HStack {
                    Toggle("Upload to Google Drive", isOn: $settings.googleDriveEnabled)
                    Spacer()
                    Button("Sign Out") {
                        cloudManager.googleDrive.signOut()
                        settings.googleDriveEnabled = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            } else {
                HStack {
                    Text("Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect") {
                        Task {
                            do {
                                try await cloudManager.googleDrive.authenticate()
                                settings.googleDriveEnabled = true
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - iCloud Drive Section
    
    private var iCloudDriveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundColor(.blue)
                Text("iCloud Drive")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                if cloudManager.iCloudDrive.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .help("Available")
                }
            }
            
            HStack {
                Toggle("Save to iCloud Drive", isOn: $settings.iCloudEnabled)
                Spacer()
                if !cloudManager.iCloudDrive.isAuthenticated {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Upload Status Section
    
    private var uploadStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Uploading to cloud...")
                    .font(.caption)
                Spacer()
            }
            
            // Show individual provider progress
            ForEach(Array(cloudManager.activeUploads.keys), id: \.self) { provider in
                if let progress = cloudManager.activeUploads[provider] {
                    HStack {
                        Text(provider)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Compact Cloud Status View

/// Compact view showing cloud upload status
struct CloudUploadStatusView: View {
    @StateObject private var cloudManager = CloudStorageManager.shared
    @StateObject private var settings = SettingsManager.shared
    
    var body: some View {
        if cloudManager.isUploading {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Uploading to cloud...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if settings.autoUploadEnabled {
            HStack(spacing: 4) {
                if settings.googleDriveEnabled && cloudManager.googleDrive.isAuthenticated {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
                if settings.iCloudEnabled {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
                if settings.googleDriveEnabled || settings.iCloudEnabled {
                    Text("Auto-upload enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview

struct CloudStorageSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CloudStorageSettingsView()

            Divider()

            CloudUploadStatusView()
        }
        .padding()
        .frame(width: 500)
    }
}
