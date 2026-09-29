import SwiftUI

struct PlannerView: View {
    @Bindable var store: PlannerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: String? = "calendar"
    @State private var hiddenClasses: Set<UUID> = []
    @State private var search = ""
    @State private var anchor = Date()
    @State private var calendarMode = "Month"
    @State private var draft: StudyTask?
    @State private var selectedDay = Date()
    @State private var classDraft: SchoolClass?
    @State private var showSetup = false
    @State private var showAI = false
    @State private var showCompleted = true
    private var calendar: Calendar { .current }
    private var selectedClass: SchoolClass? { store.data.classes.first { $0.id.uuidString == selection } }
    private var isCalendar: Bool { selection == "calendar" || selectedClass != nil }
    private var tasks: [StudyTask] {
        store.data.tasks.filter { task in
            let classMatch = selectedClass.map { task.classID == $0.id } ?? !hiddenClasses.contains(task.classID)
            let queryMatch = search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search) || (store.schoolClass(for: task)?.name.localizedCaseInsensitiveContains(search) ?? false)
            return classMatch && queryMatch && (selection == "completed" || !isCalendar || showCompleted || !task.isComplete)
        }
    }
    private var title: String {
        selectedClass?.name ?? ["calendar": "All Calendars", "today": "Today", "upcoming": "Upcoming", "overdue": "Overdue", "completed": "Completed"][selection ?? "calendar"] ?? "All Calendars"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 280)
        } detail: {
            VStack(spacing: 0) {
                heading
                Divider()
                if store.data.classes.isEmpty {
                    ContentUnavailableView {
                        BrandMark().frame(width: 76, height: 76)
                        Text("A little less to remember.")
                    } description: {
                        Text("Give your homework a home. Start with a class,\nthen add your first deadline.")
                    } actions: {
                        Button("Create Your First Class") { classDraft = SchoolClass(name: "") }
                            .buttonStyle(.borderedProminent)
                    }
                } else if isCalendar && search.isEmpty {
                    calendarContent
                } else {
                    taskList
                }
                footer
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle("forget it")
            .toolbar { toolbar }
            .searchable(text: $search, prompt: "Find a task")
        }
        .sheet(item: $draft) { task in TaskEditor(store: store, task: task, sessionDay: selectedDay) }
        .sheet(item: $classDraft) { schoolClass in ClassEditor(store: store, schoolClass: schoolClass) }
        .sheet(isPresented: $showAI) { LocalAISheet(store: store) }
        .sheet(isPresented: $showSetup) { ReminderSetup(store: store) }
        .alert("Something needs your attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .newPlannerTask)) { _ in newTask() }
        .onReceive(NotificationCenter.default.publisher(for: .newPlannerClass)) { _ in classDraft = SchoolClass(name: "") }
        .onChange(of: store.selectedTaskID) { _, id in
            if let task = store.data.tasks.first(where: { $0.id == id }) { draft = task; store.selectedTaskID = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshReminders() } }
        .onAppear {
            showSetup = store.data.defaultReminder == nil
            if let id = store.selectedTaskID, let task = store.data.tasks.first(where: { $0.id == id }) {
                draft = task; store.selectedTaskID = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandMark().frame(width: 36, height: 36)
                Text("forget it").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 22)
            List(selection: $selection) {
                Section("Your Planner") {
                    Label("All Calendars", systemImage: "calendar").tag("calendar")
                    Label("Today", systemImage: "sun.max").tag("today")
                    Label("Upcoming", systemImage: "tray").tag("upcoming")
                    HStack { Label("Overdue", systemImage: "clock.badge.exclamationmark"); Spacer(); Text("\(store.data.tasks.filter { $0.isOverdue() }.count)").foregroundStyle(.secondary).monospacedDigit() }.tag("overdue")
                    Label("Completed", systemImage: "checkmark.circle").tag("completed")
                }
                Section("Classes") {
                    ForEach(store.data.classes) { schoolClass in
                        HStack(spacing: 8) {
                            Button {
                                if hiddenClasses.contains(schoolClass.id) { hiddenClasses.remove(schoolClass.id) }
                                else { hiddenClasses.insert(schoolClass.id) }
                            } label: {
                                Image(systemName: hiddenClasses.contains(schoolClass.id) ? "square" : "checkmark.square.fill")
                                    .foregroundStyle(schoolClass.tint)
                            }.buttonStyle(.plain).help("Show or hide \(schoolClass.name) in All Calendars")
                            Text(schoolClass.name).lineLimit(1)
                        }.tag(schoolClass.id.uuidString)
                            .contextMenu { Button("Edit Class…") { classDraft = schoolClass } }
                    }
                    Button { classDraft = SchoolClass(name: "") } label: { Label("New Class", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 10) {
                Label("Just one thing at a time.", systemImage: "leaf").font(.caption).foregroundStyle(.secondary)
                SettingsLink { Label("Preferences", systemImage: "gearshape") }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }

    private var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(selectedClass?.notes.isEmpty == false ? selectedClass!.notes : "A clear head starts with a simple plan.")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isCalendar {
                Picker("Calendar View", selection: $calendarMode) {
                    Text("Month").tag("Month"); Text("Week").tag("Week")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 155)
            }
        }.padding(.horizontal, 28).padding(.vertical, 23)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Today") { anchor = Date() }.keyboardShortcut("t", modifiers: .command)
            Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous \(calendarMode.lowercased())")
            Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next \(calendarMode.lowercased())")
        }
        ToolbarItem {
            Button { store.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!store.canUndo).help(store.undoTitle)
        }
        ToolbarItem { Button("Assistant", systemImage: "sparkles") { showAI = true } }
        ToolbarItem(placement: .primaryAction) {
            Button(action: newTask) { Label("New Task", systemImage: "plus") }.keyboardShortcut("n")
        }
        ToolbarItem {
            Menu {
                Toggle("Show Finished Revision", isOn: $showCompleted)
                Button("Export Backup…", action: store.exportBackup)
                Button("Restore Backup…", action: store.restoreBackup)
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private var weeks: [Date] {
        if calendarMode == "Week" { return [calendar.dateInterval(of: .weekOfYear, for: anchor)!.start] }
        let month = calendar.dateInterval(of: .month, for: anchor)!
        let start = calendar.dateInterval(of: .weekOfYear, for: month.start)!.start
        var dates: [Date] = []; var cursor = start
        while cursor < month.end { dates.append(cursor); cursor = calendar.date(byAdding: .day, value: 7, to: cursor)! }
        return dates
    }
    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(anchor.formatted(.dateTime.month(.wide).year())).font(.title2.weight(.medium))
                Spacer()
                Text("\(tasks.filter { !$0.isComplete }.count) open tasks").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.top, 22)
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    Text(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7].uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(weeks, id: \.self) { week in
                            CalendarWeek(store: store, tasks: tasks, week: week, anchor: anchor, minimumHeight: weekHeight(week, available: geometry.size.height)) { task, day in selectedDay = day; draft = task }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }
            HStack(spacing: 16) {
                Label("Work span", systemImage: "rectangle.fill")
                Label("Deadline", systemImage: "flag.fill")
                Spacer()
                if tasks.contains(where: { $0.isOverdue() }) {
                    Button("View overdue tasks") { selection = "overdue" }.buttonStyle(.plain).foregroundStyle(.red)
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 15)
        }.padding(.horizontal, 28)
    }

    private var listTasks: [StudyTask] {
        let now = Date()
        return tasks.filter { task in
            if !search.isEmpty { return true }
            switch selection {
            case "today": return !task.isComplete && (task.isWorkDay(now) || calendar.isDateInToday(task.due))
            case "upcoming": return !task.isComplete && task.deadline() >= now
            case "overdue": return task.isOverdue(at: now)
            case "completed": return task.isComplete
            default: return true
            }
        }.sorted { $0.due < $1.due }
    }
    private func weekHeight(_ week: Date, available: CGFloat) -> CGFloat {
        func required(_ date: Date) -> CGFloat {
            let rows = (CalendarLayout.segments(tasks: tasks, weekStart: date).map(\.lane).max() ?? -1) + 1
            return max(82, CGFloat(rows) * 28 + 47)
        }
        let spare = max(0, available - 2 - weeks.map(required).reduce(0, +))
        return required(week) + spare / CGFloat(weeks.count)
    }
    private var taskList: some View {
        Group {
            if listTasks.isEmpty {
                ContentUnavailableView(search.isEmpty ? "A little breathing room." : "No matching tasks", systemImage: search.isEmpty ? "checkmark.circle" : "magnifyingglass", description: Text(search.isEmpty ? "Nothing here right now. Your planner is up to date." : "Try another title, class, or phrase."))
            } else {
                List(listTasks) { task in
                    HStack(spacing: 14) {
                        Button {
                            if task.isComplete { store.reopen(task) } else { store.recordProgress(task) }
                        } label: {
                            Image(systemName: task.isComplete || (task.isRevision && task.didStudy(on: Date())) ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(store.schoolClass(for: task)?.tint ?? .accentColor)
                        }.buttonStyle(.plain)
                            .disabled(!task.isComplete && !task.canRecord(on: Date()))
                            .help(task.isComplete ? "Reopen task" : task.isRevision ? "Complete today’s revision session" : task.targetCount() > 1 ? "Complete the next part" : "Complete homework")
                        Button { selectedDay = Date(); draft = task } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(task.title).font(.headline).strikethrough(task.isComplete)
                                    Text("\(store.schoolClass(for: task)?.name ?? "Class") · \(task.isRevision ? "Revision" : "Homework") · \(task.progressText)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(task.deadlineText)
                                    Text(task.isComplete ? "Completed" : task.isOverdue() ? "Overdue" : "Deadline").font(.caption).foregroundStyle(task.isOverdue() ? .red : .secondary)
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.padding(.vertical, 10)
                }.listStyle(.inset)
            }
        }
    }
    private var footer: some View {
        HStack {
            Label(store.isPreview ? "Preview · sample tasks, not saved" : "Saved on this Mac", systemImage: "internaldrive").font(.caption)
            Spacer()
            if let action = store.lastAction {
                Text(action).font(.caption).lineLimit(1)
                Button("Undo") { store.undo() }.buttonStyle(.link).disabled(!store.canUndo)
            }
            if store.notificationStatus.contains("off") { Label("Notifications off", systemImage: "bell.slash").font(.caption) }
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.caption)
        }.foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 12).background(.bar)
    }
    private func newTask() {
        guard let id = selectedClass?.id ?? store.data.classes.first?.id else { classDraft = SchoolClass(name: ""); return }
        selectedDay = Date()
        draft = StudyTask(classID: id)
    }
    private func move(_ offset: Int) {
        anchor = calendar.date(byAdding: calendarMode == "Month" ? .month : .weekOfYear, value: offset, to: anchor)!
    }
}

struct CalendarWeek: View {
    var store: PlannerStore
    var tasks: [StudyTask]
    var week: Date
    var anchor: Date
    var minimumHeight: CGFloat
    var onOpen: (StudyTask, Date) -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    private var segments: [CalendarSegment] { CalendarLayout.segments(tasks: tasks, weekStart: week) }
    private var height: CGFloat { max(minimumHeight, CGFloat((segments.map(\.lane).max() ?? -1) + 1) * 28 + 47) }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7) { column in
                        let day = Calendar.current.date(byAdding: .day, value: column, to: week)!
                        VStack {
                            HStack {
                                Text(day.formatted(.dateTime.day())).font(.system(size: 12, weight: Calendar.current.isDateInToday(day) ? .bold : .medium))
                                    .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.white : Color.primary)
                                    .frame(width: 26, height: 26)
                                    .background(Calendar.current.isDateInToday(day) ? SchoolClass.tint("lavender") : .clear, in: Circle())
                                    .opacity(Calendar.current.isDate(day, equalTo: anchor, toGranularity: .month) ? 1 : 0.4)
                                Spacer()
                            }.padding(6)
                            Spacer(minLength: 0)
                        }.frame(width: width, height: height)
                            .background(Calendar.current.isDateInToday(day) ? SchoolClass.tint("lavender").opacity(0.035) : Color.clear)
                            .overlay(alignment: .trailing) { Rectangle().fill(.quaternary).frame(width: 0.5) }
                    }
                }
                ForEach(segments) { segment in
                    let task = segment.task
                    let tint = store.schoolClass(for: task)?.tint ?? .accentColor
                    HStack(spacing: 5) {
                        if segment.isDone { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        Text("\(store.schoolClass(for: task)?.name ?? "") · \(task.title)")
                            .font(.system(size: 11, weight: .medium)).lineLimit(1).strikethrough(segment.isDone)
                        Spacer(minLength: 0)
                        if task.targetCount() > 1 && segment.endColumn > segment.startColumn {
                            Text("\(task.progressCount)/\(task.targetCount())").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                        }
                        if segment.hasDeadline { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(task.isOverdue() ? Color.red : Color.primary) }
                    }.padding(.horizontal, 7).frame(height: 23)
                        .foregroundStyle(.primary)
                        .background(tint.opacity(segment.isDone ? 0.09 : contrast == .increased ? 0.40 : 0.23), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(task.isOverdue() && !segment.isDone ? Color.red : tint).frame(width: 3) }
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(contrast == .increased ? 1 : 0.2), style: StrokeStyle(lineWidth: 0.5, dash: segment.deadlineOnly ? [3, 2] : [])))
                        .overlay {
                            HStack(spacing: 0) {
                                ForEach(segment.startColumn...segment.endColumn, id: \.self) { column in
                                    let day = Calendar.current.date(byAdding: .day, value: column, to: week)!
                                    Button { onOpen(task, day) } label: { Color.clear.contentShape(Rectangle()) }
                                        .buttonStyle(.plain)
                                        .help("\(task.title) · \(day.formatted(date: .abbreviated, time: .omitted)) · \(task.progressText) · Due \(task.deadlineText)")
                                        .accessibilityLabel("Open \(task.title), \(day.formatted(date: .abbreviated, time: .omitted)), \(segment.isDone ? "session completed" : "not completed"), \(task.progressText)")
                                }
                            }
                        }
                        .frame(width: width * CGFloat(segment.endColumn - segment.startColumn + 1) - 8)
                        .offset(x: CGFloat(segment.startColumn) * width + 4, y: 39 + CGFloat(segment.lane) * 28)
                }
            }.overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 0.5) }
        }.frame(height: height)
    }
}
