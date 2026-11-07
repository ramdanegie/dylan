import AppKit
import AVFoundation
import DylanCore
import SwiftUI

/// Face enrollment in four steps (design D19): the risks, the camera with a live preview, the login password,
/// and "ready". Nothing is stored before step 3 succeeds; closing the window drops everything.
/// `adding`: another identity (glasses, a mask…) for an enrolled Mac: camera, then a name.
enum FaceEnrollWindow {
    private static var window: NSWindow?

    static func show(adding: Bool = false) {
        // An open wizard may be in the other flow (or finished): start over in the one asked for.
        window?.close()
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L(adding ? "faceUnlock.addTitle" : "faceUnlock.wizardTitle")
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: FaceEnrollView(done: { close() }, step: adding ? 1 : 0, adding: adding))
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { FaceUnlockProvider.shared.cancelEnroll(); window = nil }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() { window?.close() }
}

struct FaceEnrollView: View {
    var done: () -> Void
    @StateBox var step = 0
    var adding = false
    @StateBox private var understood = false
    @StateBox private var password = ""
    @StateBox private var name = ""
    @StateBox private var error: String?
    private var face: FaceUnlockProvider { FaceUnlockProvider.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case 0: risks
                case 1: camera
                case 2: if adding { nameStep } else { passwordStep }
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                HStack(spacing: 4) {
                    ForEach(adding ? 1..<3 : 0..<4, id: \.self) { i in
                        Capsule().fill(i == step ? Color.primary : Color.secondary.opacity(0.35)).frame(width: i == step ? 16 : 5, height: 5)
                    }
                }
                Spacer()
                buttons
            }
            .padding(14)
        }
        .frame(width: 520, height: 470)
    }

    // MARK: 1 — Ini bukan Face ID

    private var risks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Badge()
            SwiftUI.Text(L("faceUnlock.notFaceID")).font(.title2.bold())
            SwiftUI.Text(L("faceUnlock.notFaceIDBody")).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 0) {
                column(L("faceUnlock.goodTitle"), L("faceUnlock.goodBody"), .green)
                Divider()
                column(L("faceUnlock.badTitle"), L("faceUnlock.badBody"), .red)
            }
            .fixedSize(horizontal: false, vertical: true)   // the vertical Divider would stretch the box
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            SwiftUI.Text(L("faceUnlock.stored")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SwiftUI.Text(L("faceUnlock.never")).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle(L("faceUnlock.understood"), isOn: $understood).toggleStyle(.checkbox)
        }
        .padding(22)
    }

    private func column(_ title: String, _ body: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SwiftUI.Text(title).font(.caption.bold()).foregroundStyle(color)
            SwiftUI.Text(body).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 2 — camera with a progress ring

    private var camera: some View {
        VStack(spacing: 14) {
            HStack {
                SwiftUI.Text(adding ? L("faceUnlock.stepOf", 1, 2) : L("faceUnlock.stepOf", 2, 4)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if face.enrollState == .capturing {
                    Label(L("faceUnlock.cameraOn"), systemImage: "circle.fill").font(.caption).foregroundStyle(.green).labelStyle(DotLabel())
                }
            }
            ZStack {
                if let cam = face.enrollCamera {
                    CameraPreview(session: cam.session).clipShape(Circle()).frame(width: 170, height: 170)
                } else {
                    Circle().fill(Color.secondary.opacity(0.15)).frame(width: 170, height: 170)
                }
                PoseRing(coverage: face.coverage).frame(width: 200, height: 200)
                if let h = face.enrollHead {
                    Circle().fill(face.enrollTooFar ? Color.orange : Color.white).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                        .offset(x: h.x * 70, y: h.y * 70)
                        .animation(.easeOut(duration: 0.12), value: h)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L("faceUnlock.frames", face.enrollCount, FaceUnlockProvider.enrollTarget))
            SwiftUI.Text(headline).font(.headline).foregroundStyle(face.enrollTooFar ? .orange : .primary)
            switch face.enrollState {
            case .failed(let why):
                SwiftUI.Text(why).font(.caption).foregroundStyle(.red)
                Button(L("faceUnlock.retry")) { face.beginEnrollCapture() }
            default:
                SwiftUI.Text(face.enrollFaces > 1 ? L("faceUnlock.oneFace") : L("faceUnlock.frames", face.enrollCount, FaceUnlockProvider.enrollTarget))
                    .font(.caption).foregroundStyle(face.enrollFaces > 1 ? .orange : .secondary).monospacedDigit()
            }
        }
        .padding(22)
        .onAppear { face.beginEnrollCapture() }
        .onChange(of: face.enrollState) { _, s in if s == .captured { step = 2 } }
    }

    /// "Look up and to the left", "Come back a little", or the generic line before a face is seen.
    private var headline: String {
        if face.enrollTooFar { return L("faceUnlock.tooFar") }
        guard face.enrollState == .capturing, face.enrollHead != nil, let p = face.coverage.missing else { return L("faceUnlock.turnHead") }
        return L("faceUnlock.pose.\(p)")
    }

    // MARK: 3 (adding) — a name for this look

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text(L("faceUnlock.stepOf", 2, 2)).font(.caption).foregroundStyle(.secondary)
            SwiftUI.Text(L("faceUnlock.nameTitle")).font(.title2.bold())
            SwiftUI.Text(L("faceUnlock.nameBody")).fixedSize(horizontal: false, vertical: true)
            TextField(L("faceUnlock.nameField"), text: $name).textFieldStyle(.roundedBorder).onSubmit(saveIdentity)
            HStack {
                ForEach(["faceUnlock.preset.glasses", "faceUnlock.preset.mask", "faceUnlock.preset.dim"], id: \.self) { k in
                    Button(L(k)) { name = L(k) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            if let error { SwiftUI.Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(22)
    }

    private func saveIdentity() {
        error = face.addIdentity(name: name)
        if error == nil { done() }
    }

    // MARK: 3 — password

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text(L("faceUnlock.stepOf", 3, 4)).font(.caption).foregroundStyle(.secondary)
            SwiftUI.Text(L("faceUnlock.password")).font(.title2.bold())
            SwiftUI.Text(L("faceUnlock.passwordBody")).fixedSize(horizontal: false, vertical: true)
            SecureField(L("faceUnlock.passwordField"), text: $password).textFieldStyle(.roundedBorder).onSubmit(save)
            if let error { SwiftUI.Text(error).font(.caption).foregroundStyle(.red) }
            SwiftUI.Text(L("faceUnlock.passwordChanged")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
    }

    private func save() {
        guard !password.isEmpty else { return }
        error = face.completeEnrollment(password: password)
        password = ""
        if error == nil { step = 3 }
    }

    // MARK: 4 — ready

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(.green)
            SwiftUI.Text(L("faceUnlock.readyTitle")).font(.title2.bold())
            SwiftUI.Text(L("faceUnlock.readyBody")).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                row(L("faceUnlock.rowLocked"), L("faceUnlock.minutes", face.vault.settings.maxLockedMinutes))
                row(L("faceUnlock.rowTries"), "1")
                row(L("faceUnlock.rowFaces"), L("faceUnlock.exactlyOne"))
                row(L("faceUnlock.rowPresentation"), L("faceUnlock.presentationOff"))
            }
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            SwiftUI.Text(L("faceUnlock.tryHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let issue = face.readinessIssue {
                Label(L("faceUnlock.denial.\(issue.rawValue)"), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(22)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { SwiftUI.Text(k).font(.callout); Spacer(); SwiftUI.Text(v).font(.callout).foregroundStyle(.secondary) }
            .padding(.horizontal, 10).padding(.vertical, 7)
    }

    // MARK: Buttons

    @ViewBuilder private var buttons: some View {
        switch step {
        case 0:
            Button(L("button.cancel")) { done() }.keyboardShortcut(.cancelAction)
            Button(L("faceUnlock.next")) { step = 1 }.keyboardShortcut(.defaultAction).disabled(!understood)
        case 1:
            Button(L("button.cancel")) { done() }.keyboardShortcut(.cancelAction)
        case 2 where adding:
            Button(L("button.cancel")) { done() }.keyboardShortcut(.cancelAction)
            Button(L("faceUnlock.save")) { saveIdentity() }.keyboardShortcut(.defaultAction)
        case 2:
            Button(L("faceUnlock.back")) { password = ""; error = nil; step = 1 }
            Button(L("faceUnlock.save")) { save() }.keyboardShortcut(.defaultAction).disabled(password.isEmpty)
        default:
            Button(L("faceUnlock.finish")) { done() }
            Button(L("faceUnlock.tryLock")) { done(); FaceUnlockProvider.lockNow() }.keyboardShortcut(.defaultAction)
        }
    }
}

/// "EKSPERIMENTAL" chip (D19, D20).
struct Badge: View {
    var body: some View {
        SwiftUI.Text(L("faceUnlock.experimental")).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.yellow.opacity(0.35)))
    }
}

private struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.system(size: 6)); configuration.title }
    }
}

/// One arc per head direction around the preview, green once that direction has its frames (D19, after Glance's
/// nine directions). Mirrored like the preview: "left" is the user's left, drawn on the left.
private struct PoseRing: View {
    var coverage: PoseCoverage
    /// Screen angle of each direction (0° = right, clockwise, as SwiftUI draws).
    private static let angles: [PoseCoverage.Pose: Double] = [
        .right: 0, .downRight: 45, .down: 90, .downLeft: 135, .left: 180, .upLeft: 225, .up: 270, .upRight: 315,
    ]
    var body: some View {
        ZStack {
            ForEach(PoseCoverage.Pose.allCases.filter { $0 != .center }, id: \.self) { p in
                Circle()
                    .trim(from: 0, to: 38.0 / 360)
                    .stroke(coverage.isFull(p) ? Color.green : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(Self.angles[p]! - 19))
            }
            Circle().stroke(coverage.isFull(.center) ? Color.green : Color.clear, lineWidth: 2).padding(14)
        }
        .animation(.easeOut(duration: 0.2), value: coverage)
    }
}

/// Live, mirrored camera preview; frames are shown, never saved.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let c = layer.connection, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
        v.layer = layer
        v.wantsLayer = true
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
