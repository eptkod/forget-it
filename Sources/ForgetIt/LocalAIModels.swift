import Foundation

struct AIModelChoice: Identifiable {
    var id: String
    var name: String
    var badge: String
    var description: String
    var download: String
    var speed: Double
    var accuracy: Double
    var lightness: Double
    static let defaults = [
        AIModelChoice(id: "qwen3.5:4b", name: "Qwen3.5 4B", badge: "Recommended", description: "A balanced choice for assignment text and screenshots.", download: "3.4 GB", speed: 3, accuracy: 4, lightness: 3),
        AIModelChoice(id: "qwen3.5:2b", name: "Qwen3.5 2B", badge: "Lighter option", description: "Faster responses with a smaller model.", download: "2.7 GB", speed: 4, accuracy: 3.5, lightness: 4),
        AIModelChoice(id: "qwen3-vl:2b", name: "Qwen3-VL 2B", badge: "Smallest download", description: "A compact vision model for everyday assignment input.", download: "1.9 GB", speed: 4.5, accuracy: 3, lightness: 5)
    ]
}

struct InstalledAIModel: Codable, Identifiable, Equatable {
    var name: String
    var size: Int64
    var remoteHost: String?
    var remoteModel: String?
    var id: String { name }
    enum CodingKeys: String, CodingKey { case name, size; case remoteHost = "remote_host", remoteModel = "remote_model" }
    var isLocal: Bool { remoteHost == nil && remoteModel == nil && AIConfiguration.isLocalModelName(name) }
}

struct AIConfiguration: Codable, Equatable {
    var endpoint = "http://127.0.0.1:11434"
    var model = ""
    static func validatedEndpoint(_ text: String) throws -> URL {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(parts.host?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", (parts.port.map { (1...65535).contains($0) } ?? true),
              let url = parts.url else { throw AIError.message("Use an Ollama address on this Mac, such as http://127.0.0.1:11434. Remote and cloud endpoints are not supported.") }
        return url
    }
    static func isLocalModelName(_ value: String) -> Bool {
        let name = value.lowercased()
        return !name.contains("cloud") && !name.contains("..") && value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*(?::[A-Za-z0-9._-]+)?$"#, options: .regularExpression) != nil && value.count <= 160
    }
    static func canonicalModel(_ value: String) -> String { value.split(separator: "/").last?.contains(":") == true ? value : value + ":latest" }
}

enum AIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct AITaskSource: Codable, Equatable {
    var text: String
    var model: String
    var capturedAt: Date
}

struct AIExtractedTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var classID: String?
    var notes: String
    var dueDate: String?
    var dueTime: String?
    var allDay: Bool
    var dateQuote: String?
    var kind: String
    var startDate: String?
    var parts: Int?
    enum CodingKeys: String, CodingKey {
        case title, notes, kind, parts
        case classID = "class_id", dueDate = "due_date", dueTime = "due_time", allDay = "all_day", dateQuote = "date_quote", startDate = "start_date"
    }
}

struct AIExtraction: Codable {
    var summary: String
    var questions: [String]
    var tasks: [AIExtractedTask]
    static let schema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["summary", "questions", "tasks"],
        "properties": [
            "summary": ["type": "string"],
            "questions": ["type": "array", "items": ["type": "string"]],
            "tasks": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["title", "class_id", "notes", "due_date", "due_time", "all_day", "date_quote", "kind", "start_date", "parts"],
                "properties": [
                    "title": ["type": "string"], "class_id": ["type": ["string", "null"]], "notes": ["type": "string"],
                    "due_date": ["type": ["string", "null"]], "due_time": ["type": ["string", "null"]],
                    "all_day": ["type": "boolean"], "date_quote": ["type": ["string", "null"]],
                    "kind": ["type": "string", "enum": ["homework", "revision"]],
                    "start_date": ["type": ["string", "null"]], "parts": ["type": ["integer", "null"]]
                ]
            ]]
        ]
    ]
    static func decode(_ content: String) throws -> AIExtraction {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 100_000, let data = trimmed.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIExtraction.self, from: data), result.tasks.count <= 20,
              result.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 160 && $0.notes.count <= 8000 && ["homework", "revision"].contains($0.kind) && ($0.parts.map { (1...99).contains($0) } ?? true) }) else {
            throw AIError.message("The model did not return usable task details. Nothing was added. Try a clearer screenshot, shorter text, or another model.")
        }
        return result
    }
}

struct AIImportDraft: Identifiable {
    var id = UUID()
    var task: StudyTask
    var classConfirmed: Bool
    var dateConfirmed: Bool
    var timeConfirmed: Bool
    var evidenceConfirmed: Bool
    var questions: [String]
    var dateQuote: String
    var duplicate = false
    var include = true
    var reviewed = false
    var isReady: Bool { reviewed && classConfirmed && dateConfirmed && timeConfirmed && evidenceConfirmed && questions.isEmpty }
}

enum AIImportValidation {
    static func date(_ value: String, time: String? = nil, timeZone: TimeZone = .current) -> Date? {
        let pattern = time == nil ? #"^\d{4}-\d{2}-\d{2}$"# : #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#
        let input = value + (time.map { " " + $0 } ?? "")
        guard input.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = timeZone; formatter.isLenient = false
        formatter.dateFormat = time == nil ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: input), formatter.string(from: date) == input else { return nil }
        return date
    }
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func duplicate(_ task: StudyTask, in tasks: [StudyTask]) -> Bool {
        tasks.contains { other in
            guard other.classID == task.classID, Calendar.current.isDate(other.due, inSameDayAs: task.due) else { return false }
            let a = normalized(task.title), b = normalized(other.title)
            if a == b { return true }
            let aa = Set(a.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let bb = Set(b.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return !aa.isEmpty && Double(aa.intersection(bb).count) / Double(aa.union(bb).count) > 0.8
        }
    }
    static func drafts(from extraction: AIExtraction, source: String, attachments: [Attachment], classes: [SchoolClass], selectedClass: UUID?, existing: [StudyTask], model: String, now: Date = Date()) -> [AIImportDraft] {
        var already = existing
        return extraction.tasks.map { item in
            let selected = classes.first { $0.id == selectedClass }
            let named = classes.first { $0.id.uuidString == item.classID && normalized(source).contains(normalized($0.name)) }
            let schoolClass = selected ?? named
            let due = item.dueDate.flatMap { date($0, time: item.allDay ? nil : item.dueTime) }
            let quote = item.dateQuote ?? ""
            let evidence = !quote.isEmpty && normalized(source).contains(normalized(quote))
            var task = StudyTask(title: item.title.trimmingCharacters(in: .whitespacesAndNewlines), classID: schoolClass?.id ?? classes.first?.id ?? UUID(), notes: item.notes, due: due ?? now, attachments: attachments)
            task.work = TaskPlan(kind: TaskKind(rawValue: item.kind) ?? .homework, allDay: item.allDay, sessionTarget: item.parts)
            // Starting work is a suggestion, not an inferred requirement.
            if let start = item.startDate.flatMap({ date($0) }), start <= task.due { task.start = start }
            var questions: [String] = []
            if let start = item.startDate, date(start) == nil || (date(start) ?? now) > task.due { questions.append("Check the suggested work start date.") }
            if task.isRevision && task.targetCount() > task.scheduledDayCount() { questions.append("There aren’t enough study days for the suggested sessions.") }
            task.aiSource = AITaskSource(text: source, model: model, capturedAt: now)
            let draft = AIImportDraft(task: task, classConfirmed: schoolClass != nil, dateConfirmed: due != nil,
                                      timeConfirmed: item.allDay || (item.dueDate.flatMap { day in item.dueTime.flatMap { time in date(day, time: time) } } != nil),
                                      evidenceConfirmed: evidence, questions: questions, dateQuote: quote,
                                      duplicate: duplicate(task, in: already))
            already.append(task)
            return draft
        }
    }
}
