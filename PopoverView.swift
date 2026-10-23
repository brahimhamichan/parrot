// The menu-bar popover: playback, voice, speed, model downloads and settings.
import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var p: Parrot
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if p.showSettings {
                Section2(title: "Model") { VStack(spacing: 4) { ForEach(voiceModels) { ModelRow(m: $0) } } }
                Divider()
                settings
            } else {
                if !p.trusted { permissionBanner }
                playback
                Divider()
                Section2(title: "Voice") { VoicePicker() }
                Section2(title: "Speed", trailing: speedLabel(p.speed)) { speedControl }
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .overlay(alignment: .bottom) { toast }
        .animation(.easeOut(duration: 0.2), value: p.toast)
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Parrot").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !p.daemonReady { ProgressView().controlSize(.small) }
            Button { p.showSettings.toggle() } label: {
                Image(systemName: p.showSettings ? "chevron.backward" : "gearshape").frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless).help(p.showSettings ? "Back" : "Settings")
        }
    }

    var statusText: String {
        if p.showSettings { return "Settings" }
        if !p.daemonReady { return "Loading voice model…" }
        return ["speaking": "Speaking…", "paused": "Paused"][p.status] ?? "Select text anywhere and press ⌥Esc"
    }

    var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Allow Accessibility access").font(.subheadline.weight(.semibold))
                Text("Parrot needs it to read the text you select.").font(.caption).foregroundStyle(.secondary)
                Button("Open System Settings") { p.openAccessibilitySettings() }.controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    var playback: some View {
        HStack(spacing: 8) {
            if p.status != "idle" {
                IconButton(symbol: "stop.fill", help: "Stop (Esc)") { p.stop() }
                IconButton(symbol: "forward.end.fill", help: "Skip sentence") { p.skip() }
                IconButton(symbol: p.status == "paused" ? "play.fill" : "pause.fill", help: "Pause or resume (⌥⇧Esc)") { p.togglePause() }
            }
            Spacer()
            if p.status == "idle" {
                Button {
                    // Hand focus back to the previous app so its selection can be read.
                    close(); NSApp.hide(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { p.toggleSpeak() }
                } label: {
                    Label("Read Selection", systemImage: "play.fill").frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!p.daemonReady)
            }
        }
    }

    var speedControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise.fill").foregroundStyle(.secondary).font(.caption)
            Slider(value: Binding(get: { p.speed }, set: { p.speed = ($0 * 20).rounded() / 20 }), in: 0.5...2.5)
            Image(systemName: "hare.fill").foregroundStyle(.secondary).font(.caption)
            Button("Reset") { p.speed = 1.25 }.buttonStyle(.link).font(.caption).opacity(p.speed == 1.25 ? 0 : 1)
        }
    }

    var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(get: { p.launchAtLogin }, set: { p.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Text("Accessibility")
                Spacer()
                Label(p.trusted ? "Allowed" : "Not allowed", systemImage: p.trusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(p.trusted ? .green : .orange).font(.caption)
            }
            VStack(alignment: .leading, spacing: 4) {
                Shortcut(keys: "⌥ Esc", label: "Read selection, or stop")
                Shortcut(keys: "⌥ ⇧ Esc", label: "Pause or resume")
                Shortcut(keys: "Esc", label: "Stop while speaking")
            }
            .padding(.top, 2)
        }
        .font(.callout)
    }

    var footer: some View {
        HStack {
            Link("GitHub", destination: URL(string: "https://github.com/brahimhamichan/parrot")!).font(.caption)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit Parrot") { NSApp.terminate(nil) }.controlSize(.small)
        }
    }

    @ViewBuilder var toast: some View {
        if let t = p.toast {
            Text(t).font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.thickMaterial, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// 1.25 → "1.25×", 1.5 → "1.5×", 2 → "2×"
func speedLabel(_ v: Double) -> String {
    var t = String(format: "%.2f", v)
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t.removeLast() }
    return t + "×"
}

struct Section2<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            content
        }
    }
}

struct IconButton: View {
    let symbol: String, help: String, action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 22) }
            .buttonStyle(.bordered).controlSize(.large).help(help)
    }
}

struct Shortcut: View {
    let keys: String, label: String
    var body: some View {
        HStack {
            Text(keys).font(.caption.monospaced())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Searchable voice dropdown with a preview button per voice.
struct VoicePicker: View {
    @EnvironmentObject var p: Parrot
    @State private var open = false
    @State private var query = ""

    var current: Voice { Voice(id: p.voice) }
    var filtered: [Voice] {
        query.isEmpty ? p.voices : p.voices.filter {
            "\($0.name) \($0.accent) \($0.gender)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack {
                Text(current.flag)
                Text(current.name).fontWeight(.medium)
                Text("\(current.accent) · \(current.gender)").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .trailing) {
            VStack(spacing: 0) {
                TextField("Search voices", text: $query).textFieldStyle(.roundedBorder).padding(10)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { v in
                            HStack {
                                Text(v.flag)
                                Text(v.name).fontWeight(v.id == p.voice ? .semibold : .regular)
                                Text(v.gender).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { p.preview(v) } label: { Image(systemName: "speaker.wave.2.fill") }
                                    .buttonStyle(.borderless).help("Preview")
                                Image(systemName: "checkmark").opacity(v.id == p.voice ? 1 : 0).foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(v.id == p.voice ? Color.accentColor.opacity(0.12) : .clear)
                            .onTapGesture { p.voice = v.id; open = false }
                        }
                        if filtered.isEmpty { Text("No voices match").foregroundStyle(.secondary).padding() }
                    }
                }
                .frame(height: 280)
            }
            .frame(width: 260)
        }
    }
}

struct ModelRow: View {
    @EnvironmentObject var p: Parrot
    let m: VoiceModel

    var body: some View {
        let inUse = p.model == m.id && m.installed
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: inUse ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(inUse ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.name).fontWeight(.medium)
                    Text("\(m.sizeMB) MB").font(.caption).foregroundStyle(.secondary)
                }
                if let progress = p.downloads[m.id] {
                    ProgressView(value: progress).controlSize(.small)
                } else {
                    Text(m.blurb).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if p.downloads[m.id] != nil {
                Button("Cancel") { p.cancelDownload(m) }.controlSize(.small)
            } else if !m.installed {
                Button { p.download(m) } label: { Label("Download", systemImage: "arrow.down.circle") }.controlSize(.small)
            } else if !inUse {
                if !m.bundled {
                    Button { p.delete(m) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove download")
                }
                Button("Use") { p.model = m.id; p.show("Switched to \(m.name)") }.controlSize(.small)
            }
        }
        .padding(8)
        .background(inUse ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
