import Foundation
import AppKit
import PDFKit

@MainActor func runSchedulingTests() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
    let direct = SimpleTaskInstruction.extraction("set a task tomorrow reminding me to write a media essay", now: now, calendar: calendar)!
    expect(direct.tasks.count == 1 && direct.tasks[0].dueDate == "2026-03-08" && direct.tasks[0].allDay)
    expect(direct.tasks[0].title == "Write a media essay")
    var inventedTime = direct; inventedTime.tasks[0].dueTime = "09:00"; inventedTime.tasks[0].allDay = false
    let repairedTime = AIImportValidation.applyingExplicitDate(to: inventedTime, latestMessage: "Do my essay tomorrow", now: now, calendar: calendar)
    expect(repairedTime.tasks[0].dueTime == nil && repairedTime.tasks[0].allDay)
    expect(RelativeDate.resolve("tomorrow or Monday", now: now, calendar: calendar) == nil)
    expect(RelativeDate.resolve("day after tomorrow", now: now, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))
    let named = SimpleTaskInstruction.extraction("Create an event called 'test' for Media on October 3rd, 2026 at 3pm.")!
    expect(SimpleTaskInstruction.extraction("Create an event called 'test' tomorrow with three parts") == nil)
    expect(named.tasks[0].title == "test" && named.tasks[0].dueDate == "2026-10-03" && named.tasks[0].dueTime == "15:00")
    let media = SchoolClass(name: "Media")
    let drafts = AIImportValidation.drafts(from: direct, source: "set a task tomorrow reminding me to write a media essay", attachments: [], classes: [media], selectedClass: nil, existing: [], model: "test")
    expect(drafts[0].dateConfirmed && drafts[0].timeConfirmed && drafts[0].classConfirmed)
    expect(AIImportValidation.reviewQuestions(drafts, proposed: [AIQuestion(title: "When should I make the task?", options: [])]).isEmpty)
    let rule = TaskRepeat(frequency: "Daily", until: calendar.date(byAdding: .day, value: 3, to: now)!)
    let weekdays = TaskRepeat(frequency: "Weekdays", until: calendar.date(byAdding: .day, value: 4, to: now)!).dates(from: now, calendar: calendar)
    expect(weekdays.count == 3 && weekdays.allSatisfy { !calendar.isDateInWeekend($0) })
    let task = StudyTask(title: "Essay", classID: media.id, due: now)
    var repeated = rule.occurrences(of: task, calendar: calendar)
    expect(repeated.count == 4 && Set(repeated.map(\.id)).count == 4)
    expect(repeated.allSatisfy { calendar.component(.hour, from: $0.due) == 23 })
    repeated[0].recordProgress(on: now)
    expect(repeated[0].isComplete && !repeated[1].isComplete)
    let store = PlannerStore(preview: true)
    var repeating = StudyTask(title: "Recurring", classID: store.data.classes[0].id, due: now); repeating.repeatRule = rule
    let before = store.data
    expect(store.save(repeating)); expect(store.data.tasks.count == before.tasks.count + 4)
    store.undo(); expect(store.data == before)
    let ics = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:media-lesson
    DTSTART;TZID=America/New_York:20260302T090000
    DTEND;TZID=America/New_York:20260302T100000
    SUMMARY:Media\\, analysis
     workshop
    RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=5
    EXDATE;TZID=America/New_York:20260304T090000
    LOCATION:Room 12
    END:VEVENT
    BEGIN:VEVENT
    UID:media-lesson
    RECURRENCE-ID;TZID=America/New_York:20260309T090000
    DTSTART;TZID=America/New_York:20260309T110000
    DTEND;TZID=America/New_York:20260309T120000
    SUMMARY:Moved lesson
    END:VEVENT
    END:VCALENDAR
    """
    let imported = try TimetableReader.read(Data(ics.utf8))
    expect(imported.lessons.count == 4 && imported.warnings.isEmpty)
    expect(imported.lessons.filter { $0.title == "Moved lesson" }.count == 1)
    expect(imported.lessons[0].title == "Media, analysisworkshop")
    expect(imported.lessons.filter { $0.title != "Moved lesson" }.allSatisfy { calendar.component(.hour, from: $0.start) == 9 })
    var withTimetable = before; withTimetable.timetable = imported.lessons
    let restored = try PlannerStore.decode(JSONEncoder().encode(withTimetable))
    expect(restored == withTimetable)
    expectThrows { _ = try TimetableReader.read(Data("not a calendar".utf8)) }
    for suffix in ["txt", "md", "csv"] {
        let read = try AttachmentReader.assistantContent(Attachment(name: "work.\(suffix)", data: Data("Write a media essay tomorrow".utf8)))
        expect(read.text.contains("media essay") && read.images.isEmpty)
    }
    let attributed = NSAttributedString(string: "Media worksheet")
    for pair: (String, NSAttributedString.DocumentType) in [("rtf", .rtf), ("docx", .officeOpenXML)] {
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: pair.1])
        let read = try AttachmentReader.assistantContent(Attachment(name: "worksheet.\(pair.0)", data: data))
        expect(read.text.contains("Media worksheet"))
    }
    let blankPDF = PDFDocument()
    let bitmap = NSImage(size: NSSize(width: 80, height: 80), flipped: false) { rect in NSColor.white.setFill(); rect.fill(); return true }
    blankPDF.insert(PDFPage(image: bitmap)!, at: 0)
    let scanned = try AttachmentReader.assistantContent(Attachment(name: "scan.pdf", data: blankPDF.dataRepresentation()!))
    expect(scanned.images.count == 1)
    let duration = TimetableReader.durationEnd("PT1H30M", start: now, calendar: calendar)
    expect(duration == now.addingTimeInterval(5400))
    expectThrows { _ = try AttachmentReader.assistantContent(Attachment(name: "unknown.zip", data: Data("bytes".utf8))) }
    let utc = TimeZone(secondsFromGMT: 0)!
    let midnight = Date(timeIntervalSince1970: 0)
    expect(ClockDisplay.time(midnight, twelveHour: true, timeZone: utc) == "12:00 AM")
    expect(ClockDisplay.time(midnight.addingTimeInterval(43200), twelveHour: true, timeZone: utc) == "12:00 PM")
    expect(ClockDisplay.time(midnight.addingTimeInterval(47100), twelveHour: true, timeZone: utc) == "1:05 PM")
    expect(ClockDisplay.time(midnight.addingTimeInterval(47100), twelveHour: false, timeZone: utc) == "13:05")
    expect(ClockDisplay.hourLabel(0, twelveHour: true) == "12 AM")
    expect(ClockDisplay.hourLabel(12, twelveHour: true) == "12 PM")
    expect(ClockDisplay.hourLabel(23, twelveHour: false) == "23:00")
    print("PASS: 12/24-hour formatting, midnight, noon and timetable hour labels.")
    let gridDay = calendar.startOfDay(for: now)
    func lesson(_ id: String, _ start: Int, _ end: Int, allDay: Bool = false) -> TimetableLesson {
        TimetableLesson(id: id, title: id, start: calendar.date(byAdding: .minute, value: start, to: gridDay)!, end: calendar.date(byAdding: .minute, value: end, to: gridDay)!, allDay: allDay, location: "", notes: "")
    }
    let tutor = lesson("Tutor", 475, 485), first = lesson("French", 485, 545)
    let adjacent = TimetableCalendar.blocks([first, tutor], day: gridDay, calendar: calendar)
    expect(adjacent.count == 2 && adjacent.allSatisfy { $0.lanes == 1 })
    expect(adjacent[0].start == 475 && adjacent[0].end == 485)
    let overlap = TimetableCalendar.blocks([first, lesson("Other", 490, 530), lesson("Later", 600, 660)], day: gridDay, calendar: calendar)
    expect(overlap[0].lanes == 2 && overlap[1].lanes == 2 && overlap[2].lanes == 1)
    let midnightEnd = lesson("Yesterday", -60, 0)
    expect(!TimetableCalendar.contains(midnightEnd, day: gridDay, calendar: calendar))
    expect(TimetableCalendar.contains(lesson("Overnight", -60, 60), day: gridDay, calendar: calendar))
    expect(TimetableCalendar.blocks([lesson("All day", 0, 1440, allDay: true)], day: gridDay, calendar: calendar).isEmpty)
    expect(TimetableCalendar.days(containing: now, mode: .day, calendar: calendar) == [gridDay])
    let month = TimetableCalendar.days(containing: now, mode: .month, calendar: calendar)
    expect(month.count % 7 == 0 && month.contains(gridDay))
    print("PASS: timetable day/month bounds, half-open midnight dates, short back-to-back lessons and overlapping lanes.")
    print("PASS: relative dates, exact reminder instruction, DST repeats, independent completion/undo, ICS repeats/exceptions/time zones, timetable backups and document input.")
}
