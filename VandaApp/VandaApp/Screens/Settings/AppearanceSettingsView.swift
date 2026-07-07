//
//  AppearanceSettingsView.swift
//  VandaApp
//
//  Beállítások › Kinézet (design-tokens 5. fejezet): élő előnézet, háttérválasztó
//  (gradiensek + fotó, Csere/Törlés), kiemelőszín (presetek + natív color picker).
//  Minden azonnal a ThemeSettings-be perzisztálódik (SwiftData → CloudKit).
//

import SwiftUI
import SwiftData
import PhotosUI

struct AppearanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var themeSettings: [ThemeSettings]

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    previewTile
                    sectionLabel("Háttér")
                    backgroundPicker
                    if theme?.usesPhotoBackground == true {
                        photoActions
                    }
                    sectionLabel("Kiemelőszín")
                    accentPicker
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
        .navigationTitle("Kinézet")
        .navigationBarTitleDisplayMode(.large)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoPickerItem,
            matching: .images
        )
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await applyPhoto(from: newItem) }
        }
    }

    /// A meglévő beállítás-rekord, vagy első módosításkor egy új alapértelmezett.
    private func editableSettings() -> ThemeSettings {
        ThemeSettings.ensureCurrent(in: modelContext)
    }

    // MARK: - Élő előnézet

    private var previewTile: some View {
        ZStack(alignment: .topLeading) {
            ThemedBackgroundPreview(settings: theme)

            VStack(alignment: .leading, spacing: 10) {
                Text("Előnézet")
                    .font(.vandaLabel(10))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color.surface, in: Capsule())
                    .softShadow()

                Spacer()

                HStack(spacing: 10) {
                    Circle()
                        .fill(accent)
                        .frame(width: 26, height: 26)
                    Capsule()
                        .fill(Color.surfaceTint)
                        .frame(width: 64, height: 10)
                    Spacer()
                }
                .padding(10)
                .background(
                    (theme?.cardSurface ?? .surface),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                )
            }
            .padding(12)
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.hairline)
        )
        .softShadow()
    }

    // MARK: - Háttér

    private var backgroundPicker: some View {
        HStack(spacing: 12) {
            ForEach(Theme.BackgroundGradient.allCases) { gradient in
                Button {
                    let settings = editableSettings()
                    settings.gradient = gradient
                    settings.backgroundKind = .gradient
                } label: {
                    RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                        .fill(gradient.gradient)
                        .frame(width: 52, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                                .strokeBorder(
                                    isSelected(gradient) ? Color.ink : Color.hairline,
                                    lineWidth: isSelected(gradient) ? 2.5 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(gradient.displayName) háttér")
            }

            Button {
                isPhotoPickerPresented = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: theme?.usesPhotoBackground == true ? "photo.fill" : "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Fotó")
                        .font(.vandaCaption(10))
                }
                .foregroundStyle(theme?.usesPhotoBackground == true ? accent : Color.inkFaint)
                .frame(width: 52, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                        .strokeBorder(
                            theme?.usesPhotoBackground == true ? Color.ink : Color.inkFaint,
                            style: StrokeStyle(
                                lineWidth: theme?.usesPhotoBackground == true ? 2.5 : 1.5,
                                dash: theme?.usesPhotoBackground == true ? [] : [5]
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fotó-háttér választása")
        }
    }

    private func isSelected(_ gradient: Theme.BackgroundGradient) -> Bool {
        let settings = theme
        let usesGradient = settings == nil || settings?.usesPhotoBackground == false
        return usesGradient && (settings?.gradient ?? .default) == gradient
    }

    private var photoActions: some View {
        HStack(spacing: Theme.Spacing.cardGap) {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label("Csere", systemImage: "photo.on.rectangle.angled")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, Theme.Spacing.chipVertical)
                    .padding(.horizontal, Theme.Spacing.chipHorizontal)
                    .background(theme?.cardSurface ?? .surface, in: Capsule())
                    .softShadow()
            }
            .buttonStyle(.plain)

            Button {
                let settings = editableSettings()
                settings.photoData = nil
                settings.backgroundKind = .gradient
            } label: {
                Label("Törlés", systemImage: "trash")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.zoneRedStrong)
                    .padding(.vertical, Theme.Spacing.chipVertical)
                    .padding(.horizontal, Theme.Spacing.chipHorizontal)
                    .background(theme?.cardSurface ?? .surface, in: Capsule())
                    .softShadow()
            }
            .buttonStyle(.plain)
        }
    }

    private func applyPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let downscaled = ImageDownscaler.jpegData(from: data) else { return }
        let settings = editableSettings()
        settings.photoData = downscaled
        settings.backgroundKind = .photo
        photoPickerItem = nil
    }

    // MARK: - Kiemelőszín

    private var accentPicker: some View {
        HStack(spacing: 12) {
            ForEach(Theme.Accent.presetHexes, id: \.self) { hex in
                Button {
                    editableSettings().accentHex = Int(hex)
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 38, height: 38)
                        .overlay {
                            if (theme?.accentHex ?? Int(Theme.Accent.defaultHex)) == Int(hex) {
                                Circle().strokeBorder(Color.ink, lineWidth: 2.5).padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            ColorPicker(
                "Saját kiemelőszín",
                selection: Binding(
                    get: { accent },
                    set: { editableSettings().accentColor = $0 }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .vandaLabelStyle()
            .foregroundStyle(Color.inkFaint)
            .padding(.top, 4)
    }
}

/// Az előnézet-csempe háttere — a ThemedBackground kicsiben, ignoresSafeArea nélkül.
private struct ThemedBackgroundPreview: View {
    let settings: ThemeSettings?

    var body: some View {
        if let settings, settings.usesPhotoBackground,
           let data = settings.photoData, let image = UIImage(data: data) {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .overlay(Theme.Gradients.photoOverlay)
        } else {
            (settings?.gradient ?? .default).gradient
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .modelContainer(VandaStore.makeContainer())
}
