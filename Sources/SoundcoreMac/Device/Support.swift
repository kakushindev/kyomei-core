import Foundation
import Observation
import ServiceManagement
import SoundcoreKit
import UserNotifications
import WidgetKit

/// User-named EQ curves, kept locally (the device only stores the active one).
@MainActor
@Observable
final class CustomEqualizerStore {
    struct Profile: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
        var bands: [Int16]
    }

    private(set) var profiles: [Profile] = []
    private let key = "customEqualizerProfiles"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = decoded
        }
    }

    func save(name: String, bands: [Int16]) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let i = profiles.firstIndex(where: { $0.name == trimmed }) {
            profiles[i].bands = bands
        } else {
            profiles.append(Profile(name: trimmed, bands: bands))
        }
        persist()
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Posts a notification once when a bud drops to 20 % while not charging.
@MainActor
final class BatteryMonitor {
    private var warned: Set<String> = []
    private var authorized = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "lowBatteryNotifications") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "lowBatteryNotifications") }
    }

    func update(state: DeviceState, deviceName: String) {
        if let right = state.right {
            check("left", state.left, deviceName: deviceName, part: "Left earbud")
            check("right", right, deviceName: deviceName, part: "Right earbud")
        } else {
            check("main", state.left, deviceName: deviceName, part: "Battery")
        }
    }

    private func check(_ key: String, _ battery: Battery, deviceName: String, part: String) {
        if battery.isCharging || battery.percent > 20 {
            warned.remove(key)
            return
        }
        guard isEnabled, !warned.contains(key) else { return }
        warned.insert(key)
        Task { await post(title: "\(deviceName) battery low", body: "\(part) is at \(battery.percent)%.") }
    }

    private func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        if !authorized {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Writes the widget snapshot when it changes and asks WidgetKit to reload, at most every few
/// seconds so slider drags do not burn the reload budget.
@MainActor
final class WidgetBridge {
    private var last: WidgetSnapshot?
    private var reloadTask: Task<Void, Never>?

    func publish(state: DeviceState?, profile: DeviceProfile?, name: String, equalizerName: String?) {
        func level(_ b: Battery?) -> WidgetSnapshot.Level? { b.map { .init(percent: $0.percent, isCharging: $0.isCharging) } }
        var snapshot = WidgetSnapshot(
            deviceName: name, isConnected: state != nil, isHeadphones: state?.model.isHeadphones ?? false,
            left: level(state?.left), right: level(state?.right), caseLevel: level(state?.caseBattery),
            ambientMode: state?.soundModes?.ambient.rawValue,
            availableModes: profile?.soundModes?.ambientModes.map(\.rawValue) ?? [],
            equalizerName: equalizerName, updated: .now)
        if state == nil, let last {
            // Keep the last known levels so the widget can show them greyed out.
            snapshot = WidgetSnapshot(deviceName: last.deviceName, isConnected: false, isHeadphones: last.isHeadphones,
                                      left: last.left, right: last.right, caseLevel: last.caseLevel, ambientMode: nil,
                                      availableModes: [], equalizerName: last.equalizerName, updated: .now)
        }
        var comparable = snapshot
        comparable.updated = last?.updated ?? snapshot.updated
        guard comparable != last else { return }
        last = snapshot
        try? snapshot.save()
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Copies preferences (saved EQ profiles, preferred device, model overrides, app options) from
/// the pre-rebrand bundle identifier the first time Kyōmei launches. Existing keys win.
enum SettingsMigration {
    private static let doneKey = "migratedFromLegacyBundle"

    static func runOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let legacy = defaults.persistentDomain(forName: Brand.legacyBundleIdentifier) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil && !key.hasPrefix("NS") {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
