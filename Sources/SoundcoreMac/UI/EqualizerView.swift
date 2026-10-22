import SoundcoreKit
import SwiftUI

struct EqualizerView: View {
    @Environment(DeviceController.self) private var controller
    @ViewState private var bands: [Int16] = Array(repeating: 0, count: 8)
    @ViewState private var isEditing = false
    @ViewState private var showingSave = false
    @ViewState private var profileName = ""

    private let columns = [GridItem(.adaptive(minimum: 136), spacing: 8)]

    var body: some View {
        if let s = controller.state, let eq = s.equalizer, let spec = controller.profile?.equalizer {
            let locked = spec.requiresBothEarbuds && s.tws?.isConnected == false
            let editable = spec.allowsCustom && !locked
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(controller.equalizerName(s) ?? "Equalizer").font(.title3.weight(.semibold))
                                    .contentTransition(.opacity)
                                Text(hint(s, spec, locked: locked)).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if spec.allowsCustom {
                                Button("Reset") { commit(Array(repeating: 0, count: 8)) }
                                    .disabled(!editable || (bands.allSatisfy { $0 == 0 } && eq.isCustom))
                                Button("Save…") {
                                    profileName = ""
                                    showingSave = true
                                }
                                .disabled(!editable)
                            }
                        }
                        ZStack {
                            // Inset so the curve's points sit on the slider knobs.
                            GeometryReader { geo in
                                EqualizerCurve(tenths: bands)
                                    .padding(.horizontal, geo.size.width / 16)
                                    .padding(.vertical, 28)
                            }
                            .allowsHitTesting(false)
                            HStack(spacing: 0) {
                                ForEach(0..<8, id: \.self) { i in
                                    BandSlider(
                                        tenths: Binding(get: { bands[i] }, set: { v in
                                            isEditing = true
                                            bands[i] = v
                                            controller.setCustomBands(bands)
                                        }),
                                        frequency: equalizerFrequencies[i],
                                        isEnabled: editable,
                                        onCommit: { isEditing = false })
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(height: 240)
                    }
                    .padding(18)
                    .glassPanel(cornerRadius: 24)

                    if spec.allowsCustom, !controller.customProfiles.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("My Profiles").font(.headline)
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(controller.customProfiles.profiles) { profile in
                                    PresetChip(title: profile.name, tenths: profile.bands,
                                               isSelected: eq.isCustom && eq.visible == profile.bands) {
                                        commit(profile.bands)
                                    }
                                    .disabled(!editable)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) { controller.customProfiles.delete(profile) }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Presets").font(.headline)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(spec.presets) { preset in
                                PresetChip(title: preset.name, tenths: Array(preset.bands.prefix(8)),
                                           isSelected: !eq.isCustom && eq.presetID == preset.id) {
                                    controller.selectPreset(preset)
                                }
                                .disabled(locked)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
            }
            .onAppear { bands = eq.visible }
            .onChange(of: eq.visible) { _, new in
                if !isEditing { withAnimation(.smooth) { bands = new } }
            }
            .sheet(isPresented: $showingSave) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Save Custom EQ").font(.headline)
                    TextField("Profile name", text: $profileName).frame(width: 260)
                        .onSubmit(saveProfile)
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { showingSave = false }
                        Button("Save", action: saveProfile)
                            .keyboardShortcut(.defaultAction)
                            .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(20)
            }
        }
    }

    private func hint(_ s: DeviceState, _ spec: EqualizerSpec, locked: Bool) -> String {
        if locked { return "Put both earbuds in to change the equalizer." }
        if !spec.allowsCustom { return "This model only supports the built-in presets." }
        if s.spatialAudio?.isEnabled == true { return "Spatial audio is on. Changing the EQ turns it off." }
        return "Drag a band to shape your sound. Double-click a band to reset it."
    }

    private func saveProfile() {
        controller.customProfiles.save(name: profileName, bands: bands)
        showingSave = false
    }

    private func commit(_ values: [Int16]) {
        withAnimation(.smooth) { bands = values }
        controller.setCustomBands(values)
    }
}

private struct PresetChip: View {
    let title: String
    let tenths: [Int16]
    let isSelected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                EqualizerCurve(tenths: tenths, showGrid: false)
                    .frame(height: 22)
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                          : AnyShapeStyle(.quaternary.opacity(hovering ? 0.8 : 0.45)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .scaleEffect(hovering ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.18)) { hovering = h } }
        .animation(.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
