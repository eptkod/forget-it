import SwiftUI
import UniformTypeIdentifiers

struct TimetableLesson: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var location: String
    var notes: String
}
struct TimetableImport {
    var lessons: [TimetableLesson]
    var warnings: [String]
}

enum TimetableReader {
    struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }
    static func unescape(_ value: String) -> String {
        var result = "", escaped = false
        for character in value {
            if escaped { result.append(character == "n" || character == "N" ? "\n" : character); escaped = false }
            else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        return result
    }
    static func date(_ property: Property) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        if let tz = property.parameters["TZID"] {
            guard let zone = TimeZone(identifier: tz) else { return nil }
            formatter.timeZone = zone
        } else { formatter.timeZone = .current }
        if property.value.hasSuffix("Z") { formatter.timeZone = TimeZone(secondsFromGMT: 0) }
        formatter.dateFormat = property.value.count == 8 ? "yyyyMMdd" : property.value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return formatter.date(from: property.value)
    }
    static func durationEnd(_ value: String, start: Date, calendar: Calendar) -> Date? {
        let regex = try! NSRegularExpression(pattern: #"^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#)
        guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        func number(_ index: Int) -> Int { Range(match.range(at: index), in: value).flatMap { Int(value[$0]) } ?? 0 }
        guard number(1) <= 522, number(2) <= 3660 else { return nil }
        let days = number(1) * 7 + number(2)
        guard days <= 3660, number(3) <= 87600, number(4) <= 5256000, number(5) <= 315360000 else { return nil }
        return calendar.date(byAdding: DateComponents(day: days, hour: number(3), minute: number(4), second: number(5)), to: start)
    }
    static func read(_ data: Data) throws -> TimetableImport {
        guard data.count <= 20_000_000, let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else { throw AIError.message("Choose a UTF-8 iCalendar (.ics) export from your school calendar.") }
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += line.dropFirst() }
            else { lines.append(line) }
        }
        var events: [[Property]] = [], current: [Property]? = nil, nested = 0
        for line in lines {
            if line == "BEGIN:VEVENT" { current = []; nested = 0; continue }
            if line == "END:VEVENT" { if let current { events.append(current) }; current = nil; continue }
            guard current != nil else { continue }
            if line.hasPrefix("BEGIN:") { nested += 1; continue }
            if line.hasPrefix("END:") { nested -= 1; continue }
            guard nested == 0, let colon = line.firstIndex(of: ":") else { continue }
            let components = line[..<colon].split(separator: ";").map(String.init)
            var params: [String: String] = [:]
            for component in components.dropFirst() {
                let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            current!.append(Property(name: components[0].uppercased(), parameters: params, value: String(line[line.index(after: colon)...])))
        }
        guard !events.isEmpty, events.count <= 10_000 else { throw AIError.message("This file has no events, or is too large. Export one school timetable at a time.") }
        var lessons: [String: TimetableLesson] = [:], warnings: [String] = []
        var exceptions: [String: Set<Date>] = [:]
        for event in events {
            if let uid = event.first(where: { $0.name == "UID" })?.value,
               let recurrence = event.first(where: { $0.name == "RECURRENCE-ID" }), let day = date(recurrence) {
                exceptions[uid, default: []].insert(day)
            }
        }
        for event in events {
            func field(_ name: String) -> Property? { event.first { $0.name == name } }
            let title = unescape(field("SUMMARY")?.value ?? "Lesson")
            guard field("STATUS")?.value != "CANCELLED" else { continue }
            guard let property = field("DTSTART"), let start = date(property) else { warnings.append("\(title): unsupported date or time zone; skipped."); continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = property.value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0)! : property.parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current
            let allDay = property.value.count == 8
            let specifiedEnd = field("DTEND").flatMap(date) ?? field("DURATION").flatMap { durationEnd($0.value, start: start, calendar: calendar) }
            if specifiedEnd == nil && (field("DTEND") != nil || field("DURATION") != nil) { warnings.append("\(title): unreadable end time or duration; skipped."); continue }
            let end = specifiedEnd ?? (allDay ? calendar.date(byAdding: .day, value: 1, to: start)! : start)
            guard end >= start, field("EXRULE") == nil, field("RECURRENCE-ID")?.parameters["RANGE"] == nil else { warnings.append("\(title): unsupported recurrence change or invalid end; skipped."); continue }
            let uid = field("UID")?.value ?? "\(title)-\(start.timeIntervalSince1970)"
            var dates = [start]
            if let rule = field("RRULE") {
                do { dates = try occurrences(rule.value, start: start, calendar: calendar, warnings: &warnings) }
                catch { warnings.append("\(title): \(error.localizedDescription)"); continue }
            }
            var excluded = field("RECURRENCE-ID") == nil ? exceptions[uid, default: []] : []
            for entry in event.filter({ $0.name == "EXDATE" || $0.name == "RDATE" }) {
                for value in entry.value.split(separator: ",") {
                    guard let day = date(Property(name: entry.name, parameters: entry.parameters, value: String(value))) else { warnings.append("\(title): could not read a recurrence exception."); continue }
                    if entry.name == "EXDATE" { excluded.insert(day) } else { dates.append(day) }
                }
            }
            for day in Set(dates).subtracting(excluded) {
                let id = "\(uid)|\(day.timeIntervalSince1970)"
                lessons[id] = TimetableLesson(id: id, title: title, start: day, end: calendar.date(byAdding: calendar.dateComponents([.day, .hour, .minute, .second], from: start, to: end), to: day) ?? day, allDay: allDay, location: unescape(field("LOCATION")?.value ?? ""), notes: unescape(field("DESCRIPTION")?.value ?? ""))
            }
            guard lessons.count <= 20_000 else { throw AIError.message("This timetable contains too many lessons. Export a shorter date range.") }
        }
        return TimetableImport(lessons: lessons.values.sorted { $0.start < $1.start }, warnings: Array(Set(warnings)).sorted())
    }
    static func occurrences(_ rule: String, start: Date, calendar: Calendar, warnings: inout [String]) throws -> [Date] {
        var fields: [String: String] = [:]
        for part in rule.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        let supported: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST", "BYMONTHDAY", "BYMONTH"]
        guard Set(fields.keys).isSubset(of: supported), let frequency = fields["FREQ"], ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(frequency) else { throw AIError.message("unsupported repeat rule; skipped.") }
        let interval = Int(fields["INTERVAL"] ?? "1") ?? 0
        let count = Int(fields["COUNT"] ?? "20000") ?? 0
        guard interval > 0, count > 0 else { throw AIError.message("invalid repeat interval; skipped.") }
        let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        let byDay = fields["BYDAY"]?.split(separator: ",").map(String.init) ?? []
        guard byDay.allSatisfy(codes.contains) else { throw AIError.message("ordinal weekday repeats are not supported; skipped.") }
        let until = fields["UNTIL"].flatMap { date(Property(name: "UNTIL", parameters: ["TZID": calendar.timeZone.identifier], value: $0)) }
        if fields["UNTIL"] != nil && until == nil { throw AIError.message("invalid repeat end date; skipped.") }
        let horizon = calendar.date(byAdding: .year, value: 2, to: max(Date(), start))!
        let limit = min(until ?? horizon, horizon)
        if (until == nil && fields["COUNT"] == nil) || (until.map { $0 > horizon } ?? false) { warnings.append("Repeating lessons are imported through \(horizon.formatted(date: .abbreviated, time: .omitted)). Re-import for later dates.") }
        let monthDays = fields["BYMONTHDAY"]?.split(separator: ",").compactMap { Int($0) } ?? []
        let months = fields["BYMONTH"]?.split(separator: ",").compactMap { Int($0) } ?? []
        guard monthDays.allSatisfy({ (1...31).contains($0) }), months.allSatisfy({ (1...12).contains($0) }) else { throw AIError.message("unsupported month rule; skipped.") }
        var weekCalendar = calendar
        weekCalendar.firstWeekday = (codes.firstIndex(of: fields["WKST"] ?? "MO") ?? 1) + 1
        let firstWeek = weekCalendar.dateInterval(of: .weekOfYear, for: start)!.start
        var result: [Date] = [], cursor = start, scanned = 0
        while cursor <= limit && result.count < count && scanned < 36_600 {
            let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: cursor)).day!
            let monthOffset = (calendar.component(.year, from: cursor) - calendar.component(.year, from: start)) * 12 + calendar.component(.month, from: cursor) - calendar.component(.month, from: start)
            let weekOffset = calendar.dateComponents([.day], from: firstWeek, to: weekCalendar.dateInterval(of: .weekOfYear, for: cursor)!.start).day! / 7
            let weekday = codes[calendar.component(.weekday, from: cursor) - 1]
            let sameDay = calendar.component(.day, from: cursor) == calendar.component(.day, from: start)
            let frequencyMatch: Bool
            switch frequency {
            case "DAILY": frequencyMatch = dayOffset % interval == 0
            case "WEEKLY": frequencyMatch = weekOffset % interval == 0 && (byDay.isEmpty ? weekday == codes[calendar.component(.weekday, from: start) - 1] : true)
            case "MONTHLY": frequencyMatch = monthOffset % interval == 0 && (!monthDays.isEmpty || !byDay.isEmpty || sameDay)
            default: frequencyMatch = (calendar.component(.year, from: cursor) - calendar.component(.year, from: start)) % interval == 0 && (!months.isEmpty || calendar.component(.month, from: cursor) == calendar.component(.month, from: start)) && (!monthDays.isEmpty || !byDay.isEmpty || sameDay)
            }
            if frequencyMatch && (byDay.isEmpty || byDay.contains(weekday)) && (monthDays.isEmpty || monthDays.contains(calendar.component(.day, from: cursor))) && (months.isEmpty || months.contains(calendar.component(.month, from: cursor))) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!; scanned += 1
        }
        if scanned == 36_600 { warnings.append("A very long repeat was limited to 100 years from its first lesson.") }
        return result
    }
}

struct TimetableView: View {
    @AppStorage("clockStyle") private var clockStyle = "system"
    @Bindable var store: PlannerStore
    @State private var day = Date()
    @State private var mode: TimetableMode = .day
    @State private var selected: TimetableLesson?
    @State private var pending: TimetableImport?
    @State private var error: String?
    @State private var clear = false
    private var lessons: [TimetableLesson] { store.data.timetable ?? [] }
    var body: some View {
        let _ = clockStyle
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Today") { day = Date() }
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous \(mode.rawValue.lowercased())")
                Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next \(mode.rawValue.lowercased())")
                Text(mode == .day ? day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) : day.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer(minLength: 8)
                Picker("Timetable view", selection: $mode) { ForEach(TimetableMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                Menu {
                    Button("Import Timetable…", systemImage: "square.and.arrow.down", action: importFile)
                    if !lessons.isEmpty { Button("Clear Timetable…", role: .destructive) { clear = true } }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help("Timetable options")
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            if lessons.isEmpty {
                ContentUnavailableView {
                    Label("Your school day, at a glance", systemImage: "calendar")
                } description: {
                    Text("Import your school’s .ics timetable to see lessons here. Tasks and events live in All Calendars.")
                } actions: { Button("Import Timetable…", action: importFile).buttonStyle(.borderedProminent) }
            } else if mode == .month {
                TimetableMonthGrid(day: $day, mode: $mode, lessons: lessons, select: { selected = $0 })
            } else {
                TimetableTimeGrid(day: day, mode: mode, lessons: lessons, select: { selected = $0 })
                    .id("\(mode.rawValue)-\(Calendar.current.startOfDay(for: day))")
            }
        }
        .onAppear { day = Date() }
        .sheet(item: $selected) { lesson in TimetableLessonDetails(lesson: lesson) }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review your timetable").font(.title2.weight(.semibold))
                if let pending {
                    Text("\(pending.lessons.count) lessons. This replaces your imported timetable. Your tasks and events are kept. You can undo the import.")
                    if let first = pending.lessons.first, let last = pending.lessons.last { Text("\(first.start.formatted(date: .abbreviated, time: .omitted)) – \(last.start.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(.secondary) }
                    ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(pending.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }; ForEach(pending.lessons.prefix(12)) { Text("\($0.title) · \($0.start.clockDateTime)") } } }
                    HStack { Button("Cancel") { self.pending = nil }; Spacer(); Button("Import Lessons") { var next = store.data; next.timetable = pending.lessons; if store.commit(next, action: "imported timetable") { day = Date(); self.pending = nil } }.buttonStyle(.borderedProminent).disabled(pending.lessons.isEmpty) }
                }
            }.padding(24).frame(width: 560, height: 460)
        }
        .alert("Couldn’t import timetable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("Clear imported lessons?", isPresented: $clear) { Button("Clear Timetable", role: .destructive) { var next = store.data; next.timetable = []; store.commit(next, action: "cleared timetable") } }
    }
    private func move(_ amount: Int) {
        day = Calendar.current.date(byAdding: mode == .month ? .month : .day, value: amount * (mode == .week ? 7 : 1), to: day)!
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { pending = try TimetableReader.read(Data(contentsOf: url)) } catch { self.error = error.localizedDescription }
    }
}
