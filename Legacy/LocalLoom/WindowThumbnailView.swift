import SwiftUI
import ScreenCaptureKit
import AppKit

/// A view that displays a thumbnail preview of an SCWindow
struct WindowThumbnailView: View {
    let window: SCWindow
    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 120, height: 80)
                    ProgressView()
                        .scaleEffect(0.7)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 120, height: 80)
                    Image(systemName: "app.dashed")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadThumbnail()
        }
        .onChange(of: window.windowID) { _, _ in
            Task {
                await loadThumbnail()
            }
        }
    }
    
    private func loadThumbnail() async {
        guard !isLoading else { return }
        
        await MainActor.run {
            isLoading = true
            thumbnailImage = nil
        }
        
        do {
            // Create a temporary filter for just this window
            let filter = SCContentFilter(desktopIndependentWindow: window)
            
            // Configure for thumbnail capture
            let config = SCStreamConfiguration()
            config.width = 240  // Small size for thumbnail
            config.height = 160
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            
            // Capture a single frame
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            
            await MainActor.run {
                thumbnailImage = NSImage(cgImage: image, size: .zero)
                isLoading = false
            }
        } catch {
            // If capture fails, just show placeholder
            await MainActor.run {
                thumbnailImage = nil
                isLoading = false
            }
        }
    }
}

/// Enhanced window picker row with thumbnail
struct WindowPickerRow: View {
    let window: SCWindow
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            WindowThumbnailView(window: window)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(window.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(1)
                
                if let app = window.owningApplication {
                    Text(app.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("\(Int(window.frame.width)) × \(Int(window.frame.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    // Preview with mock data
    VStack {
        WindowPickerRow(
            window: SCWindow(), // Note: This won't work in preview, just for layout
            isSelected: true
        )
    }
    .padding()
}
