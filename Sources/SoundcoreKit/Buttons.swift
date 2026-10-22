import Foundation

public enum ButtonSide: UInt8, Sendable, CaseIterable, Identifiable {
    case left = 0
    case right = 1
    public var id: UInt8 { rawValue }
}

public enum PressKind: Int, Sendable, CaseIterable, Identifiable {
    case single, double, triple, long
    public var id: Int { rawValue }
}

public enum ButtonAction: UInt8, Sendable, CaseIterable, Identifiable {
    case volumeUp = 0
    case volumeDown = 1
    case previousSong = 2
    case nextSong = 3
    case ambientSoundMode = 4
    case voiceAssistant = 5
    case playPause = 6
    case bassUp = 7
    case gamingMode = 9
    public var id: UInt8 { rawValue }

    public static let minimal: [ButtonAction] = [.volumeUp, .volumeDown, .previousSong, .nextSong, .playPause]
    public static let common: [ButtonAction] = [.volumeUp, .volumeDown, .previousSong, .nextSong, .ambientSoundMode, .voiceAssistant, .playPause]
    public static let withoutSoundModes: [ButtonAction] = [.volumeUp, .volumeDown, .previousSong, .nextSong, .voiceAssistant, .playPause]
    public static let withGamingMode: [ButtonAction] = common + [.gamingMode]
}

public struct ButtonKey: Hashable, Sendable {
    public var side: ButtonSide
    public var press: PressKind
    public init(_ side: ButtonSide, _ press: PressKind) {
        self.side = side
        self.press = press
    }
}

public enum EnabledFlagKind: Sendable { case none, single, twsLowBits }
public enum ActionKind: Sendable { case single, twsLowBits }

public enum ButtonDisableMode: Sendable {
    case notDisablable
    case individual
    case disablingOneSideDisablesOther
}

public struct PressSettings: Sendable {
    public let press: PressKind
    public let enabledFlag: EnabledFlagKind
    public let action: ActionKind
    public let buttonID: UInt8
    public let actions: [ButtonAction]
    public let disableMode: ButtonDisableMode
}

public struct ButtonSpec: Sendable {
    /// Order of the buttons in the state packet.
    public let order: [ButtonKey]
    public let presses: [PressSettings]
    /// Disable buttons through action 0xF instead of the enabled flag.
    public let ignoreEnabledFlag: Bool
    public let supportsSetAll: Bool

    public func settings(for press: PressKind) -> PressSettings? { presses.first { $0.press == press } }
    public var pressKinds: [PressKind] { PressKind.allCases.filter { p in order.contains { $0.press == p } } }
}

public enum EnabledStatus: Sendable, Equatable {
    case single(Bool)
    case tws(connected: Bool, disconnected: Bool)

    func current(_ tws: TwsStatus) -> Bool {
        switch self {
        case .single(let e): e
        case let .tws(c, d): tws.isConnected ? c : d
        }
    }

    func withCurrent(_ tws: TwsStatus, _ value: Bool) -> EnabledStatus {
        switch self {
        case .single: .single(value)
        case let .tws(c, d): tws.isConnected ? .tws(connected: value, disconnected: d) : .tws(connected: c, disconnected: value)
        }
    }

    var byte: UInt8 {
        switch self {
        case .single(let e): e ? 1 : 0
        case let .tws(c, d): ((d ? 1 : 0) << 4) | (c ? 1 : 0)
        }
    }
}

public enum ActionStatus: Sendable, Equatable {
    case single(UInt8)
    case tws(connected: UInt8, disconnected: UInt8)

    func current(_ tws: TwsStatus) -> UInt8 {
        switch self {
        case .single(let a): a
        case let .tws(c, d): tws.isConnected ? c : d
        }
    }

    func withCurrent(_ tws: TwsStatus, _ id: UInt8) -> ActionStatus {
        switch self {
        case .single: .single(id)
        case let .tws(c, d): tws.isConnected ? .tws(connected: id, disconnected: d) : .tws(connected: c, disconnected: id)
        }
    }

    var byte: UInt8 {
        switch self {
        case .single(let a): a
        case let .tws(c, d): (d << 4) | c
        }
    }
}

public struct ButtonStatus: Sendable, Equatable {
    public var enabled: EnabledStatus?
    public var action: ActionStatus

    static let disabled: UInt8 = 0xF

    static func read(_ r: inout ByteReader, _ s: PressSettings) throws -> ButtonStatus {
        var enabled: EnabledStatus?
        switch s.enabledFlag {
        case .none: enabled = nil
        case .single: enabled = .single(try r.bool())
        case .twsLowBits:
            let b = try r.u8()
            enabled = .tws(connected: b & 0xF == 1, disconnected: b >> 4 == 1)
        }
        let a = try r.u8()
        let action: ActionStatus = s.action == .single ? .single(a) : .tws(connected: a & 0xF, disconnected: a >> 4)
        return ButtonStatus(enabled: enabled, action: action)
    }

    var bytes: [UInt8] { (enabled.map { [$0.byte] } ?? []) + [action.byte] }

    func isEnabled(_ tws: TwsStatus) -> Bool {
        enabled.map { $0.current(tws) } ?? (action.current(tws) != Self.disabled)
    }

    func withCurrentAction(_ tws: TwsStatus, _ id: UInt8?) -> ButtonStatus {
        if let id {
            return ButtonStatus(enabled: enabled.map { $0.withCurrent(tws, true) }, action: action.withCurrent(tws, id))
        }
        return ButtonStatus(enabled: enabled.map { $0.withCurrent(tws, false) },
                            action: enabled == nil ? action.withCurrent(tws, Self.disabled) : action)
    }
}

public struct ButtonState: Sendable, Equatable {
    public var statuses: [ButtonStatus]

    static func read(_ r: inout ByteReader, spec: ButtonSpec) throws -> ButtonState {
        var statuses: [ButtonStatus] = []
        for key in spec.order {
            guard let s = spec.settings(for: key.press) else { throw ParseError.invalid("button settings") }
            statuses.append(try ButtonStatus.read(&r, s))
        }
        return ButtonState(statuses: statuses)
    }

    public func action(_ key: ButtonKey, spec: ButtonSpec, tws: TwsStatus) -> ButtonAction? {
        guard let i = spec.order.firstIndex(of: key) else { return nil }
        let status = statuses[i]
        let id: UInt8? = spec.ignoreEnabledFlag
            ? status.action.current(tws)
            : (status.isEnabled(tws) ? status.action.current(tws) : nil)
        guard let id, id != ButtonStatus.disabled else { return nil }
        return ButtonAction(rawValue: id)
    }

    /// New state after assigning `action` (nil disables) to a button, following the model's
    /// disable rules.
    public func setting(_ key: ButtonKey, to action: ButtonAction?, spec: ButtonSpec, tws: TwsStatus) -> ButtonState {
        guard let i = spec.order.firstIndex(of: key), let s = spec.settings(for: key.press) else { return self }
        var next = statuses
        let actionID: UInt8? = spec.ignoreEnabledFlag ? (action?.rawValue ?? ButtonStatus.disabled) : action?.rawValue
        switch s.disableMode {
        case .notDisablable:
            if let action { next[i] = next[i].withCurrentAction(tws, action.rawValue) }
        case .individual:
            next[i] = next[i].withCurrentAction(tws, actionID)
        case .disablingOneSideDisablesOther:
            next[i] = next[i].withCurrentAction(tws, actionID)
            if let other = spec.order.firstIndex(where: { $0.press == key.press && $0.side != key.side }) {
                if !next[other].isEnabled(tws) {
                    if let action {
                        let current = next[other].action.current(tws)
                        next[other] = next[other].withCurrentAction(tws, current != ButtonStatus.disabled ? current : action.rawValue)
                    }
                } else if action == nil {
                    next[other] = next[other].withCurrentAction(tws, nil)
                }
            }
        }
        return ButtonState(statuses: next)
    }

    /// Packets that turn `self` into `target`.
    public func packets(to target: ButtonState, spec: ButtonSpec) -> [Packet] {
        let changed = zip(statuses, target.statuses).enumerated().filter { $0.element.0 != $0.element.1 }
        if changed.isEmpty { return [] }
        if spec.supportsSetAll && changed.count > 1 {
            return [Packet(Command(0x04, 0x84), target.statuses.flatMap(\.bytes))]
        }
        var packets: [Packet] = []
        for (i, (current, wanted)) in changed {
            let key = spec.order[i]
            guard let s = spec.settings(for: key.press) else { continue }
            if current.action != wanted.action {
                packets.append(Packet(Commands.setButton, [key.side.rawValue, s.buttonID, wanted.action.byte]))
            }
            if current.enabled != wanted.enabled, let enabled = wanted.enabled {
                packets.append(Packet(Command(0x04, 0x83), [key.side.rawValue, s.buttonID, enabled.byte]))
            }
        }
        return packets
    }
}

extension ButtonSpec {
    static let lr: [ButtonKey] = [.init(.left, .single), .init(.right, .single), .init(.left, .double), .init(.right, .double)]

    static func press(_ press: PressKind, _ enabled: EnabledFlagKind, id: UInt8, _ actions: [ButtonAction],
                      _ disable: ButtonDisableMode = .individual) -> PressSettings {
        PressSettings(press: press, enabledFlag: enabled, action: .twsLowBits, buttonID: id, actions: actions, disableMode: disable)
    }

    /// Single, double, triple and long press with one action byte each (R60i NC, Liberty 5, P40i, P30i).
    static func fourPress(enabled: EnabledFlagKind = .none, ignoreEnabled: Bool, single: [ButtonAction] = ButtonAction.common,
                          tripleBeforeLong: Bool = true) -> ButtonSpec {
        let tail: [ButtonKey] = tripleBeforeLong
            ? [.init(.left, .triple), .init(.right, .triple), .init(.left, .long), .init(.right, .long)]
            : [.init(.left, .long), .init(.right, .long), .init(.left, .triple), .init(.right, .triple)]
        return ButtonSpec(
            order: lr + tail,
            presses: [
                press(.single, enabled, id: 2, single),
                press(.double, enabled, id: 0, ButtonAction.common),
                press(.triple, enabled, id: 5, ButtonAction.common),
                press(.long, enabled, id: 1, ButtonAction.common),
            ],
            ignoreEnabledFlag: ignoreEnabled, supportsSetAll: false)
    }
}
