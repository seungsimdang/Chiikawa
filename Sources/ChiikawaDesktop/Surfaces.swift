import AppKit

/// 캐릭터가 올라설 수 있는 곳: 창의 윗변 중 보이는 구간. 화면 좌표(Cocoa, 아래가 0).
struct Surface: Equatable {
    let id: Int
    let y: Double
    let x: ClosedRange<Double>
}

/// 화면에 보이는 일반 앱 창들의 위치(앞→뒤 순서). 창 이름·내용은 읽지 않는다.
func screenWindows(excludingPID pid: Int32) -> [(id: Int, rect: CGRect)] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    let h = NSScreen.screens.first?.frame.height ?? 0  // CG 좌표는 주 화면 왼쪽 위가 0
    return list.compactMap { w in
        guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? Int32) != pid,
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b)
        else { return nil }
        return (id, CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height))
    }
}

/// 창마다 윗변 위쪽 `band` 높이(캐릭터가 서 있을 자리)를 다른 창이 가리지 않는 구간만 남긴다.
/// `frontOnly`: 캐릭터가 모든 창 위에 그려질 때는 그 창보다 앞의 창만 가린다. 아니면(캐릭터가 창들 뒤) 다른 모든 창이 가린다.
func visibleTops(_ rects: [(id: Int, rect: CGRect)], band: Double, frontOnly: Bool, minWidth: Double = 60) -> [Surface] {
    var out: [Surface] = []
    for (i, w) in rects.enumerated() {
        let zone = CGRect(x: w.rect.minX, y: w.rect.maxY, width: w.rect.width, height: band)
        var free = [Double(w.rect.minX)...Double(w.rect.maxX)]
        for (j, o) in rects.enumerated() where j != i && (!frontOnly || j < i) && o.rect.intersects(zone) {
            let lo = Double(o.rect.minX), hi = Double(o.rect.maxX)
            free = free.flatMap { seg -> [ClosedRange<Double>] in
                if hi <= seg.lowerBound || lo >= seg.upperBound { return [seg] }
                return (lo > seg.lowerBound ? [seg.lowerBound...lo] : []) + (hi < seg.upperBound ? [hi...seg.upperBound] : [])
            }
        }
        out += free.filter { $0.upperBound - $0.lowerBound >= minWidth }.map { Surface(id: w.id, y: Double(w.rect.maxY), x: $0) }
    }
    return out
}
