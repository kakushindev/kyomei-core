import Testing
@testable import SoundcoreKit

/// Raw `01 01` response captured from a real soundcore R60i NC (D1202C, firmware 03.89). The
/// serial number (which embeds the Bluetooth address) is zeroed and the checksum recomputed.
let capturedR60iState: [UInt8] = hex("""
    09 ff 00 00 01 01 01 a2 00 01 01 09 09 00 00 30 33 2e 38 39 30 33 2e 38 39 31 32 30 32 30 30 30 30 30 30 30 30 30 30 30
    30 30 33 2e 38 39 03 01 00 a0 82 8c 8c a0 a0 a0 8c 78 00 ff ff ff ff ff ff ff ff ff ff ff 00 ff ff ff ff ff ff ff ff ff
    00 ff ff ff ff ff ff ff ff ff 00 00 00 00 00 00 ff ff ff ff ff ff ff ff ff 00 ff ff ff ff ff ff ff ff ff 00 00 00 0a ff
    ff 63 66 ff ff 44 44 33 01 50 00 00 00 00 00 00 31 01 01 00 01 01 02 00 5a 00 00 00 01 00 00 00 00 00 00 00 ff ff ff ff
    ff 27
    """)

func hex(_ s: String) -> [UInt8] {
    s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { UInt8($0, radix: 16)! }
}

// MARK: - Framing

@Test func requestStateFrame() {
    #expect(Commands.requestState().encoded() == [0x08, 0xEE, 0x00, 0x00, 0x00, 0x01, 0x01, 0x0A, 0x00, 0x02])
}

@Test func parserReassemblesSplitAndNoisyStream() {
    var parser = PacketStreamParser()
    let frame = capturedR60iState
    #expect(parser.feed([0x00, 0x13] + Array(frame[0..<40])).isEmpty)
    let packets = parser.feed(Array(frame[40...]) + Packet(Commands.batteryLevelUpdate, [5, 6]).encoded(.inbound))
    #expect(packets.count == 2)
    #expect(packets[0].command == Commands.state)
    #expect(packets[1].body == [5, 6])
}

@Test func parserSkipsCorruptFrame() {
    var parser = PacketStreamParser()
    var bad = Packet(Commands.batteryLevelUpdate, [1, 2]).encoded(.inbound)
    bad[bad.count - 1] &+= 1
    let good = Packet(Commands.batteryLevelUpdate, [3, 4]).encoded(.inbound)
    #expect(parser.feed(bad + good) == [Packet(Commands.batteryLevelUpdate, [3, 4])])
}

// MARK: - OpenSCQ30 style descriptions

/// Renders a state value the way OpenSCQ30's settings API names it, so fixture expectations can be
/// compared directly. Returns nil for settings this app does not model.
func describe(_ id: String, _ s: DeviceState, _ p: DeviceProfile) -> String? {
    func flag(_ f: DeviceFlag) -> String? { s.flags[f].map { "\($0)" } }
    func battery(_ b: Battery?) -> String? { b.map { "\($0.level)/\($0.scale.max)" } }
    func press(_ side: ButtonSide, _ kind: PressKind) -> String? {
        guard let spec = p.buttons, let state = s.buttons, let tws = s.tws else { return nil }
        guard let a = state.action(ButtonKey(side, kind), spec: spec, tws: tws) else { return "None" }
        return actionName(a)
    }
    let m = s.soundModes
    switch id {
    case "BatteryLevelLeft": return battery(s.left)
    case "BatteryLevelRight": return battery(s.right)
    case "BatteryLevel": return "\(s.left.level)"
    case "CaseBatteryLevel": return battery(s.caseBattery)
    case "IsChargingLeft": return s.left.isCharging ? "Yes" : "No"
    case "IsChargingRight": return s.right.map { $0.isCharging ? "Yes" : "No" }
    case "FirmwareVersionLeft": return s.firmwareLeft
    case "FirmwareVersionRight": return s.firmwareRight
    case "SerialNumber": return s.serialNumber
    case "AmbientSoundMode": return m.map { ["NoiseCanceling", "Transparency", "Normal"][Int($0.ambient.rawValue)] }
    case "NoiseCancelingMode":
        guard let m else { return nil }
        if p.model == .a3035 { return m.noiseCanceling == .manual ? "Custom" : "Adaptive" }
        return ["transport": "Transport", "outdoor": "Outdoor", "indoor": "Indoor", "custom": "Custom",
                "adaptive": "Adaptive", "manual": "Manual", "multiScene": "MultiScene",
                "transportation": "Transportation"][m.noiseCanceling.rawValue]
    case "ManualNoiseCanceling": return m.map { "\($0.manualLevel)" }
    case "AdaptiveNoiseCanceling":
        guard let m, let style = p.soundModes?.adaptiveLevel else { return nil }
        switch style {
        case .numeric(let range): return "\(m.adaptiveLevel)/\(range.upperBound)"
        case .named(let names):
            let i = names.firstIndex { $0.0 == m.adaptiveLevel } ?? 0
            return ["Weak", "Moderate", "Strong"][i]
        }
    case "MultiSceneNoiseCanceling": return m.map { ["Transport", "Outdoor", "Indoor"][Int($0.multiScene.rawValue)] }
    case "WindNoiseSuppression": return m.map { "\($0.windNoiseSuppression)" }
    case "RealTimeAdaptiveNoiseCanceling": return m.map { "\($0.realTimeAdaptive)" }
    case "EnvironmentDetection": return m.map { "\($0.environmentDetection)" }
    case "TransportationMode": return m.map { ["Plane", "Train", "Bus", "Car"][Int($0.transportation.rawValue)] }
    case "TransparencyMode":
        return m.map { ["fullyTransparent": "FullyTransparent", "vocal": "VocalMode", "talk": "TalkMode", "manual": "Manual"][$0.transparency.rawValue]! }
    case "ManualTransparency": return m.map { "\($0.manualTransparencyLevel)" }
    case "NoiseCancelingModeInCycle": return s.soundModeCycle.map { "\($0.noiseCanceling)" }
    case "TransparencyModeInCycle": return s.soundModeCycle.map { "\($0.transparency)" }
    case "NormalModeInCycle": return s.soundModeCycle.map { "\($0.normal)" }
    case "LimitHighVolume": return s.limitHighVolume.map { "\($0.isEnabled)" }
    case "LimitHighVolumeDbLimit": return s.limitHighVolume.map { "\($0.dbLimit)" }
    case "LimitHighVolumeRefreshRate": return s.limitHighVolume.map { ["RealTime", "10s", "1m"][Int($0.refreshRate.rawValue)] }
    case "AutoPowerOff":
        guard let a = s.autoPowerOff, let minutes = p.autoPowerOffMinutes else { return nil }
        return a.isEnabled ? "\(minutes[Int(a.durationIndex)])m" : "Disabled"
    case "DualConnections": return s.dualConnections.map { "\($0)" }
    case "SpatialAudio": return s.spatialAudio.map { "\($0.isEnabled)" }
    case "SpatialAudioMode": return s.spatialAudio.map { ["Music", "", "Movie", "Gaming"][Int($0.mode.rawValue)] }
    case "DoublePress": return s.bassUpButton.map { $0 ? "BassUp" : "None" }
    case "PresetEqualizerProfile":
        guard let eq = s.equalizer, let preset = p.equalizer?.presets.first(where: { $0.id == eq.presetID }) else { return "None" }
        return preset.name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "R&B", with: "RnB")
    case "VolumeAdjustments": return s.equalizer.map { "\($0.visible.map(Int.init))" }
    case "TouchTone": return flag(.touchTone)
    case "GamingMode": return flag(.gamingMode)
    case "SurroundSound": return flag(.surroundSound)
    case "SoundLeakCompensation": return flag(.soundLeakCompensation)
    case "WearingDetection": return flag(.wearingDetection)
    case "WearingTone": return flag(.wearingTone)
    case "AutoPlayPause": return flag(.autoPlayPause)
    case "TouchLock": return flag(.touchLock)
    case "Ldac": return flag(.ldac)
    case "LowBatteryPrompt": return flag(p.model == .a3035 ? .batteryAlert : .lowBatteryPrompt)
    case "VoicePrompt": return flag(p.model == .a3035 ? .ambientSoundModeVoicePrompt : .voicePrompt)
    case "LeftSinglePress": return press(.left, .single)
    case "LeftDoublePress": return press(.left, .double)
    case "LeftTriplePress": return press(.left, .triple)
    case "LeftLongPress": return press(.left, .long)
    case "RightSinglePress": return press(.right, .single)
    case "RightDoublePress": return press(.right, .double)
    case "RightTriplePress": return press(.right, .triple)
    case "RightLongPress": return press(.right, .long)
    default: return nil
    }
}

func actionName(_ a: ButtonAction) -> String {
    switch a {
    case .volumeUp: "VolumeUp"
    case .volumeDown: "VolumeDown"
    case .previousSong: "PreviousSong"
    case .nextSong: "NextSong"
    case .ambientSoundMode: "AmbientSoundMode"
    case .voiceAssistant: "VoiceAssistant"
    case .playPause: "PlayPause"
    case .bassUp: "BassUp"
    case .gamingMode: "GamingMode"
    }
}

/// `"2/5".into()` -> `2/5`, `Some("X").into()` -> `X`, `Value::OptionalString(None)` -> `None`.
func expectedValue(_ raw: String) -> String {
    var v = raw
    if v.hasSuffix(".into()") { v.removeLast(7) }
    if v.hasPrefix("Value::OptionalString(None)") { return "None" }
    if v.hasPrefix("Value::I16Vec(vec!") { return "[" + v.drop(while: { $0 != "[" }).dropFirst().prefix { $0 != "]" } + "]" }
    if v.hasPrefix("Some(") { v = String(v.dropFirst(5).dropLast()) }
    if v.hasPrefix("\"") { v = String(v.dropFirst().dropLast()) }
    return v
}

func checkFixture(_ f: Fixture, _ model: DeviceModel) throws -> DeviceState {
    let profile = DeviceProfile.profile(for: model)
    let state = try profile.parse(f.state)
    for (id, raw) in f.expect {
        guard let actual = describe(id, state, profile) else { continue }
        #expect(actual == expectedValue(raw), "\(model.rawValue) \(id)")
    }
    return state
}

func outbound(_ f: Fixture) -> [Packet] { f.outbound.map { Packet(Command($0.command[0], $0.command[1]), $0.body) } }

// MARK: - State parsing against OpenSCQ30 fixtures

@Test(arguments: [
    (DeviceModel.a3947, "test_with_known_good_packet"),
    (.a3957, "test_with_liberty5_packet_from_issue_226"),
    (.a3955, "test_with_packet_from_firmware_1_6_1"),
    (.a3955, "state_update_packet_from_github_issue_241"),
    (.a3040, "test_with_known_good_packet"),
    (.a3035, "test_with_known_good_packet"),
    (.a3949, "example_packet_matches_soundcore_app"),
    (.a3949, "p20i_packet_matches_soundcore_app"),
    (.a3949, "r50i_matches_soundcore_app"),
    (.a3949, "p25i_matches_soundcore_app"),
    (.a3959, "test_with_packet_from_github_issue_149"),
    (.a3959, "test_with_packet_from_github_issue_149_modified_to_disable_tws"),
    (.a3959, "test_with_other_packet_from_github_issue_149"),
    (.d1202, "settings_match_soundcore_app"),
])
func parsesReferenceState(model: DeviceModel, name: String) throws {
    let all: [DeviceModel: [String: Fixture]] = [
        .a3947: Fixtures.a3947, .a3957: Fixtures.a3957, .a3955: Fixtures.a3955, .a3040: Fixtures.a3040,
        .a3035: Fixtures.a3035, .a3949: Fixtures.a3949, .a3959: Fixtures.a3959, .d1202: Fixtures.d1202,
    ]
    let fixture = try #require(all[model]?[name])
    _ = try checkFixture(fixture, model)
}

@Test func a3959GamingModeNeedsFirmware160() throws {
    let s = try DeviceProfile.profile(for: .a3959).parse(Fixtures.a3959["has_no_gaming_mode_on_old_firmware"]!.state)
    #expect(s.flags[.gamingMode] == nil)
}

@Test func decodesRealR60iState() throws {
    var parser = PacketStreamParser()
    let packet = try #require(parser.feed(capturedR60iState).first)
    let p = DeviceProfile.profile(for: .d1202)
    let s = try p.parse(packet.body)
    #expect(s.tws == TwsStatus(host: .right, isConnected: true))
    #expect(s.left.percent == 100 && s.right?.percent == 100)
    #expect(s.firmwareLeft == "03.89" && s.serialNumber == "1202000000000000")
    #expect(s.caseBattery?.percent == 40)
    #expect(s.equalizer?.presetID == 1)
    #expect(s.equalizer?.primary == EqualizerPresets.type2[1].bands)
    #expect(s.soundModes?.ambient == .transparency)
    #expect(describe("LeftDoublePress", s, p) == "NextSong")
    #expect(s.flags[.touchTone] == true && s.flags[.ldac] == false && s.dualConnections == true)
}

@Test func detectsModelsByName() {
    #expect(DeviceModel.guess(name: "soundcore R60i NC") == .d1202)
    #expect(DeviceModel.guess(name: "soundcore R50i NC") == .a3959)
    #expect(DeviceModel.guess(name: "soundcore R50i") == .a3949)
    #expect(DeviceModel.guess(name: "Soundcore Liberty 4 NC") == .a3947)
    #expect(DeviceModel.guess(name: "soundcore Space One") == .a3035)
    #expect(DeviceModel.guess(name: "soundcore Space One Pro") == nil)
    #expect(DeviceModel.guess(name: "Soundcore Life Q30") == .a3028)
}

@Test func detectsModelByTrialParse() throws {
    let body = Fixtures.a3949["r50i_matches_soundcore_app"]!.state
    #expect(DeviceProfile.detect(stateBody: body, preferred: .a3949)?.model == .a3949)
}

// MARK: - Outbound packets against OpenSCQ30 fixtures

func state(_ f: Fixture, _ model: DeviceModel) throws -> (DeviceState, DeviceProfile) {
    let p = DeviceProfile.profile(for: model)
    return (try p.parse(f.state), p)
}

@Test func a3947SoundModeNormal() throws {
    let f = Fixtures.a3947["test_set_sound_mode_normal"]!
    let (s, p) = try state(f, .a3947)
    var target = s.soundModes!
    target.ambient = .normal
    #expect(p.soundModes!.packets(from: s.soundModes!, to: target) == outbound(f))
}

@Test(arguments: [
    ("set_gaming_mode", DeviceFlag.gamingMode, true),
    ("set_sound_leak_compensation", .soundLeakCompensation, false),
    ("set_surround_sound", .surroundSound, true),
    ("set_wearing_tone", .wearingTone, true),
    ("set_auto_play_pause", .autoPlayPause, true),
    ("set_touch_lock", .touchLock, false),
    ("set_low_battery_prompt", .lowBatteryPrompt, false),
])
func a3947Flags(name: String, flag: DeviceFlag, value: Bool) throws {
    let p = DeviceProfile.profile(for: .a3947)
    #expect([Commands.flag(p.flagCommands[flag]!, value)] == outbound(Fixtures.a3947[name]!))
}

@Test func a3957GamingModeCommand() {
    let p = DeviceProfile.profile(for: .a3957)
    #expect([Commands.flag(p.flagCommands[.gamingMode]!, true)] == outbound(Fixtures.a3957["gaming_mode_uses_correct_command"]!))
}

@Test(arguments: [
    ("set_equalizer_with_hear_id_uninitialized_byte_set", [Int16](arrayLiteral: 60, -60, 60, -60, 60, -60, 60, -60)),
    ("set_equalizer_with_hear_id_initialized", [Int16](repeating: -60, count: 8)),
])
func a3955CustomEqualizer(name: String, bands: [Int16]) throws {
    let f = Fixtures.a3955[name]!
    let (s, p) = try state(f, .a3955)
    let eq = p.equalizer!
    #expect([eq.packet(presetID: EqualizerState.customPresetID, bands: eq.customBands(bands), state: s.equalizer!)] == outbound(f))
}

@Test func a3040Packets() throws {
    var f = Fixtures.a3040["set_ambient_sound_mode"]!
    var (s, p) = try state(f, .a3040)
    var target = s.soundModes!
    target.ambient = .normal
    #expect(p.soundModes!.packets(from: s.soundModes!, to: target) == outbound(f))

    f = Fixtures.a3040["set_equalizer_soundcore_signature"]!
    (s, p) = try state(f, .a3040)
    let eq = p.equalizer!
    #expect([eq.packet(presetID: 0, bands: eq.bands(for: eq.presets[0]), state: s.equalizer!)] == outbound(f))

    f = Fixtures.a3040["set_equalizer_custom"]!
    (s, p) = try state(f, .a3040)
    #expect([eq.packet(presetID: EqualizerState.customPresetID, bands: eq.customBands([60, 0, 0, 0, 0, 0, 0, -60]), state: s.equalizer!)] == outbound(f))
}

@Test func a3035Packets() throws {
    var f = Fixtures.a3035["set_preset_eq"]!
    var (s, p) = try state(f, .a3035)
    let eq = p.equalizer!
    let acoustic = eq.presets.first { $0.name == "Acoustic" }!
    #expect([eq.packet(presetID: acoustic.id, bands: eq.bands(for: acoustic), state: s.equalizer!)] == outbound(f))

    f = Fixtures.a3035["set_custom_eq"]!
    (s, p) = try state(f, .a3035)
    #expect([eq.packet(presetID: EqualizerState.customPresetID, bands: eq.customBands([-60, 0, 0, 0, 0, 0, 0, 60]), state: s.equalizer!)] == outbound(f))

    f = Fixtures.a3035["set_custom_transparency"]!
    (s, p) = try state(f, .a3035)
    var target = s.soundModes!
    target.manualTransparencyLevel = 3
    #expect(p.soundModes!.packets(from: s.soundModes!, to: target) == outbound(f))
}

@Test func a3949PresetPiano() throws {
    let f = Fixtures.a3949["r50i_set_eq_matches_soundcore_app"]!
    let (s, p) = try state(f, .a3949)
    let eq = p.equalizer!
    let piano = eq.presets.first { $0.name == "Piano" }!
    #expect(!eq.allowsCustom)
    #expect([eq.packet(presetID: piano.id, bands: eq.bands(for: piano), state: s.equalizer!)] == outbound(f))
}

@Test func a3959Packets() throws {
    var f = Fixtures.a3959["set_surround_sound"]!
    var (s, p) = try state(f, .a3959)
    #expect([Commands.flag(p.flagCommands[.surroundSound]!, true)] == outbound(f))

    f = Fixtures.a3959["test_set_multiple_button_actions"]!
    (s, p) = try state(f, .a3959)
    let spec = p.buttons!
    var buttons = s.buttons!
    buttons = buttons.setting(ButtonKey(.left, .single), to: .volumeUp, spec: spec, tws: s.tws!)
    buttons = buttons.setting(ButtonKey(.right, .single), to: .volumeDown, spec: spec, tws: s.tws!)
    #expect(s.buttons!.packets(to: buttons, spec: spec) == outbound(f))

    f = Fixtures.a3959["test_disable_button"]!
    (s, p) = try state(f, .a3959)
    let disabled = s.buttons!.setting(ButtonKey(.left, .single), to: nil, spec: spec, tws: s.tws!)
    #expect(s.buttons!.packets(to: disabled, spec: spec) == outbound(f))

    f = Fixtures.a3959["set_manual_noise_canceling"]!
    (s, p) = try state(f, .a3959)
    var target = s.soundModes!
    target.manualLevel = 2
    #expect(p.soundModes!.packets(from: s.soundModes!, to: target) == outbound(f))
}

@Test func d1202Packets() throws {
    var f = Fixtures.d1202["enable_spatial_audio"]!
    var (s, p) = try state(f, .d1202)
    #expect([Commands.spatialAudio(SpatialAudio(isEnabled: true, mode: s.spatialAudio!.mode))] == outbound(f))

    f = Fixtures.d1202["set_preset_eq"]!
    (s, p) = try state(f, .d1202)
    let eq = p.equalizer!
    #expect([eq.packet(presetID: 1, bands: eq.bands(for: eq.presets[1]), state: s.equalizer!)] == outbound(f))

    f = Fixtures.d1202["disable_spatial_audio"]!
    (s, p) = try state(f, .d1202)
    var bands = s.equalizer!.primary
    bands[8] = 0
    bands[9] = Volume.min
    #expect([eq.packet(presetID: s.equalizer!.presetID, bands: bands, state: s.equalizer!)] == outbound(f))
}

// MARK: - Units

@Test func buttonDisableOneSideDisablesOther() throws {
    let p = DeviceProfile.profile(for: .a3936)
    let spec = p.buttons!
    let tws = TwsStatus()
    let state = ButtonState(statuses: Array(repeating: ButtonStatus(enabled: .tws(connected: true, disconnected: true),
                                                                    action: .tws(connected: 6, disconnected: 6)), count: 6))
    let next = state.setting(ButtonKey(.left, .double), to: nil, spec: spec, tws: tws)
    #expect(next.action(ButtonKey(.left, .double), spec: spec, tws: tws) == nil)
    #expect(next.action(ButtonKey(.right, .double), spec: spec, tws: tws) == nil)
    #expect(state.packets(to: next, spec: spec).count == 2)
}

@Test func dualConnectionPage() throws {
    let body: [UInt8] = [1, 1, 13, 1, 1, 2, 3, 4, 5, 6, 0x4D, 0x61, 0x63, 0, 0]
    let page = try #require(DualConnectionDevice.parsePage(body))
    #expect(page.total == 1 && page.index == 1)
    #expect(page.devices.first?.name == "Mac")
    #expect(page.devices.first?.macAddressString == "01:02:03:04:05:06")
}

/// Guards against the describer silently skipping expectations.
@Test func fixtureExpectationsAreActuallyCompared() throws {
    let all: [(DeviceModel, [String: Fixture])] = [
        (.a3947, Fixtures.a3947), (.a3957, Fixtures.a3957), (.a3955, Fixtures.a3955), (.a3040, Fixtures.a3040),
        (.a3035, Fixtures.a3035), (.a3949, Fixtures.a3949), (.a3959, Fixtures.a3959), (.d1202, Fixtures.d1202),
    ]
    var compared = 0, total = 0
    var skipped: Set<String> = []
    for (model, fixtures) in all {
        let p = DeviceProfile.profile(for: model)
        for f in fixtures.values where !f.expect.isEmpty {
            let s = try p.parse(f.state)
            for (id, _) in f.expect {
                total += 1
                if describe(id, s, p) != nil { compared += 1 } else { skipped.insert("\(model.rawValue).\(id)") }
            }
        }
    }
    print("compared \(compared)/\(total); skipped: \(skipped.sorted())")
    #expect(compared >= 180)
}

/// From OpenSCQ30's A3028 (Life Q30) packet tests.
@Test func lifeQ30PresetPacket() throws {
    let frame: [UInt8] = [
        0x09, 0xff, 0x00, 0x00, 0x01, 0x01, 0x01, 0x46, 0x00, 0x05, 0x00, 0x01, 0x00, 0x3c,
        0xb4, 0x8f, 0xa0, 0x8e, 0xb4, 0x74, 0x88, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x30, 0x32, 0x2e, 0x33, 0x30, 0x33, 0x30, 0x32,
        0x39, 0x30, 0x38, 0x36, 0x45, 0x43, 0x38, 0x32, 0x46, 0x31, 0x32, 0x41, 0x43, 0x35,
    ]
    var parser = PacketStreamParser()
    let packet = try #require(parser.feed(frame).first)
    let s = try DeviceProfile.profile(for: .a3028).parse(packet.body)
    #expect(s.soundModes?.ambient == .normal)
    #expect(s.soundModes?.noiseCanceling == .transport)
    #expect(s.soundModes?.transparency == .vocal)
    #expect(s.equalizer?.presetID == 1)
    #expect(s.equalizer?.primary == [-60, 60, 23, 40, 22, 60, -4, 16])
    #expect(s.firmwareLeft == "02.30")
    #expect(s.right == nil && s.left.level == 5)
    #expect(s.autoPowerOff == nil)
}

@Test func firstGenerationTransitionStepsThroughNoiseCanceling() {
    let spec = DeviceProfile.profile(for: .a3028).soundModes!
    var current = SoundModes()
    current.ambient = .normal
    current.noiseCanceling = .transport
    var target = current
    target.noiseCanceling = .indoor
    let packets = spec.packets(from: current, to: target)
    #expect(packets.map(\.body) == [[0, 0, 0, 0], [0, 2, 0, 0], [2, 2, 0, 0]])
}
