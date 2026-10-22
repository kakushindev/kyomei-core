import Foundation

public struct EqualizerPreset: Sendable, Identifiable, Hashable {
    public let id: UInt16
    public let name: String
    /// Ten bands in tenths of a dB.
    public let bands: [Int16]
}

public enum EqualizerPresets {
    private static func p(_ id: UInt16, _ name: String, _ v: [Int16]) -> EqualizerPreset {
        EqualizerPreset(id: id, name: name, bands: v + [0, -120])
    }

    /// OpenSCQ30 `common_settings_type_2` (newer earbuds).
    public static let type2: [EqualizerPreset] = [
        p(0, "Soundcore Signature", [0, 0, 0, 0, 0, 0, 0, 0]),
        p(1, "Acoustic", [40, 10, 20, 20, 40, 40, 40, 20]),
        p(2, "Bass Booster", [40, 30, 10, 0, 0, 0, 0, 0]),
        p(3, "Bass Reducer", [-40, -30, -10, 0, 0, 0, 0, 0]),
        p(4, "Classical", [30, 30, -20, -20, 0, 20, 30, 40]),
        p(5, "Podcast", [-30, 20, 40, 40, 30, 20, 0, -20]),
        p(6, "Dance", [20, -30, -10, 10, 20, 20, 10, -30]),
        p(7, "Deep", [20, 10, 30, 30, 20, -20, -40, -50]),
        p(8, "Electronic", [30, 20, -20, 20, 10, 20, 30, 30]),
        p(9, "Flat", [-20, -20, -10, 0, 0, 0, -20, -20]),
        p(10, "Hip-Hop", [20, 30, -10, -10, 20, -10, 20, 30]),
        p(11, "Jazz", [20, 20, -20, -20, 0, 20, 30, 40]),
        p(12, "Latin", [0, 0, -20, -20, -20, 0, 30, 50]),
        p(13, "Lounge", [-10, 20, 40, 30, 0, -20, 20, 10]),
        p(14, "Piano", [0, 30, 30, 20, 40, 50, 30, 40]),
        p(15, "Pop", [-10, 10, 30, 30, 10, -10, -20, -30]),
        p(16, "R&B", [60, 20, -20, -20, 20, 30, 30, 40]),
        p(17, "Rock", [30, 20, -10, -10, 10, 30, 40, 50]),
        p(18, "Small Speakers", [40, 30, 10, 0, -20, -30, -40, -40]),
        p(19, "Spoken Word", [-30, -20, 10, 20, 20, 10, 0, -30]),
        p(20, "Treble Booster", [-20, -20, -20, -10, 10, 20, 20, 40]),
        p(21, "Treble Reducer", [0, 0, 0, -20, -30, -40, -40, -60]),
    ]

    /// OpenSCQ30 `common_settings` (Life Q30 generation): identical except for Rock.
    public static let common: [EqualizerPreset] = type2.map {
        $0.id == 17 ? p(17, "Rock", [30, 20, -10, -10, 10, 30, 30, 30]) : $0
    }

    /// Space Q45: bass boost is a separate control, so no Bass Booster preset.
    public static let spaceQ45: [EqualizerPreset] = type2.filter { $0.id != 2 }

    /// Space One: like Space Q45 with Bass Booster under its own id.
    public static let spaceOne: [EqualizerPreset] = spaceQ45 + [p(0x7E7E, "Bass Booster", [40, 30, 10, 0, 0, 0, 0, 0])]
}

/// How a model writes its equalizer.
public enum EqualizerWriter: Sendable {
    /// `02 81`: preset id + channels.
    case basic
    /// `02 83`: preset id + channels + DRC of each channel.
    case drc
    /// `03 87` / `03 86` with HearID, gender and age (Space A40).
    case customHearID(forceSupportsHearID: Bool)
    /// `03 87` with HearID and DRC, last DRC band zeroed (Liberty 4 NC).
    case liberty4NC
    /// `03 87` with HearID and the effective EQ interleaved with zeros (R60i NC, Liberty 5).
    case interleaved
    /// `03 87` P40i variant.
    case p40i
    /// `03 87` Space Q45 variant (one channel, DRC in place of the right channel).
    case spaceQ45
    /// `03 87` Space One variant.
    case spaceOne
}

public struct EqualizerSpec: Sendable {
    public let channels: Int
    public let bands: Int
    public let presets: [EqualizerPreset]
    /// `nil` when the device only accepts presets.
    public let customPresetID: UInt16?
    /// Only editable while both earbuds are connected.
    public let requiresBothEarbuds: Bool
    let writer: EqualizerWriter

    public var allowsCustom: Bool { customPresetID != nil }

    /// Bands for a preset, trimmed or padded to this device's band count.
    public func bands(for preset: EqualizerPreset) -> [Int16] { fit(preset.bands) }

    /// Eight visible bands plus fixed invisible bands, as the Soundcore app sends them.
    public func customBands(_ visible: [Int16]) -> [Int16] { fit(Array(visible.prefix(8)) + [0, 0]) }

    private func fit(_ v: [Int16]) -> [Int16] {
        var out = Array(v.prefix(bands))
        while out.count < bands { out.append(0) }
        return out
    }

    public func packet(presetID: UInt16, bands values: [Int16], state: EqualizerState) -> Packet {
        let eq = Array(repeating: Optional(values), count: channels)
        var hearID = state.hearID ?? HearID(channels: channels)
        hearID.isEnabled = false  // HearID is not exposed, so make sure the chosen EQ is the one in effect
        let id = [UInt8(presetID & 0xFF), UInt8(presetID >> 8)]
        let eqBytes = eq.flatMap { Volume.bytes($0, bands: bands) }
        let drcBytes = eq.flatMap { Volume.bytes($0.map(Volume.applyDRC), bands: bands) }

        switch writer {
        case .basic:
            return Packet(Commands.setEqualizerBasic, id + eqBytes)

        case .drc:
            return Packet(Commands.setEqualizerDRC, id + eqBytes + drcBytes)

        case .customHearID(let force):
            let supports = state.ageRange != 0xFF || force
            let blank = [UInt8](repeating: 0xFF, count: channels * bands)
            var body = id
            if supports { body += hearID.musicGenreBytes }
            body += eqBytes
            body += [supports ? state.gender : 0xFF, supports ? state.ageRange : 0xFF, 0]
            body += supports ? hearID.volumeBytes(bands: bands) : blank
            body += supports ? hearID.timeBytes : [0, 0, 0, 0]
            body.append(hearID.type)
            body += supports ? hearID.customBytes(bands: bands) : blank
            body += drcBytes
            return Packet(supports ? Commands.setEqualizerHearID : Command(0x03, 0x86), body)

        case .liberty4NC:
            var body = id + hearID.musicGenreBytes + eqBytes + [0, 0]
            body.append(0)
            body += hearID.volumeBytes(bands: bands) + hearID.timeBytes + [hearID.type]
            body += hearID.customBytes(bands: bands)
            for channel in eq {
                var drc = Volume.bytes(channel.map(Volume.applyDRC), bands: bands)
                drc[9] = 0
                body += drc
            }
            body.append(0)
            return Packet(Commands.setEqualizerHearID, body)

        case .interleaved:
            var body = id + hearID.musicGenreBytes + eqBytes + [0, 0]
            body.append(0)
            body += hearID.volumeBytes(bands: bands) + hearID.timeBytes + [hearID.type]
            body += hearID.customBytes(bands: bands)
            for byte in eqBytes { body += [byte, 0] }
            body += [0, 0]
            return Packet(Commands.setEqualizerHearID, body)

        case .p40i:
            func zeroTail(_ channels: [[Int16]?]) -> [UInt8] {
                channels.flatMap { c -> [UInt8] in
                    var b = Volume.bytes(c, bands: bands)
                    if c == nil { b[b.count - 1] = 0 }
                    return b
                }
            }
            var body = id + hearID.musicGenreBytes + eqBytes
            body += state.isHearIDInitialized ? [0, 0] : [255, 255]
            body.append(0)
            body += zeroTail(hearID.volumeAdjustments) + hearID.timeBytes + [hearID.type]
            body += zeroTail(hearID.customVolumeAdjustments)
            body += drcBytes
            body.append(0)
            return Packet(Commands.setEqualizerHearID, body)

        case .spaceQ45:
            let first = Volume.bytes(eq.first ?? nil, bands: bands)
            let firstDRC = Volume.bytes((eq.first ?? nil).map(Volume.applyDRC), bands: bands)
            var body = id + hearID.musicGenreBytes + first + first + [0, 1]
            body.append(0)
            body += hearID.volumeBytes(bands: bands) + hearID.timeBytes + [hearID.type]
            let customLeft = Array(hearID.customBytes(bands: bands).prefix(bands))
            body += customLeft + customLeft
            body += firstDRC + firstDRC
            body.append(0)
            return Packet(Commands.setEqualizerHearID, body)

        case .spaceOne:
            func blankTail(_ channels: [[Int16]?]) -> [UInt8] {
                channels.flatMap { c -> [UInt8] in
                    guard let c else {
                        var b = [UInt8](repeating: 0xFF, count: bands)
                        b[bands - 1] = 0
                        return b
                    }
                    return Volume.bytes(c, bands: bands)
                }
            }
            var body = id + hearID.musicGenreBytes + eqBytes + [255, 255]
            body.append(0)
            body += blankTail(hearID.volumeAdjustments) + hearID.timeBytes + [hearID.type]
            body += blankTail(hearID.customVolumeAdjustments)
            body += drcBytes
            body.append(0)
            return Packet(Commands.setEqualizerHearID, body)
        }
    }
}
