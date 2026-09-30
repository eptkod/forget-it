import SwiftUI

@main
struct ForgetItApp: App {
    @State private var store = PlannerStore()
    @State private var ai = LocalAIController()
    @AppStorage("clockStyle") private var clockStyle = "system"
    @AppStorage("hideAssistant") private var hideAssistant = false
    var body: some Scene {
        WindowGroup("forget it", id: "planner") {
            TimelineView(.everyMinute) { _ in
                PlannerView(store: store)
                    .environment(ai)
                    .onChange(of: clockStyle) { _, _ in store.refreshReminders(); if !store.isPreview { PlannerWidgetSnapshot.publish(store.data) } }
                    .task { if !hideAssistant && !ai.checked { await ai.check() } }
                    .tint(SchoolClass.tint("lavender"))
                    .frame(minWidth: 920, minHeight: 640)
            }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { NotificationCenter.default.post(name: .newPlannerTask, object: nil) }
                    .keyboardShortcut("n")
                Button("New Event") { NotificationCenter.default.post(name: .newPlannerEvent, object: nil) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("New Class") { NotificationCenter.default.post(name: .newPlannerClass, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo Planner Change") { store.undo() }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(!store.canUndo)
            }
            CommandGroup(after: .importExport) {
                Button("Export Backup…") { store.exportBackup() }
                Button("Restore Backup…") { store.restoreBackup() }
            }
        }
        Settings {
            PreferencesView(store: store)
                .environment(ai)
                .tint(SchoolClass.tint("lavender"))
        }
    }
}

extension Notification.Name {
    static let newPlannerTask = Notification.Name("newPlannerTask")
    static let newPlannerEvent = Notification.Name("newPlannerEvent")
    static let newPlannerClass = Notification.Name("newPlannerClass")
}
