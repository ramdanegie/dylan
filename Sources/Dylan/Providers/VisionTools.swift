import AppKit
import AVFoundation
import CoreImage
import DylanCore
import Vision

/// On-device image tools: copy text (FR-87) and remove background (FR-77). Nothing leaves the Mac.
enum VisionTools {
    /// Recognises text (Indonesian + English) and copies it. Returns the text, or nil when none was found.
    static func copyText(from image: CGImage) async -> String? {
        let text: String? = await Task.detached {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["id-ID", "en-US"]
            req.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([req])
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.value
        if let text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return text
    }

    /// Writes "<name> (no background).png" next to the original and returns its URL.
    static func removeBackground(_ url: URL) async -> URL? {
        await Task.detached { () -> URL? in
            guard let ci = CIImage(contentsOf: url) else { return nil }
            let req = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ci)
            guard (try? handler.perform([req])) != nil, let result = req.results?.first,
                  let mask = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else { return nil }
            let maskImage = CIImage(cvPixelBuffer: mask)
            let out = ci.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: maskImage])
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(out, from: ci.extent) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent + " (no background).png"
            let dest = url.deletingLastPathComponent().appendingPathComponent(name)
            guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]), (try? data.write(to: dest)) != nil else { return nil }
            return dest
        }.value
    }

    static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func isImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"].contains((path as NSString).pathExtension.lowercased())
    }
}

/// Front camera preview to check how you look before a meeting (FR-79). Only while the panel is open,
/// at most 60 s, built-in camera only; nothing is recorded.
final class MirrorCamera {
    static let shared = MirrorCamera()
    let session = AVCaptureSession()
    private var stopWork: DispatchWorkItem?
    private(set) var running = false

    func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            Task { @MainActor in MirrorCamera.shared.begin() }
        }
    }

    private func begin() {
        guard let cam = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.first,
              let input = try? AVCaptureDeviceInput(device: cam) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { @Sendable in s.startRunning() }
        running = true
        AppModel.shared.mirrorOn = true
        let w = DispatchWorkItem { MainActor.assumeIsolated { MirrorCamera.shared.stop() } }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: w)
    }

    func stop() {
        stopWork?.cancel()
        guard running else { return }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { @Sendable in s.stopRunning() }
        running = false
        AppModel.shared.mirrorOn = false
    }
}

/// Scratchpad (FR-46): one plain-text note, saved as you type (0600).
enum Scratchpad {
    static var url: URL { Bridge.socketURL.deletingLastPathComponent().appendingPathComponent("scratchpad.txt") }
    static func load() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    static func save(_ s: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? s.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o600)
    }
}
