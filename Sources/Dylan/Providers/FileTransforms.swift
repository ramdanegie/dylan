import AppKit
import AVFoundation
import DylanCore
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Shelf file transforms (FR-43): convert/resize images, merge PDFs, compress video. All local;
/// results are written next to the originals and added to the shelf.
enum FileTransforms {
    nonisolated enum ImageFormat: Sendable { case png, jpeg }

    static func isPDF(_ p: String) -> Bool { (p as NSString).pathExtension.lowercased() == "pdf" }
    static func isVideo(_ p: String) -> Bool { ["mov", "mp4", "m4v"].contains((p as NSString).pathExtension.lowercased()) }

    /// Converts and optionally scales an image with ImageIO.
    static func convert(_ url: URL, to format: ImageFormat, scale: CGFloat = 1) async -> URL? {
        await Task.detached { () -> URL? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: max(w, h) * scale]
            guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            let ext = format == .png ? "png" : "jpg"
            let suffix = scale < 1 ? " (\(Int(scale * 100))%)" : ""
            let dest = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + suffix + "." + ext)
            let type = (format == .png ? UTType.png : UTType.jpeg).identifier as CFString
            guard let out = CGImageDestinationCreateWithURL(dest as CFURL, type, 1, nil) else { return nil }
            CGImageDestinationAddImage(out, img, format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary : nil)
            return CGImageDestinationFinalize(out) ? dest : nil
        }.value
    }

    /// Merges PDFs in shelf order into "Merged <date>.pdf" next to the first one.
    static func mergePDFs(_ urls: [URL]) async -> URL? {
        guard urls.count >= 2, let first = urls.first else { return nil }
        return await Task.detached { () -> URL? in
            let out = PDFDocument()
            for u in urls {
                guard let doc = PDFDocument(url: u) else { continue }
                for i in 0..<doc.pageCount { if let p = doc.page(at: i) { out.insert(p, at: out.pageCount) } }
            }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
            let dest = first.deletingLastPathComponent().appendingPathComponent("Merged \(f.string(from: Date())).pdf")
            return out.pageCount > 0 && out.write(to: dest) ? dest : nil
        }.value
    }

    /// HEVC 1080p export with AVFoundation.
    static func compressVideo(_ url: URL) async -> URL? {
        let dest = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + " (compressed).mp4")
        try? FileManager.default.removeItem(at: dest)
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVC1920x1080) else { return nil }
        do { try await session.export(to: dest, as: .mp4) } catch { return nil }
        return dest
    }
}
