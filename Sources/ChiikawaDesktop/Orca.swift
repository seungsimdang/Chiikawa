import AppKit

/// Orca 에이전트 상태를 3초마다 `orca agent list`로 읽는다. 일하던(working) 에이전트가 끝나거나
/// 입력을 기다리게(done·waiting·blocked) 되면 알린다. 지금 보고 있는 세션인지는 CLI로 알 수 없어 구분하지 않는다.
/// Orca CLI가 없으면 아무것도 하지 않는다.
final class OrcaWatcher {
    struct Agent { let key: String, state: String, worktree: String }

    static let cli: String? = (["/Applications/Orca.app/Contents/Resources/bin"]
        + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init))
        .map { $0 + "/orca" }.first { FileManager.default.isExecutableFile(atPath: $0) }

    var onNotice: (Agent) -> Void = { _ in }
    /// 매번 읽은 전체 상태(paneKey → state).
    var onUpdate: ([String: String]) -> Void = { _ in }
    private var states: [String: String]?  // poll 큐에서만 쓴다
    private let queue = DispatchQueue(label: "orca-watcher")

    func start() {
        guard Self.cli != nil else { return }
        queue.async { self.poll() }
    }

    private func poll() {
        if let list = Self.agents(Self.run(["agent", "list"])) {
            let now = Dictionary(list.map { ($0.key, $0.state) }, uniquingKeysWith: { a, _ in a })
            let done = states.map { Self.finished(old: $0, new: list) } ?? []
            states = now
            DispatchQueue.main.async { self.onUpdate(now); done.forEach(self.onNotice) }
        }
        queue.asyncAfter(deadline: .now() + 3) { self.poll() }
    }

    static func agents(_ result: Any?) -> [Agent]? {
        guard let list = (result as? [String: Any])?["agents"] as? [[String: Any]] else { return nil }
        return list.compactMap { a in
            guard let key = a["paneKey"] as? String, let state = a["state"] as? String else { return nil }
            return Agent(key: key, state: state, worktree: a["worktreeId"] as? String ?? "")
        }
    }

    /// 지난번엔 working이었는데 이제 아닌 에이전트.
    static func finished(old: [String: String], new: [Agent]) -> [Agent] {
        new.filter { old[$0.key] == "working" && $0.state != "working" }
    }

    /// 터미널 세션이면 그 터미널 탭으로, 아니면(채팅 등) 그 워크트리로 이동하고 Orca 창을 앞으로 가져온다.
    static func open(_ a: Agent) {
        DispatchQueue.global().async {
            let terms = (run(["terminal", "list"]) as? [String: Any])?["terminals"] as? [[String: Any]] ?? []
            if let t = terms.first(where: { "\($0["tabId"] ?? ""):\($0["leafId"] ?? "")" == a.key }), let handle = t["handle"] as? String {
                _ = run(["terminal", "switch", "--terminal", handle])
            } else if !a.worktree.isEmpty {
                _ = run(["worktree", "activate", "--worktree", "id:" + a.worktree])
            }
            DispatchQueue.main.async {
                guard let url = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Orca" })?.bundleURL else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    /// `orca <args> --json`의 result. 실패하면 nil.
    private static func run(_ args: [String]) -> Any? {
        guard let cli else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = args + ["--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["result"]
    }
}
