import Foundation

public typealias Vec2 = SIMD2<Double>
public typealias Vec3 = SIMD3<Double>

extension SIMD3 where Scalar == Double {
    public func dot(_ other: Vec3) -> Double { (self * other).sum() }

    public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    public var length: Double { dot(self).squareRoot() }

    public var normalized: Vec3 {
        let l = length
        return l > 1e-9 ? self / l : self
    }

    /// Top-down position. World x maps to screen right and world z to screen down,
    /// so plan points can be drawn in y-down screen space without mirroring.
    public var plan: Vec2 { Vec2(x, z) }
}

extension SIMD2 where Scalar == Double {
    public func dot(_ other: Vec2) -> Double { (self * other).sum() }

    public var length: Double { dot(self).squareRoot() }

    public var normalized: Vec2 {
        let l = length
        return l > 1e-9 ? self / l : self
    }

    public func distance(to other: Vec2) -> Double { (self - other).length }
}

/// Axis-aligned rectangle in a surface's local 2D space (metres).
public struct Rect2: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(center: Vec2, width: Double, height: Double) {
        self.init(minX: center.x - width / 2, minY: center.y - height / 2,
                  maxX: center.x + width / 2, maxY: center.y + height / 2)
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var area: Double { max(0, width) * max(0, height) }

    public func intersection(_ other: Rect2) -> Rect2? {
        let r = Rect2(minX: max(minX, other.minX), minY: max(minY, other.minY),
                      maxX: min(maxX, other.maxX), maxY: min(maxY, other.maxY))
        return r.width > 0 && r.height > 0 ? r : nil
    }

    func contains(_ x: Double, _ y: Double) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }
}

public enum Geometry {
    /// Area of a planar polygon in 3D (Newell's method). Works in any orientation,
    /// so it doesn't matter which local axes RoomPlan uses for a surface's corners.
    public static func area(of polygon: [Vec3]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var normal = Vec3.zero
        for i in polygon.indices {
            normal += polygon[i].cross(polygon[(i + 1) % polygon.count])
        }
        return normal.length / 2
    }

    /// Area of a simple 2D polygon (shoelace).
    public static func area(of polygon: [Vec2]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var twice = 0.0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            twice += a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    /// Total area covered by a set of rectangles, counting overlaps once.
    /// RoomPlan sometimes reports a door and an opening in the same spot;
    /// summing them would subtract that area twice.
    public static func unionArea(_ rects: [Rect2]) -> Double {
        let rects = rects.filter { $0.area > 0 }
        guard !rects.isEmpty else { return 0 }
        let xs = Set(rects.flatMap { [$0.minX, $0.maxX] }).sorted()
        let ys = Set(rects.flatMap { [$0.minY, $0.maxY] }).sorted()
        var total = 0.0
        for i in 0..<(xs.count - 1) {
            let cx = (xs[i] + xs[i + 1]) / 2
            for j in 0..<(ys.count - 1) {
                let cy = (ys[j] + ys[j + 1]) / 2
                if rects.contains(where: { $0.contains(cx, cy) }) {
                    total += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j])
                }
            }
        }
        return total
    }

    public static func distance(from p: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let len2 = ab.dot(ab)
        guard len2 > 1e-12 else { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(ab) / len2))
        return p.distance(to: a + ab * t)
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
