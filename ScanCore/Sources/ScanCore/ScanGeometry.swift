import Foundation

public enum SurfaceKind: String, Codable, CaseIterable, Sendable {
    case wall, ceiling, floor, door, window, opening
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
    /// Edges RoomPlan has finished scanning. A wall missing `.top` hasn't had its
    /// ceiling line captured, so its height may be short.
    public var completedEdges: Set<SurfaceEdge>
    public var isOpen: Bool?

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
        isOpen: Bool? = nil
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

/// Everything the scan found that matters for measuring a room.
public struct ScanGeometry: Codable, Equatable, Sendable {
    public var walls: [ScannedSurface]
    public var doors: [ScannedSurface]
    public var windows: [ScannedSurface]
    public var openings: [ScannedSurface]
    public var floors: [ScannedSurface]
    /// RoomPlan's guess at the room type, e.g. "livingRoom".
    public var roomType: String?

    public init(
        walls: [ScannedSurface] = [],
        doors: [ScannedSurface] = [],
        windows: [ScannedSurface] = [],
        openings: [ScannedSurface] = [],
        floors: [ScannedSurface] = [],
        roomType: String? = nil
    ) {
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.floors = floors
        self.roomType = roomType
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
