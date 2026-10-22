import Foundation

public enum DeviceModel: String, Sendable, CaseIterable, Identifiable, Codable {
    case a3004 = "A3004"
    case a3027 = "A3027"
    case a3028 = "A3028"
    case a3035 = "A3035"
    case a3040 = "A3040"
    case a3936 = "A3936"
    case a3947 = "A3947"
    case a3949 = "A3949"
    case a3955 = "A3955"
    case a3957 = "A3957"
    case a3959 = "A3959"
    case d1202 = "D1202"
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .a3004: "soundcore Q20i"
        case .a3027: "Soundcore Life Q35"
        case .a3028: "Soundcore Life Q30"
        case .a3035: "soundcore Space One"
        case .a3040: "soundcore Space Q45"
        case .a3936: "soundcore Space A40"
        case .a3947: "soundcore Liberty 4 NC"
        case .a3949: "soundcore P20i / R50i"
        case .a3955: "soundcore P40i"
        case .a3957: "soundcore Liberty 5"
        case .a3959: "soundcore P30i / R50i NC"
        case .d1202: "soundcore R60i NC / P31i"
        }
    }

    /// Over-ear headphones rather than earbuds.
    public var isHeadphones: Bool { [.a3004, .a3027, .a3028, .a3035, .a3040].contains(self) }

    /// Best guess from the Bluetooth name ("soundcore R60i NC", "Soundcore Life Q30", ...).
    public static func guess(name: String, serviceCode: String? = nil) -> DeviceModel? {
        if let code = serviceCode?.lowercased(), code.hasPrefix("1202") { return .d1202 }
        let n = name.lowercased()
        let rules: [(String, DeviceModel)] = [
            ("r60i", .d1202), ("p31i", .d1202),
            ("liberty 4 nc", .a3947), ("liberty 5", .a3957),
            ("p40i", .a3955), ("r50i nc", .a3959), ("p30i", .a3959),
            ("r50i", .a3949), ("p20i", .a3949), ("p25i", .a3949),
            ("space a40", .a3936), ("space q45", .a3040),
            ("life q35", .a3027), ("life q30", .a3028), ("q30", .a3028), ("q20i", .a3004),
        ]
        if n.contains("space one pro") { return nil }
        if n.contains("space one") { return .a3035 }
        return rules.first { n.contains($0.0) }?.1
    }
}

// MARK: - State

public struct DeviceState: Sendable, Equatable {
    public let model: DeviceModel
    public var tws: TwsStatus?
    public var left = Battery()
    /// `nil` for headphones with a single battery.
    public var right: Battery?
    public var caseBattery: Battery?
    public var firmwareLeft: String?
    public var firmwareRight: String?
    public var serialNumber: String?
    public var soundModes: SoundModes?
    public var soundModeCycle: AmbientSoundModeCycle?
    public var equalizer: EqualizerState?
    public var buttons: ButtonState?
    public var bassUpButton: Bool?
    public var flags: [DeviceFlag: Bool] = [:]
    public var dualConnections: Bool?
    public var autoPowerOff: AutoPowerOff?
    public var limitHighVolume: LimitHighVolume?
    public var spatialAudio: SpatialAudio?

    public init(model: DeviceModel) { self.model = model }

    public var firmware: String? {
        switch (firmwareLeft, firmwareRight) {
        case let (l?, r?) where l == r: l
        case let (l?, r?): "L \(l) · R \(r)"
        case let (l, r): l ?? r
        }
    }

    /// The lowest bud level, for compact displays.
    public var lowestPercent: Int { min(left.percent, right?.percent ?? left.percent) }

    /// Applies an unsolicited update. Returns false when the packet is not understood.
    @discardableResult
    public mutating func apply(_ packet: Packet, profile: DeviceProfile) -> Bool {
        do {
            var r = ByteReader(packet.body)
            switch packet.command {
            case Commands.state:
                let previous = self
                self = try profile.parse(packet.body)
                // LDAC is reported separately on some models.
                if profile.requestsLdac, flags[.ldac] == nil { flags[.ldac] = previous.flags[.ldac] }
            case Commands.soundModesUpdate:
                guard let spec = profile.soundModes else { return false }
                soundModes = try spec.decode(&r)
            case Commands.batteryLevelUpdate:
                left.rawLevel = try r.u8()
                if right != nil { right?.rawLevel = try r.u8() }
            case Commands.batteryChargingUpdate:
                left.isCharging = try r.u8() == 1
                if right != nil { right?.isCharging = try r.u8() == 1 }
            case Commands.twsStatusUpdate:
                guard tws != nil else { return false }
                tws = try TwsStatus.read(&r)
            case Commands.ldacState:
                guard profile.flagCommands[.ldac] != nil else { return false }
                flags[.ldac] = try r.bool()
            default:
                return false
            }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Profiles

public struct DeviceProfile: Sendable {
    public let model: DeviceModel
    public let soundModes: SoundModeSpec?
    public let equalizer: EqualizerSpec?
    public let buttons: ButtonSpec?
    public let hasBassUpButton: Bool
    public let flagCommands: [DeviceFlag: Command]
    /// Minutes for each auto power off index.
    public let autoPowerOffMinutes: [Int]?
    public let hasLimitHighVolume: Bool
    public let hasDualConnections: Bool
    public let hasSoundModeCycle: Bool
    public let hasSpatialAudio: Bool
    public let canResetButtons: Bool
    /// LDAC state comes from a separate `01 7F` request (Liberty 4 NC).
    public let requestsLdac: Bool
    let parser: @Sendable ([UInt8]) throws -> DeviceState

    public func parse(_ body: [UInt8]) throws -> DeviceState { try parser(body) }

    public var flags: [DeviceFlag] { DeviceFlag.allCases.filter { flagCommands[$0] != nil } }

    public static func profile(for model: DeviceModel) -> DeviceProfile { Profiles.all[model]! }

    /// Tries every profile, most likely first. Used when the name gives no hint.
    public static func detect(stateBody: [UInt8], preferred: DeviceModel?) -> DeviceProfile? {
        var order = DeviceModel.allCases
        if let preferred { order.removeAll { $0 == preferred }; order.insert(preferred, at: 0) }
        return order.lazy.map(profile(for:)).first { (try? $0.parse(stateBody)) != nil }
    }
}

private let common: [DeviceFlag: Command] = [
    .touchTone: Command(0x01, 0x83), .gamingMode: Command(0x01, 0x87), .soundLeakCompensation: Command(0x10, 0x86),
    .surroundSound: Command(0x02, 0x86), .autoPlayPause: Command(0x01, 0x81), .wearingTone: Command(0x01, 0x8C),
    .touchLock: Command(0x04, 0x86), .lowBatteryPrompt: Command(0x10, 0x82), .wearingDetection: Command(0x01, 0x81),
    .ldac: Command(0x01, 0xFF),
]

private func flags(_ list: [DeviceFlag], overrides: [DeviceFlag: Command] = [:]) -> [DeviceFlag: Command] {
    Dictionary(uniqueKeysWithValues: list.map { ($0, overrides[$0] ?? common[$0]!) })
}

private let tenToSixty = [10, 20, 30, 60]
private let halfHours = [30, 60, 90, 120]

// MARK: Parsing helpers

private extension ByteReader {
    mutating func charging() throws -> Bool { try u8() == 1 }

    mutating func dualBattery(_ scale: BatteryScale) throws -> (Battery, Battery) {
        let l = try u8(), r = try u8()
        let lc = try charging(), rc = try charging()
        return (Battery(rawLevel: l, isCharging: lc, scale: scale), Battery(rawLevel: r, isCharging: rc, scale: scale))
    }
}

private extension DeviceState {
    mutating func readDualHeader(_ r: inout ByteReader, battery scale: BatteryScale) throws {
        tws = try TwsStatus.read(&r)
        (left, right) = try r.dualBattery(scale)
        (firmwareLeft, firmwareRight) = try Firmware.readDual(&r)
        serialNumber = try Serial.read(&r)
    }
}

enum Profiles {
    static let all: [DeviceModel: DeviceProfile] = Dictionary(uniqueKeysWithValues: [
        a3004, a3027, a3028, a3035, a3040, a3936, a3947, a3949, a3955, a3957, a3959, d1202,
    ].map { ($0.model, $0) })

    // MARK: Over-ear

    static let a3004 = DeviceProfile(
        model: .a3004,
        soundModes: SoundModeSpecs.firstGeneration(noiseCancelingModes: []),
        equalizer: EqualizerSpec(channels: 1, bands: 10, presets: EqualizerPresets.common,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: false, writer: .drc),
        buttons: nil, hasBassUpButton: false, flagCommands: [:], autoPowerOffMinutes: nil,
        hasLimitHighVolume: false, hasDualConnections: false, hasSoundModeCycle: false, hasSpatialAudio: false,
        canResetButtons: false, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3004)
            s.left = Battery(rawLevel: try r.u8(), isCharging: try r.charging(), scale: BatteryScale(max: 5))
            s.firmwareLeft = try Firmware.read(&r)
            s.serialNumber = try Serial.read(&r)
            s.equalizer = try EqualizerState.read(&r, channels: 1, bands: 10)
            s.soundModes = try SoundModeSpecs.firstGeneration(noiseCancelingModes: []).decode(&r)
            return s
        })

    private static func lifeQ3x(_ model: DeviceModel) -> DeviceProfile {
        DeviceProfile(
            model: model,
            soundModes: SoundModeSpecs.firstGeneration(noiseCancelingModes: [.transport, .indoor, .outdoor]),
            equalizer: EqualizerSpec(channels: 1, bands: 8, presets: EqualizerPresets.common,
                                     customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: false, writer: .basic),
            buttons: nil, hasBassUpButton: false,
            flagCommands: model == .a3027 ? flags([.wearingDetection]) : [:],
            autoPowerOffMinutes: model == .a3028 ? halfHours : nil,
            hasLimitHighVolume: false, hasDualConnections: false, hasSoundModeCycle: false, hasSpatialAudio: false,
            canResetButtons: false, requestsLdac: false,
            parser: { body in
                var r = ByteReader(body)
                var s = DeviceState(model: model)
                s.left = Battery(rawLevel: try r.u8(), isCharging: try r.charging(), scale: BatteryScale(max: 5))
                var eq = try EqualizerState.read(&r, channels: 1, bands: 8)
                eq.gender = try r.u8()
                eq.ageRange = try r.u8()
                s.equalizer = eq
                try r.skip(1 + 2 * 8 + 4)  // basic HearID
                s.soundModes = try SoundModeSpecs.firstGeneration(noiseCancelingModes: []).decode(&r)
                s.firmwareLeft = try Firmware.read(&r)
                s.serialNumber = try Serial.read(&r)
                if model == .a3027 {
                    s.flags[.wearingDetection] = try r.bool()
                } else if r.remaining >= 7 {
                    try r.skip(3)  // unknown, touch control, dual connections
                    s.autoPowerOff = try AutoPowerOff.read(&r)
                }
                return s
            })
    }

    static let a3027 = lifeQ3x(.a3027)
    static let a3028 = lifeQ3x(.a3028)

    static let a3040 = DeviceProfile(
        model: .a3040, soundModes: SoundModeSpecs.a3040,
        equalizer: EqualizerSpec(channels: 1, bands: 10, presets: EqualizerPresets.spaceQ45,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: false, writer: .spaceQ45),
        buttons: nil, hasBassUpButton: true,
        flagCommands: flags([.ldac, .voicePrompt, .lowBatteryPrompt],
                            overrides: [.voicePrompt: Command(0x01, 0xAE), .lowBatteryPrompt: Command(0x01, 0xAF)]),
        autoPowerOffMinutes: halfHours, hasLimitHighVolume: true, hasDualConnections: true, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: false, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3040)
            s.left = Battery(rawLevel: try r.u8(), scale: BatteryScale(max: 5))
            try r.skip(1)
            s.firmwareLeft = try Firmware.read(&r)
            s.serialNumber = try Serial.read(&r)
            var eq = try EqualizerState.read(&r, channels: 1, bands: 10)
            try r.skip(10 + 2)  // DRC, unknown
            s.bassUpButton = try r.u8() == ButtonAction.bassUp.rawValue
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3040.decode(&r)
            try r.skip(6)
            s.flags[.ldac] = try r.bool()
            s.dualConnections = try r.bool()
            try r.skip(2)
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.limitHighVolume = try LimitHighVolume.read(&r)
            s.flags[.voicePrompt] = try r.bool()
            s.flags[.lowBatteryPrompt] = try r.bool()
            try r.skip(5)
            var h = HearID(channels: 2)
            h.isEnabled = try r.bool()
            h.volumeAdjustments = try (0..<2).map { _ in try Volume.readOptional(&r, bands: 10) }
            h.time = try HearID.readTime(&r)
            h.type = try r.u8()
            h.customVolumeAdjustments = try (0..<2).map { _ in try Volume.readOptional(&r, bands: 10) }
            try r.skip(10)
            h.musicGenre = try r.u16le()
            eq.hearID = h
            s.equalizer = eq
            return s
        })

    static let a3035 = DeviceProfile(
        model: .a3035, soundModes: SoundModeSpecs.a3035,
        equalizer: EqualizerSpec(channels: 1, bands: 10, presets: EqualizerPresets.spaceOne,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: false, writer: .spaceOne),
        buttons: nil, hasBassUpButton: true,
        flagCommands: flags([.autoPlayPause, .ldac, .batteryAlert, .ambientSoundModeVoicePrompt],
                            overrides: [.batteryAlert: Command(0x01, 0xAF), .ambientSoundModeVoicePrompt: Command(0x01, 0xAE)]),
        autoPowerOffMinutes: halfHours, hasLimitHighVolume: true, hasDualConnections: true, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: false, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3035)
            s.left = Battery(rawLevel: try r.u8(), scale: BatteryScale(max: 5))
            try r.skip(1)
            s.firmwareLeft = try Firmware.read(&r)
            s.serialNumber = try Serial.read(&r)
            var eq = try EqualizerState.read(&r, channels: 1, bands: 10)
            try r.skip(2)
            var h = HearID(channels: 1)
            h.isEnabled = try r.bool()
            h.volumeAdjustments = [try Volume.readOptional(&r, bands: 10)]
            h.time = try HearID.readTime(&r)
            h.type = try r.u8()
            h.customVolumeAdjustments = [try Volume.readOptional(&r, bands: 10)]
            h.musicGenre = UInt16(try r.u8())
            eq.hearID = h
            s.equalizer = eq
            try r.skip(3)
            s.bassUpButton = try r.u8() == ButtonAction.bassUp.rawValue
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3035.decode(&r)
            try r.skip(1)
            s.flags[.autoPlayPause] = try r.bool()
            try r.skip(4)
            s.flags[.ldac] = try r.bool()
            s.dualConnections = try r.bool()
            try r.skip(2)
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.limitHighVolume = try LimitHighVolume.read(&r)
            s.flags[.ambientSoundModeVoicePrompt] = try r.bool()
            s.flags[.batteryAlert] = try r.bool()
            return s
        })

    // MARK: Earbuds

    static let a3949Buttons = ButtonSpec(
        order: [.init(.left, .single), .init(.right, .single), .init(.left, .double), .init(.right, .double),
                .init(.left, .long), .init(.right, .long)],
        presses: [
            ButtonSpec.press(.single, .single, id: 2, ButtonAction.withoutSoundModes),
            ButtonSpec.press(.double, .single, id: 0, ButtonAction.withoutSoundModes),
            ButtonSpec.press(.long, .single, id: 1, ButtonAction.withoutSoundModes),
        ],
        ignoreEnabledFlag: true, supportsSetAll: false)

    static let a3949 = DeviceProfile(
        model: .a3949, soundModes: nil,
        equalizer: EqualizerSpec(channels: 1, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: nil, requiresBothEarbuds: true, writer: .drc),
        buttons: a3949Buttons, hasBassUpButton: false, flagCommands: flags([.gamingMode, .touchTone]),
        autoPowerOffMinutes: nil, hasLimitHighVolume: false, hasDualConnections: false, hasSoundModeCycle: false,
        hasSpatialAudio: false, canResetButtons: true, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3949)
            try s.readDualHeader(&r, battery: BatteryScale(max: 5))
            s.equalizer = try EqualizerState.read(&r, channels: 1, bands: 10)
            try r.skip(11)
            s.buttons = try ButtonState.read(&r, spec: a3949Buttons)
            try r.skip(4)
            s.flags[.gamingMode] = try r.bool()
            s.flags[.touchTone] = try r.bool()
            return s
        })

    static let a3959Buttons = ButtonSpec.fourPress(ignoreEnabled: true)

    static let a3959 = DeviceProfile(
        model: .a3959, soundModes: SoundModeSpecs.a3959,
        equalizer: EqualizerSpec(channels: 1, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: true, writer: .drc),
        buttons: a3959Buttons, hasBassUpButton: false,
        flagCommands: flags([.touchTone, .surroundSound, .lowBatteryPrompt, .gamingMode]),
        autoPowerOffMinutes: tenToSixty, hasLimitHighVolume: false, hasDualConnections: true, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: true, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3959)
            try s.readDualHeader(&r, battery: BatteryScale(max: 10))
            s.equalizer = try EqualizerState.read(&r, channels: 1, bands: 10)
            try r.skip(11)
            s.buttons = try ButtonState.read(&r, spec: a3959Buttons)
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3959.decode(&r)
            try r.skip(1)
            s.flags[.touchTone] = try r.bool()
            s.dualConnections = try r.bool()
            s.flags[.surroundSound] = try r.bool()
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.flags[.lowBatteryPrompt] = try r.bool()
            let gaming = try r.bool()
            try r.skip(12)
            // Gaming mode needs firmware 01.60 or newer on both buds.
            let firmware = [s.firmwareLeft, s.firmwareRight].compactMap { Firmware.number($0) }.min() ?? 0
            if firmware >= 160 { s.flags[.gamingMode] = gaming }
            return s
        })

    static let a3947Buttons = ButtonSpec.fourPress(enabled: .twsLowBits, ignoreEnabled: true, tripleBeforeLong: false)

    static let a3947 = DeviceProfile(
        model: .a3947, soundModes: SoundModeSpecs.a3947,
        equalizer: EqualizerSpec(channels: 2, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: true, writer: .liberty4NC),
        buttons: a3947Buttons, hasBassUpButton: false,
        flagCommands: flags([.ldac, .touchTone, .gamingMode, .soundLeakCompensation, .surroundSound, .autoPlayPause,
                             .wearingTone, .touchLock, .lowBatteryPrompt],
                            overrides: [.gamingMode: Command(0x10, 0x85)]),
        autoPowerOffMinutes: tenToSixty, hasLimitHighVolume: true, hasDualConnections: false, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: true, requestsLdac: true,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3947)
            try s.readDualHeader(&r, battery: BatteryScale(max: 5))
            try r.skip(5)
            var eq = try EqualizerState.read(&r, channels: 2, bands: 10)
            try r.skip(1)
            var h = HearID(channels: 2)
            h.isEnabled = try r.bool()
            h.volumeAdjustments = try (0..<2).map { _ in try Volume.readOptional(&r, bands: 10) }
            h.time = try HearID.readTime(&r)
            h.type = try r.u8()
            h.customVolumeAdjustments = try (0..<2).map { _ in try Volume.readOptional(&r, bands: 10) }
            h.musicGenre = UInt16(try r.u8())
            try r.skip(1)
            eq.hearID = h
            s.equalizer = eq
            try r.skip(1)
            s.buttons = try ButtonState.read(&r, spec: a3947Buttons)
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3947.decode(&r)
            try r.skip(6)
            s.caseBattery = Battery(rawLevel: try r.u8(), scale: BatteryScale(max: 5))
            try r.skip(1)
            s.flags[.soundLeakCompensation] = try r.bool()
            try r.skip(1)
            s.flags[.gamingMode] = try r.bool()
            s.flags[.touchTone] = try r.bool()
            try r.skip(2)
            _ = try r.bool()  // dual connections (not exposed for this model)
            s.flags[.surroundSound] = try r.bool()
            s.limitHighVolume = try LimitHighVolume.read(&r)
            s.flags[.autoPlayPause] = try r.bool()
            s.flags[.wearingTone] = try r.bool()
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.flags[.touchLock] = try r.bool()
            s.flags[.lowBatteryPrompt] = try r.bool()
            return s
        })

    static let a3957Buttons = ButtonSpec.fourPress(ignoreEnabled: false)

    static let a3957 = DeviceProfile(
        model: .a3957, soundModes: SoundModeSpecs.a3957,
        equalizer: EqualizerSpec(channels: 2, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: true, writer: .interleaved),
        buttons: a3957Buttons, hasBassUpButton: false,
        flagCommands: flags([.ldac, .touchTone, .lowBatteryPrompt, .wearingTone, .wearingDetection, .soundLeakCompensation, .gamingMode],
                            overrides: [.gamingMode: Command(0x10, 0x85)]),
        autoPowerOffMinutes: tenToSixty, hasLimitHighVolume: true, hasDualConnections: true, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: true, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3957)
            let scale = BatteryScale(max: 10, offset: 1)
            try s.readDualHeader(&r, battery: scale)
            try r.skip(5)
            s.caseBattery = Battery(rawLevel: try r.u8(), scale: scale)
            var eq = try EqualizerState.read(&r, channels: 2, bands: 10)
            eq.ageRange = try r.u8()
            eq.hearID = try HearID.readGenreAtEnd(&r, channels: 2, bands: 10)
            s.equalizer = eq
            try r.skip(1)
            s.buttons = try ButtonState.read(&r, spec: a3957Buttons)
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3957.decode(&r)
            try r.skip(1)
            s.flags[.wearingTone] = try r.bool()
            s.flags[.lowBatteryPrompt] = try r.bool()
            s.flags[.ldac] = try r.bool()
            s.dualConnections = try r.bool()
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.limitHighVolume = try LimitHighVolume.read(&r)
            try r.skip(1 + 6)  // immersive experience, unknown
            s.flags[.soundLeakCompensation] = try r.bool()
            s.flags[.wearingDetection] = try r.bool()
            s.flags[.touchTone] = try r.bool()
            s.flags[.gamingMode] = try r.bool()
            try r.skip(1 + 6)  // pressure sensitivity, unknown
            return s
        })

    static let a3955Buttons = ButtonSpec.fourPress(ignoreEnabled: false)

    static let a3955 = DeviceProfile(
        model: .a3955, soundModes: SoundModeSpecs.a3955,
        equalizer: EqualizerSpec(channels: 2, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: true, writer: .p40i),
        buttons: a3955Buttons, hasBassUpButton: false, flagCommands: flags([.touchTone, .lowBatteryPrompt]),
        autoPowerOffMinutes: tenToSixty, hasLimitHighVolume: true, hasDualConnections: true, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: true, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3955)
            try s.readDualHeader(&r, battery: BatteryScale(max: 5))
            try r.skip(5)
            s.caseBattery = Battery(rawLevel: try r.u8(), scale: BatteryScale(max: 5))
            var eq = try EqualizerState.read(&r, channels: 2, bands: 10)
            let hearIDStatus = try r.u8()
            let h = try HearID.readGenreAtEnd(&r, channels: 2, bands: 10)
            eq.isHearIDInitialized = hearIDStatus != 255
            eq.hearID = hearIDStatus == 255 ? HearID(channels: 2) : h
            s.equalizer = eq
            try r.skip(1)
            s.buttons = try ButtonState.read(&r, spec: a3955Buttons)
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3955.decode(&r)
            try r.skip(6 + 1 + 1)  // unknown, ANC personalised to ear canal, unknown
            s.flags[.touchTone] = try r.bool()
            s.dualConnections = try r.bool()
            s.limitHighVolume = try LimitHighVolume.read(&r)
            s.autoPowerOff = try AutoPowerOff.read(&r)
            try r.skip(1)
            s.flags[.lowBatteryPrompt] = try r.bool()
            return s
        })

    static let a3936Buttons = ButtonSpec(
        order: [.init(.left, .single), .init(.right, .single), .init(.left, .double), .init(.right, .double),
                .init(.left, .long), .init(.right, .long)],
        presses: [
            ButtonSpec.press(.single, .twsLowBits, id: 2, ButtonAction.minimal, .disablingOneSideDisablesOther),
            ButtonSpec.press(.double, .twsLowBits, id: 0, ButtonAction.withGamingMode, .disablingOneSideDisablesOther),
            ButtonSpec.press(.long, .twsLowBits, id: 1, ButtonAction.withGamingMode, .disablingOneSideDisablesOther),
        ],
        ignoreEnabledFlag: false, supportsSetAll: false)

    static let a3936 = DeviceProfile(
        model: .a3936, soundModes: SoundModeSpecs.a3936,
        equalizer: EqualizerSpec(channels: 2, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: true,
                                 writer: .customHearID(forceSupportsHearID: true)),
        buttons: a3936Buttons, hasBassUpButton: false, flagCommands: flags([.ldac, .touchTone, .gamingMode]),
        autoPowerOffMinutes: halfHours, hasLimitHighVolume: false, hasDualConnections: true, hasSoundModeCycle: true,
        hasSpatialAudio: false, canResetButtons: true, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .a3936)
            try s.readDualHeader(&r, battery: BatteryScale(max: 5))
            var eq = try EqualizerState.read(&r, channels: 2, bands: 10)
            eq.ageRange = try r.u8()
            eq.hearID = try HearID.readGenreAtEnd(&r, channels: 2, bands: 10)
            s.equalizer = eq
            try r.skip(1)
            s.buttons = try ButtonState.read(&r, spec: a3936Buttons)
            s.soundModeCycle = AmbientSoundModeCycle(byte: try r.u8())
            s.soundModes = try SoundModeSpecs.a3936.decode(&r)
            s.flags[.touchTone] = try r.bool()
            s.caseBattery = Battery(rawLevel: try r.u8(), scale: BatteryScale(max: 10))
            try r.skip(1)  // color
            s.flags[.ldac] = try r.bool()
            s.dualConnections = try r.bool()
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.flags[.gamingMode] = try r.bool()
            return s
        })

    static let d1202Buttons = ButtonSpec.fourPress(ignoreEnabled: false, single: ButtonAction.minimal)

    static let d1202 = DeviceProfile(
        model: .d1202, soundModes: SoundModeSpecs.d1202,
        equalizer: EqualizerSpec(channels: 2, bands: 10, presets: EqualizerPresets.type2,
                                 customPresetID: EqualizerState.customPresetID, requiresBothEarbuds: true, writer: .interleaved),
        buttons: d1202Buttons, hasBassUpButton: false, flagCommands: flags([.ldac, .touchTone, .lowBatteryPrompt]),
        autoPowerOffMinutes: tenToSixty, hasLimitHighVolume: true, hasDualConnections: true, hasSoundModeCycle: false,
        hasSpatialAudio: true, canResetButtons: true, requestsLdac: false,
        parser: { body in
            var r = ByteReader(body)
            var s = DeviceState(model: .d1202)
            let scale = BatteryScale(max: 10, offset: 1)
            try s.readDualHeader(&r, battery: scale)
            try r.skip(5)
            s.caseBattery = Battery(rawLevel: try r.u8(), scale: scale)
            var eq = try EqualizerState.read(&r, channels: 2, bands: 10)
            try r.skip(1)
            eq.hearID = try HearID.readGenreAtEnd(&r, channels: 2, bands: 10)
            s.equalizer = eq
            try r.skip(1)
            s.buttons = try ButtonState.read(&r, spec: d1202Buttons)
            try r.skip(1)
            s.soundModes = try SoundModeSpecs.d1202.decode(&r)
            try r.skip(1)
            s.flags[.touchTone] = try r.bool()
            s.flags[.lowBatteryPrompt] = try r.bool()
            s.flags[.ldac] = try r.bool()
            s.dualConnections = try r.bool()
            s.autoPowerOff = try AutoPowerOff.read(&r)
            s.limitHighVolume = try LimitHighVolume.read(&r)
            s.spatialAudio = SpatialAudio(isEnabled: try r.bool(), mode: SpatialAudioMode(rawValue: try r.u8()) ?? .music)
            return s
        })
}
