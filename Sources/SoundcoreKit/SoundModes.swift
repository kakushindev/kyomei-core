import Foundation

public enum AmbientSoundMode: UInt8, Sendable, CaseIterable, Identifiable {
    case noiseCanceling = 0
    case transparency = 1
    case normal = 2
    public var id: UInt8 { rawValue }
}

/// Union of the noise cancelling sub-modes used across models.
public enum NoiseCancelingMode: String, Sendable, CaseIterable, Identifiable {
    // First generation (Life Q30/Q35): fixed scenes plus a custom level.
    case transport, outdoor, indoor, custom
    // Later models.
    case adaptive, manual, multiScene, transportation
    public var id: String { rawValue }
}

public enum TransparencyMode: String, Sendable, CaseIterable, Identifiable {
    case fullyTransparent, vocal, talk, manual
    public var id: String { rawValue }
}

public enum MultiSceneMode: UInt8, Sendable, CaseIterable, Identifiable {
    case transport = 0
    case outdoor = 1
    case indoor = 2
    public var id: UInt8 { rawValue }
}

public enum TransportationMode: UInt8, Sendable, CaseIterable, Identifiable {
    case plane = 0
    case train = 1
    case bus = 2
    case car = 3
    public var id: UInt8 { rawValue }
}

/// Model independent view of a device's sound mode block. Each model's codec maps its own
/// byte layout onto the fields it supports and leaves the rest untouched.
public struct SoundModes: Sendable, Equatable {
    public var ambient: AmbientSoundMode = .normal
    public var noiseCanceling: NoiseCancelingMode = .adaptive
    public var manualLevel: UInt8 = 1
    /// Read-only on most models: the level the earbuds picked.
    public var adaptiveLevel: UInt8 = 0
    /// First generation custom ANC strength, 0...10.
    public var customLevel: UInt8 = 0
    public var transparency: TransparencyMode = .fullyTransparent
    public var manualTransparencyLevel: UInt8 = 1
    public var multiScene: MultiSceneMode = .transport
    public var transportation: TransportationMode = .plane
    public var windNoiseSuppression = false
    public var windNoiseDetected = false
    public var environmentDetection = false
    public var realTimeAdaptive = false
    public var adaptiveSensitivity: UInt8 = 0

    public init() {}
}

/// How a level is presented: plain numbers or named steps (raw value -> name).
public enum LevelStyle: Sendable, Equatable {
    case numeric(ClosedRange<UInt8>)
    case named([(UInt8, String)])

    public static func == (a: LevelStyle, b: LevelStyle) -> Bool {
        switch (a, b) {
        case let (.numeric(x), .numeric(y)): x == y
        case let (.named(x), .named(y)): x.map(\.0) == y.map(\.0) && x.map(\.1) == y.map(\.1)
        default: false
        }
    }
}

public struct SoundModeSpec: Sendable {
    public let ambientModes: [AmbientSoundMode]
    public let noiseCancelingModes: [NoiseCancelingMode]
    public let manualLevel: LevelStyle?
    public let adaptiveLevel: LevelStyle?
    public let customLevel: ClosedRange<UInt8>?
    public let transparencyModes: [TransparencyMode]
    /// Shown when the transparency mode is `.manual`, or always when there are no transparency modes.
    public let manualTransparency: ClosedRange<UInt8>?
    public let multiSceneModes: [MultiSceneMode]
    public let transportationModes: [TransportationMode]
    public let windNoise: Bool
    public let windNoiseDetection: Bool
    public let environmentDetection: Bool
    public let realTimeAdaptive: Bool
    public let adaptiveSensitivity: ClosedRange<UInt8>?

    let size: Int
    let decode: @Sendable (inout ByteReader) throws -> SoundModes
    let encode: @Sendable (SoundModes) -> [UInt8]
    let transition: Transition

    enum Transition: Sendable {
        /// Send the target in one packet.
        case direct
        /// First generation firmware bug workaround (see `packets(from:to:)`).
        case firstGeneration
        /// Fields that may only change while a parent field has given values.
        case migration([MigrationField])
    }

    public func decode(body: [UInt8]) throws -> SoundModes {
        var r = ByteReader(body)
        return try decode(&r)
    }

    /// `06 81` packets moving the device from `current` to `target`.
    public func packets(from current: SoundModes, to target: SoundModes) -> [Packet] {
        guard current != target else { return [] }
        switch transition {
        case .direct:
            return [Commands.soundModes(encode(target))]
        case .firstGeneration:
            // Changing the noise cancelling mode outside of noise cancelling puts the device in
            // noise cancelling without reporting it, so step through noise cancelling first.
            let needsNoiseCanceling = current.ambient != .noiseCanceling && current.noiseCanceling != target.noiseCanceling
            var packets: [Packet] = []
            if needsNoiseCanceling {
                var step = current
                step.ambient = .noiseCanceling
                packets.append(Commands.soundModes(encode(step)))
            }
            var step = target
            if needsNoiseCanceling { step.ambient = .noiseCanceling }
            packets.append(Commands.soundModes(encode(step)))
            if needsNoiseCanceling { packets.append(Commands.soundModes(encode(target))) }
            return packets
        case .migration(let fields):
            return MigrationPlanner(fields: fields).path(from: current, to: target).map { Commands.soundModes(encode($0)) }
        }
    }
}

struct MigrationField: Sendable {
    let get: @Sendable (SoundModes) -> UInt8
    let set: @Sendable (inout SoundModes, UInt8) -> Void
    let parent: Int?
    let parentValues: [UInt8]

    init(_ get: @escaping @Sendable (SoundModes) -> UInt8, _ set: @escaping @Sendable (inout SoundModes, UInt8) -> Void,
         requires parent: Int? = nil, in values: [UInt8] = []) {
        self.get = get
        self.set = set
        self.parent = parent
        self.parentValues = values
    }
}

/// Breadth-first search over field assignments, mirroring OpenSCQ30's migration planner: a field
/// can be changed only while its parent field holds one of the required values.
struct MigrationPlanner {
    let fields: [MigrationField]

    func path(from current: SoundModes, to target: SoundModes) -> [SoundModes] {
        let start = fields.map { $0.get(current) }
        let goal = fields.map { $0.get(target) }
        guard start != goal else { return current == target ? [] : [target] }

        var previous: [[UInt8]: [UInt8]] = [start: start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let state = queue[head]
            head += 1
            if state == goal { break }
            for next in successors(of: state, goal: goal) where previous[next] == nil {
                previous[next] = state
                queue.append(next)
            }
        }
        guard previous[goal] != nil else { return [target] }

        var chain: [[UInt8]] = []
        var node = goal
        while node != start {
            chain.append(node)
            node = previous[node]!
        }
        return chain.reversed().map { values in
            var modes = target
            for (field, value) in zip(fields, values) { field.set(&modes, value) }
            return modes
        }
    }

    private func successors(of state: [UInt8], goal: [UInt8]) -> [[UInt8]] {
        var moves: [(Int, UInt8)] = []
        func add(_ index: Int, _ value: UInt8) {
            if state[index] != value, !moves.contains(where: { $0 == (index, value) }) { moves.append((index, value)) }
        }
        // A field is editable once every ancestor requirement holds; for a field whose parent
        // is editable but not in a required state, moving the parent there is a candidate step.
        var editable = [Bool](repeating: false, count: fields.count)
        for (i, field) in fields.enumerated() {
            guard let parent = field.parent else {
                editable[i] = true
                add(i, goal[i])
                continue
            }
            guard editable[parent] else { continue }
            if field.parentValues.contains(state[parent]) {
                editable[i] = true
                add(i, goal[i])
            } else {
                for v in field.parentValues { add(parent, v) }
            }
        }
        return moves.map { index, value in
            var s = state
            s[index] = value
            return s
        }
    }
}

// MARK: - Byte helpers

private func ambient(_ b: UInt8) -> AmbientSoundMode { AmbientSoundMode(rawValue: b) ?? .noiseCanceling }

private extension SoundModes {
    var windByte: UInt8 { (windNoiseSuppression ? 1 : 0) | (windNoiseDetected ? 2 : 0) }

    mutating func setWind(_ b: UInt8) {
        windNoiseSuppression = b & 1 != 0
        windNoiseDetected = b & 2 != 0
    }
}

private func ncByte(_ mode: NoiseCancelingMode, _ table: [NoiseCancelingMode]) -> UInt8 {
    UInt8(table.firstIndex(of: mode) ?? 0)
}

private func ncMode(_ b: UInt8, _ table: [NoiseCancelingMode]) -> NoiseCancelingMode {
    Int(b) < table.count ? table[Int(b)] : table[0]
}

// MARK: - Codecs

public enum SoundModeSpecs {
    static let strengthNames: LevelStyle = .named([(0, "Light"), (1, "Moderate"), (2, "Strong")])

    /// Life Q30 / Q35 / Q20i: `[ambient, nc mode, transparency, custom level]`.
    static func firstGeneration(noiseCancelingModes: [NoiseCancelingMode]) -> SoundModeSpec {
        let table: [NoiseCancelingMode] = [.transport, .outdoor, .indoor, .custom]
        let transparencyTable: [TransparencyMode] = [.fullyTransparent, .vocal]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: noiseCancelingModes, manualLevel: nil, adaptiveLevel: nil,
            customLevel: noiseCancelingModes.contains(.custom) ? 0...10 : nil,
            transparencyModes: [], manualTransparency: nil, multiSceneModes: [], transportationModes: [],
            windNoise: false, windNoiseDetection: false, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 4,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                m.noiseCanceling = ncMode(try r.u8(), table)
                let t = try r.u8()
                m.transparency = Int(t) < transparencyTable.count ? transparencyTable[Int(t)] : .fullyTransparent
                let c = try r.u8()
                m.customLevel = c == 255 ? c : min(10, c)
                return m
            },
            encode: { m in
                [m.ambient.rawValue, ncByte(m.noiseCanceling, table),
                 UInt8(transparencyTable.firstIndex(of: m.transparency) ?? 0), m.customLevel]
            },
            transition: .firstGeneration)
    }

    /// soundcore R60i NC / P31i (D1202).
    static let d1202: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive, .multiScene]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual, .multiScene],
            manualLevel: .numeric(1...5), adaptiveLevel: strengthNames, customLevel: nil,
            transparencyModes: [.fullyTransparent, .vocal], manualTransparency: nil,
            multiSceneModes: MultiSceneMode.allCases, transportationModes: [],
            windNoise: true, windNoiseDetection: true, environmentDetection: false, realTimeAdaptive: true,
            adaptiveSensitivity: nil, size: 8,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, max(1, levels >> 4))
                m.adaptiveLevel = (levels & 0x0F) <= 2 ? levels & 0x0F : 0
                m.transparency = try r.u8() == 1 ? .vocal : .fullyTransparent
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.setWind(try r.u8())
                try r.skip(1)
                m.multiScene = MultiSceneMode(rawValue: try r.u8()) ?? .transport
                m.realTimeAdaptive = try r.bool()
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (min(5, max(1, m.manualLevel)) << 4) | m.adaptiveLevel,
                 m.transparency == .vocal ? 1 : 0, ncByte(m.noiseCanceling, table), m.windByte, 0,
                 m.multiScene.rawValue, m.realTimeAdaptive ? 1 : 0]
            },
            transition: .direct)
    }()

    /// soundcore P30i / R50i NC (A3959).
    static let a3959: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive, .multiScene]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual, .multiScene],
            manualLevel: .numeric(1...5), adaptiveLevel: .numeric(1...5), customLevel: nil,
            transparencyModes: [], manualTransparency: nil,
            multiSceneModes: MultiSceneMode.allCases, transportationModes: [],
            windNoise: true, windNoiseDetection: true, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: 0...10, size: 7,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, max(1, levels >> 4))
                m.adaptiveLevel = min(5, max(1, levels & 0x0F))
                try r.skip(1)
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.setWind(try r.u8())
                m.adaptiveSensitivity = try r.u8()
                m.multiScene = MultiSceneMode(rawValue: try r.u8()) ?? .transport
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.ambient.rawValue,
                 ncByte(m.noiseCanceling, table), m.windByte, m.adaptiveSensitivity, m.multiScene.rawValue]
            },
            transition: .migration([
                MigrationField({ $0.ambient.rawValue }, { $0.ambient = ambient($1) }),
                MigrationField({ ncByte($0.noiseCanceling, table) }, { $0.noiseCanceling = ncMode($1, table) }, requires: 0, in: [0]),
                MigrationField({ $0.adaptiveLevel }, { $0.adaptiveLevel = $1 }, requires: 1, in: [1]),
                MigrationField({ $0.manualLevel }, { $0.manualLevel = $1 }, requires: 1, in: [0]),
                MigrationField({ $0.multiScene.rawValue }, { $0.multiScene = MultiSceneMode(rawValue: $1) ?? .transport }, requires: 1, in: [2]),
                MigrationField({ $0.windByte }, { $0.setWind($1) }, requires: 0, in: [0, 1]),
                MigrationField({ $0.adaptiveSensitivity }, { $0.adaptiveSensitivity = $1 }),
            ]))
    }()

    /// soundcore Liberty 4 NC (A3947).
    static let a3947: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive, .transportation]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual, .transportation],
            manualLevel: .numeric(1...5), adaptiveLevel: .numeric(0...5), customLevel: nil,
            transparencyModes: [.fullyTransparent, .vocal], manualTransparency: nil,
            multiSceneModes: [], transportationModes: TransportationMode.allCases,
            windNoise: true, windNoiseDetection: true, environmentDetection: true, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 7,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, levels >> 4)
                m.adaptiveLevel = min(5, levels & 0x0F)
                m.transparency = try r.u8() == 1 ? .vocal : .fullyTransparent
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.setWind(try r.u8())
                m.environmentDetection = try r.bool()
                m.transportation = TransportationMode(rawValue: try r.u8()) ?? .plane
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.transparency == .vocal ? 1 : 0,
                 ncByte(m.noiseCanceling, table), m.windByte, m.environmentDetection ? 1 : 0, m.transportation.rawValue]
            },
            transition: .migration([
                MigrationField({ $0.ambient.rawValue }, { $0.ambient = ambient($1) }),
                MigrationField({ $0.transparency == .vocal ? 1 : 0 }, { $0.transparency = $1 == 1 ? .vocal : .fullyTransparent }, requires: 0, in: [1]),
                MigrationField({ ncByte($0.noiseCanceling, table) }, { $0.noiseCanceling = ncMode($1, table) }, requires: 0, in: [0]),
                MigrationField({ $0.transportation.rawValue }, { $0.transportation = TransportationMode(rawValue: $1) ?? .plane }, requires: 2, in: [2]),
                MigrationField({ $0.manualLevel }, { $0.manualLevel = $1 }, requires: 2, in: [0]),
                MigrationField({ $0.adaptiveLevel }, { $0.adaptiveLevel = $1 }, requires: 2, in: [1]),
                MigrationField({ $0.environmentDetection ? 1 : 0 }, { $0.environmentDetection = $1 != 0 }, requires: 2, in: [1]),
                MigrationField({ $0.windByte }, { $0.setWind($1) }, requires: 0, in: [0, 1]),
            ]))
    }()

    /// soundcore Liberty 5 (A3957).
    static let a3957: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive, .transportation]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual, .transportation],
            manualLevel: .numeric(1...5), adaptiveLevel: strengthNames, customLevel: nil,
            transparencyModes: [.fullyTransparent, .vocal], manualTransparency: nil,
            multiSceneModes: [], transportationModes: [.plane, .car],
            windNoise: true, windNoiseDetection: true, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 7,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, max(1, levels >> 4))
                m.adaptiveLevel = (levels & 0x0F) <= 2 ? levels & 0x0F : 0
                m.transparency = try r.u8() == 1 ? .vocal : .fullyTransparent
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.setWind(try r.u8())
                m.adaptiveSensitivity = try r.u8()
                m.transportation = try r.u8() == 3 ? .car : .plane
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.transparency == .vocal ? 1 : 0,
                 ncByte(m.noiseCanceling, table), m.windByte, m.adaptiveSensitivity, m.transportation == .car ? 3 : 0]
            },
            transition: .migration([
                MigrationField({ $0.ambient.rawValue }, { $0.ambient = ambient($1) }),
                MigrationField({ $0.transparency == .vocal ? 1 : 0 }, { $0.transparency = $1 == 1 ? .vocal : .fullyTransparent }, requires: 0, in: [1]),
                MigrationField({ ncByte($0.noiseCanceling, table) }, { $0.noiseCanceling = ncMode($1, table) }, requires: 0, in: [0]),
                MigrationField({ $0.adaptiveLevel }, { $0.adaptiveLevel = $1 }, requires: 2, in: [1]),
                MigrationField({ $0.manualLevel }, { $0.manualLevel = $1 }, requires: 2, in: [0]),
                MigrationField({ $0.transportation == .car ? 3 : 0 }, { $0.transportation = $1 == 3 ? .car : .plane }, requires: 2, in: [2]),
                MigrationField({ $0.windByte }, { $0.setWind($1) }, requires: 0, in: [0, 1]),
                MigrationField({ $0.adaptiveSensitivity }, { $0.adaptiveSensitivity = $1 }, requires: 2, in: [1]),
            ]))
    }()

    /// soundcore P40i (A3955).
    static let a3955: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive, .multiScene]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual, .multiScene],
            manualLevel: .numeric(1...5), adaptiveLevel: .named([(1, "Light"), (2, "Moderate"), (3, "Strong")]),
            customLevel: nil, transparencyModes: [.fullyTransparent, .vocal], manualTransparency: nil,
            multiSceneModes: MultiSceneMode.allCases, transportationModes: [],
            windNoise: true, windNoiseDetection: true, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 7,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, max(1, levels >> 4))
                m.adaptiveLevel = (1...3).contains(levels & 0x0F) ? levels & 0x0F : 1
                m.transparency = try r.u8() == 1 ? .vocal : .fullyTransparent
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.setWind(try r.u8())
                m.adaptiveSensitivity = try r.u8()
                m.multiScene = MultiSceneMode(rawValue: try r.u8()) ?? .transport
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.transparency == .vocal ? 1 : 0,
                 ncByte(m.noiseCanceling, table), m.windByte, m.adaptiveSensitivity, m.multiScene.rawValue]
            },
            transition: .migration([
                MigrationField({ $0.ambient.rawValue }, { $0.ambient = ambient($1) }),
                MigrationField({ $0.transparency == .vocal ? 1 : 0 }, { $0.transparency = $1 == 1 ? .vocal : .fullyTransparent }, requires: 0, in: [1]),
                MigrationField({ ncByte($0.noiseCanceling, table) }, { $0.noiseCanceling = ncMode($1, table) }, requires: 0, in: [0]),
                MigrationField({ $0.adaptiveLevel }, { $0.adaptiveLevel = $1 }, requires: 2, in: [1]),
                MigrationField({ $0.manualLevel }, { $0.manualLevel = $1 }, requires: 2, in: [0]),
                MigrationField({ $0.multiScene.rawValue }, { $0.multiScene = MultiSceneMode(rawValue: $1) ?? .transport }, requires: 2, in: [2]),
                MigrationField({ $0.windByte }, { $0.setWind($1) }, requires: 0, in: [0, 1]),
                MigrationField({ $0.adaptiveSensitivity }, { $0.adaptiveSensitivity = $1 }, requires: 2, in: [1]),
            ]))
    }()

    /// soundcore Space A40 (A3936).
    static let a3936: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual],
            manualLevel: .named([(1, "Light"), (2, "Moderate"), (3, "Strong")]),
            adaptiveLevel: .named([(0, "Low Noise"), (1, "Medium Noise"), (2, "High Noise")]),
            customLevel: nil, transparencyModes: [.fullyTransparent, .vocal], manualTransparency: nil,
            multiSceneModes: [], transportationModes: [],
            windNoise: true, windNoiseDetection: true, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 6,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = (1...3).contains(levels >> 4) ? levels >> 4 : 1
                m.adaptiveLevel = (levels & 0x0F) <= 2 ? levels & 0x0F : 0
                m.transparency = try r.u8() == 1 ? .vocal : .fullyTransparent
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.setWind(try r.u8())
                m.adaptiveSensitivity = try r.u8()
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.transparency == .vocal ? 1 : 0,
                 ncByte(m.noiseCanceling, table), m.windByte, m.adaptiveSensitivity]
            },
            transition: .direct)
    }()

    /// soundcore Space Q45 (A3040).
    static let a3040: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual],
            manualLevel: .numeric(1...5), adaptiveLevel: .numeric(0...5), customLevel: nil,
            transparencyModes: [.talk, .manual], manualTransparency: 1...5,
            multiSceneModes: [], transportationModes: [],
            windNoise: true, windNoiseDetection: false, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 6,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, max(1, levels >> 4))
                m.adaptiveLevel = min(5, levels & 0x0F)
                m.transparency = try r.u8() == 1 ? .manual : .talk
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.windNoiseSuppression = try r.bool()
                m.manualTransparencyLevel = min(5, max(1, try r.u8()))
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.transparency == .manual ? 1 : 0,
                 ncByte(m.noiseCanceling, table), m.windNoiseSuppression ? 1 : 0, m.manualTransparencyLevel]
            },
            transition: .migration([
                MigrationField({ $0.ambient.rawValue }, { $0.ambient = ambient($1) }),
                MigrationField({ ncByte($0.noiseCanceling, table) }, { $0.noiseCanceling = ncMode($1, table) }, requires: 0, in: [0]),
                MigrationField({ $0.manualLevel }, { $0.manualLevel = $1 }, requires: 1, in: [0]),
                MigrationField({ $0.adaptiveLevel }, { $0.adaptiveLevel = $1 }, requires: 1, in: [1]),
                MigrationField({ $0.transparency == .manual ? 1 : 0 }, { $0.transparency = $1 == 1 ? .manual : .talk }, requires: 0, in: [1]),
                MigrationField({ $0.manualTransparencyLevel }, { $0.manualTransparencyLevel = $1 }, requires: 4, in: [1]),
                MigrationField({ $0.windNoiseSuppression ? 1 : 0 }, { $0.windNoiseSuppression = $1 != 0 }, requires: 0, in: [0, 1]),
            ]))
    }()

    /// soundcore Space One (A3035). Its "custom" ANC is presented as manual.
    static let a3035: SoundModeSpec = {
        let table: [NoiseCancelingMode] = [.manual, .adaptive]
        return SoundModeSpec(
            ambientModes: [.noiseCanceling, .transparency, .normal],
            noiseCancelingModes: [.adaptive, .manual],
            manualLevel: .numeric(1...5), adaptiveLevel: .numeric(1...5), customLevel: nil,
            transparencyModes: [], manualTransparency: 1...5,
            multiSceneModes: [], transportationModes: [],
            windNoise: true, windNoiseDetection: false, environmentDetection: false, realTimeAdaptive: false,
            adaptiveSensitivity: nil, size: 6,
            decode: { r in
                var m = SoundModes()
                m.ambient = ambient(try r.u8())
                let levels = try r.u8()
                m.manualLevel = min(5, max(1, levels >> 4))
                m.adaptiveLevel = min(5, max(1, levels & 0x0F))
                try r.skip(1)
                m.noiseCanceling = ncMode(try r.u8(), table)
                m.windNoiseSuppression = try r.bool()
                m.manualTransparencyLevel = min(5, max(1, try r.u8()))
                return m
            },
            encode: { m in
                [m.ambient.rawValue, (m.manualLevel << 4) | m.adaptiveLevel, m.ambient.rawValue,
                 ncByte(m.noiseCanceling, table), m.windNoiseSuppression ? 1 : 0, m.manualTransparencyLevel]
            },
            transition: .migration([
                MigrationField({ $0.ambient.rawValue }, { $0.ambient = ambient($1) }),
                MigrationField({ ncByte($0.noiseCanceling, table) }, { $0.noiseCanceling = ncMode($1, table) }, requires: 0, in: [0]),
                MigrationField({ $0.adaptiveLevel }, { $0.adaptiveLevel = $1 }, requires: 1, in: [1]),
                MigrationField({ $0.manualLevel }, { $0.manualLevel = $1 }, requires: 1, in: [0]),
                MigrationField({ $0.manualTransparencyLevel }, { $0.manualTransparencyLevel = $1 }, requires: 0, in: [1]),
                MigrationField({ $0.windNoiseSuppression ? 1 : 0 }, { $0.windNoiseSuppression = $1 != 0 }, requires: 0, in: [0, 1]),
            ]))
    }()
}
