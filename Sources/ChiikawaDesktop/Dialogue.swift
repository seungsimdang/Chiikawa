import Foundation

struct Dialogue {
    let defaults: UserDefaults

    // 먼저 말하는 쪽, 대답하는 쪽, 대사, 대답, 하트 표시 여부
    static let conversations: [(Kind, Kind, String, String, Bool)] = [
        (.hachiware, .chiikawa, "치이카와!", "와아…!", true),
        (.chiikawa, .rakko, "멋지다…!", "…훗", false),
        (.hachiware, .rakko, "랏코 멋있어!", "…단련해", false),
        (.usagi, .chiikawa, "야하!", "와…!", false),
        (.momonga, .chiikawa, "나 귀엽지?", "히익…", false),
        (.kurimanju, .hachiware, "하아—!", "맛있어 보여~", false),
        (.shisa, .hachiware, "어서 오세요!", "라멘 주세요~!", true),
    ]

    // nil이면 기본값을 쓰고, 빈 배열을 저장하면 대사를 하지 않는다.
    func lines(for kind: Kind, state: String) -> [String]? {
        defaults.stringArray(forKey: key(for: kind, state: state))
    }

    static func defaultLines(for kind: Kind, state: String) -> [String] {
        var lines = DialogueCue.allCases.filter { $0.state(for: kind) == state }.flatMap { $0.lines(for: kind) }
        if state == "idle" {
            for (speaker, listener, line, reply, _) in conversations {
                if speaker == kind { lines.append(line) }
                if listener == kind { lines.append(reply) }
            }
        }
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    func save(_ text: String, for kind: Kind, state: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        defaults.set(lines, forKey: key(for: kind, state: state))
    }

    func reset(for kind: Kind, state: String) {
        defaults.removeObject(forKey: key(for: kind, state: state))
    }

    private func key(for kind: Kind, state: String) -> String {
        "dialogue.\(kind.rawValue).\(state)"
    }
}

enum DialogueCue: CaseIterable {
    case idle, click, held, eat, weed, wake, cry, cryFallback, dance, signature, hardLanding, missedSnack

    func state(for kind: Kind) -> String {
        switch self {
        case .idle, .missedSnack: return "idle"
        case .click, .wake, .cryFallback: return "react"
        case .held: return "held"
        case .eat: return "eat"
        case .weed: return "weed"
        case .cry: return "cry"
        case .dance: return "dance"
        case .hardLanding: return "fall"
        case .signature:
            switch kind {
            case .chiikawa: return "weed"
            case .hachiware: return "dance"
            case .usagi, .momonga: return "fall"
            case .kurimanju, .shisa: return "react"
            case .rakko: return "walk"
            }
        }
    }

    func lines(for kind: Kind) -> [String] {
        let persona = kind.persona
        switch self {
        case .idle: return persona.idleLines
        case .click: return persona.clickLines
        case .held: return [persona.heldLine]
        case .eat: return [persona.eatLine]
        case .weed: return [persona.weedLine]
        case .wake: return ["…!?"]
        case .cry: return kind == .chiikawa ? ["흐에엥…"] : []
        case .cryFallback: return kind == .chiikawa ? ["…!"] : []
        case .dance: return ["♪"]
        case .missedSnack: return kind == .chiikawa ? ["아…"] : []
        case .signature:
            switch kind {
            case .chiikawa: return [persona.weedLine]
            case .hachiware: return ["♪~"]
            case .usagi: return ["우라!"]
            case .momonga: return ["봐봐!"]
            case .kurimanju: return ["하아—!"]
            case .rakko: return ["단련해야지"]
            case .shisa: return ["열심히!"]
            }
        case .hardLanding:
            switch kind {
            case .chiikawa: return []
            case .hachiware, .shisa: return ["아야야…"]
            case .usagi: return ["야하!"]
            case .momonga: return ["흥!"]
            case .kurimanju: return ["어어…"]
            case .rakko: return ["…"]
            }
        }
    }
}

func dialogueSelfTest() {
    let suite = "chiikawa-dialogue-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let dialogue = Dialogue(defaults: defaults)
    precondition(Dialogue.defaultLines(for: .usagi, state: "held") == [Kind.usagi.persona.heldLine],
                 "들렸을 때의 기본 대사를 표시한다")
    precondition(Dialogue.defaultLines(for: .usagi, state: "fall") == ["우라!", "야하!"],
                 "떨어지는 상태에서 쓰는 기본 대사를 모두 표시한다")
    precondition(Dialogue.defaultLines(for: .chiikawa, state: "idle").contains("와아…!"),
                 "캐릭터끼리 주고받는 기본 대사도 표시한다")
    precondition(Dialogue.defaultLines(for: .usagi, state: "sleep").isEmpty,
                 "기본 대사가 없는 상태는 비워 둔다")
    let pet = Pet(kind: .usagi, x: 0, y: 0, dialogue: dialogue)
    pet.grab()
    precondition(pet.bubble == pet.persona.heldLine, "대사를 지정하지 않으면 기본 대사를 쓴다")

    dialogue.save(" 영차! \n\n 잡았다! ", for: .usagi, state: "held")
    let reloaded = Dialogue(defaults: UserDefaults(suiteName: suite)!)
    let lines = reloaded.lines(for: .usagi, state: "held")
    precondition(lines == ["영차!", "잡았다!"], "빈 줄을 제외한 대사 목록을 저장한다")
    pet.grab()
    precondition(lines?.contains(pet.bubble ?? "") == true, "이미 떠 있는 캐릭터가 수정한 대사를 쓴다")
    let other = Pet(kind: .shisa, x: 0, y: 0, dialogue: dialogue)
    other.grab()
    precondition(other.bubble == other.persona.heldLine, "다른 캐릭터의 대사를 유지한다")

    dialogue.save("날아간다!", for: .usagi, state: "fall")
    dialogue.save("눌렀어?", for: .usagi, state: "react")
    pet.release(vx: 200, vy: 100)
    precondition(pet.bubble == "날아간다!", "던지면 떨어지는 상태의 대사를 쓴다")
    pet.click(now: 0)
    precondition(pet.bubble == "눌렀어?" && pet.mode == .fall, "우사기는 눌렀을 때 대사를 하며 점프한다")
    dialogue.save(" \n ", for: .usagi, state: "held")
    let quiet = Pet(kind: .usagi, x: 0, y: 0, dialogue: reloaded)
    quiet.grab()
    precondition(reloaded.lines(for: .usagi, state: "held") == [] && quiet.bubble == nil,
                 "대사를 다 지워 저장하면 빈 목록이 유지되고 말하지 않는다")
    dialogue.reset(for: .usagi, state: "held")
    quiet.grab()
    precondition(reloaded.lines(for: .usagi, state: "held") == nil && quiet.bubble == pet.persona.heldLine,
                 "기본값을 복원하면 원래 대사를 쓴다")
    print("dialogue selftest ok")
}
