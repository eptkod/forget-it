import Foundation

@MainActor func runConversationTests() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forget-it-chat-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("ai-chat.json")
    let chat = AIConversationStore(file: file)
    let context = chat.data.contextID
    let question = AIQuestion(title: "Which class?", options: ["Maths", "English"])
    chat.data.messages = [
        AIChatMessage(contextID: context, role: "user", text: "Add my presentation"),
        AIChatMessage(contextID: context, role: "assistant", text: "Which class is it for?", questions: [question]),
        AIChatMessage(contextID: context, role: "user", text: "English, on 2 October")
    ]
    chat.data.input = "At 10 AM"
    let schoolClass = SchoolClass(name: "English")
    var event = StudyTask(title: "Presentation", classID: schoolClass.id, due: AIImportValidation.date("2026-10-02", time: "10:00")!)
    event.work.kind = .event
    chat.data.drafts = [AIImportDraft(task: event, classConfirmed: true, dateConfirmed: true, timeConfirmed: true, evidenceConfirmed: true, questions: [], dateQuote: "2 October")]
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // Simulate the legacy version's disk file, then verify upgrade discards it.
    try JSONEncoder().encode(chat.data).write(to: file)
    let reopened = AIConversationStore(file: file)
    expect(reopened.data.messages.isEmpty)
    expect(!FileManager.default.fileExists(atPath: file.path))
    let request = try chat.data.requestMessages()
    expect(request.count == 3)
    expect(request[0]["content"] as? String == "Add my presentation")
    expect(request[2]["content"] as? String == "English, on 2 October")
    expect(chat.data.pendingQuestions.isEmpty)
    chat.data.messages.removeLast()
    expect(chat.data.pendingQuestions == [question])
    chat.reset()
    expect(chat.data.messages.isEmpty && chat.data.input.isEmpty && chat.data.drafts.isEmpty)
    expect(!FileManager.default.fileExists(atPath: file.path))
    let reply = try AIChatReply.decode("""
    {"message":"Let’s clarify that.","questions":[{"title":"Which part?","options":["Introduction","Conclusion"]}]}
    """)
    expect(reply.questions.count == 1 && reply.questions[0].options.count == 2)
    expectThrows { _ = try AIChatReply.decode("not JSON") }
    event.recordProgress(on: event.due)
    expect(!event.isComplete && event.work.sessions.isEmpty)
    expect(!event.isOverdue(at: event.due.addingTimeInterval(86400)))
    let week = Calendar.current.dateInterval(of: .weekOfYear, for: event.due)!.start
    expect(CalendarLayout.segments(tasks: [event], weekStart: week).count == 1)
    let rule = ReminderRule(kind: .deadline)
    expect(event.reminderDates(rule: rule, now: event.due.addingTimeInterval(-86400)) == [event.due])
    let daily = ReminderRule(kind: .dailyWeek, continueAfterDeadline: true)
    expect(event.reminderDates(rule: daily, now: event.due.addingTimeInterval(-864000)).allSatisfy { $0 <= event.due })
    let data = PlannerData(classes: [schoolClass], tasks: [event])
    let restored = try PlannerStore.decode(JSONEncoder().encode(data))
    expect(restored.tasks[0].isEvent)
    var conversion = event; conversion.start = event.due.addingTimeInterval(-86400)
    conversion.work.sessionTarget = 3; conversion.work.excludedWeekdays = [1, 7]
    conversion.reconcileCompletion()
    expect(conversion.start == nil && conversion.work.sessionTarget == nil && conversion.work.excludedWeekdays.isEmpty)
    var extraction = AIExtraction(summary: "Created for October 3", questions: [], tasks: [
        AIExtractedTask(title: "test", notes: "", dueDate: "2026-10-03", dueTime: "15:00:00", allDay: false, kind: "event")
    ])
    let draft = AIImportValidation.drafts(from: extraction, source: "October 3", attachments: [], classes: [schoolClass], selectedClass: schoolClass.id, existing: [], model: "test")[0]
    expect(draft.dateConfirmed && draft.timeConfirmed)
    expect(AIImportValidation.reviewQuestions([draft], proposed: [AIQuestion(title: "What date is it due?", options: [])]).isEmpty)
    expect(Calendar.current.component(.day, from: draft.task.due) == 3)
    expect(Calendar.current.component(.hour, from: draft.task.due) == 15)
    extraction.tasks[0].dueTime = "garbled"
    let badTime = AIImportValidation.drafts(from: extraction, source: "", attachments: [], classes: [schoolClass], selectedClass: schoolClass.id, existing: [], model: "test")[0]
    expect(badTime.dateConfirmed && !badTime.timeConfirmed)
    expect(Calendar.current.component(.day, from: badTime.task.due) == 3)
    expect(!AIImportValidation.reviewSummary([badTime]).contains("Created"))
    let repaired = AIImportValidation.applyingExplicitDate(to: extraction, latestMessage: "Put test on October 5th, 2026 at 4pm")
    expect(repaired.tasks[0].dueDate == "2026-10-05" && repaired.tasks[0].dueTime == "16:00")
    expect(AIImportValidation.parsedDate("October 3rd, 2026") != nil)
    expect(AIImportValidation.parsedDate("February 30, 2026") == nil)
    expect(AIModelChoice.defaults.contains { $0.id == "qwen3.5:9b" })
    print("PASS: memory-only chat/reset and legacy file deletion, follow-up context, structured questions, events/calendar/reminders/backups.")
}
