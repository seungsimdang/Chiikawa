import AppKit

private let outline = NSColor(white: 0.15, alpha: 1)
private let S: CGFloat = 72

/// 캐릭터 하나 = 투명한 작은 창 하나. 창은 매 프레임 pet 위치로 옮겨진다.
final class PetWindow: NSWindow {
    /// 메뉴 `크기`로 바꾸는 배율(길이 기준). 창·그림·효과가 모두 같이 커진다.
    static var scale: CGFloat = 1
    /// 알림 말풍선이 한 줄에 들어가게 그림보다 넓다.
    static var size: NSSize { NSSize(width: 230 * scale, height: 150 * scale) }
    let pet: Pet
    private let petView: PetView

    init(pet: Pet, sprites: SpriteSet) {
        self.pet = pet
        petView = PetView(pet: pet, sprites: sprites)
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = petView
    }

    func sync() {
        if frame.size != Self.size { setContentSize(Self.size) }
        setFrameOrigin(NSPoint(x: pet.x - Self.size.width / 2, y: pet.y - PetView.baseY))
        petView.needsDisplay = true
    }
}

final class PetView: NSView {
    static let baseY: CGFloat = 6
    /// 크기 `보통`일 때 캐릭터 하나가 화면에서 차지하는 면적(pt²). 지름 약 85pt 원 정도.
    static let spriteArea: CGFloat = 5600
    /// 알림이 걸린 캐릭터를 두 번 눌렀을 때.
    static var openNotice: (Pet) -> Void = { _ in }
    private let pet: Pet
    private let sprites: SpriteSet
    private var downAt: NSPoint?
    private var grabOffset = NSPoint.zero
    private var dragging = false
    private var lastDrag = (point: NSPoint.zero, time: 0.0)
    private var velocity = NSPoint.zero
    private var lastHover: NSPoint?
    private var shownState = "", pick = 0, stateStart = 0.0

    init(pet: Pet, sprites: SpriteSet) {
        self.pet = pet
        self.sprites = sprites
        super.init(frame: NSRect(origin: .zero, size: PetWindow.size))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - 마우스

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        downAt = m
        grabOffset = NSPoint(x: m.x - pet.x, y: m.y - pet.y)
        dragging = false
        lastDrag = (m, event.timestamp)
        velocity = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        guard let start = downAt else { return }
        if !dragging && hypot(m.x - start.x, m.y - start.y) > 4 { dragging = true; pet.grab() }
        guard dragging else { return }
        let dt = max(event.timestamp - lastDrag.time, 0.001)
        // 놓을 때 던지는 속도: 최근 움직임 위주로 부드럽게
        velocity = NSPoint(x: velocity.x * 0.5 + (m.x - lastDrag.point.x) / dt * 0.5,
                           y: velocity.y * 0.5 + (m.y - lastDrag.point.y) / dt * 0.5)
        lastDrag = (m, event.timestamp)
        pet.x = m.x - grabOffset.x
        pet.y = m.y - grabOffset.y
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { pet.release(vx: velocity.x, vy: velocity.y) }
        // 알림이 걸려 있으면 한 번 누르기는 무시하고 두 번 눌러야 세션으로 간다.
        else if pet.notice != nil { if event.clickCount >= 2 { Self.openNotice(pet) } }
        else { pet.click(now: event.timestamp) }
        downAt = nil
        dragging = false
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let s = S * PetWindow.scale
        let body = NSRect(x: bounds.midX - s / 2, y: Self.baseY, width: s, height: s * 1.1)
        guard body.contains(p) else { lastHover = nil; return }
        if let last = lastHover { pet.stroke(hypot(p.x - last.x, p.y - last.y)) }
        lastHover = p
    }

    override func mouseExited(with event: NSEvent) { lastHover = nil }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        let t = pet.clock
        var cx = bounds.midX, base = Self.baseY
        switch pet.mode {
        case .walk, .goTo: base += CGFloat(abs(sin(t * 14))) * 3
        case .eat: base += CGFloat(abs(sin(t * 10))) * 2
        case .react: cx += pet.kind == .chiikawa ? CGFloat(sin(t * 70)) * 1.5 : CGFloat(sin(t * 6)) * 3
        case .dance: cx += CGFloat(sin(t * 8)) * 5; base += CGFloat(abs(sin(t * 8))) * 4
        default: break
        }
        if pet.tap > 0 { base += CGFloat(sin(pet.tap / Pet.tapDuration * .pi)) * 7 }

        let state = pet.state
        if state != shownState { shownState = state; pick = .random(in: 0..<1000); stateStart = t }
        guard let anim = sprites.anim(state, pick: pick) else { return }
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: cx, y: base)
        ctx.saveGState()
        // 걸을 때만 방향에 맞춰 뒤집는다(대부분 정면 그림이라 다른 상태는 그대로).
        if pet.facing < 0 && state == "walk" { ctx.scaleBy(x: -1, y: 1) }
        // 그림마다 여백·귀·소품·자세가 달라서 높이 대신 보이는 면적(불투명 픽셀)을 맞춘다. 창을 넘지 않게 자른다.
        let scale = PetWindow.scale
        let k = min(sqrt(Self.spriteArea / anim.mass) * scale, 140 * scale / anim.size.height, 140 * scale / anim.size.width)
        let w = anim.size.width * k, h = anim.size.height * k
        // 자는 동안은 숨 쉬듯 천천히 부풀었다 줄어든다(발은 바닥에 붙인 채).
        if state == "sleep" { let b = CGFloat(sin(t * 2.2)) * 0.025; ctx.scaleBy(x: 1 - b / 2, y: 1 + b) }
        ctx.interpolationQuality = .high
        ctx.draw(anim.frame(at: t - stateStart), in: CGRect(x: -w / 2, y: 0, width: w, height: h))
        ctx.restoreGState()
        // 우는 그림이 따로 있으면 그 위에 눈물을 또 그리지 않는다.
        ctx.scaleBy(x: scale, y: scale)
        if !(pet.effect == .tears && sprites.has("cry")) { drawEffect(pet.effect, t) }
        ctx.restoreGState()

        if let text = pet.bubble { drawBubble(text, alert: pet.showingNotice) }
    }

    /// 창 폭에 맞춰 줄을 바꾸고, 두 줄을 넘으면 끝을 말줄임(…)한다.
    /// 알림 말풍선은 노란 바탕으로 구분한다.
    private func drawBubble(_ text: String, alert: Bool) {
        let font = NSFont.boldSystemFont(ofSize: 12)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: outline, .paragraphStyle: style]
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let maxW = bounds.width - 18, twoLines = ceil(font.ascender - font.descender + font.leading) * 2
        let fit = (text as NSString).boundingRect(with: NSSize(width: maxW, height: twoLines), options: opts, attributes: attrs)
        let textW = min(ceil(fit.width), maxW), textH = min(ceil(fit.height), twoLines)
        let r = NSRect(x: bounds.midX - (textW + 14) / 2, y: bounds.height - textH - 10, width: textW + 14, height: textH + 8)
        let p = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        (alert ? NSColor(calibratedRed: 1, green: 0.95, blue: 0.7, alpha: 1) : NSColor.white).setFill(); p.fill()
        outline.setStroke(); p.lineWidth = alert ? 2 : 1.5; p.stroke()
        (text as NSString).draw(with: NSRect(x: r.midX - maxW / 2, y: r.minY + 4, width: maxW, height: textH), options: opts, attributes: attrs)
    }
}

private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
}

private let sides: [CGFloat] = [-1, 1]

private func wrap(_ v: Double, _ m: Double) -> CGFloat { CGFloat(v.truncatingRemainder(dividingBy: m)) }

private func glyph(_ s: String, _ x: CGFloat, _ y: CGFloat, _ color: NSColor, _ size: CGFloat = 14) {
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: color])
}

private func drawEffect(_ e: Effect, _ t: Double) {
    switch e {
    case .none:
        break
    case .tears:
        NSColor.systemBlue.withAlphaComponent(0.8).setFill()
        for s in sides { for i in 0..<2 { oval(s * 0.24 * S, 0.52 * S - wrap(t * 40 + Double(i) * 12, 24), 5, 7).fill() } }
    case .sweat:
        NSColor.systemTeal.withAlphaComponent(0.8).setFill()
        oval(0.46 * S, 0.92 * S - wrap(t * 10, 6), 6, 9).fill()
    case .notes:
        glyph("♪", 0.42 * S + CGFloat(sin(t * 3)) * 4, 0.85 * S + wrap(t * 25, 30), .systemPink)
        glyph("♫", -0.62 * S, 0.8 * S + wrap(t * 25 + 15, 30), .systemPurple)
    case .hearts:
        for s in sides { glyph("♥", s * 0.42 * S - 6, 0.85 * S + wrap(t * 20 + (s > 0 ? 14 : 0), 28), .systemPink) }
    case .stars:
        for i in 0..<3 {
            let a = t * 4 + Double(i) * 2.09
            glyph("✦", CGFloat(cos(a)) * 0.45 * S - 6, 0.98 * S + CGFloat(sin(a)) * 0.08 * S, .systemYellow, 12)
        }
    case .drink:
        glyph("🍶", 0.34 * S, 0.22 * S + CGFloat(abs(sin(t * 4))) * 6, .black, 16)
        glyph("~", 0.06 * S, 0.62 * S + wrap(t * 20, 20), .systemGray, 16)
    case .zzz:
        for i in 0..<3 {
            let k = wrap(t * 0.6 + Double(i) / 3, 1)
            glyph("z", 0.36 * S + k * 18, 0.8 * S + k * 30, NSColor.systemIndigo.withAlphaComponent(1 - k), 10 + k * 8)
        }
    case .grass:
        NSColor.systemGreen.setStroke()
        for s in sides {
            for i in 0..<3 {
                let gx = s * (0.42 + CGFloat(i) * 0.07) * S
                let g = NSBezierPath(); g.lineWidth = 2
                g.move(to: NSPoint(x: gx, y: 0)); g.line(to: NSPoint(x: gx + s * 3, y: 10 + CGFloat(i) * 2)); g.stroke()
            }
        }
        // 뽑혀서 날아가는 풀
        let fly = wrap(t * 1.5, 1)
        let b = NSBezierPath(); b.lineWidth = 2
        b.move(to: NSPoint(x: 0.3 * S + fly * 20, y: 0.3 * S + fly * 30))
        b.line(to: NSPoint(x: 0.3 * S + fly * 20 + 5, y: 0.3 * S + fly * 30 + 8)); b.stroke()
    }
}
