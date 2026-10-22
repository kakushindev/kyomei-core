import SoundcoreKit
import SwiftUI
import WidgetKit

@main
struct SoundcoreWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// The app pushes changes and reloads the timeline, so a single entry is enough.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .placeholder) : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SoundcoreBattery", provider: SnapshotProvider()) { entry in
            WidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName(Brand.name)
        .description("Battery and sound mode of your Soundcore headphones.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

private enum Mode: UInt8, CaseIterable {
    case noiseCanceling = 0, transparency = 1, normal = 2

    var title: String { ["Noise Cancelling", "Transparency", "Normal"][Int(rawValue)] }
    var shortTitle: String { ["ANC", "Aware", "Off"][Int(rawValue)] }
    var symbol: String { ["waveform.badge.minus", "ear.and.waveform", "speaker.wave.2"][Int(rawValue)] }
    var tint: Color {
        switch self {
        case .noiseCanceling: Color(red: 0.36, green: 0.40, blue: 0.98)
        case .transparency: Color(red: 0.10, green: 0.74, blue: 0.70)
        case .normal: Color(red: 0.55, green: 0.58, blue: 0.66)
        }
    }
}

/// Follows the system's widget styling: the background is left to macOS (glass on the desktop),
/// content uses primary/secondary so it picks up vibrancy, and colour is only added when the
/// widget is rendered in full colour.
struct WidgetView: View {
    let snapshot: WidgetSnapshot?
    /// Lets previews and render tests pick a size; WidgetKit supplies the family otherwise.
    var previewFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    /// Opaque grey standing in for translucency. On the desktop macOS turns pixel brightness into
    /// opacity and ignores the content's own alpha, so translucent white (including the
    /// hierarchical .secondary/.quaternary styles) comes out solid white. A darker opaque grey
    /// reads as a fainter element there and still looks right everywhere else.
    private func tone(_ strength: Double) -> Color {
        Color(white: colorScheme == .dark ? strength : 1 - strength)
    }

    private var fullColor: Bool { renderingMode == .fullColor }
    private var mode: Mode? { snapshot?.ambientMode.flatMap(Mode.init(rawValue:)) }

    var body: some View {
        Group {
            if let s = snapshot {
                if family == .systemSmall { small(s) } else { medium(s) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "earbuds").font(.title)
                    Text("Open \(Brand.name) to connect")
                        .font(.caption)
                        .foregroundStyle(tone(0.6))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .widgetURL(WidgetSnapshot.openURL)
        // Opaque black (white in light mode) rather than clear. The desktop maps brightness to
        // opacity, so black still shows the glass, but text edges now blend into it instead of
        // turning solid, which keeps anti-aliasing intact.
        .containerBackground(for: .widget) { colorScheme == .dark ? Color.black : Color.white }
    }

    // MARK: Small

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(s, compact: true)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                ForEach(Array(levels(s).enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 4) {
                        ring(item.level, symbol: item.symbol, size: 38)
                        percentLabel(item.level, size: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                if let mode, s.isConnected {
                    Image(systemName: mode.symbol)
                        .foregroundStyle(.primary)
                        .widgetAccentable()
                    Text(mode.title)
                } else {
                    Text(s.isConnected ? (s.equalizerName ?? " ") : "Not connected")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(tone(0.65))
            .lineLimit(1)
        }
    }

    // MARK: Medium

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                header(s, compact: false)
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    ForEach(Array(levels(s).enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 5) {
                            ring(item.level, symbol: item.symbol, size: 46)
                            percentLabel(item.level, size: 11)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(s.isConnected ? (s.equalizerName.map { "EQ · \($0)" } ?? " ") : "Not connected")
                    .font(.caption)
                    .foregroundStyle(tone(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if s.isConnected, !s.availableModes.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Mode.allCases.filter { s.availableModes.contains($0.rawValue) }, id: \.rawValue) { m in
                        modeButton(m, selected: m == mode)
                    }
                }
                .frame(width: 112)
            }
        }
    }

    private func modeButton(_ m: Mode, selected: Bool) -> some View {
        Link(destination: WidgetSnapshot.ambientURL(m.rawValue)) {
            HStack(spacing: 7) {
                Image(systemName: m.symbol)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 18)
                    .foregroundStyle(.primary)
                    .widgetAccentable(selected)
                Text(m.shortTitle).font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if selected {
                    Circle().frame(width: 5, height: 5).widgetAccentable()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background { Capsule().fill(tone(selected ? 0.36 : 0.15)) }
        }
        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(tone(0.7)))
    }

    // MARK: Pieces

    private func header(_ s: WidgetSnapshot, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: s.isHeadphones ? "headphones" : "earbuds")
            Text(compact ? shortName(s.deviceName) : s.deviceName).lineLimit(1)
        }
        .font(.system(size: compact ? 11 : 13, weight: .medium))
        .foregroundStyle(s.isConnected ? AnyShapeStyle(.primary) : AnyShapeStyle(tone(0.6)))
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: "soundcore ", with: "", options: .caseInsensitive)
    }

    private func levels(_ s: WidgetSnapshot) -> [(level: WidgetSnapshot.Level?, symbol: String)] {
        var items: [(WidgetSnapshot.Level?, String)] = []
        if s.isHeadphones || s.right == nil {
            items.append((s.left, "headphones"))
        } else {
            items.append((s.left, "airpod.left"))
            items.append((s.right, "airpod.right"))
        }
        if let c = s.caseLevel { items.append((c, "earbuds.case")) }
        return items
    }

    private func percentLabel(_ level: WidgetSnapshot.Level?, size: CGFloat) -> some View {
        HStack(spacing: 1) {
            if level?.isCharging == true {
                Image(systemName: "bolt.fill").font(.system(size: size - 2, weight: .semibold))
            }
            Text(level.map { "\($0.percent)%" } ?? "—")
                .font(.system(size: size, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    /// Ring in the style of the system Batteries widget: icon inside, progress around it.
    private func ring(_ level: WidgetSnapshot.Level?, symbol: String, size: CGFloat) -> some View {
        let percent = level?.percent ?? 0
        // Colour would turn into dim grey under the desktop's monochrome treatment, so the arc
        // stays white; charging is marked next to the percentage.
        let progress = AnyShapeStyle(.primary)
        return ZStack {
            Circle().stroke(tone(0.16), lineWidth: size * 0.065)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(progress, style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Image(systemName: symbol)
                .font(.system(size: size * 0.3, weight: .regular))
                .foregroundStyle(level == nil ? AnyShapeStyle(tone(0.4)) : AnyShapeStyle(.primary))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(percent) percent\(level?.isCharging == true ? ", charging" : "")")
    }
}
