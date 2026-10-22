import SoundcoreKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview, soundModes, equalizer, spatialAudio, controls, connections, device
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .soundModes: "Sound Modes"
        case .equalizer: "Equalizer"
        case .spatialAudio: "Spatial Audio"
        case .controls: "Controls"
        case .connections: "Multipoint"
        case .device: "Device"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "earbuds"
        case .soundModes: "waveform"
        case .equalizer: "slider.vertical.3"
        case .spatialAudio: "dot.radiowaves.left.and.right"
        case .controls: "hand.tap"
        case .connections: "laptopcomputer.and.iphone"
        case .device: "gearshape"
        }
    }

    /// Panes the connected model supports.
    static func available(for profile: DeviceProfile?) -> [Pane] {
        guard let p = profile else { return [.overview] }
        return allCases.filter { pane in
            switch pane {
            case .overview, .device: true
            case .soundModes: p.soundModes != nil
            case .equalizer: p.equalizer != nil
            case .spatialAudio: p.hasSpatialAudio
            case .controls: p.buttons != nil || p.hasBassUpButton
            case .connections: p.hasDualConnections
            }
        }
    }
}

struct MainView: View {
    @Environment(DeviceController.self) private var controller
    @SceneStorage("pane") private var selection: Pane = .overview

    var body: some View {
        let panes = Pane.available(for: controller.profile)
        let current = panes.contains(selection) ? selection : .overview
        NavigationSplitView {
            List(panes, selection: Binding(get: { current }, set: { selection = $0 ?? .overview })) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { DeviceSwitcher().padding(10) }
            .animation(.smooth, value: panes)
        } detail: {
            ZStack {
                if controller.status == .connected, controller.state != nil {
                    detail(for: current)
                        .id(current)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                } else {
                    ConnectionStateView()
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.28), value: current)
            .animation(.smooth(duration: 0.35), value: controller.status)
            .navigationTitle(current.title)
            .navigationSubtitle(controller.status == .connected ? controller.deviceName : "")
            .toolbar {
                ToolbarItem {
                    Button {
                        controller.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Read the current settings from the headphones (⌘R)")
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .overlay(alignment: .bottom) { ErrorToast() }
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .overview: OverviewView()
        case .soundModes: SoundModesView()
        case .equalizer: EqualizerView()
        case .spatialAudio: SpatialAudioView()
        case .controls: ControlsView()
        case .connections: ConnectionsView()
        case .device: DeviceSettingsView()
        }
    }
}

/// Current device plus a menu of every paired Soundcore device.
struct DeviceSwitcher: View {
    @Environment(DeviceController.self) private var controller
    var compact = false

    var body: some View {
        Menu {
            Section("Paired Soundcore Devices") {
                ForEach(controller.pairedDevices) { device in
                    Button {
                        controller.connect(to: device.address)
                    } label: {
                        let active = device.address == controller.endpoint?.address && controller.status == .connected
                        Label("\(device.name)\(device.isConnected ? "" : " — not connected")",
                              systemImage: active ? "checkmark.circle.fill" : (device.isConnected ? "circle.fill" : "circle"))
                    }
                }
            }
            Divider()
            Button("Bluetooth Settings…") { openBluetoothSettings() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill((controller.state?.soundModes?.ambient ?? .normal).gradient).frame(width: 30, height: 30)
                    Image(systemName: controller.state?.model.isHeadphones == true ? "headphones" : "earbuds")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        StatusDot(color: dotColor)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .glassPanel(cornerRadius: 14)
        .onAppear { controller.reloadPairedDevices() }
        .help("Switch headphones")
    }

    private var title: String {
        switch controller.status {
        case .connecting(let name): name
        default: controller.endpoint?.name ?? "No headphones"
        }
    }

    private var dotColor: Color {
        switch controller.status {
        case .connected: .green
        case .connecting: .orange
        case .failed, .unsupported: .red
        default: .secondary
        }
    }

    private var subtitle: String {
        switch controller.status {
        case .connected:
            guard let s = controller.state else { return "Connected" }
            if let r = s.right { return "L \(s.left.percent)%  ·  R \(r.percent)%" }
            return "\(s.left.percent)%"
        case .connecting: return "Connecting…"
        case .idle: return "Disconnected"
        case .bluetoothOff: return "Bluetooth is off"
        case .noDevice: return "Not connected"
        case .unsupported: return "Unsupported model"
        case .failed: return "Connection failed"
        }
    }
}

struct ConnectionStateView: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        switch controller.status {
        case .connecting(let name):
            VStack(spacing: 22) {
                DeviceStage(mode: .transparency, isHeadphones: false)
                    .frame(width: 220, height: 220)
                Text("Connecting to \(name)…").font(.title3).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .bluetoothOff:
            ContentUnavailableView {
                Label("Bluetooth Is Off", systemImage: "bolt.horizontal.circle")
            } description: {
                Text("Turn on Bluetooth to control your headphones.")
            } actions: {
                Button("Open Bluetooth Settings") { openBluetoothSettings() }
                Button("Try Again") { controller.connect() }
            }
        case .unsupported(let name):
            ContentUnavailableView {
                Label("Model Not Recognised", systemImage: "questionmark.circle")
            } description: {
                Text("\(name) answered, but its settings layout doesn't match a supported model. If you know the model, pick it below.")
            } actions: {
                ModelOverrideMenu()
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Connect", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { controller.connect() }
            }
        default:
            ContentUnavailableView {
                Label("No Soundcore Headphones", systemImage: "earbuds")
            } description: {
                Text("Connect your headphones to this Mac in Bluetooth settings, or pick a paired device below. The app connects automatically.")
            } actions: {
                Button("Open Bluetooth Settings") { openBluetoothSettings() }
                Button("Try Again") { controller.connect() }
            }
        }
    }
}

struct ModelOverrideMenu: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        Menu("Device Model") {
            Button("Detect Automatically") { controller.setModelOverride(nil) }
            Divider()
            ForEach(DeviceModel.allCases) { model in
                Button("\(model.displayName) (\(model.rawValue))") { controller.setModelOverride(model) }
            }
        }
        .fixedSize()
    }
}

func openBluetoothSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
        NSWorkspace.shared.open(url)
    }
}

private struct ErrorToast: View {
    @Environment(DeviceController.self) private var controller

    var body: some View {
        ZStack {
            if let message = controller.lastError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.callout)
                    Button {
                        controller.lastError = nil
                    } label: {
                        Image(systemName: "xmark").imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassPanel(cornerRadius: 22)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(5))
                    controller.lastError = nil
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.lastError)
    }
}
