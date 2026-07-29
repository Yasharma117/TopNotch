import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

public enum CaptureMode {
    case display(SCDisplay)
    case window(SCWindow)
}

public protocol CaptureControllerDelegate: AnyObject {
    func captureControllerDidStart(_ controller: CaptureController)
    func captureController(_ controller: CaptureController, didFail error: Error)
    func captureControllerDidStop(_ controller: CaptureController)
}

public final class CaptureController: NSObject {
    private var stream: SCStream?
    private var videoOutput: SCStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isWriting = false
    public private(set) var isCapturing = false
    public var frameRate: Int = 60
    public var resolution: CGSize?
    public let videoQueue = DispatchQueue(label: "capture.video.queue")

    public weak var delegate: CaptureControllerDelegate?

    public override init() {
        super.init()
    }

    public func startCapture(mode: CaptureMode, outputURL: URL) async throws {
        // Build SCContentFilter depending on mode
        let filter: SCContentFilter
        let sourceSize: CGSize

        switch mode {
        case .display(let display):
            filter = SCContentFilter(display: display, excludingWindows: [])
            sourceSize = CGSize(width: Int(display.width), height: Int(display.height))
        case .window(let window):
            filter = SCContentFilter(includeWindows: [window])
            sourceSize = CGSize(width: Int(window.frame.width), height: Int(window.frame.height))
        }

        // Build SCStreamConfiguration
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA

        if let resolution = resolution {
            config.width = Int(resolution.width)
            config.height = Int(resolution.height)
        } else {
            config.width = Int(sourceSize.width)
            config.height = Int(sourceSize.height)
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        // Create SCStream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        // Setup AVAssetWriter for .mov with H.264, matching width/height
        let writer: AVAssetWriter
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch {
            // ignore error if file does not exist
        }
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            delegate?.captureController(self, didFail: error)
            throw error
        }
        self.assetWriter = writer

        // Video output settings for H.264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        self.videoInput = videoInput

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        } else {
            let error = NSError(domain: "CaptureController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to asset writer"])
            delegate?.captureController(self, didFail: error)
            throw error
        }

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: config.pixelFormat,
            kCVPixelBufferWidthKey as String: config.width,
            kCVPixelBufferHeightKey as String: config.height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        self.pixelBufferAdaptor = adaptor

        // Start writing session
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        isWriting = true

        // Setup SCStreamOutput
        let videoOutput = VideoOutput(parent: self)
        self.videoOutput = videoOutput
        stream.addStreamOutput(videoOutput, type: .screen, sampleHandlerQueue: videoQueue)

        do {
            try await stream.startCapture()
            isCapturing = true
            delegate?.captureControllerDidStart(self)
        } catch {
            isWriting = false
            try? writer.finishWriting()
            delegate?.captureController(self, didFail: error)
            throw error
        }
    }

    public func stopCapture() async {
        guard let stream = stream else { return }

        isCapturing = false

        await withCheckedContinuation { continuation in
            stream.stopCapture { [weak self] error in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                if let error = error {
                    self.delegate?.captureController(self, didFail: error)
                }
                self.stream = nil
                self.videoOutput = nil

                if self.isWriting {
                    self.isWriting = false
                    self.videoInput?.markAsFinished()
                    self.assetWriter?.finishWriting {
                        self.assetWriter = nil
                        self.videoInput = nil
                        self.pixelBufferAdaptor = nil
                        self.delegate?.captureControllerDidStop(self)
                        continuation.resume()
                    }
                } else {
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.pixelBufferAdaptor = nil
                    self.delegate?.captureControllerDidStop(self)
                    continuation.resume()
                }
            }
        }
    }
}

extension CaptureController: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegate?.captureController(self, didFail: error)
    }
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of streamOutputType: SCStreamOutputType) {
        // No-op: handled by SCStreamOutput subclass
    }
}

private final class VideoOutput: NSObject, SCStreamOutput {
    weak var parent: CaptureController?

    private var lastPresentationTimestamp: CMTime = .zero

    init(parent: CaptureController) {
        self.parent = parent
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of streamOutputType: SCStreamOutputType) {
        guard let parent = parent else { return }
        guard parent.isWriting else { return }
        guard let pixelBufferAdaptor = parent.pixelBufferAdaptor else { return }
        guard let videoInput = parent.videoInput else { return }
        guard videoInput.isReadyForMoreMediaData else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Append pixel buffer to adaptor
        if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: pts) {
            // If append fails, forward error and stop writing
            let error = NSError(domain: "CaptureController", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to append pixel buffer"])
            DispatchQueue.main.async {
                parent.delegate?.captureController(parent, didFail: error)
            }
        }
    }
}
