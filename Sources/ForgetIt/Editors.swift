import SwiftUI

struct TaskEditor: View {
    var store: PlannerStore
    @State var task: StudyTask
    @State var sessionDay: Date = Date()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    @AppStorage("hideAssistant") private var hideAssistant = false
    @State private var showAI = false
    @State private var attachmentError: String?
    @State private var attachmentLoading = false
    @State private var progressUndo: [([WorkSession], Date?)] = []
    private var existing: Bool { store.data.tasks.contains { $0.id == task.id } }
    private var problem: String? {
        if let rule = task.repeatRule, rule.dates(from: task.due).isEmpty { return "Choose a repeat end on or after the first date." }
        if task.isEvent { return nil }
        if (task.start ?? task.due) > task.deadline() { return "Choose a work start on or before the deadline." }
        if task.work.excludedWeekdays.count == 7 { return "Keep at least one day available for work." }
        if task.scheduledDayCount() == 0 { return "There are no available work days in this span. Change the dates or included days." }
        if task.targetCount() < task.progressCount { return "Keep at least as many parts as you have already completed, or undo some progress first." }
        if task.isRevision && task.targetCount() > task.scheduledDayCount() { return "This span has \(task.scheduledDayCount()) available days. Choose fewer sessions or a longer span." }
        if task.isRevision && task.work.sessions.contains(where: { !task.isWorkDay($0.day) }) { return "The new schedule excludes a logged session. Undo that session or keep its day included." }
        return nil
    }
    private var valid: Bool { !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && problem == nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BrandMark().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.isEvent ? (existing ? "Event details" : "Something to look forward to.") : existing ? "Task details" : "One less thing to remember.").font(.title2.weight(.semibold))
                    Text(task.isEvent ? "Keep presentations and important dates in your calendar." : existing ? "Dates, a plan, and a little progress." : "Set a deadline. Make a little space to work.").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                Section(task.isEvent ? "Event" : "Task") {
                    TextField("Title", text: $task.title, prompt: Text(task.isEvent ? "e.g. History presentation" : "What do you need to do?")).focused($titleFocused)
                    Picker("Class", selection: $task.classID) {
                        ForEach(store.data.classes) { schoolClass in Text(schoolClass.name).tag(schoolClass.id) }
                    }
                    Picker("Type", selection: $task.work.kind) {
                        ForEach(TaskKind.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(!task.work.sessions.isEmpty || task.isComplete)
                    Text(task.isEvent ? "Presentations, appointments and other events stay on your calendar without a completion checkbox." : task.isRevision ? "Tick off each study day. Future revision stays on your calendar." : "Finish once, or work through several parts. Finished homework leaves the calendar.").font(.caption).foregroundStyle(.secondary)
                }
                if !task.isEvent && (existing || !task.work.sessions.isEmpty) { progressSection }
                Section(task.isEvent ? "When" : "Deadline") {
                    DayPickerField(task.isEvent ? "Event date" : "Due date", date: $task.due)
                    Toggle("All day", isOn: $task.work.allDay)
                    if !task.isAllDay {
                        ClockTimePicker(task.isEvent ? "Time" : "Due time", selection: $task.due)
                    } else {
                        Text(task.isEvent ? "Appears as an all-day event. Alerts use the schedule’s chosen time." : "Due by the end of this day. Reminder alerts use the schedule’s chosen time.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !task.isEvent {
                Section("Work Plan") {
                    Toggle("Plan a work span", isOn: Binding(get: { task.start != nil }, set: { task.start = $0 ? min(Calendar.current.startOfDay(for: Date()), task.due) : nil }))
                    if task.start != nil {
                        DayPickerField("Start working", date: Binding(get: { task.start ?? task.due }, set: { task.start = Calendar.current.startOfDay(for: $0) }))
                    }
                    WorkdaySelector(excluded: $task.work.excludedWeekdays)
                    Toggle(task.isRevision ? "Set a number of sessions" : "Split into parts", isOn: Binding(get: { task.work.sessionTarget != nil }, set: { task.work.sessionTarget = $0 ? 3 : nil }))
                    if task.work.sessionTarget != nil {
                        Stepper("\(task.targetCount()) \(task.isRevision ? "sessions" : "parts")", value: Binding(get: { task.work.sessionTarget ?? 3 }, set: { task.work.sessionTarget = $0 }), in: 1...99)
                    } else {
                        Text(task.isRevision ? "One session per included day · \(task.scheduledDayCount()) planned" : "One completion finishes the whole task.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                }
                }
                if !existing {
                    Section("Repeat") {
                        Toggle("Repeat on a schedule", isOn: Binding(get: { task.repeatRule != nil }, set: { task.repeatRule = $0 ? TaskRepeat(until: Calendar.current.date(byAdding: .month, value: 3, to: task.due)!) : nil }))
                        if task.repeatRule != nil {
                            Picker("Frequency", selection: Binding(get: { task.repeatRule!.frequency }, set: { task.repeatRule?.frequency = $0 })) {
                                ForEach(["Daily", "Weekdays", "Weekly", "Monthly"], id: \.self) { Text($0).tag($0) }
                            }
                            DayPickerField("Repeat until", date: Binding(get: { task.repeatRule!.until }, set: { task.repeatRule?.until = max($0, task.due) }))
                            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                            Text("Creates \(task.repeatRule!.dates(from: task.due).count) independent entries, up to 366. Complete or edit each one separately. Undo removes the whole new series.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if task.seriesID != nil {
                    Section { Text("Part of a repeating schedule. Changes apply to this occurrence only.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Notes") {
                    AttachmentTextEditor(text: $task.notes, attachments: $task.attachments, onError: { attachmentError = $0 }).frame(minHeight: 70).accessibilityLabel("Task notes")
                    if !hideAssistant { Button(task.isEvent ? "Ask AI about this event" : "Ask AI about this task", systemImage: "sparkles") { showAI = true } }
                }
                Section("Reminders") {
                    Toggle("Use default schedule", isOn: Binding(get: { task.reminder == nil }, set: { task.reminder = $0 ? nil : (store.data.defaultReminder ?? ReminderRule()) }))
                    if task.reminder != nil {
                        ReminderRuleEditor(rule: Binding(get: { task.reminder ?? ReminderRule() }, set: { task.reminder = $0 }))
                    } else {
                        Text(store.data.defaultReminder?.kind.title ?? "Choose your default in Preferences").foregroundStyle(.secondary)
                    }
                    Text(task.isEvent ? "Reminders use the event’s date and time." : "Excluded days skip daily reminders. One-off deadline alerts still apply.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Attachments") {
                    AttachmentInput(attachments: $task.attachments, onOpen: store.openAttachment, loading: $attachmentLoading)
                    if let attachmentError { Text(attachmentError).foregroundStyle(.red) }
                    Text("Copied into your planner and backups. Up to 20 MB each.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                if existing { Button(task.isEvent ? "Delete Event" : "Delete Task", role: .destructive) { confirmDelete = true } }
                if !progressUndo.isEmpty {
                    Button("Undo Progress", systemImage: "arrow.uturn.backward") { let previous = progressUndo.removeLast(); task.work.sessions = previous.0; task.completedAt = previous.1 }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing ? "Save Changes" : task.isEvent ? "Add Event" : "Add Task") {
                    task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if store.save(task) { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!valid || attachmentLoading)
            }.padding(20)
        }.frame(width: 650, height: 740)
            .onChange(of: hideAssistant) { _, hidden in if hidden { showAI = false } }
            .sheet(isPresented: $showAI) { LocalAISheet(store: store, contextTask: task) }
            .onAppear { titleFocused = !existing }
            .onChange(of: task.targetCount()) { _, _ in task.reconcileCompletion() }
            .onChange(of: task.work.kind) { _, kind in
                if kind == .event { task.reconcileCompletion() }
                if kind == .revision && task.start == nil { task.start = min(Calendar.current.startOfDay(for: Date()), task.due) }
            }
            .confirmationDialog("Delete this task and cancel its reminders?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(task.isEvent ? "Delete Event" : "Delete Task", role: .destructive) { store.delete(task); dismiss() }
            }
    }

    private var progressSection: some View {
        Section("Progress") {
            LabeledContent(task.isComplete ? "Finished" : "Completed", value: task.progressText)
            ProgressView(value: Double(task.progressCount), total: Double(max(task.targetCount(), task.progressCount)))
            if task.isRevision { DayPickerField("Study day", date: $sessionDay) }
            HStack {
                if task.isComplete {
                    Button("Reopen Task", systemImage: "arrow.uturn.backward") { progressUndo.append((task.work.sessions, task.completedAt)); task.reopen() }
                } else if task.isRevision && task.didStudy(on: sessionDay) {
                    Label("This day’s revision is done", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    Button(task.isRevision ? "Complete This Study Day" : task.targetCount() > 1 ? "Complete Part \(task.progressCount + 1)" : "Complete Homework", systemImage: "checkmark") {
                        progressUndo.append((task.work.sessions, task.completedAt)); task.recordProgress(on: sessionDay)
                    }.disabled(!valid || !task.canRecord(on: sessionDay))
                }
            }
            if task.isRevision && !task.isWorkDay(sessionDay) {
                Text("This is not a planned study day. Choose an included day in the work span.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(task.work.sessions.enumerated()), id: \.element.id) { index, session in
                HStack {
                    Label("\(task.isRevision ? "Session" : "Part") \(index + 1) · \(session.day.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Undo") { progressUndo.append((task.work.sessions, task.completedAt)); task.removeSession(session.id) }.buttonStyle(.borderless)
                }.font(.caption)
            }
            Text("Progress changes are applied with Save Changes.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The whole date is a button. Only this explicit action opens the anchored calendar.
struct DayPickerField: View {
    var title: String
    var placeholder: String?
    @Binding var date: Date
    @State private var presented = false
    init(_ title: String, date: Binding<Date>, placeholder: String? = nil) { self.title = title; self._date = date; self.placeholder = placeholder }
    var body: some View {
        LabeledContent(title) {
            Button { presented.toggle() } label: {
                HStack(spacing: 8) {
                    Text(placeholder ?? date.formatted(date: .abbreviated, time: .omitted)).monospacedDigit()
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                }
            }.help("Choose \(title.lowercased())").accessibilityLabel("\(title): \(placeholder ?? date.formatted(date: .complete, time: .omitted)). Open calendar")
                .popover(isPresented: $presented, arrowEdge: .bottom) {
                    DateCalendarPopover(title: title, selected: date) { selected in
                        let calendar = Calendar.current
                        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
                        var components = calendar.dateComponents([.year, .month, .day], from: selected)
                        components.hour = time.hour; components.minute = time.minute; components.second = time.second
                        date = calendar.date(from: components) ?? selected
                        presented = false
                    } onClose: { presented = false }
                }
        }
    }
}

/// Browsing months never changes the value; only choosing a day commits a date.
struct DateCalendarPopover: View {
    var title: String
    var selected: Date
    var onSelect: (Date) -> Void
    var onClose: () -> Void
    @State private var month: Date
    private var calendar: Calendar { .current }
    init(title: String, selected: Date, onSelect: @escaping (Date) -> Void, onClose: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.onSelect = onSelect; self.onClose = onClose
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selected)!.start)
    }
    private var days: [Date] {
        let first = calendar.dateInterval(of: .weekOfYear, for: month)!.start
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { month = calendar.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }.help("Previous month")
                Button { month = calendar.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }.help("Next month")
            }.buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
                ForEach(0..<7) { offset in
                    Text(calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7])
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(height: 20)
                }
                ForEach(days, id: \.self) { day in
                    let isSelected = calendar.isDate(day, inSameDayAs: selected)
                    Button { onSelect(day) } label: {
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 13, weight: isSelected || calendar.isDateInToday(day) ? .semibold : .regular))
                            .frame(maxWidth: .infinity).frame(height: 31)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? SchoolClass.tint("lavender") : calendar.isDateInToday(day) ? SchoolClass.tint("lavender").opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .opacity(calendar.isDate(day, equalTo: month, toGranularity: .month) ? 1 : 0.4)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Divider()
            HStack {
                Button("Today") { onSelect(Date()) }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
        }.padding(16).frame(width: 312).accessibilityElement(children: .contain).accessibilityLabel("Choose \(title.lowercased())")
    }
}

struct WorkdaySelector: View {
    @Binding var excluded: Set<Int>
    private let days = [2, 3, 4, 5, 6, 7, 1]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Work days")
                Spacer()
                Menu("Presets") {
                    Button("Every Day") { excluded = [] }
                    Button("Weekdays Only") { excluded = [1, 7] }
                    Button("Weekends Only") { excluded = [2, 3, 4, 5, 6] }
                }.fixedSize()
            }
            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { !excluded.contains(day) }, set: { included in
                        if included { excluded.remove(day) } else { excluded.insert(day) }
                    })).toggleStyle(.button).frame(maxWidth: .infinity)
                        .accessibilityLabel("Include \(Calendar.current.weekdaySymbols[day - 1])")
                }
            }
            Text("Selected days are included. Your deadline remains visible even on an excluded day.").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct ClassEditor: View {
    var store: PlannerStore
    @State var schoolClass: SchoolClass
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(store.data.classes.contains { $0.id == schoolClass.id } ? "Edit class" : "A home for your homework.").font(.title2.weight(.semibold))
            TextField("Class name", text: $schoolClass.name, prompt: Text("e.g. Mathematics")).textFieldStyle(.roundedBorder).focused($nameFocused)
            TextField("Description (optional)", text: $schoolClass.notes).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 10) {
                Text("Class colour").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(SchoolClass.colors, id: \.self) { color in
                        Button { schoolClass.color = color } label: {
                            Circle().fill(SchoolClass.tint(color)).frame(width: 33, height: 33)
                                .overlay { if schoolClass.color == color { Image(systemName: "checkmark").foregroundStyle(.white).fontWeight(.bold) } }
                        }.buttonStyle(.plain).accessibilityLabel(color.capitalized).accessibilityAddTraits(schoolClass.color == color ? .isSelected : [])
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Class") {
                    schoolClass.name = schoolClass.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save(schoolClass)
                    if store.error == nil { dismiss() }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(schoolClass.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 450).onAppear { nameFocused = true }
    }
}

struct ReminderRuleEditor: View {
    @Binding var rule: ReminderRule
    var body: some View {
        Picker("Schedule", selection: $rule.kind) {
            ForEach(ReminderKind.allCases) { kind in Text(kind.title).tag(kind) }
        }
        if rule.kind != .off && rule.kind != .dailyWeek && rule.kind != .custom {
            ClockTimePicker("All-day reminder time", selection: Binding(get: {
                Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date())!
            }, set: { date in
                rule.hour = Calendar.current.component(.hour, from: date)
                rule.minute = Calendar.current.component(.minute, from: date)
            }))
            Text("Used for all-day tasks. Timed tasks use their due time.").font(.caption).foregroundStyle(.secondary)
        }
        if rule.kind == .dailyWeek || rule.kind == .custom {
            if rule.kind == .custom {
                Stepper("Start \(rule.leadDays) days before", value: $rule.leadDays, in: 0...60)
                Toggle("Repeat once a day", isOn: $rule.repeatDaily)
            }
            ClockTimePicker("Reminder time", selection: Binding(get: {
                Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date())!
            }, set: { date in
                rule.hour = Calendar.current.component(.hour, from: date)
                rule.minute = Calendar.current.component(.minute, from: date)
            }))
            if rule.kind == .dailyWeek || rule.repeatDaily {
                Toggle("Continue for 7 days after the deadline", isOn: $rule.continueAfterDeadline)
                Text(rule.continueAfterDeadline ? "Stops when completed, or seven days after the deadline." : "Stops at the deadline, or as soon as you complete the task.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ReminderSetup: View {
    var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var choice: ReminderKind?
    @State private var rule = ReminderRule()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandMark().frame(width: 64, height: 64)
            Text("A gentle nudge, on your terms.").font(.title2.weight(.semibold))
            Text("Choose how you’d like to be reminded. You can change the default in Preferences, or choose a different schedule for any task.").foregroundStyle(.secondary)
            Picker("Default reminders", selection: $choice) {
                Text("Choose a schedule…").tag(Optional<ReminderKind>.none)
                ForEach(ReminderKind.allCases) { kind in Text(kind.title).tag(Optional(kind)) }
            }
            if choice != nil && choice != .off {
                Form { ReminderRuleEditor(rule: $rule) }.formStyle(.grouped).frame(height: 220)
            }
            HStack {
                Spacer()
                Button("Continue") {
                    guard let choice else { return }
                    rule.kind = choice
                    var next = store.data; next.defaultReminder = rule; store.commit(next)
                    if store.error == nil {
                        if choice != .off { store.requestNotifications() }
                        dismiss()
                    }
                }.buttonStyle(.borderedProminent).disabled(choice == nil)
            }
        }.padding(30).frame(width: 520)
            .onChange(of: choice) { _, value in if let value { rule.kind = value } }
            .onChange(of: rule.kind) { _, value in choice = value }
    }
}

struct PreferencesView: View {
    @AppStorage("clockStyle") private var clockStyle = "system"
    @Bindable var store: PlannerStore
    @State private var rule = ReminderRule()
    @AppStorage("hideAssistant") private var hideAssistant = false
    @State private var showAI = false
    var body: some View {
        Form {
            Section("Default Reminders") {
                ReminderRuleEditor(rule: $rule)
                Text("Tasks using the default schedule update when you save. A calendar work span never creates daily reminders on its own.").font(.caption).foregroundStyle(.secondary)
                Button("Save Reminder Preferences") {
                    var next = store.data; next.defaultReminder = rule; store.commit(next)
                    if rule.kind != .off { store.requestNotifications() }
                }
            }
            Section("Notifications") {
                LabeledContent("Permission", value: store.notificationStatus)
                LabeledContent("Scheduled alerts", value: String(store.pendingReminderCount))
                HStack {
                    Button("Enable Notifications") { store.requestNotifications() }
                    Button("System Settings…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                }
                Text("macOS controls banners and Focus. Up to 60 upcoming alerts are queued; opening the app refreshes the queue. Daily schedules stop after completion.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Clock format", selection: $clockStyle) {
                    Text("System default").tag("system")
                    Text("12-hour (1:00 PM)").tag("12")
                    Text("24-hour (13:00)").tag("24")
                }
                Text("Used for calendars, tasks, events and reminder times.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Your Data") {
                Text("Your planner and attachments stay on this Mac. Export a backup regularly, especially before starting a new term.").foregroundStyle(.secondary)
                HStack { Button("Export Backup…", action: store.exportBackup); Button("Restore Backup…", action: store.restoreBackup) }
            }
            Section("Optional Features") { Toggle("Show study assistant", isOn: Binding(get: { !hideAssistant }, set: { hideAssistant = !$0 })) }
            if !hideAssistant { Section("Local AI") {
                Button("Set Up or Manage Local AI…", systemImage: "sparkles") { showAI = true }
                Text("Optional task import and clarification, powered by Ollama on your Mac. Models load only when needed.").font(.caption).foregroundStyle(.secondary)
            }
            }
            Section("About forget it") {
                HStack(spacing: 12) {
                    BrandMark().frame(width: 48, height: 48)
                    Text("Version 0.3.1 · A little less to remember.")
                }
                Text("Your planner works offline.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 560, height: 710)
            .onChange(of: hideAssistant) { _, hidden in if hidden { showAI = false } }
            .sheet(isPresented: $showAI) { LocalAISheet(store: store) }
            .onAppear { rule = store.data.defaultReminder ?? ReminderRule(); store.refreshReminders() }
    }
}
