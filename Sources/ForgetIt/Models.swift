import Foundation
import SwiftUI

struct SchoolClass: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: String = "lavender"
    var notes = ""
    static let colors = ["lavender", "blue", "mint", "peach", "rose", "yellow"]
    var tint: Color { Self.tint(color) }
    static func tint(_ name: String) -> Color {
        switch name {
        case "blue": return Color(red: 0.32, green: 0.60, blue: 0.91)
        case "mint": return Color(red: 0.23, green: 0.65, blue: 0.52)
        case "peach": return Color(red: 0.89, green: 0.52, blue: 0.30)
        case "rose": return Color(red: 0.84, green: 0.38, blue: 0.54)
        case "yellow": return Color(red: 0.73, green: 0.60, blue: 0.19)
        default: return Color(red: 0.58, green: 0.48, blue: 0.84)
        }
    }
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case off, deadline, oneDay, threeDays, dailyWeek, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "No reminders"
        case .deadline: return "At the deadline"
        case .oneDay: return "One day before"
        case .threeDays: return "Three days before"
        case .dailyWeek: return "Daily, starting one week before"
        case .custom: return "Custom schedule"
        }
    }
}

struct ReminderRule: Codable, Equatable {
    var kind: ReminderKind = .off
    var leadDays = 7
    var hour = 16
    var minute = 0
    var repeatDaily = false
    var continueAfterDeadline = false

    func dates(due: Date, now: Date, calendar: Calendar = .current) -> [Date] {
        func subtract(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: due)!
        }
        switch kind {
        case .off: return []
        case .deadline: return due > now ? [due] : []
        case .oneDay: return subtract(1) > now ? [subtract(1)] : []
        case .threeDays: return subtract(3) > now ? [subtract(3)] : []
        case .dailyWeek, .custom:
            let lead = kind == .dailyWeek ? 7 : min(60, max(0, leadDays))
            let repeats = kind == .dailyWeek || repeatDaily
            let lastOffset = repeats ? (continueAfterDeadline ? 7 : 0) : -lead
            return (-lead...lastOffset).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: due),
                      let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      date > now, continueAfterDeadline || date <= due else { return nil }
                return date
            }
        }
    }
}

struct Attachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var data: Data
}

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case homework, revision, event
    var id: String { rawValue }
    var title: String { self == .event ? "Event" : self == .homework ? "Homework" : "Revision" }
}

struct WorkSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var day: Date
    var completedAt: Date
}

struct TaskPlan: Codable, Equatable {
    var kind: TaskKind = .homework
    var allDay = false
    // nil means one part for homework, or one session per available day for revision.
    var sessionTarget: Int?
    var excludedWeekdays: Set<Int> = []
    var sessions: [WorkSession] = []
}

struct StudyTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = ""
    var classID: UUID
    var notes = ""
    var due: Date = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
    var start: Date?
    var completedAt: Date?
    var reminder: ReminderRule?
    var attachments: [Attachment] = []
    // Optional for lossless decoding of version 0.1 planners and backups.
    var plan: TaskPlan?
    var aiSource: AITaskSource?
    var repeatRule: TaskRepeat?
    var seriesID: UUID?
    var work: TaskPlan {
        get { plan ?? TaskPlan() }
        set { plan = newValue }
    }
    var isEvent: Bool { work.kind == .event }
    var isRevision: Bool { work.kind == .revision }
    var isAllDay: Bool { work.allDay }
    var isComplete: Bool { completedAt != nil }
    func deadline(calendar: Calendar = .current) -> Date {
        guard isAllDay else { return due }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due))!.addingTimeInterval(-1)
    }
    var deadlineText: String { isAllDay ? "\(due.formatted(date: .abbreviated, time: .omitted)) · All day" : due.clockDateTime }
    func isOverdue(at date: Date = Date()) -> Bool { !isEvent && !isComplete && deadline() < date }
    var displayStart: Date { min(start ?? due, due) }
    var activeEnd: Date { due }
    func isWorkDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        return day >= calendar.startOfDay(for: displayStart) && day <= calendar.startOfDay(for: due)
            && !work.excludedWeekdays.contains(calendar.component(.weekday, from: day))
    }
    func scheduledDayCount(calendar: Calendar = .current) -> Int {
        let first = calendar.startOfDay(for: displayStart)
        let count = max(0, (calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: due)).day ?? 0) + 1)
        let fullWeeks = count / 7
        let firstWeekday = calendar.component(.weekday, from: first)
        return fullWeeks * (7 - work.excludedWeekdays.count) + (0..<(count % 7)).filter {
            !work.excludedWeekdays.contains((firstWeekday - 1 + $0) % 7 + 1)
        }.count
    }
    func targetCount(calendar: Calendar = .current) -> Int { work.sessionTarget ?? (isRevision ? max(1, scheduledDayCount(calendar: calendar)) : 1) }
    var progressCount: Int { work.sessions.isEmpty && isComplete ? 1 : work.sessions.count }
    var progressText: String {
        if isEvent { return "Event" }
        let noun = isRevision ? (targetCount() == 1 ? "session" : "sessions") : (targetCount() == 1 ? "part" : "parts")
        return "\(progressCount) of \(targetCount()) \(noun)"
    }
    func didStudy(on day: Date, calendar: Calendar = .current) -> Bool {
        work.sessions.contains { calendar.isDate($0.day, inSameDayAs: day) }
    }
    func canRecord(on day: Date, calendar: Calendar = .current) -> Bool {
        !isEvent && !isComplete && (!isRevision || (isWorkDay(day, calendar: calendar) && !didStudy(on: day, calendar: calendar)))
    }
    mutating func recordProgress(on day: Date, at now: Date = Date(), calendar: Calendar = .current) {
        guard canRecord(on: day, calendar: calendar) else { return }
        work.sessions.append(WorkSession(day: calendar.startOfDay(for: day), completedAt: now))
        if work.sessions.count >= targetCount(calendar: calendar) { completedAt = now }
    }
    mutating func removeSession(_ id: UUID) {
        work.sessions.removeAll { $0.id == id }
        completedAt = nil
    }
    mutating func reopen() {
        if !work.sessions.isEmpty { work.sessions.removeLast() }
        completedAt = nil
    }
    mutating func reconcileCompletion(calendar: Calendar = .current) {
        if isEvent { start = nil; completedAt = nil; work.sessionTarget = nil; work.sessions = []; work.excludedWeekdays = []; return }
        // A completion from the old app represents one session, never all newly added parts.
        if let oldCompletion = completedAt, work.sessions.isEmpty, targetCount(calendar: calendar) > 1 {
            work.sessions = [WorkSession(day: calendar.startOfDay(for: oldCompletion), completedAt: oldCompletion)]
        }
        if !work.sessions.isEmpty {
            completedAt = work.sessions.count >= targetCount(calendar: calendar) ? work.sessions.last?.completedAt : nil
        }
    }
    func reminderDates(rule: ReminderRule, now: Date, calendar: Calendar = .current) -> [Date] {
        guard !isComplete else { return [] }
        // All-day alerts use the chosen reminder time, never an arbitrary hidden deadline time.
        let reminderDue = isAllDay ? calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: due)! : due
        return rule.dates(due: reminderDue, now: now, calendar: calendar).filter { date in
            if isEvent && date > reminderDue { return false }
            let daily = rule.kind == .dailyWeek || (rule.kind == .custom && rule.repeatDaily)
            if daily && work.excludedWeekdays.contains(calendar.component(.weekday, from: date)) { return false }
            if isRevision && didStudy(on: date, calendar: calendar) { return false }
            return true
        }
    }
}

struct PlannerData: Codable, Equatable {
    var version = 2
    var classes: [SchoolClass] = []
    var tasks: [StudyTask] = []
    var defaultReminder: ReminderRule?
    var timetable: [TimetableLesson]?
}

struct CalendarSegment: Identifiable {
    var task: StudyTask
    var startColumn: Int
    var endColumn: Int
    var lane: Int
    var hasDeadline: Bool
    var isDone = false
    var deadlineOnly = false
    var id: String { "\(task.id)-\(startColumn)-\(endColumn)" }
}

enum CalendarLayout {
    static func segments(tasks: [StudyTask], weekStart: Date, calendar: Calendar = .current) -> [CalendarSegment] {
        let first = calendar.startOfDay(for: weekStart)
        let sorted = tasks.sorted {
            if $0.displayStart != $1.displayStart { return $0.displayStart < $1.displayStart }
            if $0.due != $1.due { return $0.due > $1.due }
            return $0.id.uuidString < $1.id.uuidString
        }
        var occupied: [Set<Int>] = []
        var result: [CalendarSegment] = []
        for task in sorted {
            // Homework vanishes from the calendar on final completion; the Completed list retains it.
            guard task.isRevision || !task.isComplete else { continue }
            var pieces: [CalendarSegment] = []
            for column in 0..<7 {
                let day = calendar.date(byAdding: .day, value: column, to: first)!
                let deadline = calendar.isDate(day, inSameDayAs: task.due)
                let done = task.isRevision && task.didStudy(on: day, calendar: calendar)
                let workDay = task.isWorkDay(day, calendar: calendar)
                guard (workDay && (!task.isComplete || done)) || (deadline && !task.isComplete) else { continue }
                let deadlineOnly = !workDay
                if let previous = pieces.last, previous.endColumn == column - 1, previous.isDone == done,
                   !deadlineOnly, !previous.deadlineOnly {
                    pieces[pieces.count - 1].endColumn = column
                    pieces[pieces.count - 1].hasDeadline = deadline
                } else {
                    pieces.append(CalendarSegment(task: task, startColumn: column, endColumn: column, lane: 0,
                                                   hasDeadline: deadline, isDone: done, deadlineOnly: deadlineOnly))
                }
            }
            guard !pieces.isEmpty else { continue }
            let columns = Set(pieces.flatMap { Array($0.startColumn...$0.endColumn) })
            let lane = occupied.firstIndex { $0.isDisjoint(with: columns) } ?? occupied.count
            if lane == occupied.count { occupied.append(columns) } else { occupied[lane].formUnion(columns) }
            for var piece in pieces { piece.lane = lane; result.append(piece) }
        }
        return result
    }
}
