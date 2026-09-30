import SwiftUI

enum TimetableMode: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
}

enum TimetableCalendar {
    static var calendar: Calendar { var calendar = Calendar.current; calendar.firstWeekday = 2; return calendar }
    static func days(containing date: Date, mode: TimetableMode, calendar: Calendar = calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        if mode == .day { return [day] }
        let interval = calendar.dateInterval(of: mode == .week ? .weekOfYear : .month, for: day)!
        let first = calendar.dateInterval(of: .weekOfYear, for: interval.start)!.start
        let count = mode == .week ? 7 : ((calendar.dateComponents([.day], from: first, to: interval.end).day! + 6) / 7) * 7
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }
    static func contains(_ lesson: TimetableLesson, day: Date, calendar: Calendar = calendar) -> Bool {
        let start = calendar.startOfDay(for: day), end = calendar.date(byAdding: .day, value: 1, to: start)!
        return lesson.start < end && (lesson.end > start || (lesson.end == lesson.start && lesson.start >= start))
    }
    struct Block: Identifiable {
        var lesson: TimetableLesson
        var start: Double
        var end: Double
        var lane = 0
        var lanes = 1
        var id: String { lesson.id }
    }
    static func blocks(_ lessons: [TimetableLesson], day: Date, calendar: Calendar = calendar) -> [Block] {
        let midnight = calendar.startOfDay(for: day), tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight)!
        func minute(_ date: Date) -> Double {
            let components = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double(components.hour! * 60 + components.minute!) + Double(components.second!) / 60
        }
        let visible = lessons.filter { !$0.allDay && contains($0, day: day, calendar: calendar) }
        let mapped: [Block] = visible.map { lesson in
            let start: Double = lesson.start < midnight ? 0 : minute(lesson.start)
            let end: Double = lesson.end >= tomorrow ? 1440 : minute(lesson.end)
            return Block(lesson: lesson, start: start, end: min(1440, max(start + 10, end)))
        }
        let sorted = mapped.sorted { $0.start == $1.start ? $0.lesson.id < $1.lesson.id : $0.start < $1.start }
        var result: [Block] = [], group: [Block] = [], ends: [Double] = []
        func flush() { for var block in group { block.lanes = ends.count; result.append(block) }; group = []; ends = [] }
        for var block in sorted {
            if let end = ends.max(), block.start >= end { flush() }
            let lane = ends.firstIndex(where: { $0 <= block.start }) ?? ends.count
            if lane == ends.count { ends.append(block.end) } else { ends[lane] = block.end }
            block.lane = lane; group.append(block)
        }
        flush(); return result
    }
}

struct TimetableTimeGrid: View {
    @AppStorage("clockStyle") private var clockStyle = "system"
    var day: Date
    var mode: TimetableMode
    var lessons: [TimetableLesson]
    var select: (TimetableLesson) -> Void
    private let hourHeight: CGFloat = 96
    private var days: [Date] { TimetableCalendar.days(containing: day, mode: mode) }
    private var calendar: Calendar { TimetableCalendar.calendar }
    private func lessons(on day: Date) -> [TimetableLesson] { lessons.filter { TimetableCalendar.contains($0, day: day) }.sorted { $0.start < $1.start } }
    var body: some View {
        let _ = clockStyle
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(TimeZone.current.abbreviation() ?? "Time").font(.caption2).foregroundStyle(.secondary).frame(width: 64)
                ForEach(days, id: \.self) { date in
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day())).font(.title3.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(calendar.isDateInToday(date) ? SchoolClass.tint("lavender").opacity(0.25) : .clear, in: Circle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            if days.contains(where: { lessons(on: $0).contains(where: \.allDay) }) {
                ScrollView(.vertical) { HStack(alignment: .top, spacing: 0) {
                    Text("All day").font(.caption2).foregroundStyle(.secondary).frame(width: 64).padding(.top, 8)
                    ForEach(days, id: \.self) { date in
                        VStack(spacing: 3) { ForEach(lessons(on: date).filter(\.allDay)) { lesson in
                            Button { select(lesson) } label: { Text(lesson.title).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(5).background(SchoolClass.tint("lavender").opacity(0.23), in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).help(lesson.title)
                        } }.frame(maxWidth: .infinity, alignment: .top).padding(3)
                    }
                } }.frame(height: min(110, CGFloat(days.map { lessons(on: $0).filter(\.allDay).count }.max() ?? 1) * 28 + 6))
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(0..<24) { hour in
                                Text(ClockDisplay.hourLabel(hour)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 56, height: hourHeight, alignment: .topTrailing).padding(.trailing, 8).id(hour)
                            }
                        }
                        ForEach(days, id: \.self) { date in dayColumn(date) }
                    }.padding(.top, 6)
                }
                .onAppear {
                    let first = days.flatMap { TimetableCalendar.blocks(lessons, day: $0) }.map(\.start).min() ?? 480
                    proxy.scrollTo(max(0, Int(first / 60)), anchor: .top)
                }
            }
        }
    }
    private func dayColumn(_ date: Date) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if calendar.isDateInToday(date) { SchoolClass.tint("lavender").opacity(0.035) }
                Path { path in
                    path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: hourHeight * 24))
                    for hour in 0...24 { path.move(to: CGPoint(x: 0, y: CGFloat(hour) * hourHeight)); path.addLine(to: CGPoint(x: geometry.size.width, y: CGFloat(hour) * hourHeight)) }
                }.stroke(Color.primary.opacity(0.11), lineWidth: 0.5)
                ForEach(TimetableCalendar.blocks(lessons, day: date)) { block in
                    let width = geometry.size.width / CGFloat(block.lanes)
                    let height = CGFloat(block.end - block.start) / 60 * hourHeight
                    TimetableLessonBlock(lesson: block.lesson, compact: height < 36, showDetails: height > 58, action: { select(block.lesson) })
                        .frame(width: max(1, width - 5), height: max(1, height - 2))
                        .offset(x: CGFloat(block.lane) * width + 2, y: CGFloat(block.start) / 60 * hourHeight)
                }
                if lessons(on: date).isEmpty {
                    Text("No lessons").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).offset(y: hourHeight * 8 + 20)
                }
                if calendar.isDateInToday(date) {
                    let components = calendar.dateComponents([.hour, .minute], from: Date())
                    let y = CGFloat(components.hour! * 60 + components.minute!) / 60 * hourHeight
                    Rectangle().fill(.red.opacity(0.8)).frame(height: 1).offset(y: y).allowsHitTesting(false)
                }
            }
        }.frame(height: hourHeight * 24)
    }
}

struct TimetableLessonBlock: View {
    @AppStorage("clockStyle") private var clockStyle = "system"
    var lesson: TimetableLesson
    var compact = false
    var showDetails = true
    var action: () -> Void
    var body: some View {
        let _ = clockStyle
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title).font(.system(size: compact ? 10 : 12, weight: .medium)).lineLimit(compact ? 1 : 2)
                if showDetails {
                    Text(lesson.start.clockTime).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if !lesson.location.isEmpty { Text(lesson.location).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }.padding(.horizontal, compact ? 4 : 7).padding(.vertical, compact ? 1 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.20))
                .background(Color(red: 0.66, green: 0.62, blue: 0.85), in: RoundedRectangle(cornerRadius: compact ? 4 : 7))
                .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 7))
        }.buttonStyle(.plain).help("\(lesson.title)\n\(lesson.start.clockDateTime) – \(lesson.end.clockTime)\n\(lesson.location)")
            .accessibilityLabel("\(lesson.title), \(lesson.allDay ? "All day" : lesson.start.clockTime)")
    }
}

struct TimetableMonthGrid: View {
    @AppStorage("clockStyle") private var clockStyle = "system"
    @Binding var day: Date
    @Binding var mode: TimetableMode
    var lessons: [TimetableLesson]
    var select: (TimetableLesson) -> Void
    private var calendar: Calendar { TimetableCalendar.calendar }
    var body: some View {
        let _ = clockStyle
        let days = TimetableCalendar.days(containing: day, mode: .month)
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(days.prefix(7), id: \.self) { date in Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }.padding(.vertical, 12)
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                            ForEach(days, id: \.self) { date in monthCell(date).frame(height: max(104, geometry.size.height / CGFloat(days.count / 7))).id(date) }
                        }
                    }
                    .onAppear { proxy.scrollTo(calendar.startOfDay(for: day), anchor: .center) }
                    .onChange(of: day) { _, _ in proxy.scrollTo(calendar.startOfDay(for: day), anchor: .center) }
                }
            }
        }
    }
    private func monthCell(_ date: Date) -> some View {
        let items = lessons.filter { TimetableCalendar.contains($0, day: date) }.sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 3) {
            Button { day = date; mode = .day } label: {
                Text(date.formatted(.dateTime.day())).font(.caption.weight(.semibold)).frame(width: 26, height: 26)
                    .background(calendar.isDateInToday(date) ? SchoolClass.tint("lavender").opacity(0.3) : .clear, in: Circle())
            }.buttonStyle(.plain).help("Show \(date.formatted(date: .complete, time: .omitted))")
            ForEach(items.prefix(3)) { lesson in
                Button { select(lesson) } label: {
                    HStack(spacing: 3) {
                        Circle().fill(SchoolClass.tint("lavender")).frame(width: 5, height: 5)
                        Text((lesson.allDay ? "" : lesson.start.clockTime + " ") + lesson.title).font(.system(size: 10)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help(lesson.title)
            }
            if items.count > 3 { Button("+\(items.count - 3) more") { day = date; mode = .day }.font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(calendar.isDate(date, equalTo: day, toGranularity: .month) ? Color.clear : Color.primary.opacity(0.035))
            .overlay(Rectangle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct TimetableLessonDetails: View {
    @AppStorage("clockStyle") private var clockStyle = "system"
    let lesson: TimetableLesson
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let _ = clockStyle
        VStack(alignment: .leading, spacing: 16) {
            Text(lesson.title).font(.title2.weight(.semibold)).textSelection(.enabled)
            Label(lesson.start.formatted(date: .complete, time: .omitted), systemImage: "calendar")
            if !lesson.allDay { Label("\(lesson.start.clockTime) – \(lesson.end.clockDateTime)", systemImage: "clock") }
            else { Text("All day").foregroundStyle(.secondary) }
            if !lesson.location.isEmpty { Label(lesson.location, systemImage: "mappin.and.ellipse").textSelection(.enabled) }
            if !lesson.notes.isEmpty { ScrollView { Text(lesson.notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 220) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 480)
    }
}
