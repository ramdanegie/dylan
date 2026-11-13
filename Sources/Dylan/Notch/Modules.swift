import AppKit
import AVFoundation
import DylanCore
import SwiftUI

// Home modules (FR-114, design D59): Tasks (Reminders), Flashcards and Internet radio, added with "Edit modules".

struct ModulesRow: View {
    private var prefs: Prefs { Prefs.shared }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(prefs.modules) { m in
                Group {
                    switch m {
                    case .tasks: TasksModule()
                    case .flashcards: FlashcardModule()
                    case .radio: RadioModule()
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            }
        }
    }
}

private struct ModuleTitle: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            SwiftUI.Text(text).font(DY.font(10.5, .semibold)).lineLimit(1)
        }
        .foregroundStyle(DY.fg2)
    }
}

struct TasksModule: View {
    private var r: RemindersProvider { RemindersProvider.shared }
    private var model: AppModel { AppModel.shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ModuleTitle(symbol: "checklist", text: L("module.tasks"))
            if r.status != .fullAccess {
                Button(L("reminders.allow")) { RemindersProvider.shared.start(requestAccess: true) }.buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.info)
            } else if r.items.isEmpty {
                SwiftUI.Text(L("module.tasksDone")).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
            }
            ForEach(r.items.prefix(3)) { item in
                HStack(spacing: 6) {
                    Button { RemindersProvider.shared.complete(item) } label: {
                        Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(DY.fg2)
                    }
                    .buttonStyle(.plain).accessibilityLabel(L("reminders.complete"))
                    SwiftUI.Text(model.presentationMode ? L("reminders.generic") : item.title).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                }
            }
        }
    }
}

struct FlashcardModule: View {
    private var s: FlashcardStore { FlashcardStore.shared }
    @StateBox private var flipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let deck = s.deck {
                ModuleTitle(symbol: "rectangle.on.rectangle.angled", text: "\(deck.name) · \(deck.learned)/\(deck.cards.count)")
                if AppModel.shared.presentationMode {
                    SwiftUI.Text(L("flash.hidden")).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
                } else if let card = deck.nextDue(now: Date()) {
                    SwiftUI.Text(flipped ? card.back : card.front).font(DY.font(12, flipped ? .regular : .semibold))
                        .foregroundStyle(.white).lineLimit(2)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if flipped {
                            NotchButton(title: L("flash.again"), kind: .quiet, height: 20) { s.answer(card.id, knew: false); flipped = false }
                            NotchButton(title: L("flash.knew"), height: 20) { s.answer(card.id, knew: true); flipped = false }
                        } else {
                            NotchButton(title: L("flash.flip"), height: 20) { flipped = true }
                        }
                    }
                } else {
                    SwiftUI.Text(L("flash.allDone")).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
                }
            } else {
                ModuleTitle(symbol: "rectangle.on.rectangle.angled", text: L("module.flashcards"))
                Button(L("flash.import")) { FlashcardStore.shared.importFile() }.buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.info)
            }
        }
    }
}

struct RadioModule: View {
    private var r: RadioPlayer { RadioPlayer.shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModuleTitle(symbol: "dot.radiowaves.left.and.right", text: L("module.radio"))
            if let st = r.current ?? r.stations.first {
                SwiftUI.Text(st.name).font(DY.font(12, .semibold)).foregroundStyle(.white).lineLimit(1)
                SwiftUI.Text(r.playing ? L("radio.live") : (r.failed ? L("radio.failed") : " ")).font(DY.font(10.5)).foregroundStyle(r.failed ? DY.fail : DY.fg2)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    NotchButton(title: r.playing ? L("button.pause") : L("radio.play"), height: 20) { r.playing ? r.pause() : r.play(st) }
                    if r.stations.count > 1 { NotchButton(title: L("radio.next"), kind: .quiet, height: 20) { r.nextStation() } }
                }
            } else {
                Button(L("radio.addInSettings")) { SettingsWindow.show(section: .utilities) }.buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.info)
            }
        }
    }
}

// MARK: Stores

/// One deck at a time, saved as JSON in Application Support (cards are the user's own notes).
@Observable
final class FlashcardStore {
    static let shared = FlashcardStore()
    private(set) var deck: FlashcardDeck?
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dylan/flashcards.json")
    }

    private init() { deck = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder().decode(FlashcardDeck.self, from: $0) } }

    func answer(_ id: UUID, knew: Bool) { deck?.answer(id, knew: knew, now: Date()); save() }

    /// CSV or an Anki plain-text export; replaces the current deck.
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        NSApp.activateInFront()
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let cards = FlashcardDeck.parse(text)
        guard !cards.isEmpty else { AppModel.shared.lastError = L("flash.importEmpty"); return }
        deck = FlashcardDeck(name: url.deletingPathExtension().lastPathComponent, cards: cards)
        save()
    }

    func remove() { deck = nil; try? FileManager.default.removeItem(at: Self.url) }

    private func save() {
        guard let deck, let data = try? JSONEncoder().encode(deck) else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.url, options: .atomic)
    }
}

/// Internet radio: favourite stations (name + stream URL) the user adds in Settings.
@Observable
final class RadioPlayer {
    static let shared = RadioPlayer()
    struct Station: Codable, Equatable, Identifiable { var name: String; var url: String; var id: String { url } }

    var stations: [Station] {
        didSet {
            AppModel.store.set(try? JSONEncoder().encode(stations), forKey: "radio.stations")
            // The station that is playing was removed: nothing would be left to stop it with.
            if let c = current, !stations.contains(c) { pause(); current = nil }
        }
    }
    private(set) var current: Station?
    private(set) var playing = false
    private(set) var failed = false
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    private init() {
        stations = AppModel.store.data(forKey: "radio.stations").flatMap { try? JSONDecoder().decode([Station].self, from: $0) } ?? []
    }

    func play(_ s: Station) {
        guard let url = URL(string: s.url), url.scheme?.lowercased() == "https" else { failed = true; return }
        if AppModel.shared.media?.isPlaying == true { MediaProvider.shared.playPause() }
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status) { item, _ in
            let bad = item.status == .failed
            Task { @MainActor in if bad { RadioPlayer.shared.failed = true; RadioPlayer.shared.playing = false } }
        }
        let p = AVPlayer(playerItem: item)
        p.play()
        player = p
        current = s
        playing = true
        failed = false
    }

    func pause() { player?.pause(); player = nil; playing = false }

    /// After the adhan: the station that was on.
    func resume() { if let current { play(current) } }

    func nextStation() {
        guard !stations.isEmpty else { return }
        let i = (stations.firstIndex { $0 == current } ?? -1) + 1
        let s = stations[i % stations.count]
        if playing { play(s) } else { current = s }
    }
}
