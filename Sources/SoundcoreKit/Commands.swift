import Foundation

/// Command identifiers shared across models. Model specific ones live in `DeviceProfile`.
public enum Commands {
    // Inbound
    public static let state = Command(0x01, 0x01)
    public static let twsStatusUpdate = Command(0x01, 0x02)
    public static let batteryLevelUpdate = Command(0x01, 0x03)
    public static let batteryChargingUpdate = Command(0x01, 0x04)
    public static let ldacState = Command(0x01, 0x7F)
    public static let soundModesUpdate = Command(0x06, 0x01)
    public static let dualConnectionDevices = Command(0x0B, 0x01)

    // Outbound
    public static let setSoundModes = Command(0x06, 0x81)
    public static let setSoundModeCycle = Command(0x06, 0x82)
    public static let setEqualizerBasic = Command(0x02, 0x81)
    public static let setEqualizerDRC = Command(0x02, 0x83)
    public static let setEqualizerHearID = Command(0x03, 0x87)
    public static let setSpatialAudio = Command(0x10, 0x81)
    public static let setButton = Command(0x04, 0x81)
    public static let resetButtons = Command(0x04, 0x82)
    public static let setDualConnections = Command(0x0B, 0x84)
    public static let dualConnectionDisconnect = Command(0x0B, 0x81)
    public static let dualConnectionConnect = Command(0x0B, 0x82)
    public static let setAutoPowerOff = Command(0x01, 0x86)
    public static let setLimitHighVolume = Command(0x20, 0x82)
    public static let setLimitHighVolumeRefreshRate = Command(0x20, 0x81)

    public static func requestState() -> Packet { Packet(state) }
    public static func requestLdacState() -> Packet { Packet(ldacState) }
    public static func requestDualConnectionDevices() -> Packet { Packet(dualConnectionDevices) }

    static func soundModes(_ body: [UInt8]) -> Packet { Packet(setSoundModes, body) }

    public static func flag(_ command: Command, _ value: Bool) -> Packet { Packet(command, [value ? 1 : 0]) }

    public static func soundModeCycle(_ cycle: AmbientSoundModeCycle) -> Packet { Packet(setSoundModeCycle, [cycle.byte]) }

    public static func spatialAudio(_ spatial: SpatialAudio) -> Packet {
        Packet(setSpatialAudio, [spatial.isEnabled ? 1 : 0, 0, spatial.mode.rawValue])
    }

    /// Space Q45 / Space One double press: bass up or nothing.
    public static func bassUpButton(_ enabled: Bool) -> Packet {
        Packet(setButton, [0, 0, enabled ? ButtonAction.bassUp.rawValue : 0x0F])
    }

    public static func autoPowerOff(_ value: AutoPowerOff) -> Packet {
        Packet(setAutoPowerOff, [value.isEnabled ? 1 : 0, value.durationIndex])
    }

    public static func limitHighVolume(_ value: LimitHighVolume) -> Packet {
        Packet(setLimitHighVolume, [value.isEnabled ? 1 : 0, value.dbLimit])
    }

    public static func limitHighVolumeRefreshRate(_ rate: DecibelRefreshRate) -> Packet {
        Packet(setLimitHighVolumeRefreshRate, [rate.rawValue])
    }

    public static func dualConnection(connect: Bool, mac: [UInt8]) -> Packet {
        Packet(connect ? dualConnectionConnect : dualConnectionDisconnect, mac)
    }
}
