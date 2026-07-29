import Foundation
import AVFoundation

final class AudioCaptureController: NSObject {
    public private(set) var isCapturing = false

    private let engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode? { engine.inputNode }
    private var audioFormat: AVAudioFormat?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private let audioQueue = DispatchQueue(label: "capture.audio.queue")

    public func startCapture(to assetWriter: AVAssetWriter) throws {
        guard let inputNode = inputNode else {
            throw NSError(domain: "AudioCaptureController", code: -1, userInfo: [NSLocalizedDescriptionKey: "No input node available"])
        }

        self.assetWriter = assetWriter

        // Choose hardware sample rate 44100 or 48000
        let hwSampleRate = inputNode.inputFormat(forBus: 0).sampleRate
        let preferredSampleRate: Double = (abs(hwSampleRate - 48000) < abs(hwSampleRate - 44100)) ? 48000 : 44100

        // Configure audio format
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: preferredSampleRate,
                                   channels: 1,
                                   interleaved: true)!
        self.audioFormat = format

        // Prepare audio settings for AAC
        let audioSettings = audioSettingsForAAC(sampleRate: preferredSampleRate, channels: 1)

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(audioInput) else {
            throw NSError(domain: "AudioCaptureController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input to asset writer"])
        }
        assetWriter.add(audioInput)
        self.audioInput = audioInput

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            self.audioQueue.async {
                guard let audioInput = self.audioInput,
                      audioInput.isReadyForMoreMediaData else { return }
                if let sampleBuffer = self.createSampleBuffer(from: buffer, at: time) {
                    audioInput.append(sampleBuffer)
                }
            }
        }

        try engine.start()
        isCapturing = true
    }

    public func stopCapture() {
        guard isCapturing else { return }
        inputNode?.removeTap(onBus: 0)
        engine.stop()
        audioInput?.markAsFinished()
        isCapturing = false
    }

    // MARK: - Helpers

    private func audioSettingsForAAC(sampleRate: Double, channels: Int) -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128000
        ]
    }

    private func createSampleBuffer(from buffer: AVAudioPCMBuffer, at time: AVAudioTime) -> CMSampleBuffer? {
        guard let format = audioFormat else { return nil }
        var sampleBuffer: CMSampleBuffer?

        // Create CMAudioFormatDescription
        var audioFormatDesc: CMAudioFormatDescription?
        let asbd = format.streamDescription
        let status1 = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                    asbd: asbd,
                                                    layoutSize: 0,
                                                    layout: nil,
                                                    magicCookieSize: 0,
                                                    magicCookie: nil,
                                                    extensions: nil,
                                                    formatDescriptionOut: &audioFormatDesc)
        guard status1 == noErr, let audioFormatDesc = audioFormatDesc else { return nil }

        let frameCount = CMItemCount(buffer.frameLength)
        let samplesPerPacket = format.streamDescription.pointee.mFramesPerPacket

        // Create block buffer from pcm data
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        var blockBuffer: CMBlockBuffer?
        let status2 = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                         memoryBlock: audioBuffer.mData,
                                                         blockLength: Int(audioBuffer.mDataByteSize),
                                                         blockAllocator: kCFAllocatorNull,
                                                         customBlockSource: nil,
                                                         offsetToData: 0,
                                                         dataLength: Int(audioBuffer.mDataByteSize),
                                                         flags: 0,
                                                         blockBufferOut: &blockBuffer)
        guard status2 == noErr, let blockBuffer = blockBuffer else { return nil }

        // Calculate presentation timestamp
        let pts = CMTimeMake(value: Int64(time.sampleTime), timescale: Int32(format.sampleRate))

        // Create sample timing info
        var timing = CMSampleTimingInfo(duration: CMTimeMake(value: Int64(samplesPerPacket), timescale: Int32(format.sampleRate)),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: CMTime.invalid)

        // Create CMSampleBuffer
        let status3 = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                           dataBuffer: blockBuffer,
                                           dataReady: true,
                                           makeDataReadyCallback: nil,
                                           refcon: nil,
                                           formatDescription: audioFormatDesc,
                                           sampleCount: frameCount,
                                           sampleTimingEntryCount: 1,
                                           sampleTimingArray: &timing,
                                           sampleSizeEntryCount: 0,
                                           sampleSizeArray: nil,
                                           sampleBufferOut: &sampleBuffer)
        guard status3 == noErr else { return nil }

        return sampleBuffer
    }
}
