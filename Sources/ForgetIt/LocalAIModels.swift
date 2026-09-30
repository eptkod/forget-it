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
        AIModelChoice(id: "qwen3.5:9b", name: "Qwen3.5 9B", badge: "Higher capability", description: "A larger model for more demanding instructions. Slower, with higher memory use; allow substantially more RAM than its download size.", download: "6.6 GB", speed: 2, accuracy: 4.5, lightness: 1.5),
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
    var followUps: [AIQuestion]?
    static let schema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["summary", "questions", "tasks", "followUps"],
        "properties": [
            "summary": ["type": "string"],
            "followUps": AIQuestion.arraySchema,
            "questions": ["type": "array", "items": ["type": "string"]],
            "tasks": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["title", "class_id", "notes", "due_date", "due_time", "all_day", "date_quote", "kind", "start_date", "parts"],
                "properties": [
                    "title": ["type": "string"], "class_id": ["type": ["string", "null"]], "notes": ["type": "string"],
                    "due_date": ["type": ["string", "null"]], "due_time": ["type": ["string", "null"]],
                    "all_day": ["type": "boolean"], "date_quote": ["type": ["string", "null"]],
                    "kind": ["type": "string", "enum": ["homework", "revision", "event"]],
                    "start_date": ["type": ["string", "null"]], "parts": ["type": ["integer", "null"]]
                ]
            ]]
        ]
    ]
    static func decode(_ content: String) throws -> AIExtraction {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 100_000, let data = trimmed.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIExtraction.self, from: data), result.tasks.count <= 20,
              result.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 160 && $0.notes.count <= 8000 && ["homework", "revision", "event"].contains($0.kind) && ($0.parts.map { (1...99).contains($0) } ?? true) }) else {
            throw AIError.message("The model did not return usable task details. Nothing was added. Try a clearer screenshot, shorter text, or another model.")
        }
        return result
    }
}

struct AIImportDraft: Identifiable, Codable, Equatable {
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
    static func parsedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"(?<=\d)(st|nd|rd|th)\b"#, with: "", options: .regularExpression)
        if let result = date(clean) { return result }
        if clean.range(of: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}"#, options: .regularExpression) != nil { return date(String(clean.prefix(10))) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        formatter.timeZone = .current
        for format in ["MMMM d, yyyy", "MMMM d yyyy", "d MMMM yyyy"] {
            formatter.dateFormat = format
            if let result = formatter.date(from: clean), formatter.string(from: result).lowercased() == clean.lowercased() { return result }
        }
        return nil
    }
    static func parsedTime(_ value: String?) -> (Int, Int)? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^(\d{1,2}):(\d{2})(?::00)?\s*(AM|PM)?$|^(\d{1,2})\s*(AM|PM)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) else { return nil }
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: clean).map { String(clean[$0]) } }
        guard var hour = Int(group(1) ?? group(4) ?? ""), let minute = Int(group(2) ?? "0"), (0...59).contains(minute) else { return nil }
        if let period = group(3) ?? group(5) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (period == "PM" ? 12 : 0)
        }
        guard (0...23).contains(hour) else { return nil }
        return (hour, minute)
    }
    /// A single, fully specified date in the latest instruction wins over a model's stale draft.
    static func applyingExplicitDate(to extraction: AIExtraction, latestMessage: String, now: Date = Date(), calendar: Calendar = .current, preserveTime: Bool = false) -> AIExtraction {
        guard extraction.tasks.count == 1 else { return extraction }
        let months = "January|February|March|April|May|June|July|August|September|October|November|December"
        let pattern = #"(?i)\b(?:\d{4}-\d{2}-\d{2}|(?:"# + months + #") \d{1,2}(?:st|nd|rd|th)?,? \d{4}|\d{1,2}(?:st|nd|rd|th)? (?:"# + months + #") \d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return extraction }
        let matches = regex.matches(in: latestMessage, range: NSRange(latestMessage.startIndex..., in: latestMessage))
        let explicit = matches.count == 1 ? Range(matches[0].range, in: latestMessage).flatMap { parsedDate(String(latestMessage[$0])) } : nil
        let relative = RelativeDate.resolve(latestMessage, now: now, calendar: calendar)
        guard matches.count <= 1, let day = explicit ?? relative else { return extraction }
        var result = extraction
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        result.tasks[0].dueDate = formatter.string(from: day)
        result.tasks[0].dateQuote = latestMessage
        if !preserveTime { result.tasks[0].dueTime = nil; result.tasks[0].allDay = true }
        let timePattern = #"(?i)\b(?:at\s+)?(\d{1,2}:\d{2}(?::00)?\s*(?:AM|PM)?|\d{1,2}\s*(?:AM|PM))\b"#
        if let timeRegex = try? NSRegularExpression(pattern: timePattern) {
            let times = timeRegex.matches(in: latestMessage, range: NSRange(latestMessage.startIndex..., in: latestMessage))
            if times.count == 1, let timeRange = Range(times[0].range(at: 1), in: latestMessage), let time = parsedTime(String(latestMessage[timeRange])) {
                result.tasks[0].dueTime = String(format: "%02d:%02d", time.0, time.1)
                result.tasks[0].allDay = false
            }
        }
        return result
    }
    static func reviewQuestions(_ drafts: [AIImportDraft], proposed: [AIQuestion]) -> [AIQuestion] {
        guard !drafts.isEmpty else { return proposed }
        let missingDate = drafts.contains { !$0.dateConfirmed }
        let missingTime = drafts.contains { !$0.timeConfirmed }
        let missingClass = drafts.contains { !$0.classConfirmed }
        var result = proposed.filter { question in
            let title = normalized(question.title)
            if !missingDate && ["date", "deadline", "when", "due"].contains(where: title.contains) { return false }
            if !missingTime && title.contains("time") { return false }
            if !missingClass && ["class", "subject"].contains(where: title.contains) { return false }
            return true
        }
        if missingDate && !result.contains(where: { normalized($0.title).contains("date") || normalized($0.title).contains("due") }) {
            result.insert(AIQuestion(title: "What date should I use? You can choose it in the calendar below.", options: []), at: 0)
        }
        if missingTime { result.insert(AIQuestion(title: "What time should I use, or is this all day?", options: ["All day"]), at: 0) }
        if missingClass { result.insert(AIQuestion(title: "Which class is this for?", options: []), at: 0) }
        return AIQuestion.cleaned(result)
    }
    static func reviewSummary(_ drafts: [AIImportDraft]) -> String {
        guard !drafts.isEmpty else { return "I need more details before I can prepare an item. Nothing has been added." }
        return "Ready to review—not added yet.\n" + drafts.map { draft in
            let when = !draft.dateConfirmed ? "Choose a date" : !draft.timeConfirmed ? "\(draft.task.due.formatted(date: .abbreviated, time: .omitted)) · choose a time or All day" : draft.task.deadlineText
            return "\(draft.task.title) · \(when)"
        }.joined(separator: "\n")
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
            let mentioned = classes.filter { schoolClass in
                normalized(source).range(of: #"\b"# + NSRegularExpression.escapedPattern(for: normalized(schoolClass.name)) + #"\b"#, options: .regularExpression) != nil
            }
            let named = mentioned.first { $0.id == item.classID.flatMap(UUID.init(uuidString:)) || normalized($0.name) == normalized(item.classID ?? "") }
            let schoolClass = selected ?? named ?? (mentioned.count == 1 ? mentioned.first : nil)
            let day = parsedDate(item.dueDate)
            let time = parsedTime(item.dueTime)
            let due = day.map { day in
                guard !item.allDay, let time else { return day }
                return Calendar.current.date(bySettingHour: time.0, minute: time.1, second: 0, of: day) ?? day
            }
            let quote = item.dateQuote ?? ""
            let evidence = !quote.isEmpty && normalized(source).contains(normalized(quote))
            var task = StudyTask(title: item.title.trimmingCharacters(in: .whitespacesAndNewlines), classID: schoolClass?.id ?? classes.first?.id ?? UUID(), notes: item.notes, due: due ?? now, attachments: attachments)
            task.work = TaskPlan(kind: TaskKind(rawValue: item.kind) ?? .homework, allDay: item.allDay, sessionTarget: item.parts)
            if task.isEvent { task.reconcileCompletion() }
            // Starting work is a suggestion, not an inferred requirement.
            if !task.isEvent, let start = item.startDate.flatMap({ date($0) }), start <= task.due { task.start = start }
            var questions: [String] = []
            if let start = item.startDate, date(start) == nil || (date(start) ?? now) > task.due { questions.append("Check the suggested work start date.") }
            if task.isRevision && task.targetCount() > task.scheduledDayCount() { questions.append("There aren’t enough study days for the suggested sessions.") }
            task.aiSource = AITaskSource(text: source, model: model, capturedAt: now)
            let draft = AIImportDraft(task: task, classConfirmed: schoolClass != nil, dateConfirmed: due != nil,
                                      timeConfirmed: item.allDay || time != nil,
                                      evidenceConfirmed: evidence, questions: questions, dateQuote: quote,
                                      duplicate: duplicate(task, in: already))
            already.append(task)
            return draft
        }
    }
}
