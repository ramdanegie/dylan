import Foundation

/// Flashcard module (FR-114, design D59): a Leitner box schedule, so known cards come back less often.
public struct FlashcardDeck: Codable, Equatable, Sendable {
    public struct Card: Codable, Equatable, Sendable, Identifiable {
        public var id = UUID()
        public var front: String
        public var back: String
        /// 0 = new or forgotten; each "knew it" moves the card up a box.
        public var box = 0
        public var due = Date.distantPast
        public init(front: String, back: String) { self.front = front; self.back = back }
    }

    /// Days until a card in box n is due again.
    public static let intervals: [Double] = [0, 1, 3, 7, 14, 30]

    public var name: String
    public var cards: [Card]
    public init(name: String, cards: [Card]) { self.name = name; self.cards = cards }

    /// The next card to study: the most overdue one, nil when nothing is due.
    public func nextDue(now: Date) -> Card? {
        cards.filter { $0.due <= now }.min { ($0.due, $0.box) < ($1.due, $1.box) }
    }

    public func dueCount(now: Date) -> Int { cards.filter { $0.due <= now }.count }
    /// Cards seen at least once and not forgotten since.
    public var learned: Int { cards.filter { $0.box > 0 }.count }

    public mutating func answer(_ id: UUID, knew: Bool, now: Date) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].box = knew ? min(cards[i].box + 1, Self.intervals.count - 1) : 0
        // A forgotten card comes back in this session (after 1 minute), not tomorrow.
        cards[i].due = knew ? now.addingTimeInterval(Self.intervals[cards[i].box] * 86400) : now.addingTimeInterval(60)
    }

    /// CSV (`front,back`, quotes allowed) or an Anki "Notes in Plain Text" export (tab separated, `#` header lines).
    /// HTML that Anki leaves in fields is stripped.
    public static func parse(_ text: String) -> [Card] {
        var cards: [Card] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let sep: Character = line.contains("\t") ? "\t" : (line.contains(";") && !line.contains(",") ? ";" : ",")
            let f = fields(line, sep).map(clean)
            guard f.count >= 2, !f[0].isEmpty, !f[1].isEmpty else { continue }
            cards.append(Card(front: f[0], back: f[1]))
        }
        return cards
    }

    static func fields(_ line: String, _ sep: Character) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        let it = Array(line)
        var i = 0
        while i < it.count {
            let c = it[i]
            if c == "\"" {
                if quoted && i + 1 < it.count && it[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted.toggle() }
            } else if c == sep && !quoted {
                out.append(cur); cur = ""
            } else {
                cur.append(c)
            }
            i += 1
        }
        out.append(cur)
        return out
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespaces)
    }
}
