import Foundation

enum ParakeetBridgeError: LocalizedError {
    case helperMissing(URL)
    case pythonMissing(String)
    case processNotReady
    case processWriteFailed
    case daemon(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing(let url):
            return "Missing helper at \(url.path)"
        case .pythonMissing(let path):
            return "Missing Python executable at \(path)"
        case .processNotReady:
            return "Parakeet daemon is not ready"
        case .processWriteFailed:
            return "Could not send audio path to Parakeet daemon"
        case .daemon(let message):
            return message
        }
    }
}

struct DaemonResponse: Decodable {
    let ok: Bool
    let text: String?
    let error: String?
}

final class ParakeetBridge {
    private let config: VocalConfig
    private let helperURL: URL
    private let pythonPath: String
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let queue = DispatchQueue(label: "local.vocal.app.parakeet")
    private var outputBuffer = ""
    private var pending: [(Result<String, Error>) -> Void] = []
    private var isReady = false
    private var onReady: ((String) -> Void)?
    private var onError: ((String) -> Void)?
    private var onProgress: ((Int, Int64, Int64) -> Void)?

    init(config: VocalConfig) throws {
        self.config = config
        self.helperURL = try Self.findHelper()
        self.pythonPath = Self.findPython(config: config)

        if !FileManager.default.fileExists(atPath: helperURL.path) {
            throw ParakeetBridgeError.helperMissing(helperURL)
        }
        if !FileManager.default.fileExists(atPath: pythonPath) {
            throw ParakeetBridgeError.pythonMissing(pythonPath)
        }
    }

    func start(onReady: @escaping (String) -> Void,
               onError: @escaping (String) -> Void,
               onProgress: ((Int, Int64, Int64) -> Void)? = nil) {
        self.onReady = onReady
        self.onError = onError
        self.onProgress = onProgress

        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [helperURL.path, "--model", config.model]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_DISABLE_XET"] = "1"
        // A GUI-launched app (Launchpad / `open`) gets a minimal PATH that excludes
        // Homebrew, so parakeet-mlx can't find `ffmpeg`. Prepend the usual Homebrew
        // locations (and the venv's bin) so the daemon resolves it like a shell would.
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let venvBin = URL(fileURLWithPath: pythonPath).deletingLastPathComponent().path
        let extraPaths = [venvBin, "/opt/homebrew/bin", "/usr/local/bin"]
        let mergedPath = (extraPaths + [existingPath]).joined(separator: ":")
        environment["PATH"] = mergedPath
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.consumeOutput(chunk)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.consumeError(chunk)
        }

        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 0 else { return }
            self?.failAll("Parakeet daemon exited with status \(process.terminationStatus)")
        }

        do {
            try process.run()
        } catch {
            onError("Could not start Parakeet daemon: \(error.localizedDescription)")
        }
    }

    func transcribe(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            guard self.isReady else {
                completion(.failure(ParakeetBridgeError.processNotReady))
                return
            }

            self.pending.append(completion)
            guard let data = (audioURL.path + "\n").data(using: .utf8) else {
                _ = self.pending.popLast()
                completion(.failure(ParakeetBridgeError.processWriteFailed))
                return
            }
            do {
                try self.inputPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                _ = self.pending.popLast()
                completion(.failure(error))
            }
        }
    }

    func stop() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    private func consumeOutput(_ chunk: String) {
        queue.async {
            self.outputBuffer += chunk
            while let newline = self.outputBuffer.firstIndex(of: "\n") {
                let line = String(self.outputBuffer[..<newline])
                self.outputBuffer.removeSubrange(...newline)
                self.handleLine(line)
            }
        }
    }

    private func consumeError(_ chunk: String) {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSLog("Vocal Parakeet daemon: \(trimmed)")
    }

    private func handleLine(_ line: String) {
        if line.hasPrefix("READY\t") {
            isReady = true
            let device = String(line.dropFirst("READY\t".count))
            onReady?(device)
            return
        }

        // First-run model download: "PROGRESS\t<pct>\t<doneBytes>\t<totalBytes>"
        if line.hasPrefix("PROGRESS\t") {
            let fields = line.dropFirst("PROGRESS\t".count).split(separator: "\t")
            if fields.count >= 3,
               let pct = Int(fields[0]),
               let done = Int64(fields[1]),
               let total = Int64(fields[2]) {
                onProgress?(pct, done, total)
            }
            return
        }

        guard let data = line.data(using: .utf8) else { return }
        do {
            let response = try JSONDecoder().decode(DaemonResponse.self, from: data)
            let completion = pending.isEmpty ? nil : pending.removeFirst()
            if response.ok {
                completion?(.success(response.text ?? ""))
            } else {
                completion?(.failure(ParakeetBridgeError.daemon(response.error ?? "Unknown Parakeet error")))
            }
        } catch {
            let completion = pending.isEmpty ? nil : pending.removeFirst()
            completion?(.failure(error))
        }
    }

    private func failAll(_ message: String) {
        queue.async {
            self.isReady = false
            let completions = self.pending
            self.pending.removeAll()
            completions.forEach { $0(.failure(ParakeetBridgeError.daemon(message))) }
            self.onError?(message)
        }
    }

    private static func findHelper() throws -> URL {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("parakeet_daemon.py"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/parakeet_daemon.py")
        return sourceURL
    }

    private static func findPython(config: VocalConfig) -> String {
        if let pythonExecutable = config.pythonExecutable, !pythonExecutable.isEmpty {
            return NSString(string: pythonExecutable).expandingTildeInPath
        }

        // Self-contained install: a relocatable Python lives inside the app bundle at
        // Contents/Resources/python. This is what lets the installed /Applications copy
        // run with no project folder, no venv, and no system Python present.
        if let embeddedPython = Bundle.main.resourceURL?
            .appendingPathComponent("python/bin/python3").path,
           FileManager.default.fileExists(atPath: embeddedPython) {
            return embeddedPython
        }

        if let bundleURL = Bundle.main.bundleURL as URL? {
            let projectVenvPython = bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".venv/bin/python")
                .path
            if FileManager.default.fileExists(atPath: projectVenvPython) {
                return projectVenvPython
            }
        }

        let currentDirectoryPython = FileManager.default.currentDirectoryPath + "/.venv/bin/python"
        if FileManager.default.fileExists(atPath: currentDirectoryPython) {
            return currentDirectoryPython
        }

        return "/usr/bin/python3"
    }
}
