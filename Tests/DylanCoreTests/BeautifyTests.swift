import CoreGraphics
import Testing
@testable import DylanCore

@Suite struct BeautifyTests {
    @Test func presetsMatchTheDesign() {
        #expect(Beautify.backgrounds.count == 15 && Beautify.backgrounds.first?.name == "Mesh senja" && Beautify.backgrounds.last?.fill == .transparent)
        #expect(Beautify.shadows.map(\.name) == ["Tanpa", "Lembut", "Melayang", "Tajam", "Glow"])
        #expect(Beautify.ratios.count == 8 && Beautify.layouts.count == 6 && Beautify.Frame.allCases.count == 6)
        // Every color in every preset parses.
        for b in Beautify.backgrounds + Beautify.editorBackgrounds {
            switch b.fill {
            case .solid(let c): #expect(Beautify.rgb(c) != nil)
            case .linear(_, let stops): #expect(stops.allSatisfy { Beautify.rgb($0.color) != nil })
            case .mesh(let base, let blobs): #expect(Beautify.rgb(base) != nil && blobs.allSatisfy { Beautify.rgb($0.color) != nil })
            case .transparent, .fromImage: break
            }
        }
    }

    @Test func canvas() {
        let img = CGSize(width: 1000, height: 600)
        #expect(Beautify.canvasSize(content: img, frame: .none, padding: 64, ratio: nil) == CGSize(width: 1128, height: 728))
        #expect(Beautify.canvasSize(content: img, frame: .mac, padding: 0, ratio: nil) == CGSize(width: 1000, height: 630))
        // Grown, never cropped: 1:1 from a wide picture adds height.
        #expect(Beautify.canvasSize(content: img, frame: .none, padding: 0, ratio: 1) == CGSize(width: 1000, height: 1000))
        // 9:16 from a wide picture adds height too.
        let tall = Beautify.canvasSize(content: img, frame: .none, padding: 0, ratio: 9.0 / 16)
        #expect(tall.width == 1000 && tall.height == 1778)
        #expect(Beautify.rgb("#FF8000")! == (1, 128.0 / 255, 0))
        #expect(Beautify.rgb("nope") == nil)
    }
}
