import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [PetWindow] = []
    private var pets: [Pet] { windows.filter(\.isVisible).map(\.pet) }
    private var food: (x: Double, window: NSWindow)?
    private var statusItem: NSStatusItem!
    private var topItem: NSMenuItem!
    private var areaMenu: NSMenu!
    private var picker: AreaPicker?
    private let defaults = UserDefaults.standard
    // 아래 설정들은 바뀔 때마다 저장되고 다음 실행 때 그대로 복원된다.
    private lazy var topmost = defaults.bool(forKey: "topmost")
    private static let sizes: [(String, CGFloat)] = [("작게", 0.75), ("보통", 1), ("크게", 1.25), ("아주 크게", 1.5)]
    private lazy var hidden = Set(defaults.stringArray(forKey: "hidden") ?? [])
    private lazy var areaFraction = fraction("areaFraction")
    private lazy var areaFractionY = fraction("areaFractionY")

    private func fraction(_ key: String) -> ClosedRange<Double> {
        guard let r = defaults.array(forKey: key) as? [Double], r.count == 2, r[0] < r[1] else { return 0...1 }
        return r[0]...r[1]
    }
    private var last = CACurrentMediaTime()
    private var sinceKey = 0.0
    private var surfaces: [Surface] = [], frames: [Int: CGRect] = [:], surfaceAge = 0.0
    private let orca = OrcaWatcher()
    private var agents: [String: OrcaWatcher.Agent] = [:]

    // 기본은 바탕화면 아이콘 바로 위(앱 창보다 아래). "항상 위"를 켜면 모든 창 위.
    private var level: NSWindow.Level {
        topmost ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    // ponytail: 주 화면 하나만 사용. 멀티 모니터가 필요하면 화면별 바닥을 계산하면 된다.
    private var screen: NSRect { NSScreen.screens.first?.visibleFrame ?? .zero }

    /// 활동 범위: 화면 폭·높이에 대한 비율. 해상도가 바뀌어도 같은 비율을 유지한다. 프리셋은 높이 전체.
    private static let areas: [(String, ClosedRange<Double>)] = [
        ("화면 전체", 0...1), ("왼쪽", 0...0.4), ("가운데", 0.3...0.7), ("오른쪽", 0.6...1),
    ]
    /// 캐릭터 중심이 다닐 수 있는 x 범위. 그림 폭의 절반(50)만큼 안쪽으로 줄인다.
    private var area: ClosedRange<Double> {
        let f = screen, a = areaFraction
        let lo = f.minX + f.width * a.lowerBound + 50, hi = f.minX + f.width * a.upperBound - 50
        return lo < hi ? lo...hi : (lo + hi) / 2...(lo + hi) / 2
    }
    /// 활동 범위의 바닥(발 높이)과 발이 올라갈 수 있는 최고 높이(그림 높이만큼 아래).
    private var floorY: Double { screen.minY + screen.height * areaFractionY.lowerBound }
    private var ceilingY: Double { max(floorY, screen.minY + screen.height * areaFractionY.upperBound - 100 * PetWindow.scale) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChiikawaDesktop")
        print("스프라이트 폴더: \(dir.path)  (README 참고)")

        if let s = defaults.object(forKey: "spriteScale") as? Double, Self.sizes.contains(where: { $0.1 == s }) { PetWindow.scale = s }
        // 그림이 있는 캐릭터만 등장한다.
        let cast = Kind.allCases.compactMap { k in SpriteSet(root: dir, kind: k).map { (k, $0) } }
        if cast.isEmpty { print("스프라이트가 없습니다. ./scripts/fetch-sprites.sh 로 받은 뒤 다시 실행하세요.") }
        let a = area
        let n = Double(cast.count)
        for (i, (kind, sprites)) in cast.enumerated() {
            let pet = Pet(kind: kind, x: a.lowerBound + (a.upperBound - a.lowerBound) * Double(i + 1) / (n + 1), y: floorY)
            pet.abilities = sprites.states
            let w = PetWindow(pet: pet, sprites: sprites)
            w.level = level
            if !hidden.contains(kind.rawValue) { w.orderFrontRegardless() }
            windows.append(w)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍙"
        let menu = NSMenu()
        menu.addItem(withTitle: "간식 주기", action: #selector(feed), keyEquivalent: "f")
        menu.addItem(withTitle: "풀 뽑기 시간", action: #selector(weed), keyEquivalent: "w")
        menu.addItem(withTitle: "다 같이 춤!", action: #selector(danceAll), keyEquivalent: "d")
        menu.addItem(.separator())
        let castMenu = NSMenu()
        castMenu.addItem(withTitle: "모두 보이기", action: #selector(showAll), keyEquivalent: "").target = self
        castMenu.addItem(withTitle: "모두 숨기기", action: #selector(hideAll), keyEquivalent: "").target = self
        castMenu.addItem(.separator())
        for (kind, _) in cast {
            let item = castMenu.addItem(withTitle: kind.persona.name, action: #selector(toggleCharacter(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.state = hidden.contains(kind.rawValue) ? .off : .on
            item.target = self
        }
        menu.addItem(withTitle: "캐릭터", action: nil, keyEquivalent: "").submenu = castMenu
        areaMenu = NSMenu()
        for (i, (name, _)) in Self.areas.enumerated() {
            areaMenu.addItem(withTitle: name, action: #selector(setArea(_:)), keyEquivalent: "").tag = i
        }
        areaMenu.addItem(withTitle: "마우스로 지정…", action: #selector(pickArea), keyEquivalent: "")
        areaMenu.items.forEach { $0.target = self }
        updateAreaChecks()
        menu.addItem(withTitle: "활동 범위", action: nil, keyEquivalent: "").submenu = areaMenu
        let sizeMenu = NSMenu()
        for (i, (name, s)) in Self.sizes.enumerated() {
            let item = sizeMenu.addItem(withTitle: name, action: #selector(setSize(_:)), keyEquivalent: "")
            item.tag = i
            item.state = s == PetWindow.scale ? .on : .off
            item.target = self
        }
        menu.addItem(withTitle: "크기", action: nil, keyEquivalent: "").submenu = sizeMenu
        topItem = menu.addItem(withTitle: "항상 위에 표시", action: #selector(toggleTop), keyEquivalent: "t")
        topItem.state = topmost ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu

        PetView.openNotice = { [weak self] p in
            guard let key = p.notice else { return }
            p.clearNotice()
            if let a = self?.agents[key] { OrcaWatcher.open(a) }
        }
        orca.onNotice = { [weak self] a in self?.notify(a) }
        orca.onUpdate = { [weak self] states in
            // 사용자가 그 세션에 답해서 다시 일하거나 세션이 없어지면 알림을 내린다.
            for p in self?.windows.map(\.pet) ?? [] { if let k = p.notice, (states[k] ?? "working") == "working" { p.clearNotice() } }
        }
        orca.start()

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.05)
        last = now
        let f = screen
        let a = area
        let floor = floorY, ceiling = ceilingY
        surfaceAge -= dt
        if surfaceAge <= 0 { surfaceAge = 0.3; refreshSurfaces() }
        for p in pets {
            p.step(dt, floor: floor, minX: a.lowerBound, maxX: a.upperBound, walls: (f.minX + 50)...(f.maxX - 50), ceiling: ceiling,
                   surfaces: surfaces)
        }

        if let fd = food {
            if let eater = pets.first(where: { $0.can("eat") && abs($0.x - fd.x) < 14 && $0.y <= floor + 1 && $0.mode != .held && $0.mode != .eat }) {
                eater.eat()
                fd.window.orderOut(nil)
                food = nil
                for p in pets where p !== eater {
                    guard case .goTo = p.mode else { continue }
                    p.mode = .idle; p.modeTime = 1.5
                    if p.kind == .chiikawa { p.say("아…") }
                }
            } else {
                for p in pets where p.perch == nil && (p.mode == .idle || p.mode == .walk) && p.can("walk") && p.can("eat") { p.mode = .goTo(fd.x) }
            }
        }

        // 마지막 키 입력 후 지난 시간만 본다(어떤 키인지는 모른다). 줄어들었으면 새 키를 누른 것.
        let k = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if k < sinceKey { pets.forEach { $0.keyTap() } }
        sinceKey = k

        meet(dt)

        windows.forEach { $0.sync() }
    }

    /// 가까이 있는 둘이 가끔 말을 주고받는다. (먼저 말하는 쪽, 대답하는 쪽, 대사, 대답, 대답하는 쪽에 하트)
    private static let pairs: [(Kind, Kind, String, String, Bool)] = [
        (.hachiware, .chiikawa, "치이카와!", "와아…!", true),
        (.chiikawa, .rakko, "멋지다…!", "…훗", false),
        (.hachiware, .rakko, "랏코 멋있어!", "…단련해", false),
        (.usagi, .chiikawa, "야하!", "와…!", false),
        (.momonga, .chiikawa, "나 귀엽지?", "히익…", false),
        (.kurimanju, .hachiware, "하아—!", "맛있어 보여~", false),
        (.shisa, .hachiware, "어서 오세요!", "라멘 주세요~!", true),
    ]

    private func meet(_ dt: Double) {
        guard Double.random(in: 0..<1) < dt * 0.3, let (a, b, lineA, lineB, love) = Self.pairs.randomElement(),
              let pa = pets.first(where: { $0.kind == a }), let pb = pets.first(where: { $0.kind == b }),
              pa.mode == .idle, pb.mode == .idle, pa.bubble == nil, pb.bubble == nil, abs(pa.x - pb.x) < 160, abs(pa.y - pb.y) < 20
        else { return }
        pa.facing = pb.x > pa.x ? 1 : -1
        pb.facing = -pa.facing
        pa.say(lineA); pb.say(lineB)
        if love { pa.show(.hearts, 2); pb.show(.hearts, 2) }
    }

    /// 창 윗변 중 활동 범위 안에서 보이는 구간. 창이 움직이면 그 위의 캐릭터도 같이 옮긴다.
    private func refreshSurfaces() {
        let rects = screenWindows(excludingPID: getpid())
        let a = area, lo = floorY + 30, hi = ceilingY - 40
        surfaces = visibleTops(rects, band: 60 * PetWindow.scale, frontOnly: topmost).compactMap { s in
            let l = max(s.x.lowerBound + 15, a.lowerBound), r = min(s.x.upperBound - 15, a.upperBound)
            return r - l >= 40 && s.y >= lo && s.y <= hi ? Surface(id: s.id, y: s.y, x: l...r) : nil
        }
        let now = Dictionary(rects.map { ($0.id, $0.rect) }, uniquingKeysWith: { a, _ in a })
        for p in pets where p.mode != .held {
            guard let id = p.perch, let o = frames[id], let n = now[id] else { continue }
            p.x += n.minX - o.minX; p.y += n.maxY - o.maxY
        }
        frames = now
    }

    /// 알림이 없는 캐릭터 하나가 튀어 오르며 알린다.
    private func notify(_ a: OrcaWatcher.Agent) {
        agents[a.key] = a
        guard !pets.contains(where: { $0.notice == a.key }) else { return }
        (pets.filter { $0.notice == nil }.randomElement() ?? pets.randomElement())?.alert(a.key, state: a.state)
    }

    @objc private func toggleCharacter(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let w = windows.first(where: { $0.pet.kind.rawValue == raw }) else { return }
        setVisible(!w.isVisible, [item])
    }

    @objc private func showAll(_ sender: NSMenuItem) { setVisible(true, sender.menu?.items ?? []) }
    @objc private func hideAll(_ sender: NSMenuItem) { setVisible(false, sender.menu?.items ?? []) }

    /// 메뉴 항목(캐릭터 이름)들에 해당하는 캐릭터를 보이거나 숨기고 저장한다.
    private func setVisible(_ visible: Bool, _ items: [NSMenuItem]) {
        for item in items {
            guard let raw = item.representedObject as? String, let w = windows.first(where: { $0.pet.kind.rawValue == raw }) else { continue }
            if visible { w.orderFrontRegardless(); hidden.remove(raw) } else { w.orderOut(nil); hidden.insert(raw) }
            item.state = visible ? .on : .off
        }
        defaults.set(Array(hidden), forKey: "hidden")
    }

    @objc private func feed() {
        food?.window.orderOut(nil)
        let x = Double.random(in: area)
        let w = NSWindow(contentRect: NSRect(x: x - 22, y: floorY, width: 44, height: 44), styleMask: .borderless,
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let label = NSTextField(labelWithString: ["🍙", "🍜", "🍮", "🍰"].randomElement()!)
        label.font = .systemFont(ofSize: 30)
        label.frame = NSRect(x: 2, y: 0, width: 40, height: 40)
        w.contentView?.addSubview(label)
        w.level = level
        w.orderFrontRegardless()
        food = (x, w)
        pets.first { $0.kind == .usagi }?.say("야하!")
    }

    @objc private func weed() {
        for p in pets where p.mode != .held && p.can("weed") {
            p.mode = .weed; p.modeTime = 8
            p.show(.grass, 8)
            p.say(p.persona.weedLine)
        }
    }

    @objc private func danceAll() {
        for p in pets where p.mode != .held && p.can("dance") { p.dance(6); p.say("♪") }
    }

    @objc private func setSize(_ item: NSMenuItem) {
        PetWindow.scale = Self.sizes[item.tag].1
        defaults.set(Double(PetWindow.scale), forKey: "spriteScale")
        item.menu?.items.forEach { $0.state = $0 === item ? .on : .off }
    }

    @objc private func setArea(_ item: NSMenuItem) { saveArea(Self.areas[item.tag].1, 0...1) }

    @objc private func pickArea() {
        picker = AreaPicker(frame: screen) { [weak self] r in
            guard let self else { return }
            self.picker = nil
            let f = self.screen
            if let r { self.saveArea(((r.minX - f.minX) / f.width)...((r.maxX - f.minX) / f.width),
                                     ((r.minY - f.minY) / f.height)...((r.maxY - f.minY) / f.height)) }
        }
    }

    private func saveArea(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) {
        areaFraction = max(0, a.lowerBound)...min(1, a.upperBound)
        areaFractionY = max(0, b.lowerBound)...min(1, b.upperBound)
        defaults.set([areaFraction.lowerBound, areaFraction.upperBound], forKey: "areaFraction")
        defaults.set([areaFractionY.lowerBound, areaFractionY.upperBound], forKey: "areaFractionY")
        updateAreaChecks()
    }

    /// 프리셋과 같으면 그 항목에, 아니면 "마우스로 지정…"에 체크.
    private func updateAreaChecks() {
        let preset = areaFractionY == 0...1 ? Self.areas.firstIndex { $0.1 == areaFraction } : nil
        for item in areaMenu.items { item.state = (item.action == #selector(pickArea) ? preset == nil : item.tag == preset) ? .on : .off }
    }

    @objc private func toggleTop() {
        topmost.toggle()
        defaults.set(topmost, forKey: "topmost")
        topItem.state = topmost ? .on : .off
        windows.forEach { $0.level = level }
        food?.window.level = level
    }
}

/// 화면을 덮는 반투명 창. 드래그한 사각형(화면 좌표)을 활동 범위로 돌려준다. Esc는 취소(nil).
/// 캐릭터가 들어갈 만큼(폭 200, 높이 150) 안 되는 사각형은 무시하고 다시 그리게 한다.
final class AreaPicker: NSWindow {
    static let minSize = NSSize(width: 200, height: 150)
    private let done: (NSRect?) -> Void

    init(frame: NSRect, done: @escaping (NSRect?) -> Void) {
        self.done = done
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        contentView = PickerView(frame: NSRect(origin: .zero, size: frame.size))
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { finish(nil) } }

    override func mouseDown(with event: NSEvent) { start = event.locationInWindow; pickerView.rect = nil }

    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        pickerView.rect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let r = pickerView.rect, Self.fits(r) else { pickerView.rect = nil; return }
        finish(r.offsetBy(dx: frame.minX, dy: frame.minY))
    }

    static func fits(_ r: NSRect) -> Bool { r.width >= minSize.width && r.height >= minSize.height }

    private var start = NSPoint.zero
    private var pickerView: PickerView { contentView as! PickerView }

    private func finish(_ r: NSRect?) {
        orderOut(nil)
        done(r)
    }
}

private final class PickerView: NSView {
    var rect: NSRect? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill()
        if let r = rect {
            NSColor.systemGreen.withAlphaComponent(AreaPicker.fits(r) ? 0.35 : 0.15).setFill(); r.fill()
            NSColor.systemGreen.setStroke(); NSBezierPath(rect: r).stroke()
        }
        let text = "드래그해서 활동 범위를 사각형으로 정하세요. 아래 변이 바닥이 됩니다 (Esc: 취소)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

if CommandLine.arguments.contains("--selftest") {
    selfTest()
    spriteSelfTest()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
