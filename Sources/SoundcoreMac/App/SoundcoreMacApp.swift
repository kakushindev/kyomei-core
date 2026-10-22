import AppKit
import SoundcoreKit
import SwiftUI

@main
struct SoundcoreMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ViewState private var controller = AppDelegate.controller
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some Scene {
        Window(Brand.name, id: "main") {
            MainView()
                .environment(controller)
        }
        .defaultSize(width: 940, height: 680)
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Headphones") {
                ForEach(Array(AmbientSoundMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.title) { controller.setAmbient(mode) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .disabled(controller.profile?.soundModes?.ambientModes.contains(mode) != true)
                }
                Button("Cycle Sound Mode") { controller.cycleAmbient() }
                    .keyboardShortcut("m", modifiers: .command)
                    .disabled(controller.profile?.soundModes == nil)
                Divider()
                if controller.state?.spatialAudio != nil {
                    Button("Toggle Spatial Audio") {
                        controller.setSpatialAudio(enabled: !(controller.state?.spatialAudio?.isEnabled ?? true))
                    }
                }
                Button("Refresh") { controller.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Reconnect") { controller.connect() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .onChange(of: appearance) { _, new in new.apply() }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(controller)
        } label: {
            MenuBarLabel()
                .environment(controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            AppSettingsView()
                .environment(controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let controller = DeviceController()
    /// Set by a view that has SwiftUI's `openWindow`, since AppKit cannot open a `Window` scene.
    static var openMainWindow: (() -> Void)?

    private var lastOtherApp: NSRunningApplication?
    private var activatedAt: Date?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Handle kyomei:// ourselves. Left to SwiftUI, a URL that no scene claims opens the
        // main window, which is what made widget buttons pop the app up.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
        #endif
        SettingsMigration.runOnce()
        AppAppearance.current.apply()
        Self.applyActivationPolicy(showInDock: UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true)
        Self.controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app == NSRunningApplication.current {
            activatedAt = .now
        } else {
            lastOtherApp = app
            activatedAt = nil
        }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string), Brand.acceptedURLSchemes.contains(url.scheme ?? "") else { return }
        switch url.host {
        case "ambient":
            if let raw = UInt8(url.lastPathComponent), let mode = AmbientSoundMode(rawValue: raw) {
                Self.controller.setAmbient(mode)
            }
            returnFocusIfActivatedByURL()
        default:
            NSApp.activate(ignoringOtherApps: true)
            Self.openMainWindow?()
        }
    }

    /// Opening the URL activates the app; if that is the only reason it is in front, give focus
    /// back to whatever the user was using (usually the desktop).
    private func returnFocusIfActivatedByURL() {
        let handledAt = Date.now
        // In front for a while already: the user is working in the app, leave it alone.
        if NSApp.isActive, let t = activatedAt, handledAt.timeIntervalSince(t) > 1.5 { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, NSApp.isActive, let t = self.activatedAt,
                  abs(t.timeIntervalSince(handledAt)) < 2 else { return }
            self.lastOtherApp?.activate()
        }
    }

    static func applyActivationPolicy(showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock { NSApp.activate(ignoringOtherApps: true) }
    }
}
