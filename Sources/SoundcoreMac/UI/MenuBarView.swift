import SoundcoreKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(DeviceController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showBatteryInMenuBar") private var showBattery = true

    var body: some View {
        let symbol = controller.state?.model.isHeadphones == true ? "headphones" : "earbuds"
        Group {
            if let s = controller.state, controller.status == .connected {
                Image(systemName: symbol)
                if showBattery { Text("\(s.lowestPercent)%") }
            } else {
                Image(systemName: symbol).opacity(0.5)
            }
        }
        // The menu bar label always exists, so it lends `openWindow` to AppKit code.
        .onAppear { AppDelegate.openMainWindow = { [openWindow] in openWindow(id: "main") } }
    }
}

struct MenuBarView: View {
    @Environment(DeviceController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let s = controller.state, let p = controller.profile, controller.status == .connected {
                HStack {
                    if let r = s.right {
                        BatteryChip(battery: s.left, label: "L")
                        BatteryChip(battery: r, label: "R")
                    } else {
                        BatteryChip(battery: s.left, label: "Battery")
                    }
                    if let c = s.caseBattery { BatteryChip(battery: c, label: "Case") }
                }
                .padding(.vertical, 9)
                .inset(cornerRadius: 12)

                if p.soundModes != nil { ModeSwitcher(compact: true) }

                VStack(spacing: 10) {
                    if let presets = p.equalizer?.presets {
                        HStack {
                            Label("Equalizer", systemImage: "slider.vertical.3")
                            Spacer()
                            Menu(controller.equalizerName(s) ?? "—") {
                                ForEach(presets) { preset in
                                    Button {
                                        controller.selectPreset(preset)
                                    } label: {
                                        if s.equalizer?.isCustom == false, s.equalizer?.presetID == preset.id {
                                            Label(preset.name, systemImage: "checkmark")
                                        } else {
                                            Text(preset.name)
                                        }
                                    }
                                }
                                if p.equalizer?.allowsCustom == true, !controller.customProfiles.profiles.isEmpty {
                                    Divider()
                                    ForEach(controller.customProfiles.profiles) { profile in
                                        Button(profile.name) { controller.setCustomBands(profile.bands) }
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                    if let spatial = s.spatialAudio {
                        quickToggle("Spatial Audio", "dot.radiowaves.left.and.right", spatial.isEnabled) { controller.setSpatialAudio(enabled: $0) }
                    }
                    if let on = s.flags[.gamingMode] {
                        quickToggle("Gaming Mode", "gamecontroller", on) { controller.setFlag(.gamingMode, $0) }
                    }
                    if let on = s.flags[.ldac] {
                        quickToggle("LDAC", "hifispeaker", on) { controller.setFlag(.ldac, $0) }
                    }
                }
            } else {
                Button {
                    controller.connect()
                } label: {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .glassButtonStyle(prominent: true)
            }

            if controller.pairedDevices.count > 1 { DeviceSwitcher(compact: true) }

            Divider()

            HStack {
                Button("Open \(Brand.name)") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
        .animation(.smooth(duration: 0.3), value: controller.status)
        .onAppear { controller.reloadPairedDevices() }
    }

    private var header: some View {
        let mode = controller.state?.soundModes?.ambient
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill((mode ?? .normal).gradient).frame(width: 38, height: 38)
                    .shadow(color: (mode?.tint ?? .clear).opacity(0.4), radius: 6, y: 2)
                Image(systemName: controller.state?.model.isHeadphones == true ? "headphones" : "earbuds")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.smooth, value: mode)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.status == .connected ? controller.deviceName : Brand.name).font(.headline).lineLimit(1)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
        }
    }

    private func quickToggle(_ title: String, _ symbol: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Toggle(title, isOn: Binding(get: { on }, set: set))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }

    private var statusLine: String {
        switch controller.status {
        case .connected: return controller.state?.soundModes?.ambient.title ?? controller.state?.model.displayName ?? "Connected"
        case .connecting: return "Connecting…"
        case .bluetoothOff: return "Bluetooth is off"
        case .unsupported: return "Unsupported model"
        case .failed: return "Connection failed"
        default: return "Not connected"
        }
    }
}

struct AppSettingsView: View {
    @Environment(DeviceController.self) private var controller
    @AppStorage("showBatteryInMenuBar") private var showBattery = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var notifications = true
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, new in withAnimation(.smooth) { new.apply() } }
            } footer: {
                Text("System follows the macOS light or dark setting.")
            }
            Section {
                Toggle("Open at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            try LaunchAtLogin.set(on)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, on in AppDelegate.applyActivationPolicy(showInDock: on) }
                Toggle("Show Battery Level in Menu Bar", isOn: $showBattery)
            }
            Section {
                Toggle("Low Battery Notifications", isOn: $notifications)
                    .onChange(of: notifications) { _, on in controller.batteryMonitor.isEnabled = on }
            } footer: {
                Text("Notifies you once when a battery drops to 20%.")
            }
            Section("Keyboard Shortcuts") {
                LabeledContent("Noise Cancelling", value: "⌘1")
                LabeledContent("Transparency", value: "⌘2")
                LabeledContent("Normal", value: "⌘3")
                LabeledContent("Cycle Sound Mode", value: "⌘M")
                LabeledContent("Refresh", value: "⌘R")
            }
            Section {
                Text("Add the \(Brand.name) widget from the desktop: right-click the wallpaper → Edit Widgets.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Widgets")
            }
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Text(Brand.kanji)
                        .font(.custom("Hiragino Mincho ProN", size: 18).weight(.semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.06, blue: 0.18))
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 0.78, green: 0.06, blue: 0.18), lineWidth: 1.5))
                        .rotationEffect(.degrees(-6))
                        .accessibilityLabel("Kyōmei, resonance")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Brand.name) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .font(.headline)
                        Text(Brand.tagline).foregroundStyle(.secondary)
                        Text("Open source by \(Brand.organization).").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Link("GitHub", destination: Brand.repository)
                    Link("Releases", destination: Brand.releases)
                    Link("Report an Issue", destination: Brand.issues)
                    Link("Kakushin", destination: Brand.organizationURL)
                }
                Text(Brand.disclaimer).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { notifications = controller.batteryMonitor.isEnabled }
    }
}
