import Foundation

struct PlannerTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    func date(_ day: Int, hour: Int = 17, month: Int = 3) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    func testSpanIsOneSegmentAndDeadlineAtEnd() {
        var task = StudyTask(classID: UUID()); task.start = date(2); task.due = date(6)
        let segments = CalendarLayout.segments(tasks: [task], weekStart: date(1), calendar: calendar)
        expect(segments.count == 1)
        expect(segments[0].startColumn == 1)
        expect(segments[0].endColumn == 5)
        expect(segments[0].hasDeadline)
    }
    func testCrossWeekSpanAndCollisionLanes() {
        var long = StudyTask(classID: UUID()); long.start = date(3); long.due = date(12)
        var short = StudyTask(classID: long.classID); short.due = date(9)
        let segments = CalendarLayout.segments(tasks: [short, long], weekStart: date(8), calendar: calendar)
        expect(segments.count == 2)
        expect(segments.first { $0.task.id == long.id }?.startColumn == 0)
        expect(Set(segments.map(\.lane)).count == 2)
    }
    func testCompletedHomeworkDisappearsAcrossWholeSpan() {
        var task = StudyTask(classID: UUID()); task.start = date(2); task.due = date(6)
        task.recordProgress(on: date(4), at: date(4), calendar: calendar)
        expect(task.isComplete)
        expect(CalendarLayout.segments(tasks: [task], weekStart: date(1), calendar: calendar).isEmpty)
    }
    func testRevisionOnlyCrossesOutCompletedDay() {
        var task = StudyTask(classID: UUID()); task.start = date(2); task.due = date(6)
        task.plan = TaskPlan(kind: .revision)
        task.recordProgress(on: date(3), at: date(3), calendar: calendar)
        let segments = CalendarLayout.segments(tasks: [task], weekStart: date(1), calendar: calendar)
        expect(!task.isComplete)
        expect(segments.filter(\.isDone).count == 1)
        expect(segments.first(where: \.isDone)?.startColumn == 2)
        expect(segments.first(where: \.isDone)?.endColumn == 2)
        expect(segments.contains { !$0.isDone && $0.startColumn == 3 && $0.endColumn == 5 })
        expect(Set(segments.map(\.id)).count == segments.count)
        task.recordProgress(on: date(3), at: date(3), calendar: calendar)
        expect(task.work.sessions.count == 1) // No accidental double session for the same day.
    }
    func testHomeworkNeedsThreePartsAndReopensOnePart() {
        var task = StudyTask(classID: UUID()); task.plan = TaskPlan(sessionTarget: 3)
        for index in 1...2 {
            task.recordProgress(on: date(index), calendar: calendar)
            expect(!task.isComplete)
        }
        task.recordProgress(on: date(3), calendar: calendar)
        expect(task.isComplete && task.progressCount == 3)
        task.recordProgress(on: date(4), calendar: calendar)
        expect(task.progressCount == 3)
        task.reopen()
        expect(!task.isComplete && task.progressCount == 2)
    }
    func testRevisionSessionGoalAndUndo() {
        var task = StudyTask(classID: UUID()); task.start = date(2); task.due = date(6)
        task.plan = TaskPlan(kind: .revision, sessionTarget: 3)
        for day in 2...4 { task.recordProgress(on: date(day), calendar: calendar) }
        expect(task.isComplete)
        let pieces = CalendarLayout.segments(tasks: [task], weekStart: date(1), calendar: calendar)
        expect(pieces.allSatisfy(\.isDone))
        expect(pieces.last?.endColumn == 3) // Future unused sessions disappear after the chosen goal.
        task.removeSession(task.work.sessions[1].id)
        expect(!task.isComplete && task.progressCount == 2)
        expect(!task.didStudy(on: date(3), calendar: calendar))
    }
    func testExcludedDaysSplitBarButKeepDeadline() {
        var task = StudyTask(classID: UUID()); task.start = date(5); task.due = date(8)
        task.plan = TaskPlan(kind: .revision, excludedWeekdays: [1, 7])
        expect(task.scheduledDayCount(calendar: calendar) == 2)
        expect(!task.canRecord(on: date(7), calendar: calendar))
        let first = CalendarLayout.segments(tasks: [task], weekStart: date(1), calendar: calendar)
        expect(first.count == 1 && first[0].startColumn == 4 && first[0].endColumn == 5)
        let second = CalendarLayout.segments(tasks: [task], weekStart: date(8), calendar: calendar)
        expect(second.count == 1 && second[0].deadlineOnly && second[0].hasDeadline)
    }
    func testAllDayDeadlineAndChosenReminderTime() {
        var task = StudyTask(classID: UUID()); task.due = date(8, hour: 5); task.plan = TaskPlan(allDay: true)
        let end = task.deadline(calendar: calendar)
        expect(calendar.component(.hour, from: end) == 23)
        expect(end > date(8, hour: 22))
        let alerts = task.reminderDates(rule: ReminderRule(kind: .deadline, hour: 9), now: date(7), calendar: calendar)
        expect(alerts.count == 1 && calendar.component(.hour, from: alerts[0]) == 9)
        expect(calendar.isDate(alerts[0], inSameDayAs: task.due))
    }
    func testExcludedDailyAlertsAndCompletedSessionAlerts() {
        var task = StudyTask(classID: UUID()); task.start = date(2); task.due = date(10)
        task.plan = TaskPlan(kind: .revision, excludedWeekdays: [1, 7])
        task.recordProgress(on: date(5), calendar: calendar)
        let alerts = task.reminderDates(rule: ReminderRule(kind: .dailyWeek), now: date(1), calendar: calendar)
        expect(!alerts.contains { [1, 7].contains(calendar.component(.weekday, from: $0)) || calendar.component(.day, from: $0) == 5 })
    }
    func testWorkdayCountForLongSpanMatchesEnumeration() {
        var task = StudyTask(classID: UUID()); task.start = date(1); task.due = date(30)
        task.plan = TaskPlan(kind: .revision, excludedWeekdays: [1, 3, 7])
        let count = (1...30).filter { task.isWorkDay(date($0), calendar: calendar) }.count
        expect(task.scheduledDayCount(calendar: calendar) == count)
    }
    func testAddingPartsToOldCompletedTaskRetainsOnlyOneCompletion() {
        var task = StudyTask(classID: UUID()); task.completedAt = date(4)
        task.work.sessionTarget = 3
        task.reconcileCompletion(calendar: calendar)
        expect(!task.isComplete && task.progressCount == 1)
        expect(task.work.sessions[0].completedAt == date(4))
    }
    @MainActor func testLegacyPlannerDecodesWithoutChangingTasks() throws {
        let schoolClass = SchoolClass(name: "Math")
        var task = StudyTask(title: "Existing homework", classID: schoolClass.id)
        task.start = date(2); task.due = date(6); task.completedAt = date(4)
        let old = PlannerData(version: 1, classes: [schoolClass], tasks: [task])
        let bytes = try JSONEncoder().encode(old)
        expect(!String(decoding: bytes, as: UTF8.self).contains("plan\""))
        let decoded = try PlannerStore.decode(bytes)
        expect(decoded.tasks[0] == task)
        expect(decoded.tasks[0].work.kind == .homework)
    }
    @MainActor func testUndoRestoresProgressAndDeletion() {
        let store = PlannerStore(preview: true)
        let schoolClass = SchoolClass(name: "Test")
        let task = StudyTask(title: "Three parts", classID: schoolClass.id, plan: TaskPlan(sessionTarget: 3))
        store.commit(PlannerData(classes: [schoolClass], tasks: [task]), recordUndo: false)
        store.recordProgress(task)
        expect(store.data.tasks[0].progressCount == 1 && store.canUndo)
        store.undo()
        expect(store.data.tasks[0].progressCount == 0)
        store.delete(task)
        expect(store.data.tasks.isEmpty)
        store.undo()
        expect(store.data.tasks == [task])
    }
    func testDailyReminderAcrossDSTUsesLocalHourAndStopsAtDeadline() {
        let rule = ReminderRule(kind: .dailyWeek, hour: 16)
        let dates = rule.dates(due: date(10), now: date(1), calendar: calendar)
        expect(dates.count == 8)
        expect(dates.allSatisfy { calendar.component(.hour, from: $0) == 16 })
        expect(Set(dates).count == dates.count)
        expect(dates.allSatisfy { $0 <= date(10) })
    }
    func testNoCatchUpAlertsAndExplicitOverdueLimit() {
        let off = ReminderRule()
        expect(off.dates(due: date(10), now: date(1), calendar: calendar).isEmpty)
        var rule = ReminderRule(kind: .dailyWeek, hour: 16)
        expect(rule.dates(due: date(10), now: date(11), calendar: calendar).isEmpty)
        rule.continueAfterDeadline = true
        let dates = rule.dates(due: date(10), now: date(11), calendar: calendar)
        expect(dates.count == 6)
        expect(calendar.component(.day, from: dates.last!) == 17)
    }
    func testCustomSingleReminderAndDeadlineBeforeReminderTime() {
        let rule = ReminderRule(kind: .custom, leadDays: 2, hour: 16)
        expect(rule.dates(due: date(10), now: date(1), calendar: calendar) == [date(8, hour: 16)])
        let daily = ReminderRule(kind: .dailyWeek, hour: 16)
        expect(daily.dates(due: date(10, hour: 9), now: date(1), calendar: calendar).count == 7)
    }
    @MainActor func testBackupRoundTripIncludesAttachmentsAndRejectsBrokenReferences() throws {
        let schoolClass = SchoolClass(name: "Math")
        var task = StudyTask(title: "Algebra", classID: schoolClass.id)
        task.attachments = [Attachment(name: "notes.txt", data: Data("Homework".utf8))]
        var data = PlannerData(classes: [schoolClass], tasks: [task], defaultReminder: ReminderRule(kind: .oneDay))
        let restored = try PlannerStore.decode(JSONEncoder().encode(data))
        expect(restored == data)
        data.classes = []
        expectThrows { _ = try PlannerStore.decode(JSONEncoder().encode(data)) }
    }
    @MainActor func testMalformedReminderBackupRejected() throws {
        var data = PlannerData(); data.defaultReminder = ReminderRule(hour: 99)
        expectThrows { _ = try PlannerStore.decode(JSONEncoder().encode(data)) }
    }
}

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    guard condition() else { fatalError("Assertion failed", file: file, line: line) }
}
func expectThrows(_ body: () throws -> Void, file: StaticString = #file, line: UInt = #line) {
    do { try body() } catch { return }
    fatalError("Expected validation error", file: file, line: line)
}
@main struct TestRunner {
    @MainActor static func main() async throws {
        try runSchedulingTests()
        try runConversationTests()
        try await runAITests()
        let tests = PlannerTests()
        tests.testSpanIsOneSegmentAndDeadlineAtEnd()
        tests.testCrossWeekSpanAndCollisionLanes()
        tests.testCompletedHomeworkDisappearsAcrossWholeSpan()
        tests.testRevisionOnlyCrossesOutCompletedDay()
        tests.testHomeworkNeedsThreePartsAndReopensOnePart()
        tests.testRevisionSessionGoalAndUndo()
        tests.testExcludedDaysSplitBarButKeepDeadline()
        tests.testAllDayDeadlineAndChosenReminderTime()
        tests.testExcludedDailyAlertsAndCompletedSessionAlerts()
        tests.testWorkdayCountForLongSpanMatchesEnumeration()
        tests.testAddingPartsToOldCompletedTaskRetainsOnlyOneCompletion()
        try tests.testLegacyPlannerDecodesWithoutChangingTasks()
        tests.testUndoRestoresProgressAndDeletion()
        tests.testDailyReminderAcrossDSTUsesLocalHourAndStopsAtDeadline()
        tests.testNoCatchUpAlertsAndExplicitOverdueLimit()
        tests.testCustomSingleReminderAndDeadlineBeforeReminderTime()
        try tests.testBackupRoundTripIncludesAttachmentsAndRejectsBrokenReferences()
        try tests.testMalformedReminderBackupRejected()
        print("PASS: 18 planner tests (revision days, parts, undo, exclusions, all-day dates, legacy migration, calendar layout, reminders and backups).")
    }
}
