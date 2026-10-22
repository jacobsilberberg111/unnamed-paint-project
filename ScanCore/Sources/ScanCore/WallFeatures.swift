import Foundation

// Windows, pinboards, mirrors and the like, spotted by the camera while scanning.
// RoomPlan misses some (a dark window at night looks like wall to it) and has no idea
// what a pinboard is. The app finds flat rectangles in the camera feed, places them on
// the LiDAR-measured wall to get their real size, classifies them, and only asks the
// painter about the ones it isn't sure of.

/// A ray from the camera through a point in the image, in world space.
public struct Ray: Equatable, Sendable {
    public var origin: Vec3
    public var direction: Vec3

    public init(origin: Vec3, direction: Vec3) {
        self.origin = origin
        self.direction = direction
    }
}

/// One sighting of a rectangle lying on a wall.
public struct WallFeatureObservation: Equatable, Sendable {
    public var center: Vec3
    public var width: Double
    public var height: Double
    /// Its bottom edge, and the wall's floor and ceiling, as world heights.
    public var bottom: Double
    public var floorY: Double
    public var ceilingY: Double
    public var xAxis: Vec3
    public var normal: Vec3
    /// Share of the camera image it filled; bigger means a closer, clearer view.
    public var apparentSize: Double
    /// Brightness inside it divided by the wall just around it. Glass at night is far
    /// darker than the wall; in daylight far brighter.
    public var contrast: Double?
}

/// What Apple's image classifier thought the crop was.
public enum FeatureLabel: String, Codable, Sendable, CaseIterable {
    case window, door
    /// Pinboard, whiteboard, mirror: stays on the wall, painted around.
    case board
    /// Picture, poster, painting: comes down, and the wall behind is painted.
    case picture

    /// Maps one of Vision's classifier identifiers (e.g. "bulletin_board") to a label.
    public static func from(identifier: String) -> FeatureLabel? {
        let tokens = Set(identifier.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !tokens.isDisjoint(with: ["window", "windows", "windowpane", "skylight"]) { return .window }
        if !tokens.isDisjoint(with: ["door", "doors", "doorway"]) { return .door }
        if !tokens.isDisjoint(with: ["mirror", "bulletin", "corkboard", "whiteboard", "blackboard", "chalkboard"]) { return .board }
        if !tokens.isDisjoint(with: ["poster", "painting", "picture", "artwork", "canvas", "frame", "photograph"]) { return .picture }
        return nil
    }
}

public struct WallFeatureCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var center: Vec3
    public var width: Double
    public var height: Double
    public var bottom: Double
    public var floorY: Double
    public var ceilingY: Double
    public var xAxis: Vec3
    public var normal: Vec3
    public var hits: Int
    public var contrast: Double?
    /// Best classifier confidence per label.
    public var labels: [FeatureLabel: Double]
    /// JPEG of the clearest view, straightened.
    public var thumbnail: Data?
    var bestApparentSize: Double
}

/// Merges repeated sightings across frames into stable candidates.
public struct WallFeatureTracker: Sendable {
    public private(set) var candidates: [WallFeatureCandidate] = []
    /// Sightings needed before a candidate is trusted.
    public static let minHits = 3

    public init() {}

    public var confirmed: [WallFeatureCandidate] { candidates.filter { $0.hits >= Self.minHits } }

    /// Records a sighting. `isBestView` is true when it's the clearest so far, so worth
    /// a fresh thumbnail and classification.
    @discardableResult
    public mutating func add(_ o: WallFeatureObservation) -> (id: UUID, isBestView: Bool) {
        if let i = candidates.firstIndex(where: { Self.matches($0, o) }) {
            var c = candidates[i]
            let n = Double(c.hits)
            c.center = (c.center * n + o.center) / (n + 1)
            c.width = (c.width * n + o.width) / (n + 1)
            c.height = (c.height * n + o.height) / (n + 1)
            c.bottom = (c.bottom * n + o.bottom) / (n + 1)
            if let k = o.contrast { c.contrast = c.contrast.map { ($0 * n + k) / (n + 1) } ?? k }
            c.hits += 1
            let better = o.apparentSize > c.bestApparentSize * 1.2
            if better { c.bestApparentSize = o.apparentSize }
            candidates[i] = c
            return (c.id, better)
        }
        let c = WallFeatureCandidate(
            id: UUID(), center: o.center, width: o.width, height: o.height, bottom: o.bottom,
            floorY: o.floorY, ceilingY: o.ceilingY, xAxis: o.xAxis, normal: o.normal,
            hits: 1, contrast: o.contrast, labels: [:], thumbnail: nil, bestApparentSize: o.apparentSize
        )
        candidates.append(c)
        return (c.id, true)
    }

    public mutating func setThumbnail(_ data: Data, for id: UUID) {
        if let i = candidates.firstIndex(where: { $0.id == id }) { candidates[i].thumbnail = data }
    }

    public mutating func addLabels(_ labels: [FeatureLabel: Double], for id: UUID) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        for (label, confidence) in labels {
            candidates[i].labels[label] = max(candidates[i].labels[label] ?? 0, confidence)
        }
    }

    static func matches(_ c: WallFeatureCandidate, _ o: WallFeatureObservation) -> Bool {
        (c.center - o.center).length < 0.25
            && abs(c.normal.normalized.dot(o.normal.normalized)) > 0.9
            && abs(c.width - o.width) < max(0.2, 0.25 * c.width)
            && abs(c.height - o.height) < max(0.2, 0.25 * c.height)
    }
}

public enum WallFeatureGeometry {
    /// Where a ray meets a wall's plane, if in front of the camera.
    public static func intersect(_ ray: Ray, wall: ScannedSurface) -> Vec3? {
        let n = wall.normal.normalized
        let denom = ray.direction.dot(n)
        guard abs(denom) > 1e-6 else { return nil }
        let t = (wall.center - ray.origin).dot(n) / denom
        guard t > 0.05 else { return nil }
        return ray.origin + ray.direction * t
    }

    /// Places a quad seen in the camera onto the wall its centre ray hits.
    /// `corners` go round the quad in order. Returns nil unless it lands on a wall as an
    /// upright rectangle: something on a desk or the floor projects as a slanted shape.
    public static func observe(corners: [Ray], center: Ray, walls: [ScannedSurface],
                               apparentSize: Double, contrast: Double? = nil) -> WallFeatureObservation? {
        guard corners.count == 4 else { return nil }
        var best: (wall: ScannedSurface, distance: Double)?
        for wall in walls {
            guard let p = intersect(center, wall: wall) else { continue }
            let d = p - wall.center
            guard abs(d.dot(wall.xAxis.normalized)) <= wall.dimensions.x / 2 + 0.05,
                  abs(d.dot(wall.yAxis.normalized)) <= wall.height / 2 + 0.05 else { continue }
            let distance = (p - center.origin).length
            if distance < (best?.distance ?? .infinity) { best = (wall, distance) }
        }
        guard let wall = best?.wall else { return nil }

        let x = wall.xAxis.normalized, y = wall.yAxis.normalized
        var local: [Vec2] = []
        for ray in corners {
            guard let p = intersect(ray, wall: wall) else { return nil }
            let d = p - wall.center
            local.append(Vec2(d.dot(x), d.dot(y)))
        }
        guard isUprightRectangle(local) else { return nil }

        let us = local.map(\.x), vs = local.map(\.y)
        let minU = us.min()!, maxU = us.max()!
        // Clip to the wall: a floor-to-ceiling window can't extend past it.
        let minV = max(vs.min()!, -wall.height / 2), maxV = min(vs.max()!, wall.height / 2)
        let width = maxU - minU, height = maxV - minV
        guard width >= 0.2, height >= 0.2 else { return nil }
        let center = wall.center + x * ((minU + maxU) / 2) + y * ((minV + maxV) / 2)
        let floorY = wall.center.y - wall.height / 2
        return WallFeatureObservation(
            center: center, width: width, height: height,
            bottom: wall.center.y + minV, floorY: floorY, ceilingY: floorY + wall.height,
            xAxis: wall.xAxis, normal: wall.normal, apparentSize: apparentSize, contrast: contrast
        )
    }

    /// Edges alternate horizontal and vertical (within ~8°) and opposite edges match (±15%).
    static func isUprightRectangle(_ p: [Vec2]) -> Bool {
        let edges = (0..<4).map { p[($0 + 1) % 4] - p[$0] }
        let lengths = edges.map(\.length)
        guard lengths.allSatisfy({ $0 > 0.05 }) else { return false }
        let tolerance = sin(8.0 * .pi / 180)
        let flat = edges.indices.map { abs(edges[$0].y) / lengths[$0] < tolerance }
        let upright = edges.indices.map { abs(edges[$0].x) / lengths[$0] < tolerance }
        let alternating = (flat[0] && upright[1] && flat[2] && upright[3]) || (upright[0] && flat[1] && upright[2] && flat[3])
        func similar(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 0.15 * max(a, b) }
        return alternating && similar(lengths[0], lengths[2]) && similar(lengths[1], lengths[3])
    }
}

/// What a spotted rectangle probably is. `kind` nil means "leave the wall as is".
public struct FeatureVerdict: Equatable, Sendable {
    public var kind: SurfaceKind?
    public var confidence: Double
    public var reason: String

    /// Confident enough to apply without asking.
    public var isConfident: Bool { confidence >= WallFeatureClassifier.autoApply }
}

public enum WallFeatureClassifier {
    public static let autoApply = 0.75

    public static func classify(_ c: WallFeatureCandidate) -> FeatureVerdict {
        let aboveFloor = c.bottom - c.floorY
        let belowCeiling = c.ceilingY - (c.bottom + c.height)
        let floorLevel = aboveFloor < 0.1
        let fullHeight = floorLevel && belowCeiling < 0.15
        let doorShaped = floorLevel && (1.8...2.6).contains(c.height) && (0.55...1.3).contains(c.width)
        let glassy = c.contrast.map { $0 < 0.45 || $0 > 1.8 } ?? false
        func label(_ l: FeatureLabel) -> Double { c.labels[l] ?? 0 }

        // Strong classifier answers first.
        if label(.board) >= 0.4, label(.board) >= label(.window) {
            return FeatureVerdict(kind: .noPaint, confidence: 0.8, reason: "Looks like a pinboard, whiteboard or mirror")
        }
        if label(.picture) >= 0.4, label(.picture) > label(.window), !glassy {
            return FeatureVerdict(kind: nil, confidence: 0.8, reason: "Looks like a picture: it comes down and the wall is painted")
        }
        if label(.window) >= 0.3 || (glassy && !doorShaped) {
            let both = label(.window) >= 0.3 && glassy
            let reason = fullHeight ? "Floor-to-ceiling glass" : glassy ? "Glass: much darker or brighter than the wall" : "Looks like a window"
            return FeatureVerdict(kind: .window, confidence: both || fullHeight && glassy ? 0.9 : 0.8, reason: reason)
        }
        if doorShaped {
            let sure = label(.door) >= 0.3
            return FeatureVerdict(kind: .door, confidence: sure ? 0.85 : 0.6, reason: sure ? "Door" : "Door-sized, at floor level")
        }
        if label(.door) >= 0.5, floorLevel {
            return FeatureVerdict(kind: .door, confidence: 0.75, reason: "Door")
        }
        // Not sure: best guess, and ask.
        if aboveFloor > 0.3, c.width * c.height >= 0.3 {
            return FeatureVerdict(kind: .noPaint, confidence: 0.4, reason: "Something flat on the wall")
        }
        return FeatureVerdict(kind: nil, confidence: 0.3, reason: "Something flat on the wall")
    }
}

public struct WallFeatureSuggestion: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var wallId: UUID
    public var wallLabel: String
    public var width: Double
    public var height: Double
    public var thumbnail: Data?
    public var verdict: FeatureVerdict
    var center: Vec3
    var wall: ScannedSurface

    /// The surface to add if the painter (or the classifier) says it's `kind`.
    public func surface(as kind: SurfaceKind) -> ScannedSurface {
        let n = wall.normal.normalized
        let onWall = center - n * (center - wall.center).dot(n)
        return ScannedSurface(
            id: id, kind: kind, dimensions: Vec3(width, height, 0), center: onWall,
            xAxis: wall.xAxis, yAxis: wall.yAxis, normal: wall.normal,
            parentId: wall.id, confidence: .medium, spotted: true
        )
    }
}

public enum WallFeatureSuggester {
    /// Turns confirmed candidates into suggestions for the finished room: placed on its
    /// final walls, minus anything RoomPlan already has or that's really furniture.
    public static func suggestions(_ candidates: [WallFeatureCandidate], in g: ScanGeometry) -> [WallFeatureSuggestion] {
        let walls = MeasurementEngine.clockwise(g.walls)
        let frames = walls.enumerated().map { WallFrame(wall: $1, index: $0, ends: nil, lidarHeight: $1.height, override: nil) }
        let known = g.doors + g.windows + g.openings + g.noPaint
        var results: [WallFeatureSuggestion] = []

        for c in candidates where c.hits >= WallFeatureTracker.minHits {
            // The final wall it sits on.
            guard let frame = frames.first(where: { f in
                let n = f.wall.normal.normalized
                let d = c.center - f.wall.center
                return abs(c.normal.normalized.dot(n)) > 0.9 && abs(d.dot(n)) < 0.25
                    && abs(d.dot(f.wall.xAxis.normalized)) <= f.wall.dimensions.x / 2 + 0.1
            }) else { continue }
            let local = frame.local(c.center)
            let rect = Rect2(center: local, width: c.width, height: c.height)

            // Already found by RoomPlan?
            let duplicate = known.contains { o in
                guard MeasurementEngine.wallFrame(for: o, in: [frame]) != nil else { return false }
                let r = Rect2(center: frame.local(o.center), width: o.width, height: o.height)
                return overlapShare(rect, r) > 0.3
            }
            // A cupboard or wardrobe door rather than something on the wall?
            let furniture = g.objects.contains { o in
                guard let cover = MeasurementEngine.cover(o, on: frame) else { return false }
                return overlapShare(rect, cover) > 0.5
            }
            guard !duplicate, !furniture else { continue }

            results.append(WallFeatureSuggestion(
                id: c.id, wallId: frame.wall.id, wallLabel: "Wall \(frame.shortLabel)",
                width: c.width, height: c.height, thumbnail: c.thumbnail,
                verdict: WallFeatureClassifier.classify(c), center: c.center, wall: frame.wall
            ))
        }

        // The same thing tracked twice: keep the first.
        var kept: [WallFeatureSuggestion] = []
        for s in results where !kept.contains(where: { k in
            k.wallId == s.wallId && (k.center - s.center).length < 0.3
        }) {
            kept.append(s)
        }
        return kept.sorted { ($0.wallLabel, $0.center.x) < ($1.wallLabel, $1.center.x) }
    }

    /// Overlap as a share of the smaller rectangle.
    static func overlapShare(_ a: Rect2, _ b: Rect2) -> Double {
        guard let i = a.intersection(b) else { return 0 }
        return i.area / max(1e-9, min(a.area, b.area))
    }
}

extension Room {
    /// Adds everything the classifier is sure of; returns the ones to ask about.
    public mutating func applyConfident(_ suggestions: [WallFeatureSuggestion]) -> [WallFeatureSuggestion] {
        var unsure: [WallFeatureSuggestion] = []
        for s in suggestions {
            if s.verdict.isConfident {
                if let kind = s.verdict.kind { add(s.surface(as: kind)) }
            } else {
                unsure.append(s)
            }
        }
        return unsure
    }
}
