import SwiftUI

/// Display only: stored dates and the model's ISO wire format never change.
enum ClockDisplay {
    static var uses12Hours: Bool {
        switch UserDefaults.standard.string(forKey: "clockStyle") ?? "system" {
        case "12": return true
        case "24": return false
        default: return DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
        }
    }
    static func time(_ date: Date, twelveHour: Bool = uses12Hours, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = twelveHour ? "h:mm a" : "HH:mm"
        return formatter.string(from: date)
    }
    static func hourLabel(_ hour: Int, twelveHour: Bool = uses12Hours) -> String {
        twelveHour ? "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")" : String(format: "%02d:00", hour)
    }
}
extension Date {
    var clockTime: String { ClockDisplay.time(self) }
    var clockDateTime: String { formatted(date: .abbreviated, time: .omitted) + " at " + clockTime }
}

struct ClockTimePicker: View {
    var title: String
    @Binding var selection: Date
    @AppStorage("clockStyle") private var clockStyle = "system"
    init(_ title: String, selection: Binding<Date>) { self.title = title; _selection = selection }
    private var hour: Int { Calendar.current.component(.hour, from: selection) }
    private var minute: Int { Calendar.current.component(.minute, from: selection) }
    private func set(hour: Int? = nil, minute: Int? = nil) {
        if let date = Calendar.current.date(bySettingHour: hour ?? self.hour, minute: minute ?? self.minute, second: 0, of: selection) { selection = date }
    }
    var body: some View {
        let _ = clockStyle
        let twelveHour = ClockDisplay.uses12Hours
        HStack {
            Text(title)
            Spacer()
            Picker("\(title) hour", selection: Binding(get: { twelveHour ? (hour % 12 == 0 ? 12 : hour % 12) : hour }, set: { value in set(hour: twelveHour ? value % 12 + (hour >= 12 ? 12 : 0) : value) })) {
                ForEach(twelveHour ? Array(1...12) : Array(0...23), id: \.self) { Text(twelveHour ? "\($0)" : String(format: "%02d", $0)).tag($0) }
            }.labelsHidden().frame(width: 65)
            Text(":").foregroundStyle(.secondary)
            Picker("\(title) minute", selection: Binding(get: { minute }, set: { set(minute: $0) })) {
                ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) }
            }.labelsHidden().frame(width: 65)
            if twelveHour {
                Picker("\(title) period", selection: Binding(get: { hour >= 12 }, set: { set(hour: hour % 12 + ($0 ? 12 : 0)) })) {
                    Text("AM").tag(false); Text("PM").tag(true)
                }.labelsHidden().frame(width: 70)
            }
        }
    }
}
