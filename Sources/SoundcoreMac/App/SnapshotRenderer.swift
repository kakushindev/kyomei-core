#if DEBUG
import AppKit
import SoundcoreKit
import SwiftUI

/// Debug-only: `SOUNDCORE_SNAPSHOT=<dir> SoundcoreMac` renders every pane offscreen for a few
/// models (light and dark) and exits. Used to check layouts without a device.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["SOUNDCORE_SNAPSHOT"] else { return false }
        let controller = AppDelegate.controller
        RenderStyle.solidPanels = ProcessInfo.processInfo.environment["SOUNDCORE_SNAPSHOT_SOLID"] == "1"
        let samples: [(String, DeviceModel, String, String)] = [
            ("r60i", .d1202, "soundcore R60i NC", r60i),
            ("liberty4nc", .a3947, "soundcore Liberty 4 NC", liberty4NC),
            ("q45", .a3040, "soundcore Space Q45", spaceQ45),
        ]
        for (tag, model, name, hex) in samples {
            var state = try! DeviceProfile.profile(for: model).parse(bytes(hex))
            // The samples are real captures; never publish a device's serial number or address.
            state.serialNumber = String(model.rawValue.dropFirst()) + String(repeating: "0", count: 12)
            if tag == "r60i" {
                state.right?.isCharging = true
                state.right?.rawLevel = 4
                state.soundModes?.ambient = .noiseCanceling
            }
            controller.loadPreview(state: state, endpoint: SoundcoreEndpoint(
                address: "00-00-00-00-00-00", name: name, channelID: 15, modelCode: "1202c"))
            let panes: [(String, AnyView, CGSize)] = [
                ("overview", AnyView(OverviewView()), CGSize(width: 760, height: 860)),
                ("soundmodes", AnyView(SoundModesView()), CGSize(width: 760, height: 760)),
                ("equalizer", AnyView(EqualizerView()), CGSize(width: 760, height: 980)),
                ("controls", AnyView(ControlsView()), CGSize(width: 760, height: 460)),
                ("device", AnyView(DeviceSettingsView()), CGSize(width: 700, height: 980)),
                ("menubar", AnyView(MenuBarView()), CGSize(width: 320, height: 420)),
                ("main", AnyView(MainView()), CGSize(width: 1000, height: 720)),
            ] + (tag == "r60i" ? [
                ("spatial", AnyView(SpatialAudioView()), CGSize(width: 700, height: 420)),
                ("multipoint", AnyView(ConnectionsView()), CGSize(width: 700, height: 300)),
                ("settings", AnyView(AppSettingsView()), CGSize(width: 440, height: 600)),
            ] : [])
            for (name, view, size) in panes {
                for dark in [false, true] where dark || tag == "r60i" || name == "overview" {
                    render(view.environment(controller), size: size, dark: dark,
                           to: URL(fileURLWithPath: dir).appendingPathComponent("\(tag)-\(name)-\(dark ? "dark" : "light").png"))
                }
            }
        }
        exit(0)
    }

    private static func render<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    private static func bytes(_ s: String) -> [UInt8] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { UInt8($0, radix: 16) }
    }

    private static let r60i = """
        01 01 09 09 00 00 30 33 2e 38 39 30 33 2e 38 39 31 32 30 32 30 30 30 30 30 30 30 30 30 30 30 30
        30 33 2e 38 39 03 01 00 a0 82 8c 8c a0 a0 a0 8c 78 00 ff ff ff ff ff ff ff ff ff ff ff 00 ff ff ff ff ff ff ff ff ff 00
        ff ff ff ff ff ff ff ff ff 00 00 00 00 00 00 ff ff ff ff ff ff ff ff ff 00 ff ff ff ff ff ff ff ff ff 00 00 00 0a ff ff
        63 66 ff ff 44 44 33 01 50 00 00 00 00 00 00 31 01 01 00 01 01 02 00 5a 00 00 00 01 00 00 00 00 00 00 00 ff ff ff ff ff
        """

    private static let liberty4NC = """
        01 01 02 04 00 00 30 35 2e 38 38 30 35 2e 38 38 33 39 34 37 42 36 36 32 46 44 43 43 45 45 45 38 30 30 2e 30 30 fe fe 78
        78 78 78 78 78 78 78 78 78 ff ff ff ff ff ff ff ff ff ff 00 01 70 75 8c 94 96 8e 86 83 3c 3c 70 75 8c 94 96 8e 86 83 3c
        3c 68 64 22 40 00 70 75 8c 94 96 8e 86 83 3c 3c 70 75 8c 94 96 8e 86 83 3c 3c 00 00 12 11 66 11 65 11 32 11 33 11 44 11
        44 00 21 00 20 35 00 50 01 00 01 01 03 00 00 00 00 ff 01 02 31 01 00 00 01 00 00 01 00 01 50 01 00 00 01 01 01 01 ff
        """

    private static let spaceQ45 = """
        03 ff 30 32 2e 33 34 33 30 34 30 31 41 31 41 32 46 43 43 45 45 45 38 11 00 96 8c 6e 6e 82 96 a0 aa 78 00 7a 7a 76 77 79
        7a 7a 7e 78 00 04 04 07 07 00 50 00 01 00 05 ff 00 00 ff 00 31 00 01 ff 00 01 00 00 5a 00 01 01 01 00 11 32 01 01 8f 8f
        80 8a 96 96 8f 8f 3c 3c 8f 8f 80 8a 96 96 8f 8f 3c 3c 64 98 8c cd 00 8f 8f 80 8a 96 96 8f 8f 3c 3c 00 00 00 00 00 00 00
        00 00 00 7a 7a 77 79 7a 7a 79 7b 72 00 11 00 00 00 00 00 00 00 00
        """
}
#endif
