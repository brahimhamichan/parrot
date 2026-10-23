// Menu-bar agent that reads the selected text aloud via the local Kokoro daemon.
// ⌥Esc speak/stop · ⌥⇧Esc pause/resume · Esc stops while speaking · voice and speed in the menu.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

let daemonURL = URL(string: "http://127.0.0.1:47811")!
let speeds: [Double] = [0.8, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5]
let defaults = UserDefaults.standard

/// Appends a line to ~/Library/Logs/Parrot.log for troubleshooting.
func dbg(_ fmt: String, _ args: CVarArg...) {
    let line = "\(Date()) " + String(format: fmt, arguments: args) + "\n"
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Parrot.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

func request(_ path: String, body: String = "", method: String = "POST", done: ((String?) -> Void)? = nil) {
    var req = URLRequest(url: daemonURL.appendingPathComponent(path), timeoutInterval: 2)
    req.httpMethod = method
    if method == "POST" { req.httpBody = body.data(using: .utf8) }
    URLSession.shared.dataTask(with: req) { data, _, _ in
        done?(data.flatMap { String(data: $0, encoding: .utf8) })
    }.resume()
}

/// Reads the selection through Accessibility; falls back to a simulated ⌘C that restores the clipboard.
func selectedText() -> String? {
    let system = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success {
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
           let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
    }
    let pb = NSPasteboard.general
    let saved = pb.pasteboardItems?.map { item -> NSPasteboardItem in
        let copy = NSPasteboardItem()
        for type in item.types { if let d = item.data(forType: type) { copy.setData(d, forType: type) } }
        return copy
    } ?? []
    let before = pb.changeCount
    let src = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
    }
    for _ in 0..<15 where pb.changeCount == before { usleep(20_000) }
    let text = pb.changeCount != before ? pb.string(forType: .string) : nil
    if pb.changeCount != before { pb.clearContents(); pb.writeObjects(saved) }
    return text
}

/// "af_heart" → "Heart (US ♀)"
func voiceLabel(_ id: String) -> String {
    let p = Array(id)
    let name = id.split(separator: "_").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? id
    return "\(name) (\(p[0] == "a" ? "US" : "UK") \(p[1] == "f" ? "♀" : "♂"))"
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    var daemon: Process?
    var escHotKey: EventHotKeyRef?
    var status = "idle" { didSet { if status != oldValue { statusChanged() } } }
    var voices: [String] = []
    var voice: String { get { defaults.string(forKey: "voice") ?? "af_heart" } set { defaults.set(newValue, forKey: "voice") } }
    var speed: Double { get { defaults.object(forKey: "speed") as? Double ?? 1.25 } set { defaults.set(newValue, forKey: "speed") } }

    func applicationDidFinishLaunching(_ n: Notification) {
        // Prompt for Accessibility once; needed to read selections and post ⌘C.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        startDaemon()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusChanged()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
            switch id.id { case 1: app.toggleSpeak(); case 2: app.togglePause(); default: app.stop() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        dbg("launched trusted=%d", AXIsProcessTrusted())
        register(kVK_Escape, optionKey, id: 1)
        register(kVK_Escape, optionKey | shiftKey, id: 2)

        // Poll while active so the icon and the bare-Esc hotkey track playback.
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            request("status", method: "GET") { s in DispatchQueue.main.async { self?.status = s ?? "idle" } }
        }
    }

    @discardableResult
    func register(_ key: Int, _ mods: Int, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x50525254, id: id), GetApplicationEventTarget(), 0, &ref)
        return ref
    }

    func statusChanged() {
        let symbol = ["speaking": "waveform.circle.fill", "paused": "pause.circle.fill"][status] ?? "waveform"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Parrot")
        // Plain Esc only stops speech while something is playing, so it never steals Esc otherwise.
        if status == "idle", let ref = escHotKey { UnregisterEventHotKey(ref); escHotKey = nil }
        if status != "idle", escHotKey == nil { escHotKey = register(kVK_Escape, 0, id: 3) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, to m: NSMenu = menu) -> NSMenuItem {
            let i = m.addItem(withTitle: title, action: action, keyEquivalent: ""); i.target = self; return i
        }
        if status == "idle" {
            add("Read Selection   ⌥⎋", #selector(toggleSpeak))
        } else {
            add(status == "paused" ? "Resume   ⌥⇧⎋" : "Pause   ⌥⇧⎋", #selector(togglePause))
            add("Skip Sentence", #selector(skip))
            add("Stop   ⎋", #selector(stop))
        }
        menu.addItem(.separator())

        let speedMenu = NSMenu()
        for s in speeds {
            let i = add(String(format: "%g×", s), #selector(pickSpeed(_:)), to: speedMenu)
            i.representedObject = s; i.state = s == speed ? .on : .off
        }
        menu.addItem(withTitle: String(format: "Speed: %g×", speed), action: nil, keyEquivalent: "").submenu = speedMenu

        let voiceMenu = NSMenu()
        for v in voices {
            let i = add(voiceLabel(v), #selector(pickVoice(_:)), to: voiceMenu)
            i.representedObject = v; i.state = v == voice ? .on : .off
        }
        menu.addItem(withTitle: "Voice: \(voiceLabel(voice))", action: nil, keyEquivalent: "").submenu = voiceMenu

        menu.addItem(.separator())
        add("Quit", #selector(quit))
    }

    func startDaemon() {
        let p = Process()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        p.executableURL = URL(fileURLWithPath: "\(home)/.local/share/local-tts/venv/bin/python")
        p.arguments = [Bundle.main.path(forResource: "speakd", ofType: "py")!]
        p.terminationHandler = { [weak self] _ in  // restart if it crashes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self?.daemon != nil { self?.startDaemon() } }
        }
        try? p.run()
        daemon = p
        syncWhenReady()
    }

    /// Wait for the daemon to come up, then push saved settings and load the voice list.
    func syncWhenReady(attempt: Int = 0) {
        request("voices", method: "GET") { [weak self] list in
            guard let self else { return }
            guard let list, !list.isEmpty else {
                if attempt < 60 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.syncWhenReady(attempt: attempt + 1) } }
                return
            }
            DispatchQueue.main.async { self.voices = list.split(separator: "\n").map(String.init); self.pushConfig() }
        }
    }

    func pushConfig() { request("config", body: "voice=\(voice)&speed=\(speed)") }

    @objc func toggleSpeak() {
        dbg("hotkey status=%@ trusted=%d", status, AXIsProcessTrusted())
        if status != "idle" { stop(); return }
        guard let text = selectedText(), !text.isEmpty else { dbg("no selection"); NSSound.beep(); return }
        dbg("speaking %d chars", text.count)
        request("speak", body: text)
        status = "speaking"
    }
    @objc func togglePause() { if status != "idle" { request("toggle-pause"); status = status == "paused" ? "speaking" : "paused" } }
    @objc func skip() { request("skip") }
    @objc func stop() { request("stop"); status = "idle" }
    @objc func pickSpeed(_ sender: NSMenuItem) { speed = sender.representedObject as! Double; pushConfig() }
    @objc func pickVoice(_ sender: NSMenuItem) {
        voice = sender.representedObject as! String
        pushConfig()
        request("speak", body: "Hi, I'm \(voiceLabel(voice).split(separator: " ")[0]). This is how I sound.")
    }
    /// parrot://speak|pause|stop|skip|faster|slower|voice?af_heart|speed?1.5 — used by Tinycast commands.
    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            let arg = url.query ?? ""
            switch url.host {
            case "speak": toggleSpeak()
            case "pause": togglePause()
            case "stop": stop()
            case "skip": skip()
            case "faster", "slower":
                let i = speeds.firstIndex(of: speed) ?? 3
                speed = speeds[max(0, min(speeds.count - 1, i + (url.host == "faster" ? 1 : -1)))]
                pushConfig()
            case "speed": if let v = Double(arg) { speed = v; pushConfig() }
            case "voice": if voices.contains(arg) { voice = arg; pushConfig() }
            default: break
            }
        }
    }
    @objc func quit() { let d = daemon; daemon = nil; d?.terminate(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ n: Notification) { daemon?.terminate() }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
