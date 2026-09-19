import Foundation

struct TopologyPoint: Equatable {
    var x: Float
    var z: Float
}

enum TopologyRoadKind: String, Equatable {
    case feeder
    case call
    case io
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

    static func columns(for count: Int) -> Int { min(3, max(1, count)) }

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

    static func resolveSite(_ raw: String, in ids: Set<String>) -> String? {
        if ids.contains(raw) { return raw }
        let value = raw.lowercased()
        return ids.first { value.contains($0.lowercased()) || $0.lowercased().contains(value) }
    }
}
