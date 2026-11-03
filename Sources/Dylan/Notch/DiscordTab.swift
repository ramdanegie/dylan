import AppKit
import DylanCore
import SwiftUI

/// Up to 3 avatars, newest speaker first, green ring while speaking (design D25, M9).
struct DiscordAvatars: View {
    var size: CGFloat
    private var d: DiscordProvider { DiscordProvider.shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let speakers = d.state.speakers
        let others = d.state.members.filter { m in !speakers.contains { $0.id == m.id } && m.id != d.state.userID }
        let shown = Array((speakers + others).prefix(3))
        HStack(spacing: -size * 0.3) {
            ForEach(shown) { m in DiscordAvatar(member: m, size: size) }
            if d.state.members.count > 3 {
                SwiftUI.Text("+\(d.state.members.count - 3)").font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2).padding(.leading, size * 0.4)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: speakers.map(\.id))
        .accessibilityLabel(speakers.isEmpty ? "" : L("discord.speaking", speakers.map(\.name).joined(separator: ", ")))
    }
}

struct DiscordAvatar: View {
    var member: DiscordState.Member
    var size: CGFloat
    private var model: AppModel { AppModel.shared }
    var body: some View {
        ZStack {
            Circle().fill(Color(hue: Double(abs(member.id.hashValue % 360)) / 360, saturation: 0.45, brightness: 0.6))
            if !model.presentationMode, let s = member.avatarURL, let u = URL(string: s) {
                AsyncImage(url: u) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }.clipShape(Circle())
            }
            if model.presentationMode || member.avatarURL == nil {
                SwiftUI.Text(String(member.name.prefix(1)).uppercased()).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        // 1.5 pt green ring with a 1.5 pt black gap (M9).
        .overlay(Circle().stroke(Color.black, lineWidth: 1.5).padding(-1.5))
        .overlay(Circle().stroke(member.speaking ? DY.ok : .clear, lineWidth: 1.5).padding(-3))
    }
}

/// Expanded → Discord (design D26): connected view or the 3-step Client ID guide.
struct DiscordTab: View {
    @StateBox private var clientID = AppModel.shared.discordClientID
    private var d: DiscordProvider { DiscordProvider.shared }
    private var model: AppModel { AppModel.shared }

    var body: some View {
        if d.connected && d.state.authenticated { connected } else { setup }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 10) {
            if d.state.inVoice {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        SwiftUI.Text(model.presentationMode ? L("discord.voiceGeneric") : "#\(d.state.channelName ?? "voice")")
                            .font(DY.font(14, .semibold)).foregroundStyle(.white)
                        SwiftUI.Text(L("discord.people", d.state.members.count)).font(DY.font(11, .regular)).foregroundStyle(DY.fg2)
                    }
                    Spacer()
                    NotchButton(title: d.state.selfMute ? L("discord.unmute") : L("discord.mute"), kind: d.state.selfMute ? .destructive : .normal, height: 28) { d.toggleMute() }
                    NotchButton(title: d.state.selfDeaf ? L("discord.undeafen") : L("discord.deafen"), kind: d.state.selfDeaf ? .destructive : .normal, height: 28) { d.toggleDeaf() }
                    NotchButton(title: L("discord.leave"), kind: .quiet, height: 28) { d.leave() }
                }
                HStack(spacing: 14) {
                    ForEach(d.state.members.prefix(6)) { m in
                        VStack(spacing: 3) {
                            DiscordAvatar(member: m, size: 30)
                            SwiftUI.Text(model.presentationMode ? "" : (m.id == d.state.userID ? L("discord.you", m.name) : m.name))
                                .font(DY.font(10.5, .regular)).foregroundStyle(m.speaking ? .white : DY.fg2).lineLimit(1).frame(width: 64)
                            if m.muted || m.deafened {
                                Image(systemName: m.deafened ? "headphones" : "mic.slash.fill").font(.system(size: 9)).foregroundStyle(DY.fail)
                            }
                        }
                    }
                }
            } else {
                EmptyCard(symbol: "headphones", text: L("discord.notInVoice"))
            }
            if let msg = d.state.lastMessage {
                Divider().overlay(Color.white.opacity(0.08))
                SwiftUI.Text(L("discord.dms")).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                HStack(spacing: 8) {
                    SwiftUI.Text(model.presentationMode ? L("discord.messageGeneric") : L("discord.messageIn", msg.author, msg.channel) + " · " + msg.body)
                        .font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                    Spacer()
                    if let u = DiscordState.deepLink(msg) { NotchButton(title: L("button.open")) { model.perform(.openDiscord(u)) } }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Text(L("discord.connectTitle")).font(DY.font(14, .semibold)).foregroundStyle(.white)
            SwiftUI.Text(L("discord.connectBody")).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
            ForEach(Array([L("discord.step1"), L("discord.step2"), L("discord.step3")].enumerated()), id: \.offset) { i, s in
                HStack(spacing: 8) {
                    SwiftUI.Text("\(i + 1)").font(DY.font(10.5, .bold)).foregroundStyle(.black).frame(width: 16, height: 16).background(Circle().fill(.white))
                    SwiftUI.Text(s).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg)
                }
            }
            HStack(spacing: 8) {
                TextField("Client ID", text: $clientID).textFieldStyle(.plain).font(DY.mono).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(DY.control))
                NotchButton(title: L("discord.connect"), kind: .primaryNeutral) {
                    model.discordClientID = clientID.filter(\.isNumber)
                    DiscordProvider.shared.stop(); DiscordProvider.shared.start()
                }
                .disabled(clientID.filter(\.isNumber).count < 15)
                NotchButton(title: L("discord.portal"), kind: .quiet) { NSWorkspace.shared.open(URL(string: "https://discord.com/developers/applications")!) }
            }
            if let s = d.status ?? d.state.lastError { SwiftUI.Text(s).font(DY.font(11)).foregroundStyle(DY.action) }
            SwiftUI.Text(L("discord.privacy")).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
        }
    }
}
