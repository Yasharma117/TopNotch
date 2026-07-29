import SwiftUI

// MARK: - Cloud Upload Status View

struct CloudUploadStatusView: View {
    @StateObject private var cloudManager = CloudStorageManager.shared
    
    var body: some View {
        if cloudManager.isUploading {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uploading to cloud...")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if cloudManager.uploadProgress > 0 {
                        Text("\(Int(cloudManager.uploadProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let error = cloudManager.lastUploadError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Spacer()
                
                Button {
                    cloudManager.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Cloud Storage Settings View

struct CloudStorageSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var cloudManager = CloudStorageManager.shared
    
    var body: some View {
        GroupBox("Cloud Storage") {
            VStack(alignment: .leading, spacing: 12) {
                // Auto-upload toggle
                Toggle("Auto-upload after recording", isOn: $settings.autoUploadEnabled)
                    .help("Automatically upload recordings to enabled cloud providers")
                
                Divider()
                
                // Cloud providers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Providers")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Google Drive
                    HStack {
                        Toggle("Google Drive", isOn: $settings.googleDriveEnabled)
                        
                        Spacer()
                        
                        if cloudManager.isGoogleDriveAuthenticated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .help("Authenticated")
                        } else if settings.googleDriveEnabled {
                            Button("Sign In") {
                                Task {
                                    await cloudManager.authenticateGoogleDrive()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    // iCloud Drive
                    HStack {
                        Toggle("iCloud Drive", isOn: $settings.iCloudEnabled)
                        
                        Spacer()
                        
                        if cloudManager.isiCloudAvailable {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .help("Available")
                        } else if settings.iCloudEnabled {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .help("iCloud Drive not available")
                        }
                    }
                }
                
                Divider()
                
                // Upload options
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Toggle("Generate share links", isOn: $settings.generateShareLinks)
                        .help("Create shareable links after upload (copies to clipboard)")
                    
                    Toggle("Delete local file after upload", isOn: $settings.deleteAfterUpload)
                        .help("Automatically delete the recording from your Mac after successful upload")
                }
                
                // Info message
                if settings.autoUploadEnabled && !settings.googleDriveEnabled && !settings.iCloudEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Enable at least one cloud provider to use auto-upload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Upload Status - Uploading") {
    CloudUploadStatusView()
        .padding()
        .onAppear {
            CloudStorageManager.shared.isUploading = true
            CloudStorageManager.shared.uploadProgress = 0.45
        }
}

#Preview("Upload Status - Error") {
    CloudUploadStatusView()
        .padding()
        .onAppear {
            CloudStorageManager.shared.lastUploadError = "Failed to upload to Google Drive: Network connection lost"
        }
}

#Preview("Settings") {
    CloudStorageSettingsView()
        .padding()
}
