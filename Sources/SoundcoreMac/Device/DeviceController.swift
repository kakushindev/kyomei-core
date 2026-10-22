import AppKit
import Foundation
import IOBluetooth
import Observation
import SoundcoreKit

enum ConnectionStatus: Equatable {
    case idle
    case bluetoothOff
    case noDevice
    case connecting(String)
    case connected
    case unsupported(name: String)
    case failed(String)
}

/// Owns the connection to the headphones and exposes their state to SwiftUI. Setters update the
/// state optimistically, send the model's packets and resynchronise from the device on failure.
@MainActor
@Observable
final class DeviceController: NSObject {
    private(set) var status: ConnectionStatus = .idle
    private(set) var state: DeviceState?
    private(set) var profile: DeviceProfile?
    private(set) var endpoint: SoundcoreEndpoint?
    private(set) var pairedDevices: [PairedDevice] = []
    private(set) var dualConnectionDevices: [DualConnectionDevice] = []
    private(set) var isLoadingDualConnections = false
    var lastError: String?

    var preferredAddress: String? {
        didSet { UserDefaults.standard.set(preferredAddress, forKey: "preferredAddress") }
    }

    let customProfiles = CustomEqualizerStore()
    let batteryMonitor = BatteryMonitor()
    @ObservationIgnored private let widget = WidgetBridge()

    @ObservationIgnored private var connection: RFCOMMConnection?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var pendingEqualizer: (UInt16, [Int16])?
    @ObservationIgnored private var equalizerInFlight = false
    @ObservationIgnored private var isPreview = false

    override init() {
        preferredAddress = UserDefaults.standard.string(forKey: "preferredAddress")
        #if DEBUG
        isPreview = ProcessInfo.processInfo.environment["SOUNDCORE_SNAPSHOT"] != nil
        #endif
        super.init()
    }

    var deviceName: String { endpoint?.name ?? state?.model.displayName ?? "Soundcore" }

    #if DEBUG
    /// Populates the controller without Bluetooth, for offscreen snapshot rendering.
    func loadPreview(state: DeviceState, endpoint: SoundcoreEndpoint) {
        isPreview = true
        self.profile = DeviceProfile.profile(for: state.model)
        self.state = state
        self.endpoint = endpoint
        pairedDevices = [PairedDevice(address: endpoint.address, name: endpoint.name, isConnected: true, endpoint: endpoint),
                         PairedDevice(address: "00-00-00-00-00-01", name: "soundcore R60i NC", isConnected: false, endpoint: nil),
                         PairedDevice(address: "ac-12-2f-00-11-22", name: "soundcore Liberty 4 NC", isConnected: false, endpoint: nil)]
        status = .connected
    }
    #endif

    // MARK: - Lifecycle

    func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceDidConnect(_:device:)))
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconnect(after: 3) }
        }
        observers.append(wake)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        connect()
    }

    func connect(to address: String? = nil) {
        if let address, address != endpoint?.address {
            preferredAddress = address
            teardown()
        }
        connectTask?.cancel()
        connectTask = Task { await self.connectNow(explicit: address != nil) }
    }

    func disconnect() {
        connectTask?.cancel()
        teardown()
        status = .idle
        publishWidget()
    }

    func reloadPairedDevices() {
        guard !isPreview else { return }
        pairedDevices = DeviceDiscovery.pairedDevices()
    }

    private func connectNow(explicit: Bool) async {
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            status = .bluetoothOff
            publishWidget()
            return
        }
        reloadPairedDevices()

        // The preferred device if it is connected (or the user just picked it), else any connected one.
        let candidate = pairedDevices.first { $0.address == preferredAddress && ($0.isConnected || explicit) }
            ?? pairedDevices.first { $0.isConnected }
        guard let candidate, let device = IOBluetoothDevice(addressString: candidate.address) else {
            if connection == nil { status = .noDevice }
            publishWidget()
            return
        }
        if connection?.isOpen == true, endpoint?.address == candidate.address { return }
        teardown()
        status = .connecting(candidate.name)

        if !device.isConnected() {
            // Page the device; SDP and RFCOMM need a baseband link.
            _ = await BasebandConnector.open(device)
            guard !Task.isCancelled else { return }
        }
        guard let target = await DeviceDiscovery.endpoint(for: device) else {
            status = device.isConnected() ? .unsupported(name: candidate.name) : .failed("\(candidate.name) is not in range.")
            return
        }
        endpoint = target
        reloadPairedDevices()

        let conn = RFCOMMConnection(device: device, channelID: target.channelID)
        conn.onPacket = { [weak self] in self?.handle($0) }
        conn.onClose = { [weak self] in self?.connectionClosed() }
        connection = conn
        do {
            try await conn.open()
            let response = try await conn.request(Commands.requestState())
            guard !Task.isCancelled else { return }
            guard let (profile, parsed) = resolveProfile(for: target, body: response.body) else {
                status = .unsupported(name: target.name)
                return
            }
            var state = parsed
            if profile.requestsLdac, let ldac = try? await conn.request(Commands.requestLdacState()), let on = ldac.body.first {
                state.flags[.ldac] = on != 0
            }
            self.profile = profile
            self.state = state
            status = .connected
            lastError = nil
            disconnectNotification = device.register(
                forDisconnectNotification: self, selector: #selector(deviceDidDisconnect(_:device:)))
            batteryMonitor.update(state: state, deviceName: target.name)
            publishWidget()
            if state.dualConnections == true, profile.hasDualConnections { refreshDualConnections() }
        } catch {
            guard !Task.isCancelled else { return }
            teardown()
            status = .failed(error.localizedDescription)
            scheduleReconnect(after: 5)
        }
    }

    /// Override > name/UUID guess > trying every known layout.
    private func resolveProfile(for endpoint: SoundcoreEndpoint, body: [UInt8]) -> (DeviceProfile, DeviceState)? {
        let hint = modelOverride(for: endpoint.address) ?? DeviceModel.guess(name: endpoint.name, serviceCode: endpoint.modelCode)
        if let hint {
            let p = DeviceProfile.profile(for: hint)
            if let s = try? p.parse(body) { return (p, s) }
        }
        guard let p = DeviceProfile.detect(stateBody: body, preferred: hint), let s = try? p.parse(body) else { return nil }
        return (p, s)
    }

    func modelOverride(for address: String) -> DeviceModel? {
        UserDefaults.standard.string(forKey: "model.\(address)").flatMap(DeviceModel.init(rawValue:))
    }

    func setModelOverride(_ model: DeviceModel?) {
        guard let address = endpoint?.address ?? preferredAddress else { return }
        UserDefaults.standard.set(model?.rawValue, forKey: "model.\(address)")
        teardown()
        connect(to: address)
    }

    private func teardown() {
        disconnectNotification?.unregister()
        disconnectNotification = nil
        connection?.onClose = nil
        connection?.close()
        connection = nil
        state = nil
        profile = nil
        dualConnectionDevices = []
        pendingEqualizer = nil
        equalizerInFlight = false
    }

    private func connectionClosed() {
        connection = nil
        state = nil
        status = .noDevice
        publishWidget()
        scheduleReconnect(after: 2)
    }

    private func scheduleReconnect(after seconds: Double) {
        connectTask?.cancel()
        connectTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self.connectNow(explicit: false)
        }
    }

    @objc private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        reloadPairedDevices()
        guard status != .connected else { return }
        scheduleReconnect(after: 2)
    }

    @objc private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.addressString == endpoint?.address else { return }
        teardown()
        status = .noDevice
        reloadPairedDevices()
        publishWidget()
        // Another Soundcore device may still be connected.
        scheduleReconnect(after: 1)
    }

    // MARK: - Inbound

    private func handle(_ packet: Packet) {
        guard var s = state, let profile else { return }
        if s.apply(packet, profile: profile) {
            state = s
            batteryMonitor.update(state: s, deviceName: deviceName)
            publishWidget()
        }
    }

    func refresh() {
        guard let connection, let profile, status == .connected else {
            if status != .connected { connect() }
            return
        }
        Task {
            if let response = try? await connection.request(Commands.requestState()),
               var fresh = try? profile.parse(response.body) {
                if profile.requestsLdac { fresh.flags[.ldac] = state?.flags[.ldac] }
                state = fresh
                publishWidget()
            }
        }
    }

    private func publishWidget() {
        widget.publish(state: status == .connected ? state : nil, profile: profile, name: deviceName,
                       equalizerName: state.flatMap(equalizerName))
    }

    func equalizerName(_ s: DeviceState) -> String? {
        guard let eq = s.equalizer else { return nil }
        if eq.isCustom {
            return customProfiles.profiles.first { $0.bands == eq.visible }?.name ?? "Custom"
        }
        return profile?.equalizer?.presets.first { $0.id == eq.presetID }?.name ?? "Preset"
    }

    // MARK: - Sending

    /// Applies `mutate` immediately and sends `packets` in order.
    private func send(_ packets: [Packet], refreshAfter: Bool = false, _ mutate: (inout DeviceState) -> Void) {
        guard var s = state, let connection, !packets.isEmpty else { return }
        mutate(&s)
        state = s
        publishWidget()
        Task {
            do {
                for packet in packets { try await connection.request(packet) }
                if refreshAfter { refresh() }
            } catch {
                lastError = error.localizedDescription
                refresh()
            }
        }
    }

    // MARK: Sound modes

    func updateSoundModes(_ change: (inout SoundModes) -> Void) {
        guard let current = state?.soundModes, let spec = profile?.soundModes else { return }
        var target = current
        change(&target)
        send(spec.packets(from: current, to: target)) { $0.soundModes = target }
    }

    func setAmbient(_ mode: AmbientSoundMode) { updateSoundModes { $0.ambient = mode } }

    func cycleAmbient() {
        guard let current = state?.soundModes?.ambient, let modes = profile?.soundModes?.ambientModes,
              let i = modes.firstIndex(of: current) else { return }
        setAmbient(modes[(i + 1) % modes.count])
    }

    func setSoundModeCycle(_ cycle: AmbientSoundModeCycle) {
        guard cycle.byte != 0 else { return }
        send([Commands.soundModeCycle(cycle)]) { $0.soundModeCycle = cycle }
    }

    // MARK: Equalizer

    func selectPreset(_ preset: EqualizerPreset) {
        guard let spec = profile?.equalizer else { return }
        applyEqualizer(presetID: preset.id, bands: spec.bands(for: preset))
    }

    func setCustomBands(_ visible: [Int16]) {
        guard let spec = profile?.equalizer, let id = spec.customPresetID else { return }
        applyEqualizer(presetID: id, bands: spec.customBands(visible))
    }

    /// Coalesces rapid slider updates: at most one EQ packet in flight, latest value wins.
    private func applyEqualizer(presetID: UInt16, bands: [Int16]) {
        guard var eq = state?.equalizer, let spec = profile?.equalizer else { return }
        eq.presetID = presetID
        eq.channels = Array(repeating: bands, count: spec.channels)
        state?.equalizer = eq
        if state?.spatialAudio != nil { state?.spatialAudio?.isEnabled = false }
        pendingEqualizer = (presetID, bands)
        publishWidget()
        pumpEqualizer()
    }

    private func pumpEqualizer() {
        guard !equalizerInFlight, let (presetID, bands) = pendingEqualizer, let connection,
              let spec = profile?.equalizer, let eq = state?.equalizer else { return }
        pendingEqualizer = nil
        equalizerInFlight = true
        Task {
            do {
                try await connection.request(spec.packet(presetID: presetID, bands: bands, state: eq))
            } catch {
                lastError = error.localizedDescription
                pendingEqualizer = nil
                refresh()
            }
            equalizerInFlight = false
            pumpEqualizer()
        }
    }

    // MARK: Spatial audio (R60i NC)

    func setSpatialAudio(enabled: Bool) {
        guard let s = state, var spatial = s.spatialAudio, let spec = profile?.equalizer, let eq = s.equalizer else { return }
        if enabled {
            spatial.isEnabled = true
            send([Commands.spatialAudio(spatial)]) { $0.spatialAudio = spatial }
        } else {
            // The Soundcore app turns spatial audio off by re-sending the equalizer.
            var bands = eq.primary
            if bands.count >= 10 {
                bands[8] = 0
                bands[9] = Volume.min
            }
            send([spec.packet(presetID: eq.presetID, bands: bands, state: eq)]) { $0.spatialAudio?.isEnabled = false }
        }
    }

    func setSpatialMode(_ mode: SpatialAudioMode) {
        guard var spatial = state?.spatialAudio, spatial.isEnabled else { return }
        spatial.mode = mode
        send([Commands.spatialAudio(spatial)]) { $0.spatialAudio = spatial }
    }

    // MARK: Buttons

    func buttonAction(_ key: ButtonKey) -> ButtonAction? {
        guard let s = state, let spec = profile?.buttons, let buttons = s.buttons else { return nil }
        return buttons.action(key, spec: spec, tws: s.tws ?? TwsStatus())
    }

    func setButton(_ key: ButtonKey, action: ButtonAction?) {
        guard let s = state, let spec = profile?.buttons, let buttons = s.buttons else { return }
        let next = buttons.setting(key, to: action, spec: spec, tws: s.tws ?? TwsStatus())
        send(buttons.packets(to: next, spec: spec)) { $0.buttons = next }
    }

    func setBassUpButton(_ on: Bool) {
        send([Commands.bassUpButton(on)]) { $0.bassUpButton = on }
    }

    func resetButtons() {
        send([Packet(Commands.resetButtons)], refreshAfter: true) { _ in }
    }

    // MARK: Device settings

    func setFlag(_ flag: DeviceFlag, _ on: Bool) {
        guard let command = profile?.flagCommands[flag] else { return }
        send([Commands.flag(command, on)], refreshAfter: flag == .ldac) { $0.flags[flag] = on }
    }

    func setDualConnections(_ on: Bool) {
        send([Commands.flag(Commands.setDualConnections, on)], refreshAfter: true) { $0.dualConnections = on }
        if on {
            Task {
                try? await Task.sleep(for: .seconds(1))
                refreshDualConnections()
            }
        } else {
            dualConnectionDevices = []
        }
    }

    func setAutoPowerOff(_ value: AutoPowerOff) {
        send([Commands.autoPowerOff(value)]) { $0.autoPowerOff = value }
    }

    func setLimitHighVolume(enabled: Bool, dbLimit: UInt8) {
        guard var v = state?.limitHighVolume else { return }
        v.isEnabled = enabled
        v.dbLimit = dbLimit
        send([Commands.limitHighVolume(v)]) { $0.limitHighVolume = v }
    }

    func setLimitHighVolumeRefreshRate(_ rate: DecibelRefreshRate) {
        send([Commands.limitHighVolumeRefreshRate(rate)]) { $0.limitHighVolume?.refreshRate = rate }
    }

    // MARK: Multipoint

    func refreshDualConnections() {
        guard let connection, status == .connected else { return }
        isLoadingDualConnections = true
        Task {
            defer { isLoadingDualConnections = false }
            do {
                let pages = try await connection.requestMany(Commands.requestDualConnectionDevices()) { packet in
                    guard let page = DualConnectionDevice.parsePage(packet.body) else { return true }
                    return page.index >= page.total
                }
                dualConnectionDevices = pages.compactMap { DualConnectionDevice.parsePage($0.body)?.devices }.flatMap { $0 }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setDualConnection(_ device: DualConnectionDevice, connected: Bool) {
        guard let connection else { return }
        Task {
            do {
                try await connection.request(Commands.dualConnection(connect: connected, mac: device.macAddress))
                try? await Task.sleep(for: .seconds(2))
                refreshDualConnections()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
