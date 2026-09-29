import Foundation
import AppKit
import Observation

/// Inference is restricted to loopback, including redirect handling.
final class LocalOnlySession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
struct OllamaClient {
    let endpoint: URL
    private static let delegate = LocalOnlySession()
    static let localSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    var session: URLSession = Self.localSession
    func request(_ path: String, body: [String: Any]? = nil, timeout: Double = 5) throws -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.timeoutInterval = timeout
        if let body { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }
    func json(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request(path, body: body))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIError.message("Ollama could not complete this request. Check that it is running and up to date.") }
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let error = value["error"] as? String { throw AIError.message(error) }
        return value
    }
    func models() async throws -> [InstalledAIModel] {
        let value = try await json("api/tags")
        return try JSONDecoder().decode([InstalledAIModel].self, from: JSONSerialization.data(withJSONObject: value["models"] ?? [])).filter(\.isLocal)
    }
    func stream(_ path: String, body: [String: Any], receive: @escaping ([String: Any]) async -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request(path, body: body, timeout: 600))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIError.message("Ollama rejected the request. Check the model name and available storage.") }
        var finished = false
        var size = 0
        for try await line in bytes.lines {
            size += line.utf8.count
            guard line.utf8.count < 1_000_000, path != "api/chat" || size < 2_000_000 else { throw AIError.message("The model response was too large. Try a shorter request.") }
            try Task.checkCancellation()
            guard !line.isEmpty, let data = line.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = value["error"] as? String { throw AIError.message(error) }
            await receive(value)
            if value["done"] as? Bool == true || value["status"] as? String == "success" { finished = true }
        }
        guard finished else { throw AIError.message("The connection ended before Ollama finished. Please try again.") }
    }
    func unload(_ model: String) async {
        _ = try? await json("api/generate", body: ["model": model, "keep_alive": 0, "stream": false])
    }
}

@MainActor @Observable
final class LocalAIController {
    var configuration: AIConfiguration
    var installed: [InstalledAIModel] = []
    var runtime: URL?
    var reachable = false
    var checked = false
    var busy = false
    var status = ""
    var error: String?
    var progress: Double?
    private var operation: Task<Void, Never>?
    private var server: Process?
    private var serverEndpoint: URL?
    private let preview: Bool
    private let session: URLSession
    var ready: Bool { reachable && installed.contains { AIConfiguration.canonicalModel($0.name) == AIConfiguration.canonicalModel(configuration.model) } }
    init(session: URLSession = OllamaClient.localSession) {
        self.session = session
        preview = Bundle.main.bundleIdentifier == "app.forgetit.preview" || ProcessInfo.processInfo.arguments.contains("--preview")
        configuration = (try? JSONDecoder().decode(AIConfiguration.self, from: UserDefaults.standard.data(forKey: "localAI.configuration") ?? Data())) ?? AIConfiguration()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.server?.isRunning == true { self?.server?.terminate() } }
        }
    }
    func persist() { if !preview { UserDefaults.standard.set(try? JSONEncoder().encode(configuration), forKey: "localAI.configuration") } }
    static func locateRuntime() -> URL? {
        let paths = [NSHomeDirectory() + "/Applications/Ollama.app/Contents/Resources/ollama", "/Applications/Ollama.app/Contents/Resources/ollama", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    func check() async {
        if preview && ProcessInfo.processInfo.arguments.contains("--ai-preview-models") {
            reachable = true; checked = true; installed = []; return
        }
        if preview && ProcessInfo.processInfo.arguments.contains("--ai-preview-ready") {
            reachable = true; checked = true; installed = [InstalledAIModel(name: "qwen3.5:4b", size: 3_400_000_000)]
            configuration.model = "qwen3.5:4b"; return
        }
        runtime = Self.locateRuntime()
        do {
            installed = try await OllamaClient(endpoint: AIConfiguration.validatedEndpoint(configuration.endpoint), session: session).models()
            reachable = true
            if configuration.model.isEmpty, let first = installed.first { configuration.model = first.name; persist() }
        } catch { reachable = false; installed = [] }
        checked = true
    }
    func cancel() { operation?.cancel(); status = "Cancelling…"; error = nil }
    func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; progress = nil
        operation = Task {
            defer { busy = false; operation = nil; progress = nil }
            do { try await work(); status = "" }
            catch { if Task.isCancelled { status = "Cancelled. You can continue whenever you’re ready." } else { self.error = error.localizedDescription; status = "" } }
        }
    }
    func start() async throws {
        try Task.checkCancellation()
        guard !preview else { throw AIError.message("Runtime changes are disabled in the preview app.") }
        await check()
        if reachable { return }
        guard let runtime else { throw AIError.message("Install Ollama to continue.") }
        let endpoint = try AIConfiguration.validatedEndpoint(configuration.endpoint)
        guard endpoint.scheme == "http" else { throw AIError.message("Start your HTTPS server separately, or use the default HTTP address.") }
        status = "Starting Ollama…"
        try Task.checkCancellation()
        if server?.isRunning == true && serverEndpoint != endpoint { server?.terminate(); server = nil }
        if server?.isRunning != true {
            let process = Process(); process.executableURL = runtime; process.arguments = ["serve"]
            var env = ProcessInfo.processInfo.environment
            env["OLLAMA_HOST"] = endpoint.absoluteString; env["OLLAMA_NO_CLOUD"] = "1"
            env["OLLAMA_KEEP_ALIVE"] = "0"; env["OLLAMA_MAX_LOADED_MODELS"] = "1"
            process.environment = env; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); server = process; serverEndpoint = endpoint
        }
        for _ in 0..<20 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(400))
            await check()
            if reachable { return }
        }
        throw AIError.message("Ollama did not start. Open Ollama manually, then choose Check Again.")
    }
    func install() async throws {
        guard !preview else { throw AIError.message("Installation is disabled in the preview app.") }
        if Self.locateRuntime() != nil { try await start(); return }
        status = "Downloading Ollama from ollama.com…"
        // Uses the same official Mac archive as Ollama's installer, without a shell script or package manager.
        let (download, response) = try await URLSession.shared.download(from: URL(string: "https://ollama.com/download/Ollama-darwin.zip")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.message("Couldn’t download Ollama. Try again or install it from ollama.com.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forget-it-ollama-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("Ollama.zip")
        try FileManager.default.moveItem(at: download, to: archive)
        try Task.checkCancellation()
        status = "Verifying and installing Ollama…"
        try await Self.command("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        let app = folder.appendingPathComponent("Ollama.app")
        try await Self.command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        try await Self.command("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        try Task.checkCancellation()
        let applications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let destination = applications.appendingPathComponent("Ollama.app")
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw AIError.message("Ollama already exists in your Applications folder. Choose Check Again.") }
        try FileManager.default.moveItem(at: app, to: destination)
        try Task.checkCancellation()
        try await start()
    }
    private static func command(_ executable: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw AIError.message("macOS could not verify or unpack Ollama. Install the official app from ollama.com, then choose Check Again.") }
        }.value
    }
    func pull(_ model: String) async throws {
        guard !preview else { throw AIError.message("Model downloads are disabled in the preview app.") }
        guard AIConfiguration.isLocalModelName(model) else { throw AIError.message("Enter a local Ollama model name, such as qwen3.5:4b.") }
        try await start()
        status = "Downloading \(model)…"
        let client = OllamaClient(endpoint: try AIConfiguration.validatedEndpoint(configuration.endpoint), session: session)
        try await client.stream("api/pull", body: ["model": model, "stream": true]) { value in
            await MainActor.run {
                self.status = value["status"] as? String ?? "Downloading…"
                if let total = value["total"] as? Double, total > 0, let completed = value["completed"] as? Double { self.progress = min(1, completed / total) }
            }
        }
        try Task.checkCancellation()
        await check()
        guard installed.contains(where: { AIConfiguration.canonicalModel($0.name) == AIConfiguration.canonicalModel(model) }) else { throw AIError.message("The download did not produce a local model. Choose another model.") }
        configuration.model = model; persist()
    }
    func chat(messages: [[String: Any]], schema: [String: Any]? = nil) async throws -> String {
        guard !preview else { throw AIError.message("AI inference is disabled in the preview app. Use the regular app with an installed model.") }
        guard ready else { throw AIError.message("Choose an installed local model first.") }
        let model = configuration.model
        let client = OllamaClient(endpoint: try AIConfiguration.validatedEndpoint(configuration.endpoint), session: session)
        let info = try await client.json("api/show", body: ["model": model])
        guard info["remote_host"] == nil, info["remote_model"] == nil else { throw AIError.message("Choose a local model. Cloud models are not supported.") }
        let capabilities = info["capabilities"] as? [String] ?? []
        if messages.contains(where: { ($0["images"] as? [String])?.isEmpty == false }) && !capabilities.contains("vision") { throw AIError.message("This model cannot read screenshots. Choose one of the recommended vision models or paste the text instead.") }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "keep_alive": 0, "options": ["temperature": 0.1, "num_ctx": 8192, "num_predict": 4096]]
        if capabilities.contains("thinking") { body["think"] = false }
        if let schema { body["format"] = schema }
        status = "Reading and thinking… The model may take a moment to load."
        var content = ""
        do {
            try await client.stream("api/chat", body: body) { value in
                if let message = value["message"] as? [String: Any], let text = message["content"] as? String { content += text }
            }
            try Task.checkCancellation()
            guard !content.isEmpty, content.count <= 100_000 else { throw AIError.message("The model returned an empty or oversized answer. Try a shorter request.") }
            await Task.detached { await client.unload(model) }.value
            return content
        } catch {
            await Task.detached { await client.unload(model) }.value
            throw error
        }
    }
}
