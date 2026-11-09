// 夏爾桌面版：3D 彩虹頭帶夏爾在 Dock 上方走路／喝珍奶／揮手／打瞌睡／被拎起來亂揮／跌坐爬起；點一下可以問問題（後端可自訂）
import AppKit

let SPRITE_H: CGFloat = 140
// 問答後端：~/.config/ciel-desktop/endpoint 放一行網址（POST {"q": ...}，帶 X-Token，回純文字）
let ENDPOINT_PATH = NSString(string: "~/.config/ciel-desktop/endpoint").expandingTildeInPath
let TOKEN_PATH = NSString(string: "~/.config/ciel-desktop/token").expandingTildeInPath

func idleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - 泡泡
final class Bubble: NSPanel {
    let label = NSTextField(wrappingLabelWithString: "")
    let box = NSVisualEffectView()
    var hideTimer: Timer?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .floating; collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        box.material = .popover; box.state = .active; box.wantsLayer = true
        box.layer?.cornerRadius = 12; box.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 13); label.isSelectable = true
        label.maximumNumberOfLines = 0
        box.addSubview(label)
        contentView = box
    }

    func show(_ text: String, above anchor: NSRect, seconds: Double? = nil) {
        label.stringValue = text
        let maxW: CGFloat = 320
        let size = label.sizeThatFits(NSSize(width: maxW, height: 600))
        let w = min(maxW, max(60, size.width)) + 24, h = min(600, size.height) + 18
        label.frame = NSRect(x: 12, y: 9, width: w - 24, height: h - 18)
        var x = anchor.midX - w / 2
        let screen = NSScreen.main!.visibleFrame
        x = max(screen.minX + 4, min(x, screen.maxX - w - 4))
        setFrame(NSRect(x: x, y: anchor.maxY + 4, width: w, height: h), display: true)
        orderFrontRegardless()
        hideTimer?.invalidate()
        let t = seconds ?? min(60, 5 + Double(text.count) * 0.12)
        hideTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in self?.orderOut(nil) }
    }

    func follow(_ anchor: NSRect) {
        guard isVisible else { return }
        var f = frame
        let screen = NSScreen.main!.visibleFrame
        f.origin.x = max(screen.minX + 4, min(anchor.midX - f.width / 2, screen.maxX - f.width - 4))
        f.origin.y = anchor.maxY + 4
        setFrameOrigin(f.origin)
    }

    override func mouseDown(with event: NSEvent) { orderOut(nil) }
}

// MARK: - 輸入框
final class AskPanel: NSPanel, NSTextFieldDelegate {
    let field = NSTextField()
    var onSubmit: ((String) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 36),
                   styleMask: [.borderless, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        titleVisibility = .hidden; titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        level = .floating; isMovableByWindowBackground = true
        field.placeholderString = "問夏爾⋯（Enter 送出、Esc 取消）"
        field.font = .systemFont(ofSize: 14); field.focusRingType = .none
        field.bezelStyle = .roundedBezel; field.delegate = self
        field.frame = NSRect(x: 6, y: 6, width: 288, height: 24)
        contentView?.addSubview(field)
    }
    override var canBecomeKey: Bool { true }

    func open(near anchor: NSRect) {
        let screen = NSScreen.main!.visibleFrame
        let x = max(screen.minX + 4, min(anchor.midX - 150, screen.maxX - 304))
        setFrameOrigin(NSPoint(x: x, y: anchor.maxY + 6))
        field.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            orderOut(nil)
            if !q.isEmpty { onSubmit?(q) }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { orderOut(nil); return true }
        return false
    }
}

// MARK: - 影格
struct Clip {
    let frames: [NSImage]
    init(_ name: String) {
        let dir = (Bundle.main.resourcePath ?? ".") + "/frames/" + name
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
        frames = files.compactMap { NSImage(contentsOfFile: dir + "/" + $0) }
    }
    subscript(_ r: ClosedRange<Int>) -> [NSImage] { Array(frames[max(0, r.lowerBound)...min(frames.count - 1, r.upperBound)]) }
}

func mirrored(_ img: NSImage) -> NSImage {
    NSImage(size: img.size, flipped: false) { r in
        let tr = NSAffineTransform(); tr.translateX(by: r.width, yBy: 0); tr.scaleX(by: -1, yBy: 1); tr.concat()
        img.draw(in: r); return true
    }
}

// 一段動畫：frames 依序播；loop=true 時循環、pingpong=true 時來回
struct Anim {
    var frames: [NSImage]; var fps: Double; var loop: Bool; var pingpong = false
    var then: (() -> Void)? = nil
}

// MARK: - 本體
final class PetView: NSImageView {
    weak var pet: Pet?
    var downAt: NSPoint = .zero, dragged = false
    override func mouseDown(with e: NSEvent) { downAt = NSEvent.mouseLocation; dragged = false; pet?.grab() }
    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        if hypot(p.x - downAt.x, p.y - downAt.y) > 3 { dragged = true }
        pet?.drag(to: p)
    }
    override func mouseUp(with e: NSEvent) { pet?.release(clicked: !dragged) }
    override func rightMouseDown(with e: NSEvent) { pet?.showMenu(e, in: self) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // 只有不透明的地方才吃滑鼠，透明處讓點擊穿過去
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let img = image, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return super.hitTest(point) }
        let p = convert(point, from: superview)
        let r = imageRect()
        guard r.contains(p) else { return nil }
        let x = Int((p.x - r.minX) / r.width * CGFloat(cg.width)), y = Int((1 - (p.y - r.minY) / r.height) * CGFloat(cg.height))
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return self }
        let bpp = cg.bitsPerPixel / 8, off = y * cg.bytesPerRow + x * bpp
        let alphaIdx: Int = (cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first) ? 0 : bpp - 1
        return ptr[off + alphaIdx] > 30 ? self : nil
    }
    func imageRect() -> NSRect {
        guard let img = image else { return bounds }
        let s = min(bounds.width / img.size.width, bounds.height / img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        return NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: h)   // 底部對齊
    }
    override func draw(_ dirtyRect: NSRect) { image?.draw(in: imageRect()) }
}

enum Mode { case idle, walk, sleep, held, fall, think, act }

final class Pet: NSObject {
    let win: NSPanel
    let view = PetView()
    let bubble = Bubble(), ask = AskPanel()
    // 影格
    let walkR: [NSImage], walkL: [NSImage], stand: NSImage, standL: NSImage
    let sipWave: [NSImage], wave: [NSImage], sip: [NSImage], fallAsleep: [NSImage], snooze: [NSImage], flail: [NSImage], land: [NSImage]
    var squash: Double = 0   // 落地壓扁，1 → 0
    var anim: Anim?, frameIdx = 0, frameDir = 1, frameClock: Double = 0
    // 狀態
    var mode: Mode = .idle
    var dir: CGFloat = 1, speed: CGFloat = 1.1
    var modeUntil = Date()
    var t: Double = 0, vy: CGFloat = 0
    var grabOffset = NSPoint.zero
    var forcedSleep = false
    let size: NSSize

    init(walk: Clip, idle: Clip, sleep: Clip, held: Clip, landClip: Clip) {
        walkR = walk[8...37]; walkL = walkR.map(mirrored)
        stand = idle.frames[0]; standL = mirrored(stand)
        sipWave = idle.frames; wave = idle[84...119]; sip = idle[12...48]
        fallAsleep = sleep[0...95]; snooze = sleep[95...119]; flail = held[43...79]; land = landClip.frames
        let all = walk.frames + idle.frames + sleep.frames + held.frames + land
        let maxW = all.map { $0.size.width }.max() ?? 140, maxH = all.map { $0.size.height }.max() ?? 280
        let k = SPRITE_H / maxH
        size = NSSize(width: maxW * k, height: SPRITE_H)
        win = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
        super.init()
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        view.frame = NSRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.image = stand; view.pet = self
        win.contentView = view
        let s = NSScreen.main!.visibleFrame
        win.setFrameOrigin(NSPoint(x: s.midX - size.width / 2, y: s.minY))
        win.orderFrontRegardless()
        ask.onSubmit = { [weak self] q in self?.send(q) }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        play(Anim(frames: wave, fps: 12, loop: false) { [weak self] in self?.still() })
        say("我來了。點我可以問事情，右鍵有選單。", 5)
    }

    var floorY: CGFloat { NSScreen.main!.visibleFrame.minY }
    func say(_ s: String, _ secs: Double? = nil) { bubble.show(s, above: win.frame, seconds: secs) }

    // 動畫
    func play(_ a: Anim) { anim = a; frameIdx = 0; frameDir = 1; frameClock = 0; view.image = a.frames.first; view.needsDisplay = true }
    func still() { anim = nil; view.image = dir > 0 ? stand : standL; view.needsDisplay = true }
    func stepAnim(_ dt: Double) {
        guard var a = anim, !a.frames.isEmpty else { return }
        frameClock += dt
        let spf = 1 / a.fps
        while frameClock >= spf {
            frameClock -= spf
            var n = frameIdx + frameDir
            if n >= a.frames.count || n < 0 {
                if a.pingpong { frameDir = -frameDir; n = frameIdx + frameDir }
                else if a.loop { n = 0 }
                else { let done = a.then; a.then = nil; anim = nil; done?(); return }
            }
            frameIdx = max(0, min(n, a.frames.count - 1))
        }
        view.image = a.frames[frameIdx]; view.needsDisplay = true
    }

    func pick() {
        if forcedSleep { return }
        if idleSeconds() > 300 { goSleep(); return }
        let r = Double.random(in: 0...1)
        if r < 0.5 {
            if Double.random(in: 0...1) < 0.4 { dir = -dir }
            speed = CGFloat.random(in: 0.9...1.3)
            mode = .walk; modeUntil = Date().addingTimeInterval(Double.random(in: 4...10))
            play(Anim(frames: dir > 0 ? walkR : walkL, fps: 12, loop: true))
        } else if r < 0.7 {
            mode = .act; modeUntil = .distantFuture
            play(Anim(frames: sipWave, fps: 12, loop: false) { [weak self] in self?.toIdle(3) })
        } else { toIdle(Double.random(in: 3...8)) }
    }

    func toIdle(_ secs: Double) { mode = .idle; modeUntil = Date().addingTimeInterval(secs); still() }

    func goSleep() {
        mode = .sleep; modeUntil = .distantFuture
        play(Anim(frames: fallAsleep, fps: 12, loop: false) { [weak self] in
            guard let self = self else { return }
            self.play(Anim(frames: self.snooze, fps: 8, loop: true, pingpong: true))
            self.say("Zzz⋯", 3600)
        })
    }
    func wake(_ line: String) { bubble.orderOut(nil); say(line, 2); toIdle(2) }

    func tick() {
        let dt = 1.0 / 30; t += dt
        stepAnim(dt)
        var o = win.frame.origin
        let s = NSScreen.main!.visibleFrame
        var rot: CGFloat = 0
        switch mode {
        case .walk:
            o.x += dir * speed
            if o.x < s.minX || o.x > s.maxX - size.width {
                o.x = max(s.minX, min(o.x, s.maxX - size.width)); dir = -dir
                play(Anim(frames: dir > 0 ? walkR : walkL, fps: 12, loop: true))
            }
        case .sleep:
            if idleSeconds() < 2 && !forcedSleep && anim?.loop == true { wake("⋯醒了。") }
        case .held:
            rot = sin(t * 5) * 0.06
        case .fall:
            vy -= 1.2; o.y += vy
            if o.y <= floorY {
                o.y = floorY; vy = 0
                say(["唉唷。", "屁股⋯", "珍奶沒灑。", "下次輕一點。"].randomElement()!, 2.5)
                if land.isEmpty { squash = 1; toIdle(2.5) }
                else { squash = 0.35; mode = .act; modeUntil = .distantFuture
                       play(Anim(frames: land, fps: 14, loop: false) { [weak self] in self?.toIdle(3) }) }
            }
        case .idle, .think, .act: break
        }
        if mode != .fall && mode != .held { o.y = floorY }
        if Date() > modeUntil && (mode == .walk || mode == .idle) { pick() }
        win.setFrameOrigin(o)
        if let l = view.layer {
            // 落地：先壓扁再回彈
            let k = CGFloat(squash), sy = 1 - 0.22 * k * cos((1 - k) * 9), sx = 1 + 0.15 * k * cos((1 - k) * 9)
            if squash > 0 { squash = max(0, squash - dt * 2.2) }
            l.anchorPoint = CGPoint(x: 0.5, y: squash > 0 ? 0 : 1); l.position = CGPoint(x: size.width / 2, y: squash > 0 ? 0 : size.height)
            l.setAffineTransform(CGAffineTransform(rotationAngle: rot).scaledBy(x: sx, y: sy))
        }
        bubble.follow(win.frame)
    }

    // 拖曳
    func grab() {
        let m = NSEvent.mouseLocation
        grabOffset = NSPoint(x: m.x - win.frame.minX, y: m.y - win.frame.minY)
        if mode != .think { mode = .held; bubble.orderOut(nil); play(Anim(frames: flail, fps: 12, loop: true)) }
    }
    func drag(to p: NSPoint) { win.setFrameOrigin(NSPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)) }
    func release(clicked: Bool) {
        if mode == .think { if clicked { say("還在想，等我一下。", 2) }; return }
        if clicked {
            forcedSleep = false; bubble.orderOut(nil)
            win.setFrameOrigin(NSPoint(x: win.frame.minX, y: floorY))
            mode = .act; modeUntil = .distantFuture
            play(Anim(frames: wave, fps: 12, loop: false) { [weak self] in self?.toIdle(6) })
            ask.open(near: win.frame)
        } else { vy = 0; mode = .fall }
    }

    // 選單
    func showMenu(_ e: NSEvent, in v: NSView) {
        let m = NSMenu()
        m.addItem(withTitle: "問夏爾⋯", action: #selector(menuAsk), keyEquivalent: "").target = self
        m.addItem(withTitle: forcedSleep ? "叫醒" : "去睡覺", action: #selector(menuSleep), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(m, with: e, for: v)
    }
    @objc func menuAsk() { ask.open(near: win.frame) }
    @objc func menuSleep() {
        forcedSleep.toggle()
        if forcedSleep { goSleep() } else { wake("起來了。") }
    }

    // 問
    func send(_ q: String) {
        guard let ep = try? String(contentsOfFile: ENDPOINT_PATH, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let ENDPOINT = URL(string: ep) else { say("還沒設定問答後端（~/.config/ciel-desktop/endpoint）。"); return }
        guard let tok = try? String(contentsOfFile: TOKEN_PATH, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !tok.isEmpty else { say("找不到 token（~/.config/ciel-desktop/token）。"); return }
        mode = .think; modeUntil = .distantFuture
        play(Anim(frames: sip, fps: 8, loop: true, pingpong: true))   // 邊喝珍奶邊想
        say("嗯⋯", 120)
        var req = URLRequest(url: ENDPOINT, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue(tok, forHTTPHeaderField: "X-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["q": q])
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var text: String
            if let err = err { text = "連不到後端：\(err.localizedDescription)\n（Tailscale 有開嗎？）" }
            else if code != 200 { text = "後端回 \(code)：" + (String(data: data ?? Data(), encoding: .utf8) ?? "") }
            else { text = String(data: data ?? Data(), encoding: .utf8) ?? "（空的）" }
            DispatchQueue.main.async { self.toIdle(5); self.say(text) }
        }.resume()
    }
}

// MARK: - main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let walkClip = Clip("walk"), idleClip = Clip("idle"), sleepClip = Clip("sleep"), heldClip = Clip("held"), landClip = Clip("land")
guard walkClip.frames.count > 40, idleClip.frames.count > 110, sleepClip.frames.count > 110, heldClip.frames.count > 80 else { fatalError("frames missing") }
let pet = Pet(walk: walkClip, idle: idleClip, sleep: sleepClip, held: heldClip, landClip: landClip)
app.run()
