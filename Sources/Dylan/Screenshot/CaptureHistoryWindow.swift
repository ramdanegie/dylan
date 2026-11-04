import AppKit
import DylanCore
import SwiftUI

/// Capture History… (design D38/D43): recent originals; click opens Studio, the menu copies, pins, reveals or deletes.
enum CaptureHistoryWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = L("shot.history")
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: CaptureHistoryView().artWindow())
        Art.style(w)
        w.center()
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct CaptureHistoryView: View {
    @StateBox private var items: [URL] = ScreenshotService.shared.history

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text(L("shot.historyEmpty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(items, id: \.self) { u in
                            VStack(spacing: 4) {
                                CaptureThumbnail(url: u).frame(height: 110)
                                Text(u.deletingPathExtension().lastPathComponent).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            }
                            .onTapGesture { StudioWindow.open(u) }
                            .onDrag { NSItemProvider(contentsOf: u) ?? NSItemProvider() }
                            .contextMenu {
                                Button(L("shot.copy")) { if let i = NSImage(contentsOf: u).flatMap(VisionTools.cgImage) { ScreenshotService.shared.copy(i) } }
                                Button(L("shot.annotate")) { StudioWindow.open(u, annotate: true) }
                                Button(L("shot.pin")) { PinWindow.pin(u) }
                                Button(L("shelf.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                                Divider()
                                Button(L("shot.delete"), role: .destructive) { try? FileManager.default.removeItem(at: u); reload() }
                            }
                        }
                    }
                    .padding(14)
                }
            }
            Divider()
            HStack {
                let bytes = items.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                let s = CaptureStore.summary(count: items.count, bytes: bytes)
                Text(L("shot.historySummary", s.count, s.megabytes)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("shot.clearHistory"), role: .destructive) { ScreenshotService.shared.clearHistory(); reload() }.disabled(items.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func reload() { items = ScreenshotService.shared.history }
}

struct CaptureThumbnail: View {
    var url: URL
    var body: some View {
        Group {
            if let img = NSImage(contentsOf: url) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit) } else { Color.gray.opacity(0.2) }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
