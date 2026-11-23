import AppKit
import ImageIO

/// 움직이는 이미지 한 개. GIF는 파일에 적힌 프레임 간격대로, PNG는 한 장으로 재생한다.
struct Anim {
    static let maxPixels = CGSize(width: 420, height: 420)
    let frames: [CGImage]
    let ends: [Double]  // 각 프레임이 끝나는 시각(누적)
    /// 프레임 평균 불투명 픽셀 수. 그림마다 여백·자세가 달라도 보이는 덩치를 맞추는 데 쓴다.
    let mass: Double
    var size: CGSize { CGSize(width: frames[0].width, height: frames[0].height) }

    func frame(at t: Double) -> CGImage {
        let local = t.truncatingRemainder(dividingBy: ends.last!)
        return frames[ends.firstIndex { local < $0 } ?? frames.count - 1]
    }

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [CGImage] = [], ends: [Double] = [], total = 0.0
        for i in 0..<CGImageSourceGetCount(src) {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let gif = (CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            total += delay < 0.02 ? 0.1 : delay  // 브라우저처럼 0에 가까운 간격은 0.1초로
            frames.append(img); ends.append(total)
        }
        guard !frames.isEmpty else { return nil }
        // 투명한 여백을 잘라서 발이 바닥에 닿게 한다. 모든 프레임을 덮는 영역 하나로 자른다.
        let box = frames.dropFirst().map(opaqueBounds).reduce(opaqueBounds(frames[0])) { $0.union($1) }
        // 가장 크게 그릴 때(140pt x 크기 1.5배)의 레티나 2배까지만 남긴다. 키우지는 않는다.
        let scale = min(1, Self.maxPixels.height / box.height, Self.maxPixels.width / box.width)
        self.frames = frames.map { resized($0.cropping(to: box) ?? $0, scale) }
        self.ends = ends
        mass = Double(self.frames.map { scanAlpha($0).count }.reduce(0, +)) / Double(self.frames.count)
    }
}

private func resized(_ img: CGImage, _ scale: CGFloat) -> CGImage {
    guard scale < 1 else { return img }
    let w = max(1, Int((CGFloat(img.width) * scale).rounded())), h = max(1, Int((CGFloat(img.height) * scale).rounded()))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return img }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? img
}

/// 불투명 픽셀(알파 > 20)을 감싸는 영역. CGImage 좌표(위가 0).
private func opaqueBounds(_ img: CGImage) -> CGRect { scanAlpha(img).bounds }

/// 불투명 픽셀(알파 > 20)의 영역과 개수. 전부 투명하면 그림 전체와 0.
private func scanAlpha(_ img: CGImage) -> (bounds: CGRect, count: Int) {
    let w = img.width, h = img.height, all = CGRect(x: 0, y: 0, width: w, height: h)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return (all, w * h) }
    ctx.draw(img, in: all)
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var minX = w, minY = h, maxX = -1, maxY = -1, count = 0
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 20 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y); count += 1
    } }
    guard maxX >= 0 else { return (all, 0) }
    return (CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1), count)
}

/// 사용자가 넣은 캐릭터 스프라이트.
///
/// `<root>/<kind>/<state>.gif|png` 또는 `<state>-<아무 이름>.gif|png`. 같은 상태의 파일이 여러 개면
/// 그 상태가 될 때마다 하나를 무작위로 고른다. 없는 상태는 idle을 쓴다.
struct SpriteSet {
    static let states = ["idle", "walk", "held", "fall", "react", "weed", "eat", "cry", "sleep", "dance"]
    private let variants: [String: [Anim]]

    init?(root: URL, kind: Kind) {
        let dir = root.appendingPathComponent(kind.rawValue)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["gif", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var found: [String: [Anim]] = [:]
        for url in files {
            let state = String(url.deletingPathExtension().lastPathComponent.split(separator: "-")[0])
            guard Self.states.contains(state), let anim = Anim(url: url) else { continue }
            found[state, default: []].append(anim)
        }
        guard !found.isEmpty else { return nil }
        variants = found
    }

    func has(_ state: String) -> Bool { variants[state] != nil }
    var states: Set<String> { Set(variants.keys) }

    /// 상태에 쓸 이미지. `pick`은 상태가 바뀔 때마다 새로 뽑은 난수.
    func anim(_ state: String, pick: Int) -> Anim? {
        guard let list = variants[state] ?? variants["idle"] ?? variants.values.first else { return nil }
        return list[pick % list.count]
    }
}

func spriteSelfTest() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chiikawa-selftest-\(getpid())")
    let kindDir = dir.appendingPathComponent(Kind.usagi.rawValue)
    try! FileManager.default.createDirectory(at: kindDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // 40x40 투명 그림 왼쪽 아래에 10x20 사각형
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill(); NSRect(x: 3, y: 2, width: 10, height: 20).fill()
    NSGraphicsContext.current = nil
    let png = rep.representation(using: .png, properties: [:])!
    for name in ["idle.png", "idle-b.png", "eat-x.png", "unknown.png", "note.txt"] {
        try! png.write(to: kindDir.appendingPathComponent(name))
    }

    let set = SpriteSet(root: dir, kind: .usagi)!
    precondition(set.anim("idle", pick: 0)!.size == CGSize(width: 10, height: 20), "투명 여백을 잘라낸다")
    let cropped = set.anim("idle", pick: 0)!.frames[0]
    precondition(opaqueBounds(cropped) == CGRect(x: 0, y: 0, width: 10, height: 20), "자른 영역이 그림과 정확히 겹친다")
    precondition(set.anim("idle", pick: 0)!.frames[0] !== set.anim("idle", pick: 1)!.frames[0], "같은 상태의 이미지 여러 장")
    precondition(set.anim("eat", pick: 5) != nil && set.anim("sleep", pick: 0) != nil, "없는 상태는 idle로")
    precondition(SpriteSet(root: dir, kind: .rakko) == nil, "이미지가 없으면 벡터 그림")

    // 큰 그림은 레티나 표시 크기까지만 줄여 둔다(가로세로 비율 유지)
    let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: big)
    NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 800, height: 400).fill()
    NSGraphicsContext.current = nil
    let bigURL = kindDir.appendingPathComponent("big.png")
    try! big.representation(using: .png, properties: [:])!.write(to: bigURL)
    let bigAnim = Anim(url: bigURL)!
    precondition(bigAnim.size == CGSize(width: 420, height: 210), "큰 그림은 비율 그대로 줄인다")
    precondition(bigAnim.mass == 420 * 210 && set.anim("idle", pick: 0)!.mass == 200, "덩치 = 불투명 픽셀 수")

    // 0.1초, 0.3초짜리 두 프레임 GIF
    let gifURL = kindDir.appendingPathComponent("walk.gif")
    let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, "com.compuserve.gif" as CFString, 2, nil)!
    let cg = rep.cgImage!
    for d in [0.1, 0.3] {
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: d]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(dest))
    let walk = Anim(url: gifURL)!
    precondition(walk.frame(at: 0.05) === walk.frames[0] && walk.frame(at: 0.2) === walk.frames[1]
                 && walk.frame(at: 0.45) === walk.frames[0], "GIF 프레임 간격대로 재생")
    print("sprite selftest ok")
}
