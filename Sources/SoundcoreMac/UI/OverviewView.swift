import SoundcoreKit
import SwiftUI

struct OverviewView: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        if let s = controller.state, let p = controller.profile {
            ScrollView {
                VStack(spacing: 16) {
                    hero(s)
                    if p.soundModes != nil { ModeSwitcher() }
                    HStack(alignment: .top, spacing: 16) {
                        if let eq = s.equalizer { equalizerCard(eq, s) }
                        quickSettings(s, p)
                    }
                    infoCard(s, p)
                }
                .padding(20)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func hero(_ s: DeviceState) -> some View {
        let mode = s.soundModes?.ambient
        return VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.deviceName).font(.title2.weight(.semibold))
                    Text(subtitle(s)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let mode {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(.white)
                        .background(mode.gradient, in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.smooth, value: mode)
                }
            }
            DeviceStage(mode: mode, isHeadphones: s.model.isHeadphones)
                .frame(height: 190)
            BatteryRow(state: s)
        }
        .padding(20)
        .glassPanel(cornerRadius: 26, tint: mode?.tint)
    }

    private func subtitle(_ s: DeviceState) -> String {
        var parts = [s.model.displayName]
        if let tws = s.tws { parts.append(tws.isConnected ? "Both earbuds" : "Single earbud") }
        if s.flags[.ldac] == true { parts.append("LDAC") }
        return parts.joined(separator: " · ")
    }

    private func equalizerCard(_ eq: EqualizerState, _ s: DeviceState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(title: "Equalizer", symbol: "slider.vertical.3", trailing: controller.equalizerName(s))
            EqualizerCurve(tenths: eq.visible, tint: s.soundModes?.ambient.tint ?? .accentColor)
                .frame(height: 84)
            if let presets = controller.profile?.equalizer?.presets {
                Menu {
                    ForEach(presets) { preset in
                        Button(preset.name) { controller.selectPreset(preset) }
                    }
                } label: {
                    Label("Choose Preset", systemImage: "music.note.list")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    private func quickSettings(_ s: DeviceState, _ p: DeviceProfile) -> some View {
        let quick = p.flags.filter { [.ldac, .gamingMode, .surroundSound, .wearingDetection, .touchLock].contains($0) }.prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            PanelTitle(title: "Quick Settings", symbol: "switch.2")
            if let spatial = s.spatialAudio {
                Toggle(isOn: Binding(get: { spatial.isEnabled }, set: { controller.setSpatialAudio(enabled: $0) })) {
                    Label("Spatial Audio", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            ForEach(Array(quick)) { flag in
                Toggle(isOn: Binding(get: { s.flags[flag] ?? false }, set: { controller.setFlag(flag, $0) })) {
                    Label(flag.title, systemImage: flag.symbol)
                }
            }
            if let dual = s.dualConnections, p.hasDualConnections {
                Toggle(isOn: Binding(get: { dual }, set: { controller.setDualConnections($0) })) {
                    Label("Multipoint", systemImage: "laptopcomputer.and.iphone")
                }
            }
            Spacer(minLength: 0)
        }
        .toggleStyle(.switch)
        .padding(18)
        .frame(maxWidth: 270, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel()
    }

    private func infoCard(_ s: DeviceState, _ p: DeviceProfile) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 9) {
            info("Model", "\(s.model.displayName) (\(s.model.rawValue))")
            info("Firmware", s.firmware ?? "—")
            info("Serial Number", s.serialNumber ?? "—")
            info("Bluetooth Address", controller.endpoint?.address.uppercased() ?? "—")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    private func info(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).monospacedDigit()
        }
    }
}
