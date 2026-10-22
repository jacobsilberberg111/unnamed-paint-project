import Foundation

public enum SurfaceKind: String, Codable, CaseIterable, Sendable {
    case wall, ceiling, floor, door, window, opening
    /// A patch of wall that isn't painted: pinboard, mirror, whiteboard.
    case noPaint
}

public enum ScanConfidence: String, Codable, Sendable {
    case low, medium, high
}

public enum SurfaceEdge: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right
}

/// One surface exactly as RoomPlan reported it, copied out of `CapturedRoom.Surface`
/// so the maths doesn't depend on RoomPlan. Metres, in the scan's world space (y up).
public struct ScannedSurface: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: SurfaceKind
    /// Size along the surface's own axes: x = width along the wall, y = height.
    public var dimensions: Vec3
    public var center: Vec3
    public var xAxis: Vec3
    public var yAxis: Vec3
    public var normal: Vec3
    /// Outline in the surface's local space. Empty when the surface is a plain rectangle.
    public var polygon: [Vec3]
    /// Arc length of a curved wall; nil for flat surfaces.
    public var curveLength: Double?
    /// The wall a door or window sits in, when RoomPlan knows it.
    public var parentId: UUID?
    public var confidence: ScanConfidence
    /// Edges RoomPlan reports as finished. Kept for reference but not used: on a real
    /// iPad it didn't track whether the ceiling line had been scanned, so short walls
    /// are detected from their height instead.
    public var completedEdges: Set<SurfaceEdge>
    public var isOpen: Bool?
    /// Found by the camera after RoomPlan missed it, rather than by RoomPlan.
    public var spotted: Bool?

    public init(
        id: UUID = UUID(),
        kind: SurfaceKind,
        dimensions: Vec3,
        center: Vec3,
        xAxis: Vec3,
        yAxis: Vec3,
        normal: Vec3,
        polygon: [Vec3] = [],
        curveLength: Double? = nil,
        parentId: UUID? = nil,
        confidence: ScanConfidence = .high,
        completedEdges: Set<SurfaceEdge> = Set(SurfaceEdge.allCases),
        isOpen: Bool? = nil,
        spotted: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.dimensions = dimensions
        self.center = center
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.normal = normal
        self.polygon = polygon
        self.curveLength = curveLength
        self.parentId = parentId
        self.confidence = confidence
        self.completedEdges = completedEdges
        self.isOpen = isOpen
        self.spotted = spotted
    }

    public var isCurved: Bool {
        guard let curveLength else { return false }
        return curveLength.isFinite && curveLength > 0
    }

    /// Length along the surface: the arc for curved walls, otherwise the straight width.
    public var width: Double { isCurved ? curveLength! : dimensions.x }

    public var height: Double { dimensions.y }

    /// The two ends of a vertical surface seen from above.
    public var planEndpoints: (start: Vec2, end: Vec2) {
        let dir = xAxis.plan.normalized
        let unit = dir.length > 0.5 ? dir : Vec2(1, 0)
        let half = dimensions.x / 2
        let c = center.plan
        return (c - unit * half, c + unit * half)
    }

    /// Converts a point in this surface's local space to world space.
    public func worldPoint(_ local: Vec3) -> Vec3 {
        center + xAxis.normalized * local.x + yAxis.normalized * local.y + normal.normalized * local.z
    }
}

/// A piece of furniture RoomPlan recognised (bed, storage, table…). Not measured,
/// but clutter is what most often fools door and window detection.
public struct ScannedObject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// RoomPlan's category, e.g. "bed", "storage".
    public var category: String
    /// x = width, y = height, z = depth, in the object's own axes.
    public var dimensions: Vec3
    public var center: Vec3
    public var xAxis: Vec3
    public var zAxis: Vec3

    public init(id: UUID = UUID(), category: String, dimensions: Vec3, center: Vec3,
                xAxis: Vec3 = Vec3(1, 0, 0), zAxis: Vec3 = Vec3(0, 0, 1)) {
        self.id = id
        self.category = category
        self.dimensions = dimensions
        self.center = center
        self.xAxis = xAxis
        self.zAxis = zAxis
    }

    /// Footprint corners seen from above.
    public var planCorners: [Vec2] {
        let a = xAxis.plan.normalized * (dimensions.x / 2)
        let b = zAxis.plan.normalized * (dimensions.z / 2)
        let c = center.plan
        return [c + a + b, c - a + b, c - a - b, c + a - b]
    }

    /// Whether this object stands in front of a door or window: within `depth` of
    /// its wall, covering at least `coverage` of its width, and overlapping its height.
    /// Something merely beside the opening (a shoe rack next to a door) doesn't count.
    func blocks(_ opening: ScannedSurface, width: Double, bottom: Double, top: Double,
                depth: Double, coverage: Double) -> Bool {
        let objectBottom = center.y - dimensions.y / 2, objectTop = center.y + dimensions.y / 2
        guard top > objectBottom, bottom < objectTop else { return false }
        let along = opening.xAxis.plan.normalized, out = opening.normal.plan.normalized
        let rel = planCorners.map { $0 - opening.center.plan }
        let us = rel.map { $0.dot(along) }, ns = rel.map { $0.dot(out) }
        // Footprint reaches within `depth` of the wall plane (either side).
        guard ns.min()! <= depth, ns.max()! >= -depth else { return false }
        let overlap = min(us.max()!, width / 2) - max(us.min()!, -width / 2)
        return overlap >= coverage * width
    }
}

/// Everything the scan found that matters for measuring a room.
public struct ScanGeometry: Codable, Equatable, Sendable {
    public var walls: [ScannedSurface]
    public var doors: [ScannedSurface]
    public var windows: [ScannedSurface]
    public var openings: [ScannedSurface]
    /// Patches the painter marked as not painted (added after the scan, not by RoomPlan).
    public var noPaint: [ScannedSurface]
    public var floors: [ScannedSurface]
    public var objects: [ScannedObject]
    /// RoomPlan's guess at the room type, e.g. "livingRoom".
    public var roomType: String?

    public init(
        walls: [ScannedSurface] = [],
        doors: [ScannedSurface] = [],
        windows: [ScannedSurface] = [],
        openings: [ScannedSurface] = [],
        noPaint: [ScannedSurface] = [],
        floors: [ScannedSurface] = [],
        objects: [ScannedObject] = [],
        roomType: String? = nil
    ) {
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.noPaint = noPaint
        self.floors = floors
        self.objects = objects
        self.roomType = roomType
    }

    private enum CodingKeys: String, CodingKey {
        case walls, doors, windows, openings, noPaint, floors, objects, roomType
    }

    // Rooms saved before furniture was recorded have no "objects" key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        walls = try c.decode([ScannedSurface].self, forKey: .walls)
        doors = try c.decode([ScannedSurface].self, forKey: .doors)
        windows = try c.decode([ScannedSurface].self, forKey: .windows)
        openings = try c.decode([ScannedSurface].self, forKey: .openings)
        noPaint = try c.decodeIfPresent([ScannedSurface].self, forKey: .noPaint) ?? []
        floors = try c.decode([ScannedSurface].self, forKey: .floors)
        objects = try c.decodeIfPresent([ScannedObject].self, forKey: .objects) ?? []
        roomType = try c.decodeIfPresent(String.self, forKey: .roomType)
    }

    /// "livingRoom" → "Living room"; nil when RoomPlan couldn't tell.
    public var roomTypeName: String? {
        guard let roomType, !roomType.isEmpty, roomType != "unidentified" else { return nil }
        var words: [String] = []
        var current = ""
        for ch in roomType {
            if ch.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(ch)
        }
        words.append(current)
        let sentence = words.map { $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
