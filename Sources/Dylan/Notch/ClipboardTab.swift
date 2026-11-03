import AppKit
import DylanCore
import SwiftUI

/// Expanded → Clipboard (design D11). Smart-detect cards and generators only in the Developer profile.
struct ClipboardTab: View {
    enum Filter: CaseIterable { case all, text, image, file, pinned }
    @StateBox private var query = ""
    @StateBox private var filter = Filter.all
    @StateBox private var selected: UUID?
    @FocusState private var searchFocused: Bool
    private var model: AppModel { AppModel.shared }
    private var provider: ClipboardProvider { ClipboardProvider.shared }

    var body: some View {
        let _ = model.clipboardRevision   // re-render when the history changes
        if model.presentationMode {
            EmptyCard(symbol: "lock.fill", text: L("clipboard.locked")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    search
                    chips
                    list
                }
                .frame(width: model.isDeveloper ? 330 : nil)
                .frame(maxWidth: model.isDeveloper ? nil : .infinity)
                if model.isDeveloper {
                    VStack(alignment: .leading, spacing: 10) {
                        if let item = provider.history.items.first(where: { $0.id == selected }) ?? items.first {
                            DetectCard(item: item)
                        }
                        Spacer(minLength: 0)
                        GeneratorRow(source: provider.history.items.first { $0.id == selected }?.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .onAppear { searchFocused = model.focusClipboardSearch; model.focusClipboardSearch = false }
        }
    }

    private var items: [ClipboardHistory.Item] {
        let kind: ClipboardHistory.Item.Kind? = switch filter {
        case .text: .text
        case .image: .image
        case .file: .file
        default: nil
        }
        return provider.history.search(query, kind: kind, pinnedOnly: filter == .pinned)
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(DY.fg2)
            TextField(L("clipboard.search"), text: $query)
                .textFieldStyle(.plain).font(DY.font(12, .regular)).foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { if let first = items.first { provider.copy(first, paste: true) } }
            SwiftUI.Text("⌃⌥V").font(DY.font(10.5)).foregroundStyle(DY.fg2)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(DY.control))
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button { filter = f } label: {
                    SwiftUI.Text(title(f)).font(DY.font(11, filter == f ? .semibold : .regular))
                        .foregroundStyle(filter == f ? .white : DY.fg2)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(Capsule().fill(filter == f ? Color.white.opacity(0.14) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func title(_ f: Filter) -> String {
        switch f {
        case .all: return L("clipboard.all")
        case .text: return L("clipboard.text")
        case .image: return L("clipboard.image")
        case .file: return L("clipboard.file")
        case .pinned: return L("clipboard.pinned")
        }
    }

    @ViewBuilder private var list: some View {
        if items.isEmpty {
            EmptyCard(symbol: "doc.on.clipboard", text: L(query.isEmpty ? "clipboard.empty" : "clipboard.noMatch"))
        } else {
            VStack(spacing: 2) {
                ForEach(items.prefix(model.isDeveloper ? 9 : 8)) { item in row(item) }
            }
        }
    }

    private func row(_ item: ClipboardHistory.Item) -> some View {
        HStack(spacing: 8) {
            SwiftUI.Text(badge(item)).font(.system(size: 9, weight: .bold)).foregroundStyle(item.secret ? DY.action : DY.fg2)
                .frame(width: 42, alignment: .leading)
            if item.kind == .image, let img = provider.images[item.id] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 3))
            }
            SwiftUI.Text(preview(item)).font(DY.mono).foregroundStyle(DY.fg).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if item.secret {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ValueText(text: DurationFormat.running(max(0, SecretDetector.ttl - ctx.date.timeIntervalSince(item.date))), color: DY.action)
                }
            } else {
                SwiftUI.Text(age(item.date)).font(DY.font(10.5)).foregroundStyle(DY.fg2).monospacedDigit()
            }
            Button { provider.togglePin(item.id) } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin").font(.system(size: 10)).foregroundStyle(item.pinned ? .white : DY.fg2)
            }
            .buttonStyle(.plain).disabled(item.secret).accessibilityLabel(L("clipboard.pin"))
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected == item.id ? Color.white.opacity(0.10) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { provider.copy(item, paste: true) }
        .onTapGesture { selected = item.id; provider.copy(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func badge(_ item: ClipboardHistory.Item) -> String {
        if item.secret { return Detectors.jwt(item.text) != nil ? "JWT" : "TOKEN" }
        switch item.kind {
        case .image: return L("clipboard.image").uppercased()
        case .file: return "FILE"
        case .text:
            switch Detectors.detect(item.text).first {
            case .jwt?: return "JWT"
            case .json?: return "JSON"
            case .timestamp?: return L("clipboard.time").uppercased()
            case .url?: return "URL"
            case .path?: return "PATH"
            case .uuid?: return "UUID"
            case .hexColor?: return L("clipboard.color").uppercased()
            default: return L("clipboard.text").uppercased()
            }
        }
    }

    private func preview(_ item: ClipboardHistory.Item) -> String {
        if item.secret { return SecretDetector.mask(item.text) + " · " + L("clipboard.hidden") }
        switch item.kind {
        case .image: return item.text
        case .file: return item.text.split(separator: "\n").map { TextRules.abbreviatePath(String($0)) }.joined(separator: ", ")
        case .text: return TextRules.singleLine(item.text)
        }
    }

    private func age(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return L("clipboard.now") }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}

/// Smart-detect card for the selected item (design D11, right column).
struct DetectCard: View {
    var item: ClipboardHistory.Item
    private var provider: ClipboardProvider { ClipboardProvider.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch item.kind == .text ? Detectors.detect(item.text).first : nil {
            case .jwt(let header, let payload, let iat, let exp)?:
                title("JWT", item.secret ? L("clipboard.hiddenFor") : nil)
                code(L("clipboard.header"), header)
                code(L("clipboard.payload"), payload)
                if let exp { meta(L("clipboard.expires", exp.formatted(.dateTime.locale(L10n.locale)), relative(exp))) }
                if let iat { meta(L("clipboard.issued", iat.formatted(.dateTime.locale(L10n.locale)))) }
                HStack { button(L("clipboard.copyPayload"), payload); button(L("clipboard.copyHeader"), header) }
            case .json(let pretty, let mini, let keys)?:
                title("JSON", L("clipboard.jsonValid", keys))
                code(nil, String(pretty.prefix(600)))
                HStack { button(L("clipboard.copyPretty"), pretty); button(L("clipboard.copyMinify"), mini) }
            case .timestamp(let d)?:
                title(L("clipboard.unixTimestamp"), item.text)
                meta(L("clipboard.local") + "  " + d.formatted(.dateTime.weekday().day().month().year().hour().minute().locale(L10n.locale)))
                meta("UTC  " + Generators.timestamps(d).iso)
                meta(L("clipboard.relative") + "  " + relative(d))
                button(L("clipboard.copyISO"), Generators.timestamps(d).iso)
            case .hexColor(let c)?:
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: c.r, green: c.g, blue: c.b)).frame(width: 36, height: 36)
                    VStack(alignment: .leading) { SwiftUI.Text(c.hex).font(DY.mono); SwiftUI.Text(c.rgb).font(DY.mono).foregroundStyle(DY.fg2) }
                }
                HStack { button("RGB", c.rgb); button("HSL", "hsl(\(c.hsl))"); button("SwiftUI", c.swiftUI) }
            case .url(let u)?:
                title("URL", nil)
                code(nil, u.absoluteString)
                NotchButton(title: L("button.open")) { AppModel.shared.perform(.openURL(u)) }
            case .path(let p)?:
                title("PATH", nil)
                code(nil, p)
                NotchButton(title: L("clipboard.showInFinder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (p as NSString).expandingTildeInPath)])
                }
            case .uuid(let u)?:
                title("UUID", nil)
                HStack { button(L("clipboard.lower"), u.lowercased()); button(L("clipboard.upper"), u.uppercased()) }
            case .base64(let t)?:
                title("Base64", L("clipboard.decoded"))
                code(nil, String(t.prefix(600)))
                button(L("button.copy"), t)
            case .urlEncoded(let t)?:
                title(L("clipboard.urlEncoded"), L("clipboard.decoded"))
                code(nil, t)
                button(L("button.copy"), t)
            default:
                EmptyCard(symbol: "wand.and.stars", text: L("clipboard.noDetect"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func title(_ t: String, _ sub: String?) -> some View {
        HStack(spacing: 6) {
            SwiftUI.Text(t).font(DY.font(12, .semibold)).foregroundStyle(.white)
            if let sub { SwiftUI.Text(sub).font(DY.font(11, .regular)).foregroundStyle(DY.fg2) }
        }
    }

    private func code(_ label: String?, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label { SwiftUI.Text(label).font(DY.font(10.5)).foregroundStyle(DY.fg2) }
            SwiftUI.Text(s).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DY.fg).lineLimit(7).textSelection(.enabled)
        }
    }

    private func meta(_ s: String) -> some View { SwiftUI.Text(s).font(DY.font(11, .regular)).foregroundStyle(DY.fg2).lineLimit(1) }

    private func button(_ t: String, _ value: String) -> some View {
        NotchButton(title: t) { provider.copyText(value) }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = L10n.locale
        return f.localizedString(for: d, relativeTo: Date())
    }
}

struct GeneratorRow: View {
    var source: String?
    @StateBox private var output = ""
    private var provider: ClipboardProvider { ClipboardProvider.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwiftUI.Text(L("clipboard.generator")).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
            HStack(spacing: 6) {
                NotchButton(title: "UUID") { output = Generators.uuid() }
                NotchButton(title: L("clipboard.time")) { output = Generators.timestamps(Date()).iso }
                NotchButton(title: "SHA-256") { output = Generators.hashes(source ?? "").sha256 }
                    .disabled(source == nil)
            }
            if !output.isEmpty {
                HStack {
                    SwiftUI.Text(output).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DY.fg).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    NotchButton(title: L("button.copy")) { provider.copyText(output) }
                }
            }
        }
    }
}
