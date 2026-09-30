import Foundation
@main struct InstructionCheck {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let ai = LocalAIController(conversationFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        ai.configuration = AIConfiguration(endpoint: "http://127.0.0.1:11434", model: "qwen3.5:4b")
        await ai.check()
        let schoolClass = SchoolClass(name: "Media")
        var conversation = AIConversation(); conversation.classID = schoolClass.id
        let cases: [(String, String?, String?)] = [
            ("Create an event called 'test' for Media on October 3rd, 2026 at 3pm.", "2026-10-03", "15:00"),
            ("Actually move it to October 5th, 2026 at 4pm.", "2026-10-05", "16:00"),
            ("Add a homework task called Essay for Media. I don't know the deadline yet.", nil, nil),
            ("set a task tomorrow reminding me to write a media essay", AIImportPrompt.localDay(Calendar.current.date(byAdding: .day, value: 1, to: Date())!), nil)
        ]
        for (index, test) in cases.enumerated() {
            if index >= 2 { conversation = AIConversation(); conversation.classID = schoolClass.id }
            let previous = conversation
            conversation.messages.append(AIChatMessage(contextID: conversation.contextID, role: "user", text: test.0))
            var messages = try conversation.requestMessages()
            messages.insert(["role": "system", "content": AIImportPrompt.make(classes: [schoolClass], previous: previous)], at: 0)
            let content: String
            let direct = SimpleTaskInstruction.extraction(test.0, previous: previous)
            if let direct { content = String(data: try JSONEncoder().encode(direct), encoding: .utf8)! }
            else { content = try await ai.chat(messages: messages, schema: AIExtraction.schema) }
            let raw = try AIExtraction.decode(content)
            let extraction = AIImportValidation.applyingExplicitDate(to: raw, latestMessage: test.0)
            guard extraction.tasks.count == 1, extraction.tasks[0].dueDate == test.1,
                  test.2 == nil || extraction.tasks[0].dueTime == test.2 else {
                print("FAIL case \(index + 1): \(content)"); throw AIError.message("Live instruction regression")
            }
            if index < 2 {
                guard extraction.tasks[0].kind == "event", extraction.tasks[0].title.lowercased() == "test" else { throw AIError.message("Event title/type regression: " + content) }
            } else if index == 2 {
                guard !(extraction.followUps ?? []).isEmpty || !extraction.questions.isEmpty else { throw AIError.message("No missing-date question") }
            }
            let drafts = AIImportValidation.drafts(from: extraction, source: test.0, attachments: [], classes: [schoolClass], selectedClass: schoolClass.id, existing: [], model: ai.configuration.model)
            if index < 2 { guard drafts[0].dateConfirmed && drafts[0].timeConfirmed else { throw AIError.message("Review rejected valid date/time") } }
            else if index == 2 { guard !drafts[0].dateConfirmed else { throw AIError.message("Invented review date") } }
            if index == 3 { guard drafts[0].dateConfirmed && drafts[0].timeConfirmed && drafts[0].task.isAllDay else { throw AIError.message("Tomorrow was not resolved as all day") } }
            conversation.drafts = drafts
            conversation.messages.append(AIChatMessage(contextID: conversation.contextID, role: "assistant", text: AIImportValidation.reviewSummary(drafts), wireContent: content))
            print("PASS integration case \(index + 1) [\(direct == nil ? "local model" : "app date handling")]: raw date=\(raw.tasks.first?.dueDate ?? "missing"), raw time=\(raw.tasks.first?.dueTime ?? "missing"); review date=\(extraction.tasks[0].dueDate ?? "missing")")
        }
    }
}
