import AppKit
import CinnabarCore
import SwiftUI

enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.45, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.78, green: 0.14, blue: 0.16, alpha: 1)
    }))

    static let accentFill = Color(red: 0.76, green: 0.13, blue: 0.15)

    static let canvas = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.086, green: 0.090, blue: 0.098, alpha: 1)
            : NSColor(srgbRed: 0.965, green: 0.955, blue: 0.941, alpha: 1)
    }))

    static let sidebar = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.067, green: 0.070, blue: 0.078, alpha: 1)
            : NSColor(srgbRed: 0.935, green: 0.922, blue: 0.904, alpha: 1)
    }))

    static let mark = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.42, blue: 0.35),
            Color(red: 0.62, green: 0.08, blue: 0.13)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }
}

@propertyWrapper
struct Stored<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> {
        storage.projectedValue
    }

    static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        let offset = fieldOffset + MemoryLayout<Self>.offset(of: \.storage)!
        State<Value>._makeProperty(
            in: &buffer,
            container: container,
            fieldOffset: offset,
            inputs: &inputs
        )
    }
}

struct PrimaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
        }
    }
}

struct QuietButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .controlSize(.large)
        } else {
            content
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}

extension Quality {
    var title: String {
        switch self {
        case .best: String(localized: "Best")
        case .p2160: "4K"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .audio: String(localized: "Audio")
        }
    }

    var containerName: String {
        self == .audio ? "M4A" : "MP4"
    }
}

enum Formatters {
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func views(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: String(localized: "%@ million views"), compact(Double(count) / 1_000_000))
        case 1_000...:
            return String(format: String(localized: "%@ thousand views"), compact(Double(count) / 1_000))
        default:
            let formatter = NumberFormatter()
            formatter.locale = Locale.current
            formatter.numberStyle = .decimal
            let number = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
            return String(format: String(localized: "%@ views"), number)
        }
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }

    static func speed(_ raw: String) -> String {
        guard Locale.current.language.languageCode == .russian else { return raw }
        return raw
            .replacingOccurrences(of: "GiB/s", with: "ГБ/с")
            .replacingOccurrences(of: "MiB/s", with: "МБ/с")
            .replacingOccurrences(of: "KiB/s", with: "КБ/с")
            .replacingOccurrences(of: "B/s", with: "Б/с")
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func compact(_ value: Double) -> String {
        let text = String(format: "%.1f", locale: Locale.current, value)
        let zeroSuffix = String(format: "%.1f", locale: Locale.current, 0).dropFirst()
        if text.hasSuffix(zeroSuffix) {
            return String(text.dropLast(2))
        }
        return text
    }
}
