import DylanCore
import SwiftUI

/// FR-41: output above, one input line below. Keyboard focus only after the field is clicked (design rule).
struct TerminalTab: View {
    private var model: AppModel { AppModel.shared }
    private var term: TerminalProvider { TerminalProvider.shared }
    @StateBox private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.presentationMode {
                SwiftUI.Text(L("terminal.hidden")).font(DY.font(12)).foregroundStyle(DY.fg2).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if Snapshot.rendering {   // ImageRenderer cannot draw the AppKit scroll view
                SwiftUI.Text(verbatim: term.lines.joined(separator: "\n")).font(DY.mono).foregroundStyle(DY.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        SwiftUI.Text(verbatim: term.lines.suffix(200).joined(separator: "\n"))
                            .font(DY.mono).foregroundStyle(DY.fg).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onChange(of: term.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            }
            HStack(spacing: 6) {
                SwiftUI.Text(verbatim: "›").font(DY.mono).foregroundStyle(DY.fg2)
                TextField(L("terminal.placeholder"), text: $input)
                    .textFieldStyle(.plain).font(DY.mono).foregroundStyle(.white)
                    .onSubmit { term.send(input); input = "" }
                NotchButton(title: "⌃C", kind: .quiet) { term.interrupt() }.accessibilityLabel(L("terminal.interrupt"))
                NotchButton(title: L("terminal.clear"), kind: .quiet) { term.clear() }
                NotchButton(title: "Terminal") { term.handOff(toVSCode: false) }
                if term.vsCodeInstalled { NotchButton(title: "VS Code") { term.handOff(toVSCode: true) } }
            }
        }
        .onAppear { if !Snapshot.rendering { term.start() } }
    }
}
