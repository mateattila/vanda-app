//
//  SoundLibrary.swift
//  VandaApp
//
//  Zenetár (spec 4.1): Files appból importált hangfájlok és appban rögzített
//  felvételek a Library/Sounds mappában — innen tudja az AlarmKit név szerint
//  megszólaltatni őket. Csak lokális fájl játszható le (DRM-es stream nem).
//

import AVFoundation
import Foundation

enum SoundLibrary {

    static var soundsDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        return sounds
    }

    /// A könyvtár tartalma (fájlnevek), névsorban.
    static func fileNames() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory, includingPropertiesForKeys: nil)) ?? []
        return contents.map(\.lastPathComponent).sorted()
    }

    /// Importált fájl bemásolása; ütköző névnél sorszámoz. A formátum-konverzió
    /// későbbi kör (docs/decisions.md) — mp3/m4a/wav közvetlenül működik.
    @discardableResult
    static func importFile(from source: URL) throws -> String {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        var name = source.lastPathComponent
        var destination = soundsDirectory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            name = "\(base)-\(counter).\(ext)"
            destination = soundsDirectory.appendingPathComponent(name)
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return name
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: soundsDirectory.appendingPathComponent(fileName))
    }

    static func url(for fileName: String) -> URL {
        soundsDirectory.appendingPathComponent(fileName)
    }

    /// Új felvétel cél-URL-je (m4a/AAC).
    static func newRecordingURL() -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day().timeSeparator(.omitted).time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        return soundsDirectory.appendingPathComponent("Felvetel-\(stamp).m4a")
    }

    static let recorderSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
}
