import AppKit
import SoundcoreKit
import SwiftUI

/// The macOS 27 SDK also declares `State` as a macro whose plugin ships only with Xcode, so a
/// Command Line Tools build resolves the property wrapper through this alias instead.
typealias ViewState = SwiftUI.State

// MARK: - Palette

extension AmbientSoundMode {
    var tint: Color {
        switch self {
        case .noiseCanceling: Color(red: 0.36, green: 0.40, blue: 0.98)
        case .transparency: Color(red: 0.10, green: 0.74, blue: 0.70)
        case .normal: Color(red: 0.55, green: 0.58, blue: 0.66)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .noiseCanceling:
            LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 1.0), Color(red: 0.16, green: 0.52, blue: 1.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .transparency:
            LinearGradient(colors: [Color(red: 0.06, green: 0.78, blue: 0.62), Color(red: 0.10, green: 0.62, blue: 0.92)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .normal:
            LinearGradient(colors: [Color(red: 0.52, green: 0.56, blue: 0.66), Color(red: 0.38, green: 0.42, blue: 0.52)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

func batteryTint(_ battery: Battery?) -> Color {
    guard let battery else { return .secondary }
    if battery.isCharging { return .green }
    return battery.percent <= 20 ? .red : battery.percent <= 40 ? .orange : .green
}

// MARK: - Glass

/// Debug-only switch used by the snapshot renderer (SOUNDCORE_SNAPSHOT_SOLID=1).
enum RenderStyle {
    nonisolated(unsafe) static var solidPanels = false
}

extension View {
    /// Liquid Glass panel on macOS 26+, translucent material before that.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        if RenderStyle.solidPanels {
            // Offscreen captures cannot composite glass; draw a solid stand-in instead.
            self
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
        } else if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint?.opacity(0.18)).interactive(interactive),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    /// Plain rounded surface for dense content inside a panel.
    func inset(cornerRadius: CGFloat = 14) -> some View {
        background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

/// Section heading used inside panels.
struct PanelTitle: View {
    let title: String
    var symbol: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            Spacer()
            if let trailing { Text(trailing).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Visibility

/// True while the hosting window is on screen and not fully covered. Used to pause continuous
/// animations so a hidden window costs nothing.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = VisibilityView()
        view.onChange = { visible in
            DispatchQueue.main.async { if isVisible != visible { isVisible = visible } }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            guard let window else {
                onChange?(false)
                return
            }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            report()
        }

        private func report() {
            onChange?(window?.occlusionState.contains(.visible) ?? false)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let token {
                NotificationCenter.default.removeObserver(token)
                self.token = nil
            }
        }
    }
}

extension View {
    func trackWindowVisibility(_ isVisible: Binding<Bool>) -> some View {
        background(WindowVisibilityReader(isVisible: isVisible).frame(width: 0, height: 0))
    }
}

// MARK: - Appearance

/// App-wide light/dark override, applied to every window including the menu bar panel.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    static let storageKey = "appearance"

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
