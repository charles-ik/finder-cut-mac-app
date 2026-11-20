// Finder Cut: ⌘X then ⌘V moves files in Finder, by rewriting the real keypress (⌘X→⌘C, ⌘V→⌥⌘V).
import AppKit
import ApplicationServices
import ServiceManagement

enum Action: Equatable { case pass, toCopy, toMove }

/// Pure decision logic, kept separate so --selftest can check it.
func decide(key: Int64, flags: CGEventFlags, inFinder: Bool, editingText: Bool, cutPending: Bool) -> Action {
    let mods = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
    guard inFinder, !editingText, mods == .maskCommand else { return .pass }
    if key == 7 { return .toCopy }                 // X
    if key == 9 && cutPending { return .toMove }   // V
    return .pass
}

final class Controller: NSObject {
    var tap: CFMachPort?
    var cutChangeCount: Int?          // pasteboard changeCount right after our ⌘X copy
    var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var cutPending: Bool { cutChangeCount != nil && cutChangeCount == NSPasteboard.general.changeCount }

    func finderPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.finder" else { return nil }
        return app.processIdentifier
    }

    func editingText(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)  // never stall typing if Finder is busy
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el as! AXUIElement, kAXRoleAttribute as CFString, &role)
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role as? String ?? "")
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        guard enabled, type == .keyDown else { return event }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == 7 || key == 9, event.flags.contains(.maskCommand) else { return event }  // cheap exit for all other keys
        let pid = finderPID()
        let action = decide(key: key, flags: event.flags, inFinder: pid != nil,
                            editingText: pid.map(editingText) ?? false, cutPending: cutPending)
        switch action {
        case .pass: break
        case .toCopy:
            event.setIntegerValueField(.keyboardEventKeycode, value: 8)
            cutChangeCount = nil
            let before = NSPasteboard.general.changeCount
            // Finder writes the pasteboard asynchronously; remember the count once it has.
            func check(_ tries: Int) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let now = NSPasteboard.general.changeCount
                    if now != before { self.cutChangeCount = now; self.updateIcon() }
                    else if tries > 0 { check(tries - 1) }
                }
            }
            check(40)
        case .toMove:
            event.flags.insert(.maskAlternate)
            cutChangeCount = nil
        }
        updateIcon()
        return event
    }

    func installTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, ctx in
            let me = Unmanaged<Controller>.fromOpaque(ctx!).takeUnretainedValue()
            guard let out = me.handle(type, event) else { return nil }
            return Unmanaged.passUnretained(out)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: cb,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func start() {
        if !UserDefaults.standard.bool(forKey: "didSetUpLogin") {  // open at login by default, once; user can untick it
            try? SMAppService.mainApp.register(); UserDefaults.standard.set(true, forKey: "didSetUpLogin")
        }
        buildMenu(); updateIcon()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) { installTap(); return }
        // Wait for the user to grant Accessibility, then start.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if AXIsProcessTrusted() { t.invalidate(); self.installTap(); self.buildMenu(); self.updateIcon() }
        }
    }

    func updateIcon() {
        let name = !enabled || tap == nil ? "scissors.badge.ellipsis" : (cutPending ? "scissors.circle.fill" : "scissors")
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Finder Cut")
        item.button?.appearsDisabled = !enabled
    }

    func buildMenu() {
        let m = NSMenu()
        if tap == nil {
            m.addItem(withTitle: "Needs Accessibility permission…", action: #selector(openAX), keyEquivalent: "").target = self
            m.addItem(.separator())
        }
        let e = m.addItem(withTitle: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        e.target = self; e.state = enabled ? .on : .off
        let l = m.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        l.target = self; l.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Finder Cut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
    }

    @objc func toggleEnabled() {
        enabled.toggle(); UserDefaults.standard.set(enabled, forKey: "enabled"); cutChangeCount = nil
        buildMenu(); updateIcon()
    }
    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { if s.status == .enabled { try s.unregister() } else { try s.register() } } catch { NSSound.beep() }
        buildMenu()
    }
    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

if CommandLine.arguments.contains("--selftest") {
    let cmd = CGEventFlags.maskCommand
    precondition(decide(key: 7, flags: cmd, inFinder: true, editingText: false, cutPending: false) == .toCopy)
    precondition(decide(key: 9, flags: cmd, inFinder: true, editingText: false, cutPending: true) == .toMove)
    precondition(decide(key: 9, flags: cmd, inFinder: true, editingText: false, cutPending: false) == .pass)
    precondition(decide(key: 7, flags: cmd, inFinder: true, editingText: true, cutPending: false) == .pass)   // renaming
    precondition(decide(key: 7, flags: cmd, inFinder: false, editingText: false, cutPending: false) == .pass) // other apps
    precondition(decide(key: 7, flags: [cmd, .maskShift], inFinder: true, editingText: false, cutPending: false) == .pass)
    precondition(decide(key: 9, flags: [cmd, .maskAlternate], inFinder: true, editingText: false, cutPending: true) == .pass) // native ⌥⌘V untouched
    print("selftest ok"); exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.start()
app.run()
