import SoundcoreKit
import SwiftUI

struct SpatialAudioView: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        if let spatial = controller.state?.spatialAudio {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 18) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(spatial.isEnabled ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.secondary))
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: spatial.isEnabled)
                            .frame(height: 60)
                        Toggle(isOn: Binding(get: { spatial.isEnabled }, set: { controller.setSpatialAudio(enabled: $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spatial Audio").font(.headline)
                                Text("Virtual surround that places sound around you.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(20)
                    .glassPanel(cornerRadius: 24, tint: spatial.isEnabled ? .accentColor : nil)

                    VStack(alignment: .leading, spacing: 12) {
                        PanelTitle(title: "Mode")
                        OptionTiles(options: SpatialAudioMode.allCases, selection: spatial.isEnabled ? spatial.mode : nil,
                                    title: \.title, symbol: \.symbol) { controller.setSpatialMode($0) }
                            .disabled(!spatial.isEnabled)
                            .opacity(spatial.isEnabled ? 1 : 0.5)
                        Text("Choosing an equalizer preset turns spatial audio off, the same as in the Soundcore app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .glassPanel()
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .animation(.smooth, value: spatial)
            }
        }
    }
}

struct ControlsView: View {
    @Environment(DeviceController.self) private var controller
    @ViewState private var confirmReset = false

    var body: some View {
        if let s = controller.state, let p = controller.profile {
            ScrollView {
                VStack(spacing: 16) {
                    if let spec = p.buttons { grid(spec, s) }
                    if let bassUp = s.bassUpButton {
                        VStack(alignment: .leading, spacing: 12) {
                            PanelTitle(title: "Double Press", symbol: "hand.tap.fill")
                            Toggle(isOn: Binding(get: { bassUp }, set: { controller.setBassUpButton($0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("BassUp")
                                    Text("Double-press the power button to boost bass.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                        .padding(18)
                        .glassPanel()
                    }
                    if p.canResetButtons {
                        Button("Restore Default Controls…") { confirmReset = true }
                            .glassButtonStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .confirmationDialog("Restore the default touch controls?", isPresented: $confirmReset) {
                Button("Restore Defaults", role: .destructive) { controller.resetButtons() }
            }
        }
    }

    private func grid(_ spec: ButtonSpec, _ s: DeviceState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle(title: "Touch Controls", symbol: "hand.tap",
                       trailing: s.tws?.isConnected == false ? "Single earbud" : "Both earbuds")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Label("Left", systemImage: "airpod.left").font(.callout.weight(.semibold))
                    Label("Right", systemImage: "airpod.right").font(.callout.weight(.semibold))
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(spec.pressKinds) { press in
                    GridRow {
                        Label(press.title, systemImage: press.symbol).foregroundStyle(.secondary)
                        picker(.left, press, spec)
                        picker(.right, press, spec)
                    }
                }
            }
            Text(s.tws?.isConnected == false
                 ? "Showing actions used when wearing a single earbud."
                 : "Showing actions used when both earbuds are in your ears.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .glassPanel()
    }

    private func picker(_ side: ButtonSide, _ press: PressKind, _ spec: ButtonSpec) -> some View {
        let key = ButtonKey(side, press)
        let current = controller.buttonAction(key)
        let actions = spec.settings(for: press)?.actions ?? []
        return Picker("", selection: Binding<ButtonAction?>(get: { current }, set: { controller.setButton(key, action: $0) })) {
            Text("None").tag(ButtonAction?.none)
            Divider()
            ForEach(actions) { Text($0.title).tag(ButtonAction?.some($0)) }
            if let current, !actions.contains(current) {
                Text(current.title).tag(ButtonAction?.some(current))
            }
        }
        .labelsHidden()
        .frame(minWidth: 170, maxWidth: .infinity)
    }
}

struct ConnectionsView: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        if let s = controller.state, let dual = s.dualConnections {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(get: { dual }, set: { controller.setDualConnections($0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connect to Two Devices").font(.headline)
                                Text("Stay connected to this Mac and your phone at the same time.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        if s.flags[.ldac] == true {
                            Label("LDAC is on. Multipoint may be unavailable while LDAC is enabled.", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .glassPanel()

                    if dual {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                PanelTitle(title: "Paired Devices", symbol: "laptopcomputer.and.iphone")
                                Button {
                                    controller.refreshDualConnections()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Reload")
                            }
                            .padding(.bottom, 6)
                            if controller.dualConnectionDevices.isEmpty {
                                HStack {
                                    Text(controller.isLoadingDualConnections ? "Loading…" : "No devices reported").foregroundStyle(.secondary)
                                    if controller.isLoadingDualConnections { ProgressView().controlSize(.small) }
                                }
                            }
                            ForEach(controller.dualConnectionDevices) { device in
                                HStack(spacing: 12) {
                                    Image(systemName: icon(for: device.name))
                                        .font(.title3)
                                        .frame(width: 30)
                                        .foregroundStyle(device.isConnected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name.isEmpty ? device.macAddressString : device.name)
                                        Text(device.isConnected ? "Connected" : "Paired").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(device.isConnected ? "Disconnect" : "Connect") {
                                        controller.setDualConnection(device, connected: !device.isConnected)
                                    }
                                    .glassButtonStyle(prominent: !device.isConnected)
                                }
                                .padding(.vertical, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(18)
                        .glassPanel()
                        .animation(.smooth, value: controller.dualConnectionDevices)
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("mac") { return "laptopcomputer" }
        if n.contains("ipad") || n.contains("tab") { return "ipad" }
        if n.contains("pc") || n.contains("desktop") { return "desktopcomputer" }
        return "iphone"
    }
}

struct DeviceSettingsView: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        if let s = controller.state, let p = controller.profile {
            Form {
                let audio = p.flags.filter(\.isAudio)
                let general = p.flags.filter { !$0.isAudio }
                if !audio.isEmpty { Section("Audio") { ForEach(audio) { flagToggle($0, s) } } }
                if !general.isEmpty { Section("General") { ForEach(general) { flagToggle($0, s) } } }

                if let minutes = p.autoPowerOffMinutes, let off = s.autoPowerOff {
                    Section("Power") {
                        Toggle("Auto Power Off", isOn: Binding(
                            get: { off.isEnabled },
                            set: { controller.setAutoPowerOff(AutoPowerOff(isEnabled: $0, durationIndex: off.durationIndex)) }))
                        Picker("Turn Off After", selection: Binding(
                            get: { off.durationIndex },
                            set: { controller.setAutoPowerOff(AutoPowerOff(isEnabled: off.isEnabled, durationIndex: $0)) }
                        )) {
                            ForEach(Array(minutes.enumerated()), id: \.offset) { Text("\($0.element) minutes").tag(UInt8($0.offset)) }
                        }
                        .disabled(!off.isEnabled)
                    }
                }

                if let limit = s.limitHighVolume, p.hasLimitHighVolume {
                    Section("Hearing Protection") {
                        Toggle(isOn: Binding(get: { limit.isEnabled },
                                             set: { controller.setLimitHighVolume(enabled: $0, dbLimit: limit.dbLimit) })) {
                            Text("Limit High Volume")
                            Text("Caps the maximum output level.")
                        }
                        Picker("Maximum Level", selection: Binding(
                            get: { limit.dbLimit },
                            set: { controller.setLimitHighVolume(enabled: limit.isEnabled, dbLimit: $0) }
                        )) {
                            ForEach(Array(stride(from: UInt8(75), through: 100, by: 5)), id: \.self) { Text("\($0) dB").tag($0) }
                            if limit.dbLimit % 5 != 0 || !(75...100).contains(limit.dbLimit) {
                                Text("\(limit.dbLimit) dB").tag(limit.dbLimit)
                            }
                        }
                        .disabled(!limit.isEnabled)
                        Picker("Level Reading", selection: Binding(
                            get: { limit.refreshRate }, set: { controller.setLimitHighVolumeRefreshRate($0) }
                        )) {
                            ForEach(DecibelRefreshRate.allCases) { Text($0.title).tag($0) }
                        }
                        .disabled(!limit.isEnabled)
                    }
                }

                Section("About") {
                    LabeledContent("Name", value: controller.deviceName)
                    LabeledContent("Model") {
                        HStack {
                            Text("\(s.model.displayName) (\(s.model.rawValue))")
                            ModelOverrideMenu()
                        }
                    }
                    LabeledContent("Firmware", value: s.firmware ?? "—")
                    LabeledContent("Serial Number") { Text(s.serialNumber ?? "—").textSelection(.enabled) }
                    if let tws = s.tws { LabeledContent("Primary Earbud", value: tws.host == .left ? "Left" : "Right") }
                    LabeledContent("Bluetooth Address", value: controller.endpoint?.address.uppercased() ?? "—")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func flagToggle(_ flag: DeviceFlag, _ s: DeviceState) -> some View {
        Toggle(isOn: Binding(get: { s.flags[flag] ?? false }, set: { controller.setFlag(flag, $0) })) {
            Label {
                Text(flag.title)
                if let detail = flag.detail { Text(detail) }
            } icon: {
                Image(systemName: flag.symbol)
            }
        }
    }
}
