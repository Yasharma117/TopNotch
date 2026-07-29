import Foundation
import AVFoundation

public protocol CaptureControllerDelegate: AnyObject {
    func captureControllerDidStart(_ controller: CaptureController)
    func captureController(_ controller: CaptureController, didFail error: Error)
    func captureControllerDidStop(_ controller: CaptureController)
}

public final class CaptureController: NSObject {
    private var assetWriter: AVAssetWriter?
    fileprivate var audioInput: AVAssetWriterInput?
    fileprivate var isWriting = false
    private var sessionStarted = false

    private var captureSession: AVCaptureSession?
    private let audioQueue = DispatchQueue(label: "capture.audio.queue")

    public private(set) var isCapturing = false

    public weak var delegate: CaptureControllerDelegate?

    public override init() { super.init() }

    public func startCapture(outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            delegate?.captureController(self, didFail: error)
            throw error
        }
        self.assetWriter = writer

        let audioSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        self.audioInput = audioInput
        guard writer.canAdd(audioInput) else {
            let e = NSError(domain: "CaptureController", code: -5,
                            userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input"])
            delegate?.captureController(self, didFail: e); throw e
        }
        writer.add(audioInput)

        let session = AVCaptureSession()
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
        self.captureSession = session
        session.startRunning()

        writer.startWriting()
        isWriting = true
        sessionStarted = false
        isCapturing = true
        delegate?.captureControllerDidStart(self)
    }

    public func stopCapture() async {
        isCapturing = false

        captureSession?.stopRunning()
        captureSession = nil

        if isWriting {
            isWriting = false
            audioInput?.markAsFinished()
            await assetWriter?.finishWriting()
        }

        assetWriter = nil
        audioInput = nil
        sessionStarted = false
        delegate?.captureControllerDidStop(self)
    }
}

extension CaptureController: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard isWriting,
              let writer = assetWriter,
              let audioInput = audioInput else { return }

        // Start session at the first sample's PTS so writer is anchored to real audio time.
        if !sessionStarted {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }

        guard audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }
}
