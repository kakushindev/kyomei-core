import SoundcoreKit
import SwiftUI

// MARK: - Device stage

/// The headphones floating above a sound field that visualises the current mode: rings collapse
/// inward for noise cancelling, radiate outward for transparency and rest for normal. Drawn with
/// a single Canvas at 30 fps and paused whenever the window is hidden or Reduce Motion is on.
struct DeviceStage: View {
    let mode: AmbientSoundMode?
    let isHeadphones: Bool
    var isConnected = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var visible = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !visible || !isConnected)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                if let mode {
                    SoundField(mode: mode, time: t)
                        .id(mode)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                Image(systemName: isHeadphones ? "headphones" : "earbuds")
                    .font(.system(size: isHeadphones ? 78 : 86, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .shadow(color: (mode?.tint ?? .clear).opacity(0.45), radius: 22, y: 6)
                    .offset(y: reduceMotion ? 0 : sin(t * 1.3) * 3)
                    .opacity(isConnected ? 1 : 0.35)
            }
        }
        .animation(.smooth(duration: 0.5), value: mode)
        .trackWindowVisibility($visible)
        .accessibilityHidden(true)
    }
}

private struct SoundField: View {
    let mode: AmbientSoundMode
    let time: Double

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) / 2
            let minR = maxR * 0.34
            let tint = mode.tint

            context.fill(Path(ellipseIn: CGRect(x: c.x - maxR, y: c.y - maxR, width: maxR * 2, height: maxR * 2)),
                         with: .radialGradient(Gradient(colors: [tint.opacity(0.32), tint.opacity(0)]),
                                               center: c, startRadius: 0, endRadius: maxR))
            let rings = 4
            for i in 0..<rings {
                let p = (time * 0.32 + Double(i) / Double(rings)).truncatingRemainder(dividingBy: 1)
                let r: Double, alpha: Double, width: Double
                switch mode {
                case .transparency:
                    r = minR + (maxR - minR) * p
                    alpha = pow(1 - p, 1.6) * 0.55
                    width = 2
                case .noiseCanceling:
                    r = maxR - (maxR - minR) * p
                    alpha = sin(p * .pi) * 0.5
                    width = 1.5 + p * 1.5
                case .normal:
                    r = minR + (maxR - minR) * Double(i + 1) / Double(rings + 1) * (1 + 0.015 * sin(time * 1.4 + Double(i)))
                    alpha = 0.16
                    width = 1
                }
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(tint.opacity(alpha)), lineWidth: width)
            }
        }
    }
}

// MARK: - Battery

struct BatteryTile: View {
    let battery: Battery?
    let symbol: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.callout).foregroundStyle(.secondary)
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if battery?.isCharging == true {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse, options: .repeating)
                }
            }
            Text(battery.map { "\($0.percent)%" } ?? "—")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(battery?.percent ?? 0)))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(colors: [batteryTint(battery).opacity(0.75), batteryTint(battery)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(battery?.percent ?? 0) / 100))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .inset()
        .animation(.smooth(duration: 0.6), value: battery?.percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) battery \(battery.map { "\($0.percent) percent" } ?? "unavailable")\(battery?.isCharging == true ? ", charging" : "")")
    }
}

/// Compact readout for the menu bar panel.
struct BatteryChip: View {
    let battery: Battery?
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(battery?.isCharging == true ? .green : (battery?.percent ?? 100) <= 20 ? .red : .primary)
            Text(battery.map { "\($0.percent)%" } ?? "—")
                .font(.callout.weight(.medium)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private var symbolName: String {
        guard let battery else { return "battery.0percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<20: return "battery.0percent"
        case ..<45: return "battery.25percent"
        case ..<70: return "battery.50percent"
        case ..<95: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct BatteryRow: View {
    let state: DeviceState

    var body: some View {
        HStack(spacing: 10) {
            if let right = state.right {
                BatteryTile(battery: state.left, symbol: "airpod.left", label: "Left")
                BatteryTile(battery: right, symbol: "airpod.right", label: "Right")
            } else {
                BatteryTile(battery: state.left, symbol: "headphones", label: "Battery")
            }
            if let c = state.caseBattery {
                BatteryTile(battery: c, symbol: "earbuds.case", label: "Case")
            }
        }
    }
}

// MARK: - Mode switcher

/// Segmented control for the ambient sound modes with a sliding, mode-coloured pill.
struct ModeSwitcher: View {
    @Environment(DeviceController.self) private var controller
    var compact = false
    @Namespace private var pill

    var body: some View {
        let modes = controller.profile?.soundModes?.ambientModes ?? AmbientSoundMode.allCases
        let current = controller.state?.soundModes?.ambient
        HStack(spacing: 4) {
            ForEach(modes) { mode in
                let selected = current == mode
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { controller.setAmbient(mode) }
                } label: {
                    VStack(spacing: compact ? 3 : 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: compact ? 15 : 20, weight: .medium))
                            .symbolEffect(.bounce, value: selected)
                            .frame(height: compact ? 18 : 24)
                        Text(compact ? mode.shortTitle : mode.title)
                            .font(compact ? .caption.weight(.medium) : .callout.weight(.semibold))
                            .lineLimit(1)
                        if !compact {
                            Text(mode.caption)
                                .font(.caption)
                                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 8 : 13)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: compact ? 11 : 15, style: .continuous)
                                .fill(mode.gradient)
                                .shadow(color: mode.tint.opacity(0.35), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .inset(cornerRadius: compact ? 14 : 19)
    }
}

// MARK: - Option tiles

/// Grid of selectable icon tiles (noise cancelling sub-modes, scenes, transport types).
struct OptionTiles<Option: Hashable>: View {
    let options: [Option]
    let selection: Option?
    let title: (Option) -> String
    let symbol: (Option) -> String
    var tint: Color = .accentColor
    let onSelect: (Option) -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onSelect(option) }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: symbol(option))
                            .font(.system(size: 17, weight: .medium))
                            .symbolEffect(.bounce, value: selected)
                        Text(title(option)).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5))
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(tint.gradient)
                                .matchedGeometryEffect(id: "tile", in: highlight)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Levels

/// 1...5 style level picker drawn as pills that fill up to the value.
struct LevelPills: View {
    let range: ClosedRange<UInt8>
    let value: UInt8
    var tint: Color = .accentColor
    var isReadOnly = false
    let onChange: (UInt8) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(range), id: \.self) { level in
                Capsule()
                    .fill(level <= value ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.quaternary))
                    .frame(height: 10 + CGFloat(level - range.lowerBound) * 3)
                    .frame(maxHeight: 26, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isReadOnly { withAnimation(.snappy) { onChange(level) } } }
            }
            Text("\(value)")
                .font(.callout.weight(.semibold)).monospacedDigit()
                .frame(width: 22)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: 240)
        .animation(.snappy, value: value)
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            guard !isReadOnly else { return }
            switch direction {
            case .increment: if value < range.upperBound { onChange(value + 1) }
            case .decrement: if value > range.lowerBound { onChange(value - 1) }
            @unknown default: break
            }
        }
    }
}

// MARK: - Equalizer drawing

/// Smooth EQ response curve drawn through the band points.
struct EqualizerCurve: View {
    let tenths: [Int16]
    var range: ClosedRange<Double> = -60...60
    var showGrid = true
    var tint: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            let points = tenths.enumerated().map { i, v -> CGPoint in
                let x = tenths.count > 1 ? size.width * CGFloat(i) / CGFloat(tenths.count - 1) : size.width / 2
                let clamped = min(range.upperBound, max(range.lowerBound, Double(v)))
                let y = size.height * (1 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
                return CGPoint(x: x, y: y)
            }
            if showGrid {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: size.height / 2))
                grid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(grid, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            guard points.count > 1 else { return }
            let curve = Self.smoothPath(points)
            var fill = curve
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(curve, with: .color(tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .animation(.smooth, value: tenths)
        .accessibilityHidden(true)
    }

    /// Catmull-Rom spline converted to cubic Béziers.
    static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }
}

/// Vertical slider for one EQ band. Drag to change, double-click to reset to 0 dB.
struct BandSlider: View {
    @Binding var tenths: Int16
    let frequency: Int
    var range: ClosedRange<Int16> = -60...60
    var isEnabled = true
    var onCommit: () -> Void = {}

    @ViewState private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Text(formatDecibels(tenths))
                .font(.caption2.weight(.medium)).monospacedDigit()
                .foregroundStyle(tenths == 0 ? .secondary : .primary)
            GeometryReader { geo in
                let h = geo.size.height
                let knobY = y(for: tenths, height: h)
                let zeroY = y(for: 0, height: h)
                ZStack(alignment: .top) {
                    Capsule().fill(.quaternary).frame(width: 6)
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: 6, height: abs(knobY - zeroY))
                        .offset(y: min(knobY, zeroY))
                    Circle()
                        .fill(.background)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .shadow(color: Color.accentColor.opacity(isDragging ? 0.55 : 0.15), radius: isDragging ? 8 : 2, y: 1)
                        .frame(width: 18, height: 18)
                        .scaleEffect(isDragging ? 1.25 : 1)
                        .offset(y: knobY - 9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard isEnabled else { return }
                            if !isDragging { withAnimation(.snappy(duration: 0.15)) { isDragging = true } }
                            let value = self.value(for: g.location.y, height: h)
                            if value != tenths { tenths = value }
                        }
                        .onEnded { _ in
                            withAnimation(.snappy(duration: 0.2)) { isDragging = false }
                            onCommit()
                        }
                )
                .onTapGesture(count: 2) {
                    guard isEnabled else { return }
                    tenths = 0
                    onCommit()
                }
            }
            .frame(width: 34)
            Text(formatFrequency(frequency)).font(.caption2).foregroundStyle(.secondary)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel("\(formatFrequency(frequency)) hertz")
        .accessibilityValue("\(formatDecibels(tenths)) decibels")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: tenths = min(range.upperBound, tenths + 5)
            case .decrement: tenths = max(range.lowerBound, tenths - 5)
            @unknown default: break
            }
            onCommit()
        }
    }

    private func y(for value: Int16, height: CGFloat) -> CGFloat {
        let inset: CGFloat = 9
        let t = Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
        return inset + (height - 2 * inset) * (1 - t)
    }

    private func value(for y: CGFloat, height: CGFloat) -> Int16 {
        let inset: CGFloat = 9
        let t = 1 - Double((y - inset) / max(1, height - 2 * inset))
        let raw = Double(range.lowerBound) + t * Double(range.upperBound - range.lowerBound)
        let stepped = (raw / 5).rounded() * 5  // 0.5 dB steps, like the Soundcore app
        return Int16(min(Double(range.upperBound), max(Double(range.lowerBound), stepped)))
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}
