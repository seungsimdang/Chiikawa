import Foundation

enum Kind: String, CaseIterable { case chiikawa, hachiware, usagi, momonga, kurimanju, rakko, shisa }
enum Effect { case none, tears, sweat, notes, hearts, stars, grass, drink, zzz }
enum Mode: Equatable { case idle, walk, held, fall, react, weed, eat, sleep, dance, goTo(Double) }

struct Persona {
    let name: String
    let speed: Double
    let clickLines: [String]
    let heldLine: String
    let idleLines: [String]
    let eatLine: String
    let weedLine: String
    let pettedLine: String
}

extension Kind {
    var persona: Persona {
        switch self {
        case .chiikawa:
            return Persona(name: "치이카와", speed: 60, clickLines: ["와…!", "히익…", "…!"], heldLine: "와아…",
                           idleLines: ["…", "와…", "풀 뽑기…"], eatLine: "맛있어…!",
                           weedLine: "풀 뽑기…!", pettedLine: "…♡")
        case .hachiware:
            return Persona(name: "하치와레", speed: 80, clickLines: ["어떻게든 되겠지!", "치이카와~!", "♪~"], heldLine: "우와~",
                           idleLines: ["♪", "헤헤", "어떻게든 될 거야"], eatLine: "맛있다~!",
                           weedLine: "힘내자!", pettedLine: "헤헤…")
        case .usagi:
            return Persona(name: "우사기", speed: 170, clickLines: ["우라!", "야하!", "하앗?", "푸루루루루"], heldLine: "우라우라우라!",
                           idleLines: ["야하!", "우라!", "흐응"], eatLine: "야하~!",
                           weedLine: "우라! 우라!", pettedLine: "흐응♡")
        case .momonga:
            return Persona(name: "모몽가", speed: 90, clickLines: ["칭찬해줘!", "나 귀엽지?", "흥!"], heldLine: "내려놔!",
                           idleLines: ["봐봐!", "나 귀엽지?", "흥"], eatLine: "내 거야!",
                           weedLine: "귀찮아…", pettedLine: "더 쓰다듬어!")
        case .kurimanju:
            return Persona(name: "밤만쥬", speed: 45, clickLines: ["하아—!", "캬—!"], heldLine: "어어…",
                           idleLines: ["…", "한 잔 할까", "하아—"], eatLine: "하아—!",
                           weedLine: "…영차", pettedLine: "후우…")
        case .rakko:
            return Persona(name: "랏코", speed: 150, clickLines: ["…", "토벌 갈까", "훗"], heldLine: "…",
                           idleLines: ["…", "단련해야지", "흠"], eatLine: "잘 먹지",
                           weedLine: "…", pettedLine: "…훗")
        case .shisa:
            return Persona(name: "시사", speed: 85, clickLines: ["어서 오세요!", "열심히 할게요!", "네!"], heldLine: "으아앗!",
                           idleLines: ["라멘 맛있어요!", "열심히!", "에헤헤"], eatLine: "맛있어요!",
                           weedLine: "열심히 할게요!", pettedLine: "에헤헤…")
        }
    }
}

/// 캐릭터 한 마리의 상태와 동작. 화면 좌표(x = 발 중앙, y = 발바닥)를 쓴다.
final class Pet {
    let kind: Kind
    var persona: Persona { kind.persona }
    var x: Double, y: Double
    var vx = 0.0, vy = 0.0, facing = 1.0
    var mode: Mode = .fall
    var modeTime = 0.0
    private(set) var bubble: String?
    private(set) var effect: Effect = .none
    private(set) var clock = 0.0
    private var bubbleTime = 0.0, effectTime = 0.0
    private var walkTarget = 0.0, petting = 0.0
    private var clicks: [Double] = []

    /// 그림이 있는 상태들. nil이면 벡터 그림이라 모든 동작을 그릴 수 있다.
    /// 들기·떨어지기는 물리 동작이라 그림이 없어도 idle 그림으로 한다.
    var abilities: Set<String>?

    init(kind: Kind, x: Double, y: Double) {
        self.kind = kind; self.x = x; self.y = y
    }

    func can(_ state: String) -> Bool { ["held", "fall"].contains(state) || abilities?.contains(state) ?? true }

    /// 지금 그릴 그림의 상태 이름(스프라이트 파일 이름과 같다).
    var state: String {
        if effect == .tears { return "cry" }
        switch mode {
        case .idle: return "idle"
        case .walk, .goTo: return "walk"
        case .held: return "held"
        case .fall: return "fall"
        case .react: return "react"
        case .weed: return "weed"
        case .eat: return "eat"
        case .sleep: return "sleep"
        case .dance: return "dance"
        }
    }

    /// 모몽가는 떨어질 때 활공한다.
    var gliding: Bool { kind == .momonga && mode == .fall && vy < 0 }

    func say(_ s: String, _ duration: Double = 2.2) { bubble = s; bubbleTime = duration }
    func show(_ e: Effect, _ duration: Double) { effect = e; effectTime = duration }

    /// `minX...maxX`는 돌아다니는 활동 범위, `walls`는 던졌을 때 튕기는 벽(기본은 활동 범위와 같다).
    /// `ceiling`은 점프해도 발이 이보다 높이 올라가지 않는 높이(이미 그 위에 있으면 그냥 떨어진다).
    func step(_ dt: Double, floor: Double, minX: Double, maxX: Double, walls: ClosedRange<Double>? = nil,
              ceiling: Double = .infinity) {
        let walls = walls ?? minX...maxX
        clock += dt; modeTime -= dt; bubbleTime -= dt; effectTime -= dt
        if bubbleTime <= 0 { bubble = nil }
        if effectTime <= 0 { effect = .none }
        if mode == .held { return }
        if y < floor - 0.5 { y = floor }  // 바닥을 올렸을 때 그 아래 있던 캐릭터
        if mode != .fall && y > floor + 0.5 { mode = .fall }
        // 범위 밖에 있으면(던졌거나 범위를 바꿨을 때) 걸어서 돌아온다. 못 걸으면 바로 옮긴다.
        if (mode == .idle || mode == .walk) && (x < minX || x > maxX) {
            if can("walk") { mode = .goTo(min(max(x, minX + 30), maxX - 30)) } else { x = min(max(x, minX), maxX) }
        }

        switch mode {
        case .fall:
            vy -= 1800 * dt
            if kind == .momonga { vy = max(vy, -140) }
            if y >= ceiling && vy > 0 { vy = 0 }
            x += vx * dt; y += vy * dt
            if !walls.contains(x) { x = min(max(x, walls.lowerBound), walls.upperBound); vx = -vx * 0.5 }
            if y <= floor {
                y = floor
                if vy < -900 { vy = -vy * 0.35; vx *= 0.6; landedHard() }
                else { vy = 0; vx = 0; mode = .idle; modeTime = 1 }
            }
        case .walk, .goTo:
            var target = walkTarget
            if case .goTo(let t) = mode { target = t }
            target = min(max(target, minX), maxX)
            let stride = persona.speed * (mode == .walk ? 0.6 : 1.5) * dt
            facing = target >= x ? 1 : -1
            if abs(target - x) <= stride { x = target; mode = .idle; modeTime = .random(in: 4...9) }
            else { x += facing * stride }
        case .idle:
            if modeTime <= 0 { decide(minX: minX, maxX: maxX) }
        case .react, .weed, .eat, .sleep, .dance:
            if modeTime <= 0 { mode = .idle; modeTime = .random(in: 3...7) }
        case .held:
            break
        }
    }

    /// 그림이 없는 동작은 고르지 않는다. 할 게 없으면 제자리에서 혼잣말.
    private func decide(minX: Double, maxX: Double) {
        let r = Double.random(in: 0..<1)
        if r < 0.3 && can("walk") {
            walkTarget = min(max(x + .random(in: -140...140), minX), maxX); mode = .walk
        } else if r >= 0.65 && r < 0.78 && can("sleep") {
            mode = .sleep; modeTime = .random(in: 6...12); show(.zzz, modeTime)
        } else if r >= 0.78 && signatureMove() {
        } else {
            say(persona.idleLines.randomElement()!); modeTime = .random(in: 5...10)
        }
    }

    /// 캐릭터별 버릇. 그 그림이 없으면 하지 않고 false.
    private func signatureMove() -> Bool {
        switch kind {
        case .chiikawa where can("weed"): mode = .weed; modeTime = 4; show(.grass, 4); say(persona.weedLine)
        case .hachiware where can("dance"): dance(3); say("♪~")
        case .usagi: mode = .fall; vy = 650; vx = .random(in: -120...120); say("우라!")
        case .momonga: mode = .fall; vy = 750; vx = .random(in: -80...80); say("봐봐!")
        case .kurimanju where can("react"): react(3, .drink); say("하아—!")
        case .rakko where can("walk"): walkTarget = x + (Bool.random() ? 220 : -220); mode = .goTo(walkTarget); say("단련해야지")
        case .shisa where can("react"): react(2, .sweat); say("열심히!")
        default: return false
        }
        return true
    }

    /// 반응 그림이 있으면 반응 동작, 없으면 제자리에서 효과만.
    private func react(_ duration: Double, _ e: Effect) {
        if can("react") { mode = .react; modeTime = duration } else if mode == .sleep { mode = .idle; modeTime = 1 }
        show(e, duration)
    }

    func click(now: Double) {
        guard mode != .held else { return }
        if mode == .sleep { react(1, .sweat); say("…!?"); return }
        clicks = clicks.filter { now - $0 < 2 } + [now]
        let line = persona.clickLines.randomElement()!
        switch kind {
        case .chiikawa:
            if clicks.count >= 3 { clicks = []; cry() }
            else { react(0.8, .sweat); say(line) }
        case .hachiware: react(2.5, .notes); say(line)
        case .usagi: mode = .fall; vy = 700; vx = 0; say(line)
        case .momonga: react(1.5, .hearts); say(line)
        case .kurimanju: react(2.5, .drink); say(line)
        case .rakko: react(1.2, .stars); say(line)
        case .shisa: react(1.5, .sweat); say(line)
        }
    }

    func dance(_ duration: Double) { mode = .dance; modeTime = duration; show(.notes, duration) }

    func cry() {
        guard can("cry") else { react(1.5, .sweat); say("…!"); return }
        if mode != .fall { mode = .react; modeTime = 3 }
        show(.tears, 3); say("흐에엥…", 3)
    }

    /// 마우스로 쓰다듬은 거리. 우는 중에도 쓰다듬으면 달래진다.
    func stroke(_ distance: Double) {
        guard mode != .held else { return }
        petting += distance
        if petting > 500 { petting = 0; show(.hearts, 2); say(persona.pettedLine) }
    }

    func grab() {
        mode = .held; vx = 0; vy = 0
        say(persona.heldLine, 1.5)
        if kind == .chiikawa { show(.sweat, 1.5) }
    }

    func release(vx: Double, vy: Double) {
        mode = .fall
        self.vx = min(max(vx, -1400), 1400)
        self.vy = min(max(vy, -1400), 1400)
    }

    func eat() {
        mode = .eat; modeTime = 2.5; show(.hearts, 2.5); say(persona.eatLine)
    }

    private func landedHard() {
        switch kind {
        case .chiikawa: cry()
        case .hachiware, .shisa: show(.stars, 1.5); say("아야야…")
        case .usagi: say("야하!")
        case .momonga: say("흥!")
        case .kurimanju: show(.stars, 1.5); say("어어…")
        case .rakko: say("…")
        }
    }
}

func selfTest() {
    let p = Pet(kind: .chiikawa, x: 500, y: 400)
    for _ in 0..<600 { p.step(1.0 / 60, floor: 100, minX: 0, maxX: 1000) }
    precondition(p.y == 100 && p.mode != .fall, "떨어지면 바닥에 착지")

    let c = Pet(kind: .chiikawa, x: 500, y: 100); c.mode = .idle
    c.click(now: 0); c.click(now: 0.5)
    precondition(c.effect != .tears)
    c.click(now: 1)
    precondition(c.effect == .tears, "2초 안에 3번 누르면 치이카와가 운다")

    let u = Pet(kind: .usagi, x: 500, y: 100); u.mode = .idle; u.click(now: 0)
    precondition(u.mode == .fall && u.vy > 0, "우사기는 누르면 점프")

    let thrown = Pet(kind: .hachiware, x: 60, y: 300); thrown.release(vx: -5000, vy: 0)
    for _ in 0..<600 { thrown.step(1.0 / 60, floor: 100, minX: 50, maxX: 1000) }
    precondition(thrown.x >= 50 && thrown.y == 100, "던져도 화면 밖으로 안 나감")

    let m = Pet(kind: .momonga, x: 500, y: 900)
    for _ in 0..<30 { m.step(1.0 / 60, floor: 100, minX: 0, maxX: 1000) }
    precondition(m.vy >= -140 && m.gliding, "모몽가는 천천히 활공")
    let s = Pet(kind: .hachiware, x: 500, y: 100); s.mode = .sleep; s.modeTime = 5; s.show(.zzz, 5)
    s.click(now: 0)
    precondition(s.mode == .react && s.effect != .zzz, "자다가 누르면 깬다")
    s.dance(1)
    for _ in 0..<120 { s.step(1.0 / 60, floor: 100, minX: 0, maxX: 1000) }
    precondition(s.mode != .dance, "춤은 시간이 지나면 끝난다")
    let k = Pet(kind: .kurimanju, x: 500, y: 100); k.abilities = ["idle"]; k.mode = .idle
    for i in 0..<6000 {
        k.step(1.0 / 60, floor: 100, minX: 0, maxX: 1000)
        if i % 500 == 0 { k.click(now: Double(i)) }
        precondition(k.mode == .idle && k.state == "idle", "그림이 없는 동작은 하지 않는다")
    }
    let sad = Pet(kind: .chiikawa, x: 500, y: 100); sad.abilities = ["idle", "react"]; sad.mode = .idle
    sad.cry()
    precondition(sad.effect != .tears && sad.mode == .react, "우는 그림이 없으면 울지 않는다")
    let out = Pet(kind: .chiikawa, x: 900, y: 100); out.mode = .idle
    for _ in 0..<1200 { out.step(1.0 / 60, floor: 100, minX: 200, maxX: 400, walls: 0...1000) }
    precondition((200...400).contains(out.x), "활동 범위 밖이면 걸어서 돌아온다")
    let tossed = Pet(kind: .hachiware, x: 300, y: 300); tossed.release(vx: 3000, vy: 0)
    for _ in 0..<10 { tossed.step(1.0 / 60, floor: 100, minX: 200, maxX: 400, walls: 0...1000) }
    precondition(tossed.x > 400, "던지면 활동 범위 밖으로도 날아간다")
    let jumper = Pet(kind: .usagi, x: 300, y: 100); jumper.mode = .fall; jumper.vy = 700
    var top = 0.0
    for _ in 0..<120 { jumper.step(1.0 / 60, floor: 100, minX: 0, maxX: 1000, ceiling: 150); top = max(top, jumper.y) }
    precondition(top < 165 && jumper.y == 100, "점프해도 활동 범위 위로 나가지 않는다")
    let under = Pet(kind: .chiikawa, x: 300, y: 50); under.mode = .idle
    under.step(1.0 / 60, floor: 100, minX: 0, maxX: 1000)
    precondition(under.y == 100, "바닥보다 아래 있으면 바닥으로 올린다")
    print("selftest ok")
}
