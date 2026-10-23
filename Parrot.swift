// Menu-bar agent that reads the selected text aloud via the local Kokoro daemon (speakd.py).
// ⌥Esc read/stop · ⌥⇧Esc pause/resume · Esc stops while speaking · click the icon for controls and settings.
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

let daemonURL = URL(string: "http://127.0.0.1:47811")!
let defaults = UserDefaults.standard
let supportDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Parrot")

/// Appends a line to ~/Library/Logs/Parrot.log for troubleshooting (never logs the text itself).
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

// MARK: - Models

struct VoiceModel: Identifiable {
    let id: String, name: String, file: String, sizeMB: Int, blurb: String
    var bundled: Bool { id == "fast" }
    var url: URL {
        bundled ? Bundle.main.resourceURL!.appendingPathComponent("models/\(file)")
                : supportDir.appendingPathComponent("models/\(file)")
    }
    var remote: URL { URL(string: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/\(file)")! }
    var installed: Bool { FileManager.default.fileExists(atPath: url.path) }
}

let voiceModels = [
    VoiceModel(id: "fast", name: "Fast", file: "kokoro-v1.0.int8.onnx", sizeMB: 88, blurb: "Built in. Quickest start, great quality."),
    VoiceModel(id: "balanced", name: "Balanced", file: "kokoro-v1.0.fp16.onnx", sizeMB: 169, blurb: "Slightly cleaner audio."),
    VoiceModel(id: "best", name: "Best", file: "kokoro-v1.0.onnx", sizeMB: 310, blurb: "Full precision. Richest sound, slower start."),
]

struct Voice: Identifiable, Hashable {
    let id: String
    var name: String { id.split(separator: "_").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? id }
    var accent: String { id.hasPrefix("a") ? "American" : "British" }
    var gender: String { id.dropFirst().hasPrefix("f") ? "Female" : "Male" }
    var flag: String { id.hasPrefix("a") ? "🇺🇸" : "🇬🇧" }
}

// MARK: - State

final class Parrot: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Parrot()

    @Published var status = "idle" { didSet { if status != oldValue { onStatusChange?() } } }
    @Published var voices: [Voice] = []
    @Published var voice = defaults.string(forKey: "voice") ?? "af_heart" { didSet { defaults.set(voice, forKey: "voice"); pushConfig() } }
    @Published var speed = defaults.object(forKey: "speed") as? Double ?? 1.25 { didSet { defaults.set(speed, forKey: "speed"); pushConfig() } }
    @Published var model = defaults.string(forKey: "model") ?? "fast" { didSet { defaults.set(model, forKey: "model"); pushConfig() } }
    @Published var downloads: [String: Double] = [:]  // model id → progress 0…1
    @Published var trusted = AXIsProcessTrusted()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var daemonReady = false
    @Published var toast: String?
    @Published var showSettings = false

    var onStatusChange: (() -> Void)?
    var daemon: Process?
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func show(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.toast == message { self?.toast = nil } }
    }

    // Daemon lifecycle
    func startDaemon() {
        let p = Process()
        p.executableURL = supportDir.appendingPathComponent("venv/bin/python")
        p.arguments = [Bundle.main.path(forResource: "speakd", ofType: "py")!]
        p.terminationHandler = { [weak self] _ in  // restart if it crashes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, self.daemon != nil else { return }
                self.daemonReady = false; self.startDaemon()
            }
        }
        try? p.run()
        daemon = p
        syncWhenReady()
    }

    /// Wait for the daemon to come up, then push saved settings and load the voice list.
    func syncWhenReady(attempt: Int = 0) {
        request("voices", method: "GET") { [weak self] list in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let list, !list.isEmpty else {
                    if attempt < 120 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.syncWhenReady(attempt: attempt + 1) } }
                    return
                }
                self.voices = list.split(separator: "\n").map { Voice(id: String($0)) }
                self.daemonReady = true
                self.pushConfig()
            }
        }
    }

    func pushConfig() {
        let m = voiceModels.first { $0.id == model && $0.installed } ?? voiceModels[0]
        let path = m.url.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request("config", body: "voice=\(voice)&speed=\(speed)&model=\(path)")
    }

    // Playback
    func toggleSpeak() {
        dbg("read status=%@ trusted=%d", status, AXIsProcessTrusted())
        if status != "idle" { stop(); return }
        guard let text = selectedText(), !text.isEmpty else { dbg("no selection"); NSSound.beep(); return }
        dbg("speaking %d chars", text.count)
        request("speak", body: text)
        status = "speaking"
    }
    func togglePause() { if status != "idle" { request("toggle-pause"); status = status == "paused" ? "speaking" : "paused" } }
    func skip() { request("skip") }
    func stop() { request("stop"); status = "idle" }
    func preview(_ v: Voice) {
        voice = v.id
        request("speak", body: "Hi, I'm \(v.name). This is how I sound.")
        status = "speaking"
    }

    // Settings
    func setLaunchAtLogin(_ on: Bool) {
        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        catch { show("Couldn't change login item") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // Model downloads
    func download(_ m: VoiceModel) {
        try? FileManager.default.createDirectory(at: m.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let task = session.downloadTask(with: m.remote)
        task.taskDescription = m.id
        tasks[m.id] = task
        downloads[m.id] = 0
        task.resume()
    }
    func cancelDownload(_ m: VoiceModel) { tasks[m.id]?.cancel(); tasks[m.id] = nil; downloads[m.id] = nil }
    func delete(_ m: VoiceModel) {
        try? FileManager.default.removeItem(at: m.url)
        if model == m.id { model = "fast" }
        objectWillChange.send()
        show("\(m.name) model removed")
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        if let id = t.taskDescription, e > 0 { downloads[id] = Double(w) / Double(e) }
    }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = t.taskDescription, let m = voiceModels.first(where: { $0.id == id }) else { return }
        guard (t.response as? HTTPURLResponse)?.statusCode == 200 else { return }
        try? FileManager.default.removeItem(at: m.url)
        try? FileManager.default.moveItem(at: location, to: m.url)
    }
    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = t.taskDescription, let m = voiceModels.first(where: { $0.id == id }) else { return }
        tasks[id] = nil; downloads[id] = nil
        if m.installed { model = id; show("\(m.name) model ready") }
        else if (error as? URLError)?.code != .cancelled { show("Download failed. Check your connection.") }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let parrot = Parrot.shared
    var item: NSStatusItem!
    let popover = NSPopover()
    lazy var anchor: NSWindow = {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        w.isOpaque = false; w.backgroundColor = .clear; w.level = .statusBar; w.ignoresMouseEvents = true
        return w
    }()
    var escHotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        dbg("launched trusted=%d", AXIsProcessTrusted())
        // Prompt for Accessibility once; needed to read selections and post ⌘C.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if !defaults.bool(forKey: "didSetLoginItem") { parrot.setLaunchAtLogin(true); defaults.set(true, forKey: "didSetLoginItem") }
        parrot.startDaemon()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        popover.behavior = .transient
        let host = NSHostingController(rootView: PopoverView(close: { [weak self] in self?.popover.performClose(nil) }).environmentObject(parrot))
        host.sizingOptions = .preferredContentSize  // popover follows the SwiftUI size, e.g. when switching pages
        popover.contentViewController = host
        parrot.onStatusChange = { [weak self] in self?.statusChanged() }
        statusChanged()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let p = Parrot.shared
            switch id.id { case 1: p.toggleSpeak(); case 2: p.togglePause(); default: p.stop() }
            return noErr
        }, 1, &spec, nil, nil)
        register(kVK_Escape, optionKey, id: 1)
        register(kVK_Escape, optionKey | shiftKey, id: 2)

        // Poll so the icon, popover and bare-Esc hotkey track playback and permission changes.
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let p = self?.parrot else { return }
            if p.trusted != AXIsProcessTrusted() { p.trusted.toggle() }
            request("status", method: "GET") { s in DispatchQueue.main.async { if let s { p.status = s } } }
        }
    }

    @discardableResult
    func register(_ key: Int, _ mods: Int, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x50525254, id: id), GetApplicationEventTarget(), 0, &ref)
        return ref
    }

    func statusChanged() {
        let symbol = ["speaking": "waveform.circle.fill", "paused": "pause.circle.fill"][parrot.status] ?? "waveform"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Parrot")
        // Plain Esc only stops speech while something is playing, so it never steals Esc otherwise.
        if parrot.status == "idle", let ref = escHotKey { UnregisterEventHotKey(ref); escHotKey = nil }
        if parrot.status != "idle", escHotKey == nil { escHotKey = register(kVK_Escape, 0, id: 3) }
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        parrot.trusted = AXIsProcessTrusted()
        // Measure before showing so the popover is positioned for its real height.
        if let view = popover.contentViewController?.view { view.layoutSubtreeIfNeeded(); popover.contentSize = view.fittingSize }
        if let button = item.button, let w = button.window, w.occlusionState.contains(.visible), w.frame.maxX <= (w.screen?.frame.maxX ?? .infinity) {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            // Icon hidden (e.g. behind the notch): anchor to a tiny window at the top centre of the screen.
            let screen = NSScreen.main!.visibleFrame
            anchor.setFrame(NSRect(x: screen.midX, y: screen.maxY - 1, width: 1, height: 1), display: false)
            anchor.orderFrontRegardless()
            popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    /// parrot://speak|open|settings|pause|stop|skip|faster|slower|voice?af_heart|speed?1.5 — used by launchers such as Tinycast.
    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            let arg = url.query ?? ""
            switch url.host {
            case "speak": parrot.toggleSpeak()
            case "open", "settings":
                parrot.showSettings = url.host == "settings"
                if !popover.isShown { togglePopover() }
            case "pause": parrot.togglePause()
            case "stop": parrot.stop()
            case "skip": parrot.skip()
            case "faster": parrot.speed = min(2.5, ((parrot.speed + 0.25) * 4).rounded() / 4)
            case "slower": parrot.speed = max(0.5, ((parrot.speed - 0.25) * 4).rounded() / 4)
            case "speed": if let v = Double(arg) { parrot.speed = min(2.5, max(0.5, v)) }
            case "voice": if parrot.voices.contains(where: { $0.id == arg }) { parrot.voice = arg }
            default: break
            }
        }
    }

    func applicationWillTerminate(_ n: Notification) { let d = parrot.daemon; parrot.daemon = nil; d?.terminate() }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
