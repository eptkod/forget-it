import SwiftUI
import WidgetKit

struct CalendarEntry: TimelineEntry {
    var date: Date
    var snapshot: PlannerWidgetSnapshot?
}
struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry { CalendarEntry(date: Date(), snapshot: PlannerWidgetSnapshot(updatedAt: Date(), items: [PlannerWidgetItem(id: "example", title: "Media essay", subject: "Media", due: Date(), allDay: true)])) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : CalendarEntry(date: Date(), snapshot: .read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(Timeline(entries: [CalendarEntry(date: now, snapshot: .read())], policy: .after(tomorrow)))
    }
}
struct CalendarWidgetView: View {
    let entry: CalendarEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var rendering
    private var upcoming: [PlannerWidgetItem] { (entry.snapshot?.items ?? []).filter { $0.due >= Calendar.current.startOfDay(for: entry.date) } }
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("forget it").font(.caption.weight(.semibold)).widgetAccentable()
                Text(entry.date.formatted(.dateTime.month(.wide))).font(.headline)
                month
            }.frame(maxWidth: .infinity)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 9) {
                    Text("All Calendars").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if entry.snapshot == nil { Text("Open forget it to load your planner.").font(.caption) }
                    else if upcoming.isEmpty { Text("A little room to breathe.").font(.callout) }
                    ForEach(upcoming.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(item.due.formatted(.dateTime.day().month()) + (item.allDay ? " · All day" : " · " + ClockDisplay.time(item.due, twelveHour: entry.snapshot?.twelveHour ?? ClockDisplay.uses12Hours))).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        .widgetURL(URL(string: "forgetit://calendar"))
    }
    private var month: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: entry.date)!.start
        let days = calendar.range(of: .day, in: .month, for: start)!.count
        let padding = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 3) {
            ForEach(0..<7, id: \.self) { index in Text(calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.system(size: 8)).foregroundStyle(.secondary) }
            ForEach(0..<(padding + days), id: \.self) { index in
                if index < padding { Color.clear.frame(height: 14) }
                else {
                    let date = calendar.date(byAdding: .day, value: index - padding, to: start)!
                    let today = calendar.isDate(date, inSameDayAs: entry.date)
                    let hasItems = upcoming.contains { calendar.isDate($0.due, inSameDayAs: date) }
                    Text("\(index - padding + 1)").font(.system(size: 10, weight: today || hasItems ? .bold : .regular)).frame(maxWidth: .infinity).frame(height: 14)
                        .background(today ? (rendering == .fullColor ? Color.purple.opacity(0.22) : Color.primary.opacity(0.18)) : Color.clear, in: Capsule())
                        .underline(hasItems && !today).widgetAccentable(today || hasItems)
                }
            }
        }
    }
}
@main struct ForgetItCalendarWidget: Widget {
    let kind = "ForgetItCalendar"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarProvider()) { entry in CalendarWidgetView(entry: entry) }
            .configurationDisplayName("forget it · All Calendars")
            .description("Your month and upcoming deadlines at a glance.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
