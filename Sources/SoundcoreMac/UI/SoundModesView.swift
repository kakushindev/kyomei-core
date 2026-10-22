import SoundcoreKit
import SwiftUI

struct SoundModesView: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        if let m = controller.state?.soundModes, let spec = controller.profile?.soundModes {
            ScrollView {
                VStack(spacing: 16) {
                    ModeSwitcher()
                    if !spec.noiseCancelingModes.isEmpty || spec.manualLevel != nil {
                        noiseCanceling(m, spec)
                    }
                    if !spec.transparencyModes.isEmpty || spec.manualTransparency != nil {
                        transparency(m, spec)
                    }
                    if let cycle = controller.state?.soundModeCycle, controller.profile?.hasSoundModeCycle == true {
                        cycleCard(cycle)
                    }
                }
                .padding(20)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func update(_ change: @escaping (inout SoundModes) -> Void) {
        controller.updateSoundModes(change)
    }

    // MARK: Noise cancelling

    private func noiseCanceling(_ m: SoundModes, _ spec: SoundModeSpec) -> some View {
        let tint = AmbientSoundMode.noiseCanceling.tint
        return VStack(alignment: .leading, spacing: 16) {
            PanelTitle(title: "Noise Cancelling", symbol: AmbientSoundMode.noiseCanceling.symbol,
                       trailing: m.ambient == .noiseCanceling ? "Active" : nil)

            if !spec.noiseCancelingModes.isEmpty {
                OptionTiles(options: spec.noiseCancelingModes, selection: m.noiseCanceling,
                            title: \.title, symbol: \.symbol, tint: tint) { mode in update { $0.noiseCanceling = mode } }
            }

            Group {
                switch m.noiseCanceling {
                case .adaptive:
                    if let style = spec.adaptiveLevel {
                        row("Current Strength") { readOnlyLevel(m.adaptiveLevel, style) }
                    }
                    if spec.realTimeAdaptive {
                        toggle("Real-Time Adaptation", "Continuously adjusts to your environment and fit.", m.realTimeAdaptive) { v in update { $0.realTimeAdaptive = v } }
                    }
                    if spec.environmentDetection {
                        toggle("Environment Detection", "Adapts to the noise level around you.", m.environmentDetection) { v in update { $0.environmentDetection = v } }
                    }
                    if let range = spec.adaptiveSensitivity {
                        row("Sensitivity") {
                            LevelPills(range: range, value: min(range.upperBound, max(range.lowerBound, m.adaptiveSensitivity)), tint: tint) { v in update { $0.adaptiveSensitivity = v } }
                        }
                    }
                case .manual:
                    if let style = spec.manualLevel { row("Strength") { editableLevel(m.manualLevel, style, tint) { v in update { $0.manualLevel = v } } } }
                case .multiScene:
                    OptionTiles(options: spec.multiSceneModes, selection: m.multiScene, title: \.title, symbol: \.symbol, tint: tint) { scene in
                        update { $0.multiScene = scene }
                    }
                case .transportation:
                    OptionTiles(options: spec.transportationModes, selection: m.transportation, title: \.title, symbol: \.symbol, tint: tint) { mode in
                        update { $0.transportation = mode }
                    }
                case .custom:
                    if let range = spec.customLevel {
                        row("Custom Strength") {
                            Slider(value: Binding(get: { Double(min(10, m.customLevel)) }, set: { v in update { $0.customLevel = UInt8(v) } }),
                                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                                .frame(maxWidth: 240)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))

            if spec.windNoise {
                Divider()
                toggle("Wind Noise Reduction", m.windNoiseDetected ? "Wind detected right now." : nil, m.windNoiseSuppression) { v in
                    update { $0.windNoiseSuppression = v }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: m.noiseCanceling)
        .padding(18)
        .glassPanel(tint: m.ambient == .noiseCanceling ? tint : nil)
    }

    // MARK: Transparency

    private func transparency(_ m: SoundModes, _ spec: SoundModeSpec) -> some View {
        let tint = AmbientSoundMode.transparency.tint
        return VStack(alignment: .leading, spacing: 16) {
            PanelTitle(title: "Transparency", symbol: AmbientSoundMode.transparency.symbol,
                       trailing: m.ambient == .transparency ? "Active" : nil)
            if !spec.transparencyModes.isEmpty {
                Picker("Mode", selection: Binding(get: { m.transparency }, set: { v in update { $0.transparency = v } })) {
                    ForEach(spec.transparencyModes) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let range = spec.manualTransparency, spec.transparencyModes.isEmpty || m.transparency == .manual {
                row("Level") { LevelPills(range: range, value: m.manualTransparencyLevel, tint: tint) { v in update { $0.manualTransparencyLevel = v } } }
            }
        }
        .padding(18)
        .glassPanel(tint: m.ambient == .transparency ? tint : nil)
    }

    // MARK: Cycle

    private func cycleCard(_ cycle: AmbientSoundModeCycle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(title: "Touch Cycle", symbol: "arrow.triangle.2.circlepath")
            Text("Modes the “Switch Sound Mode” touch action steps through.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                cycleToggle(.noiseCanceling, cycle.noiseCanceling) { var c = cycle; c.noiseCanceling = $0; return c }
                cycleToggle(.transparency, cycle.transparency) { var c = cycle; c.transparency = $0; return c }
                cycleToggle(.normal, cycle.normal) { var c = cycle; c.normal = $0; return c }
            }
        }
        .padding(18)
        .glassPanel()
    }

    private func cycleToggle(_ mode: AmbientSoundMode, _ on: Bool, _ make: @escaping (Bool) -> AmbientSoundModeCycle) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { controller.setSoundModeCycle(make($0)) })) {
            Label(mode.title, systemImage: mode.symbol)
        }
        .toggleStyle(.button)
        .tint(mode.tint)
        .frame(maxWidth: .infinity)
    }

    // MARK: Building blocks

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private func toggle(_ title: String, _ detail: String?, _ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private func editableLevel(_ value: UInt8, _ style: LevelStyle, _ tint: Color, _ set: @escaping (UInt8) -> Void) -> some View {
        switch style {
        case .numeric(let range):
            LevelPills(range: range, value: min(range.upperBound, max(range.lowerBound, value)), tint: tint, onChange: set)
        case .named(let names):
            Picker("", selection: Binding(get: { value }, set: set)) {
                ForEach(names, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
        }
    }

    @ViewBuilder
    private func readOnlyLevel(_ value: UInt8, _ style: LevelStyle) -> some View {
        switch style {
        case .numeric(let range):
            LevelPills(range: range, value: min(range.upperBound, max(range.lowerBound, value)),
                       tint: AmbientSoundMode.noiseCanceling.tint, isReadOnly: true) { _ in }
        case .named(let names):
            Text(names.first { $0.0 == value }?.1 ?? "—")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(AmbientSoundMode.noiseCanceling.tint.opacity(0.15), in: Capsule())
        }
    }
}
