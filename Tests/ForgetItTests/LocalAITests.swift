import Foundation
import AppKit

final class MockOllama: URLProtocol {
    static var requests: [URLRequest] = []
    static var delayChat = false
    static var reply: (URLRequest) -> (Int, String) = { _ in (200, "{}") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
            captured.httpBody = data
        }
        Self.requests.append(captured)
        if Self.delayChat && request.url?.lastPathComponent == "chat" { return }
        let (code, text) = Self.reply(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/x-ndjson"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor func runAITests() async throws {
    for endpoint in ["https://example.com", "http://127.0.0.1.evil.com", "http://user@localhost", "file:///tmp/a", "http://localhost/path", "http://localhost?url=remote"] {
        expectThrows { _ = try AIConfiguration.validatedEndpoint(endpoint) }
    }
    let endpoint = try AIConfiguration.validatedEndpoint("http://127.0.0.1:11434"); expect(endpoint.host == "127.0.0.1")
    expect(!AIConfiguration.isLocalModelName("qwen3:cloud"))
    expect(!AIConfiguration.isLocalModelName("../../oops"))
    expect(AIConfiguration.isLocalModelName("qwen3.5:4b"))
    expect(AIImportValidation.date("2026-02-30") == nil)
    expect(AIImportValidation.date("2026-09-29", time: "25:00") == nil)
    expect(AIImportValidation.date("2028-02-29", time: "17:00") != nil)
    let schoolClass = SchoolClass(name: "Maths")
    let json = """
    {"summary":"A worksheet","questions":[],"tasks":[{"title":"Algebra worksheet","class_id":"\(schoolClass.id)","notes":"Answer questions 1–5","due_date":"2026-10-02","due_time":null,"all_day":true,"date_quote":"Friday 2 October","kind":"homework","start_date":null,"parts":3}]}
    """
    let extraction = try AIExtraction.decode(json)
    let draft = AIImportValidation.drafts(from: extraction, source: "Maths: Algebra worksheet due Friday 2 October.", attachments: [], classes: [schoolClass], selectedClass: nil, existing: [], model: "qwen3.5:4b")[0]
    expect(draft.dateConfirmed && draft.classConfirmed && draft.evidenceConfirmed)
    expect(!draft.isReady) // Explicit review is required, even for a clear source.
    expect(draft.task.targetCount() == 3)
    let uncertain = AIImportValidation.drafts(from: extraction, source: "Do this sometime", attachments: [], classes: [schoolClass], selectedClass: nil, existing: [draft.task], model: "test")[0]
    expect(!uncertain.classConfirmed && !uncertain.evidenceConfirmed && uncertain.duplicate)
    expectThrows { _ = try AIExtraction.decode(json.replacingOccurrences(of: "\"parts\":3", with: "\"parts\":0")) }
    let data = PlannerData(classes: [schoolClass], tasks: [draft.task])
    let restored = try PlannerStore.decode(JSONEncoder().encode(data)); expect(restored == data)
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockOllama.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = OllamaClient(endpoint: URL(string: "http://127.0.0.1:11434")!, session: session)
    MockOllama.reply = { _ in (200, "{\"models\":[{\"name\":\"local:latest\",\"size\":123},{\"name\":\"remote:latest\",\"size\":123,\"remote_host\":\"https://example.com\"}]}") }
    let models = try await client.models(); expect(models.map(\.name) == ["local:latest"])
    MockOllama.reply = { _ in (200, "{\"message\":{\"content\":\"partial\"}}\n") }
    do { try await client.stream("api/chat", body: [:]) { _ in }; fatalError("Truncated response accepted") } catch {}
    MockOllama.reply = { _ in (200, "{\"error\":\"model missing\"}\n") }
    do { try await client.stream("api/chat", body: [:]) { _ in }; fatalError("API error accepted") } catch {}
    MockOllama.requests = []
    MockOllama.reply = { request in
        switch request.url!.lastPathComponent {
        case "show": return (200, "{\"capabilities\":[\"completion\",\"vision\",\"thinking\"]}")
        case "chat": return (200, "{\"message\":{\"content\":\"A clear first step.\"}}\n{\"done\":true}\n")
        default: return (200, "{}")
        }
    }
    let ai = LocalAIController(session: session, conversationFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    ai.configuration = AIConfiguration(); ai.configuration.model = "qwen3.5:4b"
    ai.installed = [InstalledAIModel(name: "qwen3.5:4b", size: 123)]; ai.reachable = true
    let response = try await ai.chat(messages: [["role": "user", "content": "Explain this"]])
    expect(response == "A clear first step.")
    let chat = MockOllama.requests.first { $0.url?.lastPathComponent == "chat" }!
    let body = try JSONSerialization.jsonObject(with: chat.httpBody!) as! [String: Any]
    expect(body["keep_alive"] as? Int == 0 && body["think"] as? Bool == false)
    expect(MockOllama.requests.last?.url?.lastPathComponent == "generate")
    MockOllama.requests = []
    MockOllama.reply = { request in
        request.url!.lastPathComponent == "chat" ? (500, "{}") : (200, "{}")
    }
    do { _ = try await ai.chat(messages: [["role": "user", "content": "Test"]]); fatalError("Failed request accepted") } catch {}
    expect(MockOllama.requests.last?.url?.lastPathComponent == "generate") // Cleanup on failure.
    MockOllama.requests = []; MockOllama.delayChat = true
    let cancelled = Task { try await ai.chat(messages: [["role": "user", "content": "Cancel this"]]) }
    for _ in 0..<100 {
        if MockOllama.requests.contains(where: { $0.url?.lastPathComponent == "chat" }) { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    cancelled.cancel()
    do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch {}
    expect(MockOllama.requests.last?.url?.lastPathComponent == "generate")
    MockOllama.delayChat = false
    MockOllama.requests = []
    MockOllama.reply = { _ in (200, "{\"models\":[]}")}
    await ai.check()
    expect(MockOllama.requests.map { $0.url!.lastPathComponent } == ["tags"])
    MockOllama.requests = []
    MockOllama.reply = { _ in (200, "") }
    let deleteClient = OllamaClient(endpoint: endpoint, session: session)
    try await deleteClient.deleteModel("test:small")
    expect(MockOllama.requests.last?.httpMethod == "DELETE")
    expect(MockOllama.requests.last?.url?.lastPathComponent == "delete")
    MockOllama.reply = { _ in (500, "") }
    do { try await deleteClient.deleteModel("test:small"); fatalError("Ignored failed deletion") } catch {}
    let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let png = pixel.representation(using: .png, properties: [:])!
    let attachment = try AttachmentReader.image(png)
    let encoded = try AttachmentReader.aiImage(attachment); expect(!attachment.data.isEmpty && !encoded.isEmpty)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.declareTypes([.png], owner: nil)
    expect(pasteboard.setData(png, forType: .png))
    let pasted = try AttachmentReader.pasteboard(pasteboard); expect(pasted.count == 1)
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in completion(png, nil); return nil }
    let dropped = try await AttachmentReader.providers([provider])
    expect(dropped.count == 1 && NSImage(data: dropped[0].data) != nil)
    expectThrows { _ = try AttachmentReader.image(Data("not an image".utf8)) }
    print("PASS: local AI validation, review gating, source backup, API errors/truncation, keep_alive, failure/cancellation cleanup, launch detection, image paste and drop.")
}
