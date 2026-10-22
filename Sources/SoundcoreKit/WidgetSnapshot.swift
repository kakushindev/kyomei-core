import Foundation

/// What the desktop widget shows. The app writes it whenever the headphones' state changes and
/// the sandboxed widget extension reads it (it has a read-only exception for this folder).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Level: Codable, Equatable, Sendable {
        public var percent: Int
        public var isCharging: Bool
        public init(percent: Int, isCharging: Bool) {
            self.percent = percent
            self.isCharging = isCharging
        }
    }

    public var deviceName: String
    public var isConnected: Bool
    public var isHeadphones: Bool
    public var left: Level?
    public var right: Level?
    public var caseLevel: Level?
    /// `AmbientSoundMode.rawValue`, nil when the model has no sound modes.
    public var ambientMode: UInt8?
    public var availableModes: [UInt8]
    public var equalizerName: String?
    public var updated: Date

    public init(deviceName: String, isConnected: Bool, isHeadphones: Bool, left: Level?, right: Level?, caseLevel: Level?,
                ambientMode: UInt8?, availableModes: [UInt8], equalizerName: String?, updated: Date) {
        self.deviceName = deviceName
        self.isConnected = isConnected
        self.isHeadphones = isHeadphones
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.ambientMode = ambientMode
        self.availableModes = availableModes
        self.equalizerName = equalizerName
        self.updated = updated
    }

    public static let placeholder = WidgetSnapshot(
        deviceName: "soundcore R60i NC", isConnected: true, isHeadphones: false,
        left: Level(percent: 90, isCharging: false), right: Level(percent: 80, isCharging: false),
        caseLevel: Level(percent: 60, isCharging: true), ambientMode: 0, availableModes: [0, 1, 2],
        equalizerName: "Acoustic", updated: .now)

    /// `~/Library/Application Support/Kyomei/widget.json` in the user's real home, which
    /// is also correct from inside the widget's sandbox container.
    public static var fileURL: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/\(Brand.asciiName)/widget.json")
    }

    public static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// URL the widget opens to switch sound mode through the app.
    public static func ambientURL(_ mode: UInt8) -> URL { URL(string: "\(Brand.urlScheme)://ambient/\(mode)")! }
    public static let openURL = URL(string: "\(Brand.urlScheme)://open")!
}
