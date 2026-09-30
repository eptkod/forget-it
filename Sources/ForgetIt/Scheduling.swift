import Foundation

/// Resolve only a single unambiguous relative date, using calendar arithmetic across DST.
enum RelativeDate {
    static func resolve(_ text: String, now: Date, calendar: Calendar = .current) -> Date? {
        let pattern = #"(?i)\b(day after tomorrow|tomorrow|today|in \d{1,3} (?:days?|weeks?)|(?:next |this )?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range, in: text) else { return nil }
        let value = text[range].lowercased()
        let today = calendar.startOfDay(for: now)
        var offset = 0
        if value == "tomorrow" { offset = 1 }
        else if value == "day after tomorrow" { offset = 2 }
        else if value.hasPrefix("in ") {
            let words = value.split(separator: " ")
            offset = (Int(words[1]) ?? 0) * (words[2].hasPrefix("week") ? 7 : 1)
        } else if value != "today" {
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            guard let index = weekdays.firstIndex(where: { value.hasSuffix($0) }) else { return nil }
            offset = (index + 1 - calendar.component(.weekday, from: today) + 7) % 7
            if offset == 0 && !value.hasPrefix("this ") { offset = 7 }
        }
        return calendar.date(byAdding: .day, value: offset, to: today)
    }
}

struct TaskRepeat: Codable, Equatable {
    var frequency = "Weekly"
    var until = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
    func dates(from start: Date, calendar: Calendar = .current) -> [Date] {
        guard until >= calendar.startOfDay(for: start) else { return [] }
        var result: [Date] = frequency == "Weekdays" && calendar.isDateInWeekend(start) ? [] : [start]
        var cursor = start
        while result.count < 366 {
            let component: Calendar.Component = frequency == "Monthly" ? .month : .day
            let step = frequency == "Weekly" ? 7 : 1
            // Anchor monthly dates to the original day, avoiding February drift.
            let next = component == .month ? calendar.date(byAdding: .month, value: result.count, to: start) : calendar.date(byAdding: component, value: step, to: cursor)
            guard let next, calendar.startOfDay(for: next) <= calendar.startOfDay(for: until) else { break }
            cursor = next
            if frequency == "Weekdays" && calendar.isDateInWeekend(next) { continue }
            result.append(next)
        }
        return result
    }
    func occurrences(of task: StudyTask, calendar: Calendar = .current) -> [StudyTask] {
        let series = UUID()
        return dates(from: task.due, calendar: calendar).enumerated().map { index, date in
            var copy = task
            copy.id = index == 0 ? task.id : UUID(); copy.seriesID = series; copy.repeatRule = nil
            copy.due = date
            if let start = task.start {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: task.due), to: calendar.startOfDay(for: date)).day ?? 0
                copy.start = calendar.date(byAdding: .day, value: days, to: start)
            }
            copy.completedAt = nil; copy.work.sessions = []
            return copy
        }
    }
}

/// Narrow fast path for explicit single-task reminders; complex requests still go to the model.
enum SimpleTaskInstruction {
    static func extraction(_ text: String, now: Date = Date(), calendar: Calendar = .current, previous: AIConversation = AIConversation()) -> AIExtraction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let months = "January|February|March|April|May|June|July|August|September|October|November|December"
        let datePattern = #"(?:\d{4}-\d{2}-\d{2}|(?:"# + months + #") \d{1,2}(?:st|nd|rd|th)?,? \d{4}|today|tomorrow|day after tomorrow)"#
        let timePattern = #"(?:\d{1,2}:\d{2}\s*(?:am|pm)?|\d{1,2}\s*(?:am|pm))"#
        let tailPattern = #"\s+(?:for [\p{L}\p{N} _-]+ )?(?:on )?"# + datePattern + #"(?:\s+at\s+"# + timePattern + #")?[.!]?$"#
        let named = try! NSRegularExpression(pattern: #"(?i)^(?:please\s+)?(?:create|add|set)\s+(?:a[n]?\s+)?(event|task|homework task)\s+(?:called|named)\s+['"]([^'"]{1,160})['"]"# + tailPattern)
        if previous.drafts.isEmpty, !trimmed.localizedCaseInsensitiveContains(" and "),
           let match = named.firstMatch(in: trimmed, range: range),
           let titleRange = Range(match.range(at: 2), in: trimmed), let kindRange = Range(match.range(at: 1), in: trimmed) {
            let item = AIExtractedTask(title: String(trimmed[titleRange]), notes: text, allDay: true, kind: trimmed[kindRange].lowercased() == "event" ? "event" : "homework")
            let result = AIImportValidation.applyingExplicitDate(to: AIExtraction(summary: "", questions: [], tasks: [item], followUps: []), latestMessage: text, now: now, calendar: calendar)
            if result.tasks[0].dueDate != nil { return result }
        }
        let correction = try! NSRegularExpression(pattern: #"(?i)^(?:actually[, ]+)?(?:move it to|change (?:it|the date) to|make it)\s+"# + datePattern + #"(?:\s+at\s+"# + timePattern + #")?[.!]?$"#)
        if previous.drafts.count == 1, correction.firstMatch(in: trimmed, range: range) != nil {
            let draft = previous.drafts[0]
            let task = draft.task
            let clock = DateFormatter(); clock.locale = Locale(identifier: "en_US_POSIX"); clock.timeZone = calendar.timeZone; clock.dateFormat = "HH:mm"
            let item = AIExtractedTask(title: task.title, classID: draft.classConfirmed ? task.classID.uuidString : nil, notes: task.notes, dueTime: task.isAllDay ? nil : clock.string(from: task.due), allDay: task.isAllDay, kind: task.work.kind.rawValue, startDate: task.start.map(AIImportPrompt.localDay), parts: task.work.sessionTarget)
            let result = AIImportValidation.applyingExplicitDate(to: AIExtraction(summary: "", questions: [], tasks: [item], followUps: []), latestMessage: text, now: now, calendar: calendar, preserveTime: true)
            if result.tasks[0].dueDate != nil { return result }
        }
        guard previous.drafts.isEmpty, RelativeDate.resolve(text, now: now, calendar: calendar) != nil,
              !text.localizedCaseInsensitiveContains(" and "), !text.contains("\n"),
              let regex = try? NSRegularExpression(pattern: #"(?i)^\s*(?:please\s+)?(?:set|add|create)\s+(?:a\s+)?task\s+(?:today|tomorrow|the day after tomorrow|day after tomorrow)\s+(?:reminding me to|to)\s+(.+?)\s*[.!]?\s*$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        let title = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { return nil }
        let task = AIExtractedTask(title: title.prefix(1).uppercased() + title.dropFirst(), notes: "", allDay: true, kind: "homework")
        return AIImportValidation.applyingExplicitDate(to: AIExtraction(summary: "", questions: [], tasks: [task], followUps: []), latestMessage: text, now: now, calendar: calendar)
    }
}
