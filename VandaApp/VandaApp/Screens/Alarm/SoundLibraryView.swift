//
//  SoundLibraryView.swift
//  VandaApp
//
//  Zenetár-képernyő (spec 4.1): fájlimport a Files appból, hangfelvétel
//  (pl. családtag hangja), előhallgatás, törlés, és hang kiválasztása az
//  ébresztőhöz.
//

import AVFoundation
import SwiftUI

struct SoundLibraryView: View {
    /// Az ébresztő-szerkesztő kiválasztott hangja; nil = alapértelmezett hang
    @Binding var selectedFileName: String?
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    @State private var files: [String] = []
    @State private var isImporterPresented = false
    @State private var importError: String?

    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var player: AVAudioPlayer?
    @State private var playingFile: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        actionButtons

                        if let importError {
                            Text(importError)
                                .font(.vandaCaption())
                                .foregroundStyle(Color.zoneRedStrong)
                        }

                        soundRow(name: nil)
                        ForEach(files, id: \.self) { file in
                            soundRow(name: file)
                        }

                        Text("Tipp: Apple Music-számot (DRM) nem lehet ébresztőnek használni — csak saját fájlt vagy felvételt.")
                            .font(.vandaCaption())
                            .foregroundStyle(Color.inkFaint)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle("Zenetár")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
            .onAppear { files = SoundLibrary.fileNames() }
            .onDisappear { stopPlayback(); stopRecording(save: false) }
        }
    }

    // MARK: - Műveletek

    private var actionButtons: some View {
        HStack(spacing: Theme.Spacing.cardGap) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Fájl importálása", systemImage: "folder")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .softShadow()
            }
            .buttonStyle(.plain)

            Button {
                isRecording ? stopRecording(save: true) : startRecording()
            } label: {
                Label(isRecording ? "Felvétel leállítása" : "Hangfelvétel", systemImage: isRecording ? "stop.fill" : "mic.fill")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(isRecording ? .white : Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        isRecording ? Color.zoneRedStrong : Color.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )
                    .softShadow()
            }
            .buttonStyle(.plain)
        }
    }

    private func soundRow(name: String?) -> some View {
        let isSelected = selectedFileName == name
        return HStack(spacing: 10) {
            Button {
                if let name {
                    playingFile == name ? stopPlayback() : play(name)
                }
            } label: {
                Image(systemName: name == nil ? "bell.fill" : (playingFile == name ? "pause.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 22))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .disabled(name == nil)

            Text(name ?? "Alapértelmezett csörgés")
                .font(.vandaBody())
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
            }
        }
        .padding(12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
        .softShadow()
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFileName = name
        }
        .contextMenu {
            if let name {
                Button(role: .destructive) {
                    stopPlayback()
                    SoundLibrary.delete(name)
                    if selectedFileName == name { selectedFileName = nil }
                    files = SoundLibrary.fileNames()
                } label: {
                    Label("Törlés", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Import / felvétel / lejátszás

    private func importFiles(_ result: Result<[URL], Error>) {
        importError = nil
        guard case .success(let urls) = result else { return }
        for url in urls {
            do {
                try SoundLibrary.importFile(from: url)
            } catch {
                importError = "Nem sikerült importálni: \(url.lastPathComponent)"
            }
        }
        files = SoundLibrary.fileNames()
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            Task { @MainActor in
                guard granted else {
                    importError = "A mikrofon-engedély hiányzik — a rendszer-Beállításokban tudod bekapcsolni."
                    return
                }
                do {
                    try session.setCategory(.playAndRecord, mode: .default)
                    try session.setActive(true)
                    let url = SoundLibrary.newRecordingURL()
                    recorder = try AVAudioRecorder(url: url, settings: SoundLibrary.recorderSettings)
                    recorder?.record()
                    isRecording = true
                } catch {
                    importError = "Nem sikerült elindítani a felvételt."
                }
            }
        }
    }

    private func stopRecording(save: Bool) {
        guard let recorder else { return }
        recorder.stop()
        if !save {
            try? FileManager.default.removeItem(at: recorder.url)
        }
        self.recorder = nil
        isRecording = false
        files = SoundLibrary.fileNames()
    }

    private func play(_ name: String) {
        stopPlayback()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        player = try? AVAudioPlayer(contentsOf: SoundLibrary.url(for: name))
        player?.play()
        playingFile = name
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingFile = nil
    }
}

#Preview {
    SoundLibraryView(selectedFileName: .constant(nil), accent: Theme.Accent.default)
}
