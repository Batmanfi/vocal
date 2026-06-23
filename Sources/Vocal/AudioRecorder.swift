import AVFoundation
import Foundation

final class AudioRecorder {
    private let sampleRate: Double
    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var tempURL: URL?
    private(set) var lastSampleCount = 0
    private(set) var lastRecordedDuration = 0.0

    /// Reports a normalized 0...1 input level for each captured buffer (for the recording HUD).
    var onLevel: ((Float) -> Void)?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func start() throws {
        if engine.isRunning {
            return
        }

        lastSampleCount = 0
        lastRecordedDuration = 0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocal-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        tempURL = url

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        outputFile = try AVAudioFile(forWriting: url, settings: inputFormat.settings)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let outputFile = self.outputFile else { return }
            do {
                try outputFile.write(from: buffer)
                self.lastSampleCount += Int(buffer.frameLength)
                self.lastRecordedDuration += Double(buffer.frameLength) / inputFormat.sampleRate
            } catch {
                NSLog("Vocal audio write failed: \(error.localizedDescription)")
            }

            if let onLevel = self.onLevel, let channel = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sumSquares: Float = 0
                for i in 0..<count { let s = channel[i]; sumSquares += s * s }
                let rms = count > 0 ? sqrt(sumSquares / Float(count)) : 0
                let level = min(1.0, rms * 9) // gain so speech fills the meter
                DispatchQueue.main.async { onLevel(level) }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() throws -> URL? {
        guard engine.isRunning else {
            return nil
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil
        return tempURL
    }
}
