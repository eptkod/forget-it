import Foundation
import WidgetKit

struct PlannerWidgetItem: Codable, Identifiable {
    var id: String
    var title: String
    var subject: String
    var due: Date
    var allDay: Bool
}
struct PlannerWidgetSnapshot: Codable {
    var updatedAt: Date
    var items: [PlannerWidgetItem]
    var twelveHour: Bool?
    static var file: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PlannerAppGroup") as? String, !group.isEmpty,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return folder.appendingPathComponent("widget-calendar.json")
    }
    static func read() -> Self? {
        guard let file, let bytes = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: bytes)
    }
}
#if !WIDGET_EXTENSION
extension PlannerWidgetSnapshot {
    @MainActor static func publish(_ data: PlannerData) {
        guard let file else { return }
        let items = data.tasks.filter { !$0.isComplete }.sorted { $0.due < $1.due }.map { task in
            PlannerWidgetItem(id: task.id.uuidString, title: task.title, subject: data.classes.first(where: { $0.id == task.classID })?.name ?? "", due: task.due, allDay: task.isAllDay)
        }
        do {
            try JSONEncoder().encode(PlannerWidgetSnapshot(updatedAt: Date(), items: items, twelveHour: ClockDisplay.uses12Hours)).write(to: file, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: "ForgetItCalendar")
        } catch { NSLog("Could not update planner widget: %@", error.localizedDescription) }
    }
}
#endif
