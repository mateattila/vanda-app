//
//  ImageDownscaler.swift
//  VandaApp
//
//  Közös képkicsinyítő: a tárolt képeknek (téma-háttér, naplófotó) nem kell
//  többmegabájtos eredetinek lenniük — a CloudKit-szinkron és a memória kedvéért.
//

import UIKit

enum ImageDownscaler {

    static func jpegData(from data: Data, maxDimension: CGFloat = 2000, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image.jpegData(compressionQuality: quality) }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
