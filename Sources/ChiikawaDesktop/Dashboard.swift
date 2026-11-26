import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 스프라이트 폴더의 그림 목록. 넣기·바꾸기·옮기기·지우기를 하고, 바뀔 때마다 `onChange`로 캐릭터를 다시 불러오게 한다.
/// 파일 이름 규칙은 SpriteSet과 같다: `<kind>/<state>-<아무 이름>.png|gif`.
final class SpriteStore: ObservableObject {
    static let labels: [String: String] = [
        "idle": "기본", "walk": "걷기", "held": "들렸을 때", "fall": "떨어질 때", "react": "눌렀을 때",
        "weed": "풀 뽑기", "eat": "먹기", "cry": "울기", "sleep": "자기", "dance": "춤",
    ]
    static let hints: [String: String] = [
        "idle": "없으면 캐릭터가 나오지 않습니다", "walk": "오른쪽을 보는 그림. 없으면 걷지 않습니다",
        "held": "없으면 기본 그림", "fall": "없으면 기본 그림",
    ]

    /// 지울 때 쓰는 방법. 기본은 휴지통(되살릴 수 있게), 자체 점검에서는 바로 지운다.
    static var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    let root: URL
    let dialogue = Dialogue(defaults: .standard)
    var onChange: () -> Void = {}
    @Published private(set) var files: [Kind: [String: [URL]]] = [:]

    /// 마지막으로 반영한 폴더 상태와, 바뀐 걸 보고 한 번 더 확인하려고 기다리는 상태.
    private var applied: [String: String] = [:]
    private var pending: [String: String]?
    private var watchTimer: Timer?

    init(root: URL) {
        self.root = root
        reload()
        applied = snapshot()
    }

    /// 앱 밖(스크립트·Finder)에서 폴더를 바꿔도 캐릭터에 반영한다.
    func watch() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }

    /// 바뀐 상태가 다음 확인 때도 같으면(받는 중인 파일이 없으면) 다시 불러온다. 받는 도중 캐릭터를 여러 번 새로 만들지 않기 위해서.
    func poll() {
        let now = snapshot()
        if now == applied { pending = nil; return }
        if now == pending { pending = nil; changed() } else { pending = now }
    }

    private func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for kind in Kind.allCases {
            let dir = root.appendingPathComponent(kind.rawValue)
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
            where ["gif", "png"].contains(url.pathExtension.lowercased()) {
                let v = try? url.resourceValues(forKeys: Set(keys))
                out[kind.rawValue + "/" + url.lastPathComponent] = "\(v?.fileSize ?? 0) \(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            }
        }
        return out
    }

    func reload() {
        var out: [Kind: [String: [URL]]] = [:]
        for kind in Kind.allCases {
            let dir = root.appendingPathComponent(kind.rawValue)
            let urls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["gif", "png"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in urls {
                let state = Self.state(of: url)
                if SpriteSet.states.contains(state) { out[kind, default: [:]][state, default: []].append(url) }
            }
        }
        files = out
    }

    func count(_ kind: Kind) -> Int { files[kind]?.values.reduce(0) { $0 + $1.count } ?? 0 }

    static func state(of url: URL) -> String { String(url.deletingPathExtension().lastPathComponent.split(separator: "-")[0]) }

    /// 그림을 복사해 넣는다. 읽을 수 없는 파일은 넣지 않고 이름을 돌려준다.
    @discardableResult
    func add(_ urls: [URL], kind: Kind, state: String) -> [String] {
        var failed: [String] = []
        for url in urls {
            guard Anim(url: url) != nil else { failed.append(url.lastPathComponent); continue }
            do { try FileManager.default.copyItem(at: url, to: freeURL(kind, state, url.pathExtension.lowercased())) }
            catch { failed.append(url.lastPathComponent) }
        }
        changed()
        return failed
    }

    /// 같은 자리(상태)에 다른 그림을 넣는다. 원래 그림은 휴지통으로 보낸다.
    func replace(_ old: URL, with new: URL) -> Bool {
        guard Anim(url: new) != nil, let kind = Kind(rawValue: old.deletingLastPathComponent().lastPathComponent) else { return false }
        let state = Self.state(of: old)
        do {
            try Self.discard(old)
            try FileManager.default.copyItem(at: new, to: freeURL(kind, state, new.pathExtension.lowercased()))
        } catch { changed(); return false }
        changed()
        return true
    }

    func move(_ url: URL, to state: String) {
        guard let kind = Kind(rawValue: url.deletingLastPathComponent().lastPathComponent) else { return }
        try? FileManager.default.moveItem(at: url, to: freeURL(kind, state, url.pathExtension.lowercased()))
        changed()
    }

    func trash(_ url: URL) {
        try? Self.discard(url)
        changed()
    }

    private func freeURL(_ kind: Kind, _ state: String, _ ext: String) -> URL {
        let dir = root.appendingPathComponent(kind.rawValue)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(state)-\(UUID().uuidString.prefix(8).lowercased()).\(ext)")
    }

    private func changed() {
        reload()
        applied = snapshot()
        onChange()
    }
}

/// 메뉴 `캐릭터 편집…`으로 여는 창.
final class DashboardWindow: NSWindow {
    init(store: SpriteStore) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "캐릭터 편집"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: DashboardView(store: store))
        setContentSize(NSSize(width: 860, height: 620))
        center()
    }
}

struct DashboardView: View {
    @ObservedObject var store: SpriteStore
    @State private var selected: Kind? = Kind.allCases.first

    var body: some View {
        NavigationSplitView {
            List(Kind.allCases, id: \.self, selection: $selected) { kind in
                HStack {
                    Text(kind.persona.name)
                    Spacer()
                    let n = store.count(kind)
                    Text(n == 0 ? "없음" : "\(n)장").foregroundStyle(n == 0 ? .tertiary : .secondary).monospacedDigit()
                }
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            if let kind = selected { KindView(store: store, kind: kind) } else { Text("캐릭터를 고르세요").foregroundStyle(.secondary) }
        }
        .navigationTitle("캐릭터 편집")
        .toolbar {
            ToolbarItem {
                Button { NSWorkspace.shared.open(store.root) } label: { Label("폴더 열기", systemImage: "folder") }
                    .help("스프라이트 폴더를 Finder에서 엽니다")
            }
        }
    }
}

private struct KindView: View {
    @ObservedObject var store: SpriteStore
    let kind: Kind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("PNG·GIF를 끌어다 놓거나 + 버튼으로 넣으세요. 같은 상태에 여러 장이면 그때마다 하나를 무작위로 씁니다. "
                     + "그림이 없는 상태의 동작은 하지 않습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(SpriteSet.states, id: \.self) { state in
                    StateRow(store: store, kind: kind, state: state)
                }
            }
            .padding(20)
        }
    }
}

private struct StateRow: View {
    @ObservedObject var store: SpriteStore
    let kind: Kind
    let state: String
    @State private var targeted = false
    @State private var editingDialogue = false
    @State private var draft = ""
    @State private var restoreDefaults = false

    private var urls: [URL] { store.files[kind]?[state] ?? [] }
    private var defaultDialogue: String { Dialogue.defaultLines(for: kind, state: state).joined(separator: "\n") }
    private var savedDialogue: String {
        store.dialogue.lines(for: kind, state: state)?.joined(separator: "\n") ?? defaultDialogue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SpriteStore.labels[state] ?? state).font(.headline)
                Text(state).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let hint = SpriteStore.hints[state] { Text(hint).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("대사 편집") {
                    draft = savedDialogue
                    restoreDefaults = false
                    editingDialogue = true
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(urls, id: \.self) { url in Thumb(store: store, url: url) }
                    Button(action: pickFiles) {
                        Image(systemName: "plus").font(.title2).frame(width: 96, height: 96)
                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("그림 넣기")
                }
                .padding(4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06)))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadURLs(providers) { add($0) }
            return true
        }
        .sheet(isPresented: $editingDialogue) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(kind.persona.name) · \(SpriteStore.labels[state] ?? state) 대사").font(.headline)
                Text("한 줄에 대사 하나씩 입력하세요. 여러 줄이면 무작위로 고릅니다. 모두 지우고 저장하면 이 상태에서 대사를 하지 않습니다.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft)
                    .accessibilityLabel("대사")
                    .font(.body)
                    .frame(minHeight: 120)
                    .border(Color(nsColor: .separatorColor))
                HStack {
                    Button("기본 대사 복원") {
                        draft = defaultDialogue
                        restoreDefaults = true
                    }
                    Spacer()
                    Button("취소") { editingDialogue = false }.keyboardShortcut(.cancelAction)
                    Button("저장") {
                        if restoreDefaults && draft == defaultDialogue {
                            store.dialogue.reset(for: kind, state: state)
                        } else if draft != savedDialogue {
                            store.dialogue.save(draft, for: kind, state: state)
                        }
                        editingDialogue = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func pickFiles() {
        if let urls = openImages(multiple: true) { add(urls) }
    }

    private func add(_ urls: [URL]) {
        let failed = store.add(urls, kind: kind, state: state)
        if !failed.isEmpty { showAlert("넣지 못한 파일", "PNG·GIF 그림만 넣을 수 있습니다.\n" + failed.joined(separator: "\n")) }
    }
}

private struct Thumb: View {
    @ObservedObject var store: SpriteStore
    let url: URL

    var body: some View {
        AnimatedImage(url: url)
            .frame(width: 96, height: 96)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            .overlay(alignment: .topTrailing) {
                Menu { actions } label: { Image(systemName: "ellipsis.circle.fill").font(.title3) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(4)
            }
            .contextMenu { actions }
            .help(url.lastPathComponent)
    }

    @ViewBuilder private var actions: some View {
        Button("다른 그림으로 바꾸기…") {
            guard let new = openImages(multiple: false)?.first else { return }
            if !store.replace(url, with: new) { showAlert("바꾸지 못했습니다", "PNG·GIF 그림만 넣을 수 있습니다.") }
        }
        Menu("다른 상태로 옮기기") {
            ForEach(SpriteSet.states.filter { $0 != SpriteStore.state(of: url) }, id: \.self) { s in
                Button("\(SpriteStore.labels[s] ?? s) (\(s))") { store.move(url, to: s) }
            }
        }
        Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Divider()
        Button("휴지통으로 이동", role: .destructive) { store.trash(url) }
    }
}

/// GIF도 움직이게 보여 주는 썸네일.
private struct AnimatedImage: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        if v.toolTip != url.path { v.image = NSImage(contentsOf: url); v.toolTip = url.path }
    }
}

private func openImages(multiple: Bool) -> [URL]? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .gif]
    panel.allowsMultipleSelection = multiple
    return panel.runModal() == .OK ? panel.urls : nil
}

private func loadURLs(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    for p in providers {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            DispatchQueue.main.async { if let url { urls.append(url) }; group.leave() }
        }
    }
    group.notify(queue: .main) { done(urls) }
}

private func showAlert(_ title: String, _ text: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.runModal()
}

func storeSelfTest() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chiikawa-store-\(getpid())")
    let src = dir.appendingPathComponent("src")
    try! FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    NSGraphicsContext.current = nil
    let png = src.appendingPathComponent("a.png"), bad = src.appendingPathComponent("b.png")
    try! rep.representation(using: .png, properties: [:])!.write(to: png)
    try! Data("not an image".utf8).write(to: bad)

    SpriteStore.discard = { try FileManager.default.removeItem(at: $0) }
    let store = SpriteStore(root: dir.appendingPathComponent("sprites"))
    var changes = 0
    store.onChange = { changes += 1 }
    precondition(store.add([png, png, bad], kind: .usagi, state: "idle") == ["b.png"], "그림이 아닌 파일은 넣지 않는다")
    precondition(store.files[.usagi]?["idle"]?.count == 2 && store.count(.usagi) == 2 && changes == 1, "같은 상태에 여러 장")
    precondition(SpriteSet(root: store.root, kind: .usagi) != nil, "넣은 그림을 앱이 읽는다")
    let first = store.files[.usagi]!["idle"]![0]
    store.move(first, to: "walk")
    precondition(store.files[.usagi]?["walk"]?.count == 1 && store.files[.usagi]?["idle"]?.count == 1, "다른 상태로 옮긴다")
    store.trash(store.files[.usagi]!["walk"]![0])
    precondition(store.files[.usagi]?["walk"] == nil && store.count(.usagi) == 1, "지운다")
    let before = changes
    store.poll(); store.poll()
    precondition(changes == before, "앱이 직접 바꾼 건 다시 반영하지 않는다")
    let kuri = store.root.appendingPathComponent("kurimanju")
    try! FileManager.default.createDirectory(at: kuri, withIntermediateDirectories: true)
    try! FileManager.default.copyItem(at: png, to: kuri.appendingPathComponent("idle.png"))
    store.poll()
    precondition(changes == before, "밖에서 바뀐 걸 처음 보면 한 번 더 확인할 때까지 기다린다")
    store.poll()
    precondition(changes == before + 1 && store.count(.kurimanju) == 1, "밖에서 넣은 그림을 반영한다")
    store.poll()
    precondition(changes == before + 1, "한 번만 반영한다")
    print("store selftest ok")
}
