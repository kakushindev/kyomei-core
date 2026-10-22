import Foundation

// Building blocks shared by every model's state packet. Layouts follow OpenSCQ30's
// `common::structures` module.

// MARK: - Battery

public struct BatteryScale: Sendable, Equatable {
    public var max: UInt8
    public var offset: UInt8
    public init(max: UInt8, offset: UInt8 = 0) {
        self.max = max
        self.offset = offset
    }
}

public struct Battery: Sendable, Equatable {
    public var rawLevel: UInt8
    public var isCharging: Bool
    public var scale: BatteryScale

    public init(rawLevel: UInt8 = 0, isCharging: Bool = false, scale: BatteryScale = BatteryScale(max: 5)) {
        self.rawLevel = rawLevel
        self.isCharging = isCharging
        self.scale = scale
    }

    /// Level as the Soundcore app shows it, e.g. 4 of 5.
    public var level: Int { min(Int(scale.max), Int(rawLevel) + Int(scale.offset)) }

    public var percent: Int { scale.max == 0 ? 0 : level * 100 / Int(scale.max) }
}

public enum HostSide: UInt8, Sendable {
    case left = 0
    case right = 1
}

public struct TwsStatus: Sendable, Equatable {
    public var host: HostSide
    public var isConnected: Bool
    public init(host: HostSide = .left, isConnected: Bool = true) {
        self.host = host
        self.isConnected = isConnected
    }

    static func read(_ r: inout ByteReader) throws -> TwsStatus {
        TwsStatus(host: HostSide(rawValue: try r.u8()) ?? .left, isConnected: try r.bool())
    }
}

// MARK: - Firmware / serial

enum Firmware {
    /// "03.89". Throws on anything else, which is what makes trial parsing reliable.
    static func read(_ r: inout ByteReader) throws -> String {
        let raw = try r.take(5)
        guard let s = parse(raw) else { throw ParseError.invalid("firmware") }
        return s
    }

    /// Dual firmware: either side may be absent (all 0x00 or 0xFF), but not both.
    static func readDual(_ r: inout ByteReader) throws -> (String?, String?) {
        let left = try r.take(5), right = try r.take(5)
        let l = parse(left), r2 = parse(right)
        if (l == nil && !isAbsent(left)) || (r2 == nil && !isAbsent(right)) || (l == nil && r2 == nil) {
            throw ParseError.invalid("dual firmware")
        }
        return (l, r2)
    }

    static func parse(_ raw: [UInt8]) -> String? {
        guard raw.count == 5, raw[2] == UInt8(ascii: "."),
              [0, 1, 3, 4].allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(raw[$0]) })
        else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }

    static func isAbsent(_ raw: [UInt8]) -> Bool { raw.allSatisfy { $0 == 0 } || raw.allSatisfy { $0 == 0xFF } }

    static func number(_ s: String?) -> Int? {
        guard let s, let major = Int(s.prefix(2)), let minor = Int(s.suffix(2)) else { return nil }
        return major * 100 + minor
    }
}

enum Serial {
    static func read(_ r: inout ByteReader) throws -> String {
        let raw = try r.take(16)
        guard raw.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) })
        else { throw ParseError.invalid("serial number") }
        return String(decoding: raw, as: UTF8.self)
    }
}

// MARK: - Equalizer

public enum Volume {
    public static let min: Int16 = -120
    public static let max: Int16 = 134

    static func tenths(_ byte: UInt8) -> Int16 { Swift.min(max, Int16(byte) + min) }
    static func byte(_ tenths: Int16) -> UInt8 { UInt8(Swift.max(min, Swift.min(max, tenths)) - min) }

    /// One channel, `nil` when the device reports it absent (first byte 0xFF).
    static func readOptional(_ r: inout ByteReader, bands: Int) throws -> [Int16]? {
        let raw = try r.take(bands)
        return raw[0] == 0xFF ? nil : raw.map(tenths)
    }

    static func bytes(_ channel: [Int16]?, bands: Int) -> [UInt8] {
        guard let channel else { return Array(repeating: 0xFF, count: bands) }
        return channel.map(byte)
    }

    /// The Soundcore apps' dynamic range compression over the first eight bands.
    /// Port of OpenSCQ30's `VolumeAdjustments::apply_drc`.
    public static func applyDRC(_ tenths: [Int16]) -> [Int16] {
        let a = tenths.map { Double($0) / 10 }
        let s = 0.85, l = 0.95
        let lows = a[2] * 0.81 * s
        let highs = a[5] * 0.81 * s
        let c: [[Double]] = [
            [1.26, -0.71 * s, 0.177, -0.0494, 0.0345, -0.0197, 0.0075, -0.00217],
            [-0.71 * s, 1.73 * l, 0, 0.204, -0.068, 0.045, -0.0235, 0.0075],
            [0.177, -0.81 * s, 1.73 * l, -0.81 * s, 0.208, -0.07, 0.045, -0.0197],
            [-0.0494, 0.204, 0, 1.73 * l, -0.82 * s, 0.208, -0.068, 0.0345],
            [0.0345, -0.068, 0.208, -0.82 * s, 1.73 * l, 0, 0.204, -0.0494],
            [-0.0197, 0.045, -0.07, 0.208, -0.81 * s, 1.73 * l, -0.81 * s, 0.177],
            [0.0075, -0.0235, 0.045, -0.068, 0.204, 0, 1.83 * l, -0.71 * s],
            [-0.00217, 0.0075, -0.0197, 0.0345, -0.0494, 0.177, -0.71 * s, 1.5],
        ]
        var out: [Int16] = (0..<8).map { row in
            var acc = 0.0
            for (i, adj) in a.prefix(8).enumerated() {
                if (row == 1 || row == 3) && i == 2 {
                    acc -= lows
                } else if (row == 4 || row == 6) && i == 5 {
                    acc -= highs
                } else {
                    acc += adj * c[row][i]
                }
            }
            return Int16((acc / 10 * 10).rounded())
        }
        let defaults: [Int16] = [0, 0, 0, 0, 0, 0, 0, 0, 0, -120]
        while out.count < tenths.count { out.append(defaults[Swift.min(out.count, defaults.count - 1)]) }
        return out.map { Swift.max(min, Swift.min(max, $0)) }
    }
}

/// HearID data is never edited here, but most EQ packets echo it back, so it is kept.
public struct HearID: Sendable, Equatable {
    public var isEnabled = false
    public var volumeAdjustments: [[Int16]?]
    public var time: UInt32 = 0
    public var type: UInt8 = 0
    public var customVolumeAdjustments: [[Int16]?]
    public var musicGenre: UInt16 = 0

    public init(channels: Int) {
        volumeAdjustments = Array(repeating: nil, count: channels)
        customVolumeAdjustments = Array(repeating: nil, count: channels)
    }

    var timeBytes: [UInt8] { [UInt8(time >> 24), UInt8((time >> 16) & 0xFF), UInt8((time >> 8) & 0xFF), UInt8(time & 0xFF)] }
    var musicGenreBytes: [UInt8] { [UInt8(musicGenre & 0xFF), UInt8(musicGenre >> 8)] }

    static func readTime(_ r: inout ByteReader) throws -> UInt32 {
        try r.take(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// `CustomHearId::take_with_music_genre_at_end`.
    static func readGenreAtEnd(_ r: inout ByteReader, channels: Int, bands: Int) throws -> HearID {
        var h = HearID(channels: channels)
        h.isEnabled = try r.bool()
        h.volumeAdjustments = try (0..<channels).map { _ in try Volume.readOptional(&r, bands: bands) }
        h.time = try readTime(&r)
        h.type = try r.u8()
        h.customVolumeAdjustments = try (0..<channels).map { _ in try Volume.readOptional(&r, bands: bands) }
        h.musicGenre = try r.u16le()
        return h
    }

    func volumeBytes(bands: Int) -> [UInt8] { volumeAdjustments.flatMap { Volume.bytes($0, bands: bands) } }
    func customBytes(bands: Int) -> [UInt8] { customVolumeAdjustments.flatMap { Volume.bytes($0, bands: bands) } }
}

public struct EqualizerState: Sendable, Equatable {
    public static let customPresetID: UInt16 = 0xFEFE

    public var presetID: UInt16
    public var channels: [[Int16]?]
    public var hearID: HearID?
    public var gender: UInt8 = 0
    public var ageRange: UInt8 = 0xFF
    /// P40i: HearID was never set up (status byte 0xFF).
    public var isHearIDInitialized = true

    public init(presetID: UInt16, channels: [[Int16]?]) {
        self.presetID = presetID
        self.channels = channels
    }

    public var primary: [Int16] {
        channels.compactMap { $0 }.first ?? Array(repeating: 0, count: channels.isEmpty ? 10 : 10)
    }

    public var visible: [Int16] { Array(primary.prefix(8)) }
    public var isCustom: Bool { presetID == Self.customPresetID }

    static func read(_ r: inout ByteReader, channels: Int, bands: Int) throws -> EqualizerState {
        let id = try r.u16le()
        let ch = try (0..<channels).map { _ in try Volume.readOptional(&r, bands: bands) }
        return EqualizerState(presetID: id, channels: ch)
    }
}

// MARK: - Sound mode cycle, power, volume limit, spatial

/// Which modes the "switch sound mode" touch action cycles through.
public struct AmbientSoundModeCycle: Sendable, Equatable {
    public var noiseCanceling: Bool
    public var transparency: Bool
    public var normal: Bool

    public init(byte: UInt8) {
        noiseCanceling = byte & 1 != 0
        transparency = byte & 2 != 0
        normal = byte & 4 != 0
    }

    public var byte: UInt8 { (noiseCanceling ? 1 : 0) | (transparency ? 2 : 0) | (normal ? 4 : 0) }
}

public struct AutoPowerOff: Sendable, Equatable {
    public var isEnabled: Bool
    public var durationIndex: UInt8
    public init(isEnabled: Bool = false, durationIndex: UInt8 = 0) {
        self.isEnabled = isEnabled
        self.durationIndex = durationIndex
    }

    static func read(_ r: inout ByteReader) throws -> AutoPowerOff {
        AutoPowerOff(isEnabled: try r.bool(), durationIndex: try r.u8())
    }
}

public enum DecibelRefreshRate: UInt8, Sendable, CaseIterable, Identifiable {
    case realTime = 0
    case tenSeconds = 1
    case oneMinute = 2
    public var id: UInt8 { rawValue }
}

public struct LimitHighVolume: Sendable, Equatable {
    public var isEnabled: Bool
    public var dbLimit: UInt8
    public var refreshRate: DecibelRefreshRate
    public init(isEnabled: Bool = false, dbLimit: UInt8 = 85, refreshRate: DecibelRefreshRate = .realTime) {
        self.isEnabled = isEnabled
        self.dbLimit = dbLimit
        self.refreshRate = refreshRate
    }

    static func read(_ r: inout ByteReader) throws -> LimitHighVolume {
        LimitHighVolume(isEnabled: try r.bool(), dbLimit: try r.u8(),
                        refreshRate: DecibelRefreshRate(rawValue: try r.u8()) ?? .realTime)
    }
}

public enum SpatialAudioMode: UInt8, Sendable, CaseIterable, Identifiable {
    case music = 0
    case movie = 2
    case gaming = 3
    public var id: UInt8 { rawValue }
}

public struct SpatialAudio: Sendable, Equatable {
    public var isEnabled: Bool
    public var mode: SpatialAudioMode
    public init(isEnabled: Bool = false, mode: SpatialAudioMode = .music) {
        self.isEnabled = isEnabled
        self.mode = mode
    }
}

// MARK: - Multipoint

public struct DualConnectionDevice: Sendable, Equatable, Identifiable {
    public var isConnected: Bool
    public var macAddress: [UInt8]
    public var name: String
    public var id: String { macAddressString }

    public var macAddressString: String {
        macAddress.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Parses one `0b 01` response body: [total][index] then length-prefixed entries.
    public static func parsePage(_ body: [UInt8]) -> (total: Int, index: Int, devices: [DualConnectionDevice])? {
        var r = ByteReader(body)
        guard let total = try? r.u8(), let index = try? r.u8() else { return nil }
        var devices: [DualConnectionDevice] = []
        while r.remaining > 0 {
            guard let length = try? r.u8(), let connected = try? r.bool(), let mac = try? r.take(6) else { break }
            let nameLength = min(Int(length >= 8 ? length - 8 : 0), r.remaining)
            let name = (try? r.string(nameLength)) ?? ""
            devices.append(DualConnectionDevice(isConnected: connected, macAddress: mac, name: name))
        }
        return (Int(total), Int(index), devices)
    }
}

// MARK: - Flags

/// Simple on/off settings. Each model maps the ones it has to its own set command.
public enum DeviceFlag: String, Sendable, CaseIterable, Identifiable {
    case ldac
    case touchTone
    case lowBatteryPrompt
    case wearingDetection
    case wearingTone
    case autoPlayPause
    case gamingMode
    case touchLock
    case soundLeakCompensation
    case surroundSound
    case voicePrompt
    case batteryAlert
    case ambientSoundModeVoicePrompt
    public var id: String { rawValue }
}
