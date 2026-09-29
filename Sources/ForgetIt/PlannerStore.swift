import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable
final class PlannerStore {
    var data = PlannerData()
    var error: String?
    var selectedTaskID: UUID?
    var notificationStatus = "Not requested"
    var pendingReminderCount = 0
    var notifications = ReminderService()
    var lastAction: String?
    private var undoHistory: [(PlannerData, String)] = []
    var canUndo: Bool { !undoHistory.isEmpty }
    var undoTitle: String { undoHistory.last.map { "Undo \($0.1)" } ?? "Undo" }
    private var loadFailed = false
    let isPreview: Bool
    private let file: URL

    init(preview: Bool = ProcessInfo.processInfo.arguments.contains("--preview") || Bundle.main.bundleIdentifier == "app.forgetit.preview") {
        isPreview = preview
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForgetIt", isDirectory: true).appendingPathComponent("planner.json")
        if isPreview {
            data = Self.previewData()
            notificationStatus = "Preview · reminders disabled"
            return
        }
        if FileManager.default.fileExists(atPath: file.path) {
            do { data = try Self.decode(Data(contentsOf: file)) }
            catch { self.error = "Your saved planner could not be opened. The original file has been preserved. Restore a backup to continue.\n\(error.localizedDescription)"; loadFailed = true }
        }
        notifications.onOpen = { [weak self] id in self?.selectedTaskID = id }
        refreshReminders()
    }

    static func decode(_ bytes: Data) throws -> PlannerData {
        let decoded = try JSONDecoder().decode(PlannerData.self, from: bytes)
        let ids = Set(decoded.classes.map(\.id))
        guard (1...2).contains(decoded.version), ids.count == decoded.classes.count,
              Set(decoded.tasks.map(\.id)).count == decoded.tasks.count,
              decoded.classes.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              decoded.tasks.allSatisfy({ ids.contains($0.classID) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.start ?? $0.due) <= $0.due }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard decoded.tasks.allSatisfy({ task in
            let work = task.work
            return work.excludedWeekdays.isSubset(of: Set(1...7)) && work.excludedWeekdays.count < 7
                && (work.sessionTarget.map { (1...999).contains($0) } ?? true)
                && Set(work.sessions.map(\.id)).count == work.sessions.count
                && (!task.isRevision || Set(work.sessions.map { Calendar.current.startOfDay(for: $0.day) }).count == work.sessions.count)
        }) else { throw CocoaError(.fileReadCorruptFile) }
        let rules = decoded.tasks.compactMap(\.reminder) + [decoded.defaultReminder].compactMap { $0 }
        guard rules.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute) && (0...60).contains($0.leadDays) }) else { throw CocoaError(.fileReadCorruptFile) }
        return decoded
    }

    @discardableResult
    func commit(_ proposed: PlannerData, action: String = "changes", recordUndo: Bool = true) -> Bool {
        var next = proposed
        next.version = 2
        guard !loadFailed else { error = "Restore a valid backup before saving. Your original planner has not been overwritten."; return false }
        do {
            if !isPreview {
                let bytes = try JSONEncoder().encode(next)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let recovery = file.deletingLastPathComponent().appendingPathComponent("planner-before-v0.2.json")
                if data.version == 1 && FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: recovery.path) {
                    try FileManager.default.copyItem(at: file, to: recovery)
                }
                try bytes.write(to: file, options: .atomic)
            }
            if recordUndo && next != data {
                undoHistory.append((data, action))
                if undoHistory.count > 20 { undoHistory.removeFirst() }
                lastAction = action.prefix(1).uppercased() + action.dropFirst()
            }
            data = next
            refreshReminders()
            return true
        } catch { self.error = "Couldn’t save your changes: \(error.localizedDescription)"; return false }
    }

    func undo() {
        guard let previous = undoHistory.last else { return }
        if commit(previous.0, recordUndo: false) {
            undoHistory.removeLast()
            lastAction = "Undid \(previous.1)"
        }
    }

    @discardableResult
    func save(_ task: StudyTask, action: String = "task changes") -> Bool {
        var next = data
        var task = task
        task.reconcileCompletion()
        if let i = next.tasks.firstIndex(where: { $0.id == task.id }) { next.tasks[i] = task }
        else { next.tasks.append(task) }
        return commit(next, action: action)
    }
    func save(_ schoolClass: SchoolClass) {
        var next = data
        if let i = next.classes.firstIndex(where: { $0.id == schoolClass.id }) { next.classes[i] = schoolClass }
        else { next.classes.append(schoolClass) }
        commit(next)
    }
    func recordProgress(_ task: StudyTask, on day: Date = Date()) {
        guard var next = data.tasks.first(where: { $0.id == task.id }), next.canRecord(on: day) else { return }
        next.recordProgress(on: day)
        save(next, action: next.isComplete ? "completed \(next.title)" : "logged \(next.progressText) for \(next.title)")
    }
    func reopen(_ task: StudyTask) {
        var next = task; next.reopen()
        save(next, action: "reopened \(next.title)")
    }
    func delete(_ task: StudyTask) {
        var next = data
        next.tasks.removeAll { $0.id == task.id }
        commit(next, action: "deleted \(task.title)")
        selectedTaskID = nil
    }
    func schoolClass(for task: StudyTask) -> SchoolClass? { data.classes.first { $0.id == task.classID } }

    func refreshReminders() {
        guard !isPreview else { return }
        notifications.synchronize(data: data) { [weak self] status, count, error in
            self?.notificationStatus = status
            self?.pendingReminderCount = count
            if let error { self?.error = error }
        }
    }
    func requestNotifications() {
        guard !isPreview else { return }
        notifications.requestPermission { [weak self] in self?.refreshReminders() }
    }
    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "forget-it-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: url, options: .atomic)
        } catch { self.error = "Backup failed: \(error.localizedDescription)" }
    }
    func restoreBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let restored = try Self.decode(Data(contentsOf: url))
            let alert = NSAlert()
            alert.messageText = "Replace your planner with this backup?"
            alert.informativeText = "This backup contains \(restored.classes.count) classes and \(restored.tasks.count) tasks. Your current saved file will be kept alongside the planner as a recovery copy."
            alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("before-restore-\(UUID().uuidString).json"))
            }
            loadFailed = false
            commit(restored, action: "restored backup")
        } catch { self.error = "Couldn’t restore this backup: \(error.localizedDescription)" }
    }

    func addAttachments(to task: inout StudyTask) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw NSError(domain: "ForgetIt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Keep each attachment under 20 MB."]) }
                task.attachments.append(Attachment(name: url.lastPathComponent, data: try Data(contentsOf: url)))
            }
        } catch { self.error = error.localizedDescription }
    }
    func openAttachment(_ attachment: Attachment) {
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ForgetIt-\(attachment.id)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(URL(fileURLWithPath: attachment.name).lastPathComponent)
            try attachment.data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch { self.error = error.localizedDescription }
    }

    private static func previewData() -> PlannerData {
        let classes = [SchoolClass(name: "Mathematics", color: "lavender"), SchoolClass(name: "English", color: "blue"), SchoolClass(name: "Biology", color: "mint"), SchoolClass(name: "Media Studies", color: "peach")]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { cal.date(bySettingHour: 17, minute: 0, second: 0, of: cal.date(byAdding: .day, value: offset, to: today)!)! }
        var tasks = [
            StudyTask(title: "Revise quadratic equations", classID: classes[0].id, notes: "Practice completing the square and the quadratic formula.", due: day(2), start: day(-2)),
            StudyTask(title: "Poetry comparison essay", classID: classes[1].id, notes: "Compare imagery and tone. Bring a first draft to class.", due: day(4), start: day(0)),
            StudyTask(title: "Cell structure worksheet", classID: classes[2].id, due: day(1)),
            StudyTask(title: "Revise audience theories", classID: classes[3].id, due: day(-3), start: day(-7), completedAt: day(-4)),
            StudyTask(title: "Lab report: osmosis", classID: classes[2].id, due: day(-1), start: day(-4)),
            StudyTask(title: "Read chapter six", classID: classes[1].id, due: day(-9), completedAt: day(-10))
        ]
        tasks[0].plan = TaskPlan(kind: .revision, allDay: true, sessionTarget: 3, excludedWeekdays: [1, 7])
        tasks[0].recordProgress(on: day(-1))
        tasks[1].plan = TaskPlan(sessionTarget: 3)
        tasks[1].recordProgress(on: day(0))
        return PlannerData(classes: classes, tasks: tasks, defaultReminder: ReminderRule())
    }
}
