import AppKit
import DylanCore
import SwiftUI
import UniformTypeIdentifiers

/// Expanded → Shelf (design D10): grid, drop zone, per-item actions.
struct ShelfTab: View {
    @StateBox private var selected: UUID?
    @StateBox private var targeted = false
    private var provider: ShelfProvider { ShelfProvider.shared }
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if provider.shelf.items.isEmpty || targeted {
                dropZone
            } else {
                HStack {
                    SwiftUI.Text(L("shelf.count", provider.shelf.items.count)).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                    Spacer()
                    NotchButton(title: L("shelf.dragAll")) {}
                        .onDrag { allItemsProvider() }
                    NotchButton(title: L("shelf.clear"), kind: .quiet) { provider.clear() }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 10) { ForEach(provider.shelf.items) { tile($0) } }
                }
                .scrollIndicators(.never)
                if let item = provider.shelf.items.first(where: { $0.id == selected }) ?? provider.shelf.items.first {
                    actions(item)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in ShelfDrop.accept(providers); return true }
        .onAppear { provider.refreshMissing(); provider.loadThumbnails() }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: targeted ? "plus.circle.fill" : "tray.and.arrow.down").font(.system(size: 22)).foregroundStyle(targeted ? .white : DY.fg2)
            SwiftUI.Text(targeted ? L("shelf.dropHere") : L("shelf.empty")).font(DY.font(12.5, .semibold)).foregroundStyle(.white)
            SwiftUI.Text(targeted ? L("shelf.reference") : L("shelf.cli")).font(DY.mono).foregroundStyle(DY.fg2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(targeted ? Color.white.opacity(0.6) : Color.white.opacity(0.2)))
    }

    private func tile(_ item: Shelf.Item) -> some View {
        let gone = provider.missing.contains(item.id)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if !model.presentationMode, let t = provider.thumbnails[item.id] { Image(nsImage: t).resizable().aspectRatio(contentMode: .fit) }
                    else { Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().aspectRatio(contentMode: .fit) }
                }
                .frame(width: 48, height: 48)
                .opacity(gone ? 0.35 : 1)
                if item.fromScreenshot && Date().timeIntervalSince(item.addedAt) < 600 {
                    SwiftUI.Text(L("shelf.new")).font(.system(size: 8.5, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 4).background(Capsule().fill(DY.info))
                }
            }
            SwiftUI.Text(model.presentationMode ? item.ext : item.name)
                .font(DY.font(10.5, .regular)).foregroundStyle(gone ? DY.fg2 : DY.fg)
                .lineLimit(1).truncationMode(.middle).frame(width: 84)   // keeps the extension visible
            if gone { SwiftUI.Text(L("shelf.moved")).font(DY.font(9.5)).foregroundStyle(DY.action) }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected == item.id ? Color.white.opacity(0.10) : .clear))
        .onTapGesture { selected = item.id }
        .onTapGesture(count: 2) { provider.quickLook(item) }
        .onDrag { NSItemProvider(object: provider.url(item) as NSURL) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func actions(_ item: Shelf.Item) -> some View {
        HStack(spacing: 6) {
            SwiftUI.Text(model.presentationMode ? item.ext : TextRules.abbreviatePath(item.path, max: 40))
                .font(DY.mono).foregroundStyle(DY.fg2).lineLimit(1)
            Spacer()
            NotchButton(title: L("shelf.quickLook")) { provider.quickLook(item) }
            NotchButton(title: L("shelf.copyPath")) { provider.copyPath(item) }
            NotchButton(title: L("shelf.openEditor")) { provider.openInEditor(item) }
            if VisionTools.isImage(item.path) {
                Menu(L("transform.convert")) {
                    Button("PNG") { run { await FileTransforms.convert(provider.url(item), to: .png) } }
                    Button("JPEG") { run { await FileTransforms.convert(provider.url(item), to: .jpeg) } }
                    Button(L("transform.half")) { run { await FileTransforms.convert(provider.url(item), to: .jpeg, scale: 0.5) } }
                }
                .menuStyle(.borderlessButton).fixedSize().font(DY.font(12)).foregroundStyle(.white)
                NotchButton(title: L("vision.copyText")) {
                    Task { if let img = NSImage(contentsOfFile: item.path).flatMap(VisionTools.cgImage) { _ = await VisionTools.copyText(from: img) } }
                }
                NotchButton(title: L("vision.removeBg")) {
                    Task { if let out = await VisionTools.removeBackground(provider.url(item)) { provider.add([out]) } }
                }
            }
            if FileTransforms.isVideo(item.path) {
                NotchButton(title: L("transform.compress")) { run { await FileTransforms.compressVideo(provider.url(item)) } }
            }
            if FileTransforms.isPDF(item.path), provider.shelf.items.filter({ FileTransforms.isPDF($0.path) }).count >= 2 {
                NotchButton(title: L("transform.mergePDF")) {
                    let pdfs = provider.shelf.items.filter { FileTransforms.isPDF($0.path) }.map(provider.url)
                    run { await FileTransforms.mergePDFs(pdfs) }
                }
            }
            NotchButton(title: "AirDrop") { provider.airDrop([item]) }
            NotchButton(title: "Zip") { provider.zip(provider.shelf.items) }
            Button { provider.remove(item.id) } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(DY.fg2) }
                .buttonStyle(.plain).accessibilityLabel(L("shelf.remove"))
        }
    }

    /// Runs a transform and puts its result on the shelf.
    private func run(_ work: @escaping @MainActor () async -> URL?) {
        Task { @MainActor in if let out = await work() { ShelfProvider.shared.add([out]) } }
    }

    private func allItemsProvider() -> NSItemProvider {
        // SwiftUI drags one provider; register every file URL on it.
        let p = NSItemProvider()
        for item in provider.shelf.items where !provider.missing.contains(item.id) {
            p.registerObject(provider.url(item) as NSURL, visibility: .all)
        }
        return p
    }
}

enum ShelfDrop {
    /// Reads file URLs from dropped item providers and adds them to the shelf.
    static func accept(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { @Sendable url, _ in
                guard let url else { return }
                Task { @MainActor in
                    ShelfProvider.shared.add([url])
                    AppModel.shared.selectedTab = .shelf
                    AppModel.shared.notchState = .expanded
                }
            }
        }
    }
}
