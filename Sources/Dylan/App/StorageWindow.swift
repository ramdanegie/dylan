import AppKit
import DylanCore
import SwiftUI

/// "Optimasi penyimpanan" (FR-100–FR-102): scan, check what to remove, confirm, clean.
enum StorageWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = L("storage.title")
            w.isReleasedWhenClosed = false
            w.minSize = CGSize(width: 620, height: 420)
            w.contentView = NSHostingView(rootView: StorageView())
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        let p = StorageProvider.shared
        if p.items.isEmpty && !p.scanning { p.scan() }
    }
}

private struct StorageView: View {
    @StateBox private var confirm = false
    private var p: StorageProvider { StorageProvider.shared }
    private var shown: [StorageCategory] { StorageCategory.allCases.filter { c in p.items.contains { $0.category == c } } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if p.items.isEmpty && !p.scanning && p.blocked.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.green)
                    SwiftUI.Text(p.result ?? L("storage.nothing")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(shown, id: \.self) { c in
                        Section { ForEach(p.items.filter { $0.category == c }) { row($0) } } header: { categoryHeader(c) }
                    }
                    if !p.blocked.isEmpty {
                        Section(L("storage.blockedTitle")) {
                            HStack {
                                SwiftUI.Text(p.blocked.sorted { $0.rawValue < $1.rawValue }.map { L("storage.cat.\($0.rawValue)") }.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(L("focus.openFullDiskAccess")) {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
        .alert(L("storage.confirmTitle", p.plan.count), isPresented: $confirm) {
            Button(L("storage.clean"), role: .destructive) { p.clean() }
            Button(L("button.cancel"), role: .cancel) {}
        } message: {
            SwiftUI.Text(confirmText)
        }
    }

    /// Says exactly what happens to each kind of item (review: Empty Trash cannot be undone; the Trash frees nothing yet).
    private var confirmText: String {
        let plan = p.plan
        var lines: [String] = []
        if plan.deleted > 0 { lines.append(L("storage.confirmDeleted", plan.deleted, StorageProvider.bytes(plan.deletedBytes))) }
        if plan.emptiesTrash { lines.append(L("storage.confirmEmptyTrash", StorageProvider.bytes(plan.trashBytes))) }
        if plan.trashed > 0 { lines.append(L("storage.confirmTrashed", plan.trashed, StorageProvider.bytes(plan.trashedBytes))) }
        return lines.joined(separator: "\n\n")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    SwiftUI.Text(L("storage.title")).font(.headline)
                    SwiftUI.Text(L("storage.disk", StorageProvider.bytes(p.free), StorageProvider.bytes(p.total))).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if p.scanning {
                    ProgressView().controlSize(.small)
                    SwiftUI.Text(L("storage.scanningCount", p.scanned, p.toScan)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button(p.items.isEmpty && !p.scanning ? L("storage.scan") : L("storage.rescan")) { p.scan() }.disabled(p.scanning || p.cleaning)
            }
            if p.total > 0 {
                ProgressView(value: Double(p.total - p.free), total: Double(p.total))
                    .tint(StorageRules.isLowSpace(free: p.free, total: p.total) ? .red : .accentColor)
                    .accessibilityLabel(L("storage.disk", StorageProvider.bytes(p.free), StorageProvider.bytes(p.total)))
            }
        }
        .padding(14)
    }

    private func categoryHeader(_ c: StorageCategory) -> some View {
        let list = p.items.filter { $0.category == c }
        let ids = Set(list.map(\.id)), on = ids.intersection(p.selected).count
        let total = list.reduce(Int64(0)) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Button {
                    if on == ids.count { p.selected.subtract(ids) } else { p.selected.formUnion(ids) }
                } label: {
                    Image(systemName: on == 0 ? "square" : on == ids.count ? "checkmark.square.fill" : "minus.square.fill")
                        .foregroundStyle(on == 0 ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("storage.selectCategory", L("storage.cat.\(c.rawValue)")))
                SwiftUI.Text(L("storage.cat.\(c.rawValue)")).font(.headline).foregroundStyle(.primary)
                ImpactBadge(impact: c.impact)
                Spacer()
                SwiftUI.Text(StorageProvider.bytes(total)).monospacedDigit().foregroundStyle(.primary)
            }
            SwiftUI.Text(L("storage.impact.\(c.rawValue)") + " " + L(c.action == .delete ? "storage.actionDelete" : "storage.actionTrash"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
        .padding(.vertical, 4)
    }

    private func row(_ i: StorageItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { p.selected.contains(i.id) },
                                     set: { on in if on { p.selected.insert(i.id) } else { p.selected.remove(i.id) } }))
                .labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text(i.title).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    SwiftUI.Text((i.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: i.path)]) } label: {
                        Image(systemName: "arrow.right.circle").font(.caption)
                    }
                    .buttonStyle(.borderless).help(L("storage.reveal")).accessibilityLabel(L("storage.reveal"))
                }
                if let note = i.note { SwiftUI.Text(note).font(.caption2).foregroundStyle(i.running ? .orange : .secondary) }
            }
            Spacer()
            SwiftUI.Text(StorageProvider.bytes(i.size)).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            if let r = p.result { Label(r, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1) }
            if p.cleaning { ProgressView().controlSize(.small); SwiftUI.Text(L("storage.cleaning")).foregroundStyle(.secondary) }
            Spacer()
            SwiftUI.Text(L("storage.selected", p.plan.count, StorageProvider.bytes(p.plan.bytes))).monospacedDigit().foregroundStyle(.secondary)
            Button(L("storage.clean")) { confirm = true }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(p.plan.count == 0 || p.cleaning || p.scanning)
        }
        .padding(14)
    }
}

/// Rendah / Sedang / Tinggi.
struct ImpactBadge: View {
    var impact: StorageImpact
    var body: some View {
        let color: Color = impact == .low ? .green : impact == .medium ? .orange : .red
        SwiftUI.Text(L("storage.impact.\(impact)")).font(.caption2.bold()).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .accessibilityLabel(L("storage.impactA11y", L("storage.impact.\(impact)")))
    }
}

/// Settings → Penyimpanan.
struct StorageSettings: View {
    private var p: StorageProvider { StorageProvider.shared }
    private var d: UserDefaults { AppModel.store }
    @StateBox private var refresh = 0

    var body: some View {
        FeatureToggles(features: [.storage])
        Section {
            LabeledContent(L("storage.free")) {
                SwiftUI.Text(L("storage.disk", StorageProvider.bytes(p.free), StorageProvider.bytes(p.total))).foregroundStyle(.secondary)
            }
            Button(L("storage.open")) { StorageWindow.show() }
            Toggle(isOn: Binding(get: { _ = refresh; return d.object(forKey: "storage.warn") as? Bool ?? true },
                                 set: { d.set($0, forKey: "storage.warn"); refresh += 1 })) {
                SwiftUI.Text(L("storage.warn"))
                SwiftUI.Text(L("storage.warnHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { StorageProvider.shared.refreshDisk() }
    }
}
