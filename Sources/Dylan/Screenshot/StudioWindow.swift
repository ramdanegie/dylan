import AppKit
import CoreImage
import DylanCore
import SwiftUI
import Vision

/// Studio (FR-93, design D44) and the annotation editor (FR-92, D41) in one window, on the original capture.
/// Preview and export are the same SwiftUI view, so what you see is what is copied or saved.
final class StudioWindow: NSWindow {
    private static var windows: [StudioWindow] = []

    static func open(_ url: URL, annotate: Bool = false) {
        guard let image = NSImage(contentsOf: url), let cg = VisionTools.cgImage(image) else { return }
        let model = StudioModel(original: cg, url: url)
        model.annotating = annotate
        let w = StudioWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
        w.title = "Studio · \(cg.width / 2) × \(cg.height / 2)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: StudioView(model: model))
        w.center()
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        windows.append(w)
        if ShotPrefs.autoBlur { model.autoBlurSensitive() }
    }

    override func close() {
        super.close()
        Self.windows.removeAll { $0 === self }
    }
}

// MARK: - Model

struct Mark: Identifiable, Equatable {
    enum Kind: String { case arrow, rect, text, highlight, blur, number }
    let id = UUID()
    var kind: Kind
    /// Normalized image coordinates (0…1, origin top-left).
    var a: CGPoint
    var b: CGPoint
    var text = ""
    var number = 0
    var color: Color
}

@Observable
final class StudioModel {
    enum Tool: String, CaseIterable { case select, arrow, rect, text, highlight, blur, number, crop, pick
        var key: String { ["select": "v", "arrow": "a", "rect": "r", "text": "t", "highlight": "h", "blur": "b", "number": "n", "crop": "k", "pick": "i"][rawValue]! }
        var symbol: String { ["select": "cursorarrow", "arrow": "arrow.up.right", "rect": "rectangle", "text": "textformat", "highlight": "highlighter",
                              "blur": "square.grid.3x3.fill", "number": "1.circle", "crop": "crop", "pick": "eyedropper"][rawValue]! }
    }

    let original: CGImage
    let url: URL
    var annotating = false
    var tool: Tool = .arrow
    var ink: Color = Color(red: 1, green: 0.23, blue: 0.19)
    var marks: [Mark] = [] { didSet { rebuildWorking() } }
    var crop: CGRect? { didSet { rebuildWorking() } }       // normalized
    private(set) var working: NSImage
    var redoStack: [[Mark]] = []
    var undoStack: [[Mark]] = []
    var status: String?

    // Studio settings (last preset is remembered).
    var frame: Beautify.Frame { didSet { save() } }
    var background: Int { didSet { save() } }
    var shadow: Int { didSet { save() } }
    var ratio: Int { didSet { save() } }
    var layout: Int { didSet { save() } }
    var radius: Double { didSet { save() } }
    var padding: Double { didSet { save() } }
    var zoom: Double { didSet { save() } }
    var count: Int { didSet { save() } }
    var grain: Bool { didSet { save() } }
    var address = "dylan.app"
    var format = ShotPrefs.format

    init(original: CGImage, url: URL) {
        self.original = original
        self.url = url
        working = NSImage(cgImage: original, size: CGSize(width: original.width / 2, height: original.height / 2))
        let d = AppModel.store
        frame = Beautify.Frame(rawValue: d.string(forKey: "studio.frame") ?? "") ?? .mac
        background = d.object(forKey: "studio.bg") as? Int ?? ShotPrefs.studioBackground
        shadow = d.object(forKey: "studio.shadow") as? Int ?? 2
        ratio = d.object(forKey: "studio.ratio") as? Int ?? 0
        layout = d.object(forKey: "studio.layout") as? Int ?? 0
        radius = d.object(forKey: "studio.radius") as? Double ?? 12
        padding = d.object(forKey: "studio.padding") as? Double ?? 64
        zoom = d.object(forKey: "studio.zoom") as? Double ?? 100
        count = d.object(forKey: "studio.count") as? Int ?? 1
        grain = d.object(forKey: "studio.grain") as? Bool ?? true
    }

    private func save() {
        let d = AppModel.store
        d.set(frame.rawValue, forKey: "studio.frame"); d.set(background, forKey: "studio.bg"); d.set(shadow, forKey: "studio.shadow")
        d.set(ratio, forKey: "studio.ratio"); d.set(layout, forKey: "studio.layout"); d.set(radius, forKey: "studio.radius")
        d.set(padding, forKey: "studio.padding"); d.set(zoom, forKey: "studio.zoom"); d.set(count, forKey: "studio.count"); d.set(grain, forKey: "studio.grain")
    }

    func randomize() {
        frame = Beautify.Frame.allCases.randomElement()!
        background = Int.random(in: 0..<(Beautify.backgrounds.count - 1))
        shadow = Int.random(in: 1..<Beautify.shadows.count)
        layout = Int.random(in: 0..<Beautify.layouts.count)
    }

    func reset() {
        frame = .mac; background = ShotPrefs.studioBackground; shadow = 2; ratio = 0; layout = 0; radius = 12; padding = 64; zoom = 100; count = 1; grain = true
        commit([]); crop = nil
    }

    // MARK: Annotations

    func commit(_ new: [Mark]) {
        undoStack.append(marks)
        redoStack = []
        marks = new
    }

    func add(_ m: Mark) { commit(marks + [m]) }

    func undo() { guard let last = undoStack.popLast() else { return }; redoStack.append(marks); marks = last }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(marks); marks = next }

    var nextNumber: Int { (marks.filter { $0.kind == .number }.map(\.number).max() ?? 0) + 1 }

    /// The capture with blur marks applied and the crop taken; annotations other than blur are drawn on top by the view.
    private func rebuildWorking() {
        var img = CIImage(cgImage: original)
        let w = CGFloat(original.width), h = CGFloat(original.height)
        for m in marks where m.kind == .blur {
            let r = Self.rect(m.a, m.b, w: w, h: h)
            // CIImage is bottom-left based.
            let ciRect = CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
            let pix = img.cropped(to: ciRect).applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(8, min(r.width, r.height) / 6),
                                                                                           kCIInputCenterKey: CIVector(x: ciRect.midX, y: ciRect.midY)])
                .cropped(to: ciRect)
            img = pix.composited(over: img)
        }
        if let c = crop {
            let r = Self.rect(c.origin, CGPoint(x: c.maxX, y: c.maxY), w: w, h: h)
            img = img.cropped(to: CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height))
        }
        let ctx = CIContext()
        if let out = ctx.createCGImage(img, from: img.extent) {
            working = NSImage(cgImage: out, size: CGSize(width: out.width / 2, height: out.height / 2))
        }
    }

    static func rect(_ a: CGPoint, _ b: CGPoint, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: min(a.x, b.x) * w, y: min(a.y, b.y) * h, width: abs(a.x - b.x) * w, height: abs(a.y - b.y) * h).integral
    }

    /// Blur emails, tokens and card numbers found by OCR (same secret patterns as the Clipboard).
    func autoBlurSensitive() {
        let image = original
        Task {
            let boxes: [CGRect] = await Task.detached {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                try? VNImageRequestHandler(cgImage: image).perform([req])
                return (req.results ?? []).compactMap { o -> CGRect? in
                    guard let s = o.topCandidates(1).first?.string, SensitiveText.isSensitive(s) else { return nil }
                    let b = o.boundingBox   // normalized, bottom-left
                    return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height).insetBy(dx: -0.004, dy: -0.006)
                }
            }.value
            guard !boxes.isEmpty else { return }
            let blurs = boxes.map { Mark(kind: .blur, a: $0.origin, b: CGPoint(x: $0.maxX, y: $0.maxY), color: .clear) }
            marks += blurs
            status = L("shot.autoBlurred", blurs.count)
        }
    }

    // MARK: Export

    var contentSize: CGSize { working.size }

    var canvasSize: CGSize {
        Beautify.canvasSize(content: contentSize, frame: frame, padding: padding, ratio: Beautify.ratios[ratio].value)
    }

    func render() -> CGImage? {
        let r = ImageRenderer(content: StudioCanvas(model: self, exporting: true).frame(width: canvasSize.width, height: canvasSize.height))
        r.scale = 2
        return r.cgImage
    }

    func copy() {
        guard let img = render() else { return }
        ScreenshotService.shared.copy(img)
        status = L("shot.copied")
    }

    @discardableResult
    func saveFile() -> URL? {
        guard let img = render(), let u = ScreenshotService.store(img, in: ShotPrefs.folder, ext: format) else { return nil }
        status = L("shot.savedTo", u.lastPathComponent)
        return u
    }

    /// A temporary file for dragging the result into another app.
    func exportTemp() -> URL? {
        guard let img = render() else { return nil }
        return ScreenshotService.store(img, in: FileManager.default.temporaryDirectory.appendingPathComponent("dylan-studio"), ext: "png")
    }
}

/// Text worth blurring in a screenshot: secrets, emails, card numbers.
nonisolated enum SensitiveText {
    static func isSensitive(_ s: String) -> Bool {
        if SecretDetector.isSecret(s) { return true }
        if s.range(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"\b(?:\d[ -]?){13,19}\b"#, options: .regularExpression) != nil { return true }
        return false
    }
}

// MARK: - Rendering

extension Color {
    init(hex: String) {
        let c = Beautify.rgb(hex) ?? (0, 0, 0)
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}

struct FillView: View {
    var fill: Beautify.Fill
    var image: CGImage?
    var exporting = false

    var body: some View {
        GeometryReader { g in
            switch fill {
            case .transparent:
                if exporting { Color.clear } else { Checkerboard() }
            case .solid(let c):
                Color(hex: c)
            case .linear(let angle, let stops):
                let rad = angle * .pi / 180
                LinearGradient(stops: stops.map { .init(color: Color(hex: $0.color), location: $0.at) },
                               startPoint: UnitPoint(x: 0.5 - sin(rad) / 2, y: 0.5 + cos(rad) / 2),
                               endPoint: UnitPoint(x: 0.5 + sin(rad) / 2, y: 0.5 - cos(rad) / 2))
            case .mesh(let base, let blobs):
                ZStack {
                    Color(hex: base)
                    ForEach(Array(blobs.enumerated()), id: \.offset) { _, b in
                        RadialGradient(colors: [Color(hex: b.color), Color(hex: b.color).opacity(0)], center: UnitPoint(x: b.x, y: b.y),
                                       startRadius: 0, endRadius: b.radius * max(g.size.width, g.size.height))
                    }
                }
            case .fromImage:
                let (a, b) = Self.colors(image)
                LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    /// Two average colors of the capture (top-left and bottom-right halves), darkened a little.
    static func colors(_ image: CGImage?) -> (Color, Color) {
        guard let image, let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (.gray, .black) }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let p = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return (.gray, .black) }
        func c(_ i: Int) -> Color { Color(red: Double(p[i]) / 255 * 0.8, green: Double(p[i + 1]) / 255 * 0.8, blue: Double(p[i + 2]) / 255 * 0.8) }
        return (c(8), c(4))
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where Int(x / s + y / s) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.87)))
                }
            }
        }
        .background(Color.white)
    }
}

/// Film grain over the background (D44 "Grain").
struct GrainView: View {
    nonisolated(unsafe) static let noise: CGImage? = {
        var d = [UInt8](repeating: 0, count: 128 * 128 * 4)
        for i in stride(from: 0, to: d.count, by: 4) { let v = UInt8.random(in: 0...255); d[i] = v; d[i + 1] = v; d[i + 2] = v; d[i + 3] = 40 }
        let ctx = CGContext(data: &d, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return ctx?.makeImage()
    }()
    var body: some View {
        if let n = Self.noise {
            Image(decorative: n, scale: 1).resizable(resizingMode: .tile).blendMode(.overlay)
        }
    }
}

/// Background + framed screenshot + annotations, at canvas size in points.
struct StudioCanvas: View {
    var model: StudioModel
    var exporting = false

    var body: some View {
        let canvas = model.canvasSize
        let lay = Beautify.layouts[model.layout]
        ZStack {
            FillView(fill: Beautify.backgrounds[model.background].fill, image: model.original, exporting: exporting)
            if model.grain && Beautify.backgrounds[model.background].fill != .transparent { GrainView().opacity(0.3) }
            ZStack {
                // Extra copies behind (D44 "Jumlah").
                ForEach(Array((1..<max(1, model.count)).reversed()), id: \.self) { i in
                    framed.scaleEffect(1 - CGFloat(i) * 0.06).offset(y: CGFloat(i) * -18).opacity(1 - Double(i) * 0.25)
                }
                framed
            }
            .scaleEffect(model.zoom / 100)
            .rotation3DEffect(.degrees(lay.rotateX), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(lay.rotateY), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(lay.rotateZ))
            .position(x: canvas.width * lay.anchorX, y: canvas.height * lay.anchorY)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private var framed: some View {
        let f = model.frame
        let size = model.contentSize
        let sh = Beautify.shadows[model.shadow].layers
        return VStack(spacing: 0) {
            if f.barHeight > 0 { titleBar(f) }
            ZStack {
                Image(nsImage: model.working).resizable().interpolation(.high)
                AnnotationLayer(model: model)
            }
            .frame(width: size.width, height: size.height)
        }
        .padding(f.glassBorder)
        .background(f == .glass ? Color.white.opacity(0.28) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: model.radius, style: .continuous))
        // One silhouette for the shadow: without this every arrow and number inside casts its own.
        .compositingGroup()
        .modifier(ShadowLayers(layers: sh))
    }

    private func titleBar(_ f: Beautify.Frame) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: "#FF5F57")).frame(width: 11, height: 11)
                Circle().fill(Color(hex: "#FEBC2E")).frame(width: 11, height: 11)
                Circle().fill(Color(hex: "#28C840")).frame(width: 11, height: 11)
            }
            if f.hasAddressBar {
                Spacer(minLength: 0)
                Text(verbatim: model.address)
                    .font(.system(size: 11)).foregroundStyle(f.isDark ? Color.white.opacity(0.55) : Color(hex: "#5F5F64"))
                    .padding(.horizontal, 40).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(f.isDark ? Color.white.opacity(0.07) : Color.white))
                Spacer(minLength: 0)
                Color.clear.frame(width: 47, height: 1)
            } else { Spacer() }
        }
        .padding(.horizontal, 12)
        .frame(width: model.contentSize.width, height: f.barHeight)
        .background(Color(hex: f.barColor))
    }
}

/// Up to two CSS-like shadow layers from a Beautify preset.
struct ShadowLayers: ViewModifier {
    var layers: [Beautify.ShadowLayer]
    func body(content: Content) -> some View {
        let a = layers.first, b = layers.dropFirst().first
        return content
            .shadow(color: color(a), radius: (a?.blur ?? 0) / 2, x: a?.x ?? 0, y: a?.y ?? 0)
            .shadow(color: color(b), radius: (b?.blur ?? 0) / 2, x: b?.x ?? 0, y: b?.y ?? 0)
    }
    private func color(_ l: Beautify.ShadowLayer?) -> Color { l.map { Color(hex: $0.color).opacity($0.opacity) } ?? .clear }
}

/// Arrows, boxes, text, highlights and numbers, drawn in normalized coordinates over the picture.
struct AnnotationLayer: View {
    var model: StudioModel
    var body: some View {
        Canvas { ctx, size in
            let lw = max(2, min(size.width, size.height) / 160)   // line width follows the picture size (D41)
            for m in model.marks where m.kind != .blur {
                let a = CGPoint(x: m.a.x * size.width, y: m.a.y * size.height), b = CGPoint(x: m.b.x * size.width, y: m.b.y * size.height)
                switch m.kind {
                case .arrow:
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    ctx.stroke(p, with: .color(m.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    let ang = atan2(b.y - a.y, b.x - a.x), head = lw * 5
                    var h = Path()
                    h.move(to: b)
                    h.addLine(to: CGPoint(x: b.x - head * cos(ang - .pi / 7), y: b.y - head * sin(ang - .pi / 7)))
                    h.addLine(to: CGPoint(x: b.x - head * cos(ang + .pi / 7), y: b.y - head * sin(ang + .pi / 7)))
                    h.closeSubpath()
                    ctx.fill(h, with: .color(m.color))
                case .rect:
                    ctx.stroke(Path(roundedRect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)), cornerRadius: lw * 2),
                               with: .color(m.color), lineWidth: lw)
                case .highlight:
                    ctx.fill(Path(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))), with: .color(Color.yellow.opacity(0.35)))
                case .text:
                    ctx.draw(Text(m.text).font(.system(size: lw * 8, weight: .semibold)).foregroundColor(m.color), at: a, anchor: .topLeading)
                case .number:
                    let r = lw * 5
                    ctx.fill(Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)), with: .color(m.color))
                    ctx.draw(Text("\(m.number)").font(.system(size: r * 1.1, weight: .bold)).foregroundColor(.white), at: a)
                case .blur:
                    break
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Window content

struct StudioView: View {
    @Bindable var model: StudioModel
    @StateBox private var dragStart: CGPoint?
    @StateBox private var dragNow: CGPoint?
    @StateBox private var pendingText: CGPoint?
    @StateBox private var textValue = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.93))
                Divider()
                ScrollView { inspector.padding(14) }.frame(width: 300)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(KeyCatcher { key, flags in handleKey(key, flags) })
        .alert(L("shot.addText"), isPresented: Binding(get: { pendingText != nil }, set: { if !$0 { pendingText = nil } })) {
            TextField("", text: $textValue)
            Button(L("button.add")) {
                if let p = pendingText, !textValue.isEmpty { model.add(Mark(kind: .text, a: p, b: p, text: textValue, color: model.ink)) }
                textValue = ""; pendingText = nil
            }
            Button(L("button.cancel"), role: .cancel) { pendingText = nil }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoStack.isEmpty).help("⌘Z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(model.redoStack.isEmpty).help("⇧⌘Z")
            Picker("", selection: $model.annotating) {
                Text(L("shot.studio")).tag(false)
                Text(L("shot.annotate")).tag(true)
            }
            .pickerStyle(.segmented).frame(width: 220)
            if model.annotating {
                ForEach(StudioModel.Tool.allCases, id: \.self) { t in
                    Button { model.tool = t } label: { Image(systemName: t.symbol).frame(width: 20) }
                        .buttonStyle(.borderless).foregroundStyle(model.tool == t ? Color.accentColor : Color.primary)
                        .help("\(L("shot.tool.\(t.rawValue)")) (\(t.key.uppercased()))")
                }
                ColorPicker("", selection: $model.ink).labelsHidden().frame(width: 30)
            } else {
                Button { model.randomize() } label: { Label(L("shot.random"), systemImage: "sparkles") }
                Button(L("shot.reset")) { model.reset() }
            }
            Spacer()
            if let s = model.status { Text(s).font(.caption).foregroundStyle(.secondary) }
            DragOut(model: model)
            Picker("", selection: $model.format) {
                Text("PNG").tag("png"); Text("JPG").tag("jpg")
                if ScreenshotService.canWriteWebP { Text("WebP").tag("webp") }
            }
            .frame(width: 80)
            Button(L("shot.save")) { model.saveFile() }
            Button(L("shot.copy")) { model.copy() }.keyboardShortcut("c", modifiers: .command).buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12).frame(height: 46)
    }

    /// The canvas scaled to fit, with the editing gestures mapped back to normalized picture coordinates.
    private var preview: some View {
        GeometryReader { g in
            let canvas = model.canvasSize
            let fit = min((g.size.width - 40) / canvas.width, (g.size.height - 40) / canvas.height, 1)
            ZStack {
                StudioCanvas(model: model)
                    .scaleEffect(fit)
                    .frame(width: canvas.width * fit, height: canvas.height * fit)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                if model.annotating { editingOverlay(canvas: canvas, fit: fit) }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    /// Gestures over the picture itself (annotation mode shows the picture without 3D layout so it can be edited).
    private func editingOverlay(canvas: CGSize, fit: CGFloat) -> some View {
        let content = model.contentSize, f = model.frame
        let picture = CGRect(x: (canvas.width - content.width) / 2 * fit, y: ((canvas.height - content.height - f.barHeight) / 2 + f.barHeight + f.glassBorder) * fit,
                             width: content.width * fit, height: content.height * fit)
        return ZStack(alignment: .topLeading) {
            Color.clear
            if let s = dragStart, let n = dragNow, model.tool == .crop || model.tool == .blur {
                Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: abs(n.x - s.x) * picture.width, height: abs(n.y - s.y) * picture.height)
                    .offset(x: picture.minX + min(s.x, n.x) * picture.width, y: picture.minY + min(s.y, n.y) * picture.height)
            }
        }
        .frame(width: canvas.width * fit, height: canvas.height * fit)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let p = CGPoint(x: (v.location.x - picture.minX) / picture.width, y: (v.location.y - picture.minY) / picture.height)
            let clamped = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
            if dragStart == nil { dragStart = clamped }
            dragNow = clamped
        }.onEnded { _ in
            defer { dragStart = nil; dragNow = nil }
            guard let a = dragStart, let b = dragNow else { return }
            let moved = hypot(a.x - b.x, a.y - b.y) > 0.005
            switch model.tool {
            case .arrow: if moved { model.add(Mark(kind: .arrow, a: a, b: b, color: model.ink)) }
            case .rect: if moved { model.add(Mark(kind: .rect, a: a, b: b, color: model.ink)) }
            case .highlight: if moved { model.add(Mark(kind: .highlight, a: a, b: b, color: model.ink)) }
            case .blur: if moved { model.add(Mark(kind: .blur, a: a, b: b, color: .clear)) }
            case .number: model.add(Mark(kind: .number, a: b, b: b, number: model.nextNumber, color: model.ink))
            case .text: pendingText = b
            case .crop: if moved { model.crop = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)) }
            case .pick:
                let rep = NSBitmapImageRep(cgImage: model.original)
                if let c = rep.colorAt(x: Int(b.x * CGFloat(rep.pixelsWide)), y: Int(b.y * CGFloat(rep.pixelsHigh))) { model.ink = Color(nsColor: c) }
            case .select: break
            }
        })
    }

    @ViewBuilder private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(L("shot.frame")) {
                grid(Beautify.Frame.allCases.map(\.name), selected: Beautify.Frame.allCases.firstIndex(of: model.frame) ?? 0) { model.frame = Beautify.Frame.allCases[$0] }
                if model.frame.hasAddressBar { TextField(L("shot.address"), text: $model.address).textFieldStyle(.roundedBorder) }
            }
            section(L("shot.corner") + " \(Int(model.radius))") { Slider(value: $model.radius, in: 0...32) }
            section(L("shot.padding") + " \(Int(model.padding))") { Slider(value: $model.padding, in: 0...200) }
            section(L("shot.shadow")) { grid(Beautify.shadows.map(\.name), selected: model.shadow) { model.shadow = $0 } }
            section(L("shot.ratio")) { grid(Beautify.ratios.map { $0.glyph.isEmpty ? $0.name : "\($0.glyph) \($0.name)" }, selected: model.ratio) { model.ratio = $0 } }
            section(L("shot.background")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Array(Beautify.backgrounds.enumerated()), id: \.offset) { i, b in
                        FillView(fill: b.fill, image: model.original).frame(width: 44, height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.background == i ? Color.accentColor : Color.black.opacity(0.1), lineWidth: model.background == i ? 2 : 1))
                            .help(b.name)
                            .onTapGesture { model.background = i }
                    }
                }
                Toggle("Grain", isOn: $model.grain)
            }
            section(L("shot.count")) { Picker("", selection: $model.count) { Text("1").tag(1); Text("2").tag(2); Text("3").tag(3) }.pickerStyle(.segmented) }
            section(L("shot.size") + " \(Int(model.zoom))%") { Slider(value: $model.zoom, in: 50...150) }
            section(L("shot.layout")) { grid(Beautify.layouts.map(\.name), selected: model.layout) { model.layout = $0 } }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func grid(_ names: [String], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                Button { pick(i) } label: {
                    Text(n).font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected == i ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected == i ? Color.accentColor : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleKey(_ key: String, _ flags: NSEvent.ModifierFlags) -> Bool {
        if flags.contains(.command) {
            if key == "z" { flags.contains(.shift) ? model.redo() : model.undo(); return true }
            return false
        }
        guard model.annotating, let t = StudioModel.Tool.allCases.first(where: { $0.key == key }) else { return false }
        model.tool = t
        return true
    }
}

/// "⠿ Seret ke app": drags the rendered result as a PNG file.
struct DragOut: View {
    var model: StudioModel
    var body: some View {
        Label(L("shot.dragToApp"), systemImage: "line.3.horizontal")
            .font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            .onDrag { model.exportTemp().map { NSItemProvider(contentsOf: $0) ?? NSItemProvider() } ?? NSItemProvider() }
    }
}

/// Key events for tool shortcuts (V A R T H B N K I) and ⌘Z; returns true when handled.
struct KeyCatcher: NSViewRepresentable {
    var handler: (String, NSEvent.ModifierFlags) -> Bool
    func makeNSView(context: Context) -> NSView {
        let v = KeyView(); v.handler = handler; return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v as? KeyView)?.handler = handler }

    final class KeyView: NSView {
        var handler: ((String, NSEvent.ModifierFlags) -> Bool)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.window === self.window, !(e.window?.firstResponder is NSTextView) else { return e }
                return self.handler?(e.charactersIgnoringModifiers?.lowercased() ?? "", e.modifierFlags) == true ? nil : e
            }
        }
    }
}
