import CoreGraphics
import Foundation

struct TopologyPoint: Equatable {
    var x: Float
    var z: Float
}

enum TopologyRoadKind: String, Equatable, CaseIterable {
    case feeder
    case call
    case io

    var origin: TopologyOrigin {
        switch self {
        case .feeder: return .external
        case .call: return .ourService
        case .io: return .ourData
        }
    }
}

enum TopologyOrigin: String, Equatable {
    case external
    case ourService
    case ourData

    var title: String {
        switch self {
        case .external: return "External"
        case .ourService: return "Our service"
        case .ourData: return "Our data"
        }
    }

    var legend: String {
        switch self {
        case .external: return "EXTERNAL · PUBLIC CLIENTS"
        case .ourService: return "OUR SERVICES · INTERNAL CALLS"
        case .ourData: return "OUR DATA · DB / CACHE"
        }
    }
}

struct TopologyFlow: Equatable {
    let from: String
    let to: String
    let kind: TopologyRoadKind

    var origin: TopologyOrigin { kind.origin }

    static func parse(roadName name: String) -> TopologyFlow? {
        guard name.hasPrefix("road:") else { return nil }
        let body = String(name.dropFirst(5))
        guard let kind = TopologyRoadKind.allCases.first(where: { body.hasSuffix(":" + $0.rawValue) }) else { return nil }
        let pair = String(body.dropLast(kind.rawValue.count + 1))
        let nodes = splitNodes(pair)
        guard !nodes.from.isEmpty, !nodes.to.isEmpty else { return nil }
        return TopologyFlow(from: nodes.from, to: nodes.to, kind: kind)
    }

    private static func splitNodes(_ pair: String) -> (from: String, to: String) {
        if pair.hasPrefix("ext:") {
            let rest = String(pair.dropFirst(4))
            if let range = rest.range(of: ":ext:") {
                return ("ext:" + String(rest[..<range.lowerBound]), String(rest[rest.index(after: range.lowerBound)...]))
            }
            if let index = rest.lastIndex(of: ":") {
                return ("ext:" + String(rest[..<index]), String(rest[rest.index(after: index)...]))
            }
            return ("ext:" + rest, "")
        }
        if let range = pair.range(of: ":ext:") {
            return (String(pair[..<range.lowerBound]), String(pair[pair.index(after: range.lowerBound)...]))
        }
        if let index = pair.firstIndex(of: ":") {
            return (String(pair[..<index]), String(pair[pair.index(after: index)...]))
        }
        return (pair, "")
    }
}

struct TopologyLink: Equatable {
    let from: String
    let to: String
    let kind: TopologyRoadKind
    let volume: Double
}

enum TopologyAxis {
    case horizontal
    case vertical
}

enum TopologyLayout {
    static let spacing: Float = 4.4
    static let plateHalf: Float = 1.6
    static let channelMargin: Float = 1.5
    static let snapGrid: Float = 0.4
    static let roadY: Float = 0.18

    static func columns(for count: Int) -> Int {
        if count <= 2 { return max(1, count) }
        if count == 3 { return 2 }
        return min(3, count)
    }

    static func gridPosition(index: Int, count: Int) -> TopologyPoint {
        let cols = columns(for: count)
        let rows = Int(ceil(Double(count) / Double(max(cols, 1))))
        let column = index % cols
        let row = index / cols
        return TopologyPoint(
            x: (Float(column) - Float(cols - 1) / 2) * spacing,
            z: (Float(row) - Float(rows - 1) / 2) * spacing - 1.0
        )
    }

    static func hubPosition() -> TopologyPoint { TopologyPoint(x: 0, z: 3.6) }

    static func externalPosition(index: Int, count: Int, siteXs: [Float], siteZs: [Float]) -> TopologyPoint {
        let maxX = (siteXs.max() ?? 0) + spacing + 0.2
        let minZ = siteZs.min() ?? -2
        let maxZ = siteZs.max() ?? 2
        if count <= 1 { return TopologyPoint(x: maxX, z: (minZ + maxZ) / 2) }
        let t = Float(index) / Float(count - 1)
        return TopologyPoint(x: maxX, z: minZ + t * (maxZ - minZ))
    }

    static func snap(_ value: Float) -> Float { (value / snapGrid).rounded() * snapGrid }

    static func uniqueSorted(_ values: [Float]) -> [Float] {
        Array(Set(values.map { snap($0) })).sorted()
    }

    static func channels(from centers: [Float]) -> [Float] {
        let unique = uniqueSorted(centers)
        guard let first = unique.first, let last = unique.last else { return [0] }
        let margin = plateHalf + channelMargin
        var out = [snap(first - margin)]
        if unique.count > 1 {
            for index in 0..<(unique.count - 1) {
                out.append(snap((unique[index] + unique[index + 1]) / 2))
            }
        }
        out.append(snap(last + margin))
        return out
    }

    static func nearest(_ values: [Float], to value: Float) -> Float {
        values.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    static func attach(_ point: TopologyPoint, verticals: [Float], horizontals: [Float]) -> (axis: TopologyAxis, point: TopologyPoint) {
        let vx = nearest(verticals, to: point.x)
        let hz = nearest(horizontals, to: point.z)
        if abs(vx - point.x) < abs(hz - point.z) {
            return (.vertical, TopologyPoint(x: vx, z: point.z))
        }
        return (.horizontal, TopologyPoint(x: point.x, z: hz))
    }

    static func connect(
        _ a: (axis: TopologyAxis, point: TopologyPoint),
        _ b: (axis: TopologyAxis, point: TopologyPoint),
        verticals: [Float],
        horizontals: [Float]
    ) -> [TopologyPoint] {
        let start = a.point, end = b.point
        switch (a.axis, b.axis) {
        case (.horizontal, .horizontal):
            if abs(start.z - end.z) < 0.05 { return [start, end] }
            let vx = nearest(verticals, to: (start.x + end.x) / 2)
            return [start, TopologyPoint(x: vx, z: start.z), TopologyPoint(x: vx, z: end.z), end]
        case (.vertical, .vertical):
            if abs(start.x - end.x) < 0.05 { return [start, end] }
            let hz = nearest(horizontals, to: (start.z + end.z) / 2)
            return [start, TopologyPoint(x: start.x, z: hz), TopologyPoint(x: end.x, z: hz), end]
        case (.horizontal, .vertical):
            return [start, TopologyPoint(x: end.x, z: start.z), end]
        case (.vertical, .horizontal):
            return [start, TopologyPoint(x: start.x, z: end.z), end]
        }
    }

    static func manhattan(from start: TopologyPoint, to end: TopologyPoint, siteXs: [Float], siteZs: [Float]) -> [TopologyPoint] {
        let verticals = channels(from: siteXs)
        let horizontals = channels(from: siteZs)
        let a = attach(start, verticals: verticals, horizontals: horizontals)
        let b = attach(end, verticals: verticals, horizontals: horizontals)
        return simplify([start] + connect(a, b, verticals: verticals, horizontals: horizontals) + [end])
    }

    static func simplify(_ points: [TopologyPoint]) -> [TopologyPoint] {
        guard points.count > 2 else { return collapse(points) }
        var out = [points[0]]
        for index in 1..<(points.count - 1) {
            let a = out[out.count - 1], b = points[index], c = points[index + 1]
            let collinear = abs((b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x)) < 0.001
            if !collinear { out.append(b) }
        }
        out.append(points[points.count - 1])
        return collapse(out)
    }

    static func collapse(_ points: [TopologyPoint]) -> [TopologyPoint] {
        var out: [TopologyPoint] = []
        for point in points {
            if let last = out.last, abs(last.x - point.x) < 0.02, abs(last.z - point.z) < 0.02 { continue }
            out.append(point)
        }
        return out
    }

    static func isOrthogonal(_ points: [TopologyPoint]) -> Bool {
        guard points.count >= 2 else { return true }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let horizontal = abs(a.z - b.z) < 0.05
            let vertical = abs(a.x - b.x) < 0.05
            if !horizontal && !vertical { return false }
        }
        return true
    }

    struct LabelWindow: Equatable {
        var tops: [CGFloat]
        var start: Int
        var count: Int
        var moreAbove: Int
        var moreBelow: Int
    }

    /// Pin each chip to its section. If they cannot fit without overlap, show a scroll window
    /// instead of squeezing them into a smear. UIKit Y grows downward.
    static func arrangeLabels(
        preferredTops: [CGFloat],
        heights: [CGFloat],
        minY: CGFloat,
        maxY: CGFloat,
        gap: CGFloat = 3,
        start: Int = 0
    ) -> LabelWindow {
        let count = heights.count
        guard count > 0, count == preferredTops.count else {
            return LabelWindow(tops: [], start: 0, count: 0, moreAbove: 0, moreBelow: 0)
        }
        let median = heights.sorted()[count / 2]
        let slot = max(median + gap, 18)
        let capacity = max(1, Int(floor((max(maxY - minY, slot) + gap) / slot)))
        if count <= capacity, let pinned = pinLabels(preferredTops: preferredTops, heights: heights, minY: minY, maxY: maxY, gap: gap) {
            return LabelWindow(tops: pinned, start: 0, count: count, moreAbove: 0, moreBelow: 0)
        }
        let visible = min(count, capacity)
        let lo = min(max(0, start), max(0, count - visible))
        let hi = lo + visible
        let sliceTops = Array(preferredTops[lo..<hi])
        let sliceHeights = Array(heights[lo..<hi])
        let tops = pinLabels(preferredTops: sliceTops, heights: sliceHeights, minY: minY, maxY: maxY, gap: gap)
            ?? evenSpace(heights: sliceHeights, minY: minY, maxY: maxY)
        return LabelWindow(tops: tops, start: lo, count: visible, moreAbove: lo, moreBelow: count - hi)
    }

    static func pinLabels(preferredTops: [CGFloat], heights: [CGFloat], minY: CGFloat, maxY: CGFloat, gap: CGFloat) -> [CGFloat]? {
        guard !heights.isEmpty, heights.count == preferredTops.count else { return [] }
        var tops = preferredTops
        for index in 1..<tops.count {
            tops[index] = max(tops[index], tops[index - 1] + heights[index - 1] + gap)
        }
        if tops[0] < minY {
            let shift = minY - tops[0]
            tops = tops.map { $0 + shift }
        }
        if let last = tops.last, let height = heights.last, last + height > maxY {
            let shift = last + height - maxY
            tops = tops.map { $0 - shift }
            if tops[0] < minY - 0.5 { return nil }
        }
        return tops
    }

    static func evenSpace(heights: [CGFloat], minY: CGFloat, maxY: CGFloat) -> [CGFloat] {
        guard !heights.isEmpty else { return [] }
        if heights.count == 1 {
            let top = min(max(minY, (minY + maxY - heights[0]) / 2), maxY - heights[0])
            return [top]
        }
        let body = heights.reduce(0, +)
        let slack = max(0, maxY - minY - body)
        let spacing = slack / CGFloat(heights.count - 1)
        var y = minY
        return heights.map { height in
            let top = y
            y += height + spacing
            return top
        }
    }

    /// Tight column of label tops inside `[minY, maxY]`. Prefer `arrangeLabels` for live callouts.
    static func packLabels(heights: [CGFloat], minY: CGFloat, maxY: CGFloat, gap: CGFloat = 2) -> [CGFloat] {
        arrangeLabels(preferredTops: evenSpace(heights: heights, minY: minY, maxY: maxY), heights: heights, minY: minY, maxY: maxY, gap: gap).tops
    }

    static func resolveSite(_ raw: String, in ids: Set<String>) -> String? {
        if ids.contains(raw) { return raw }
        let value = raw.lowercased()
        return ids.first { value.contains($0.lowercased()) || $0.lowercased().contains(value) }
    }
}
