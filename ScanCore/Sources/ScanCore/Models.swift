import Foundation

// Shared data model (see the hackathon spec). Room and Surface follow the spec with
// three deliberate changes:
//  - Surface.grossAreaM2 is stored, because width × height is wrong for gable,
//    raked-ceiling and curved walls.
//  - Room.scanFile is a file name relative to the room's folder, not an absolute URL:
//    an app's container path changes on reinstall, which would orphan every scan.
//  - Surfaces are derived from the scan on demand, so tape-measure corrections
//    re-flow through openings, skirting and totals.

public enum SurfaceFlag: String, Codable, Sendable {
    /// Painter typed in a tape measurement.
    case tapeMeasured
    /// RoomPlan wasn't confident about this surface.
    case lowConfidence
    /// The wall came up noticeably shorter than the rest of the room (usually its
    /// ceiling line wasn't scanned), so the room's height was used instead.
    case heightFromRoom
    /// A wall under 30 cm long: often a sliver RoomPlan adds at a corner. Remove it
    /// if the wall doesn't really step there.
    case tinyWall
    /// A door or window with furniture in front of it. Clutter is the most common
    /// cause of false detections, so it's worth a glance.
    case nearFurniture
    /// The painter changed what RoomPlan thought this was (e.g. window → door).
    case typeCorrected
    case curved
    /// Not a rectangle: gable end, raked ceiling or similar.
    case sloped
    /// A door or window that couldn't be matched to a wall, so it isn't subtracted.
    case notOnAWall
}

public struct Surface: Codable, Identifiable, Equatable, Sendable {
    public static let ceilingID = UUID(uuidString: "00000000-0000-0000-0000-00000000CE11")!

    public let id: UUID                // matches the RoomPlan surface id
    public var kind: SurfaceKind
    public var label: String           // "Wall A", "Door 1"
    public var widthM: Double
    public var heightM: Double
    public var grossAreaM2: Double
    public var openingsM2: Double      // doors + windows on this wall, overlaps counted once
    public var wallId: UUID?           // doors/windows/openings: the wall they sit in
    public var scannedWidthM: Double   // best LiDAR value, before any tape correction
    public var scannedHeightM: Double
    public var flags: [SurfaceFlag]

    public init(
        id: UUID, kind: SurfaceKind, label: String,
        widthM: Double, heightM: Double, grossAreaM2: Double, openingsM2: Double = 0,
        wallId: UUID? = nil, scannedWidthM: Double? = nil, scannedHeightM: Double? = nil,
        flags: [SurfaceFlag] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.widthM = widthM
        self.heightM = heightM
        self.grossAreaM2 = grossAreaM2
        self.openingsM2 = openingsM2
        self.wallId = wallId
        self.scannedWidthM = scannedWidthM ?? widthM
        self.scannedHeightM = scannedHeightM ?? heightM
        self.flags = flags
    }

    public var paintAreaM2: Double { max(0, grossAreaM2 - openingsM2) }
}

/// The painter's correction to one surface. nil fields keep what the scan said.
public struct SurfaceOverride: Codable, Equatable, Sendable {
    public var surfaceId: UUID
    /// Tape-measured size.
    public var widthM: Double?
    public var heightM: Double?
    /// What it really is, when RoomPlan got the type wrong (doors, windows, openings only).
    public var kind: SurfaceKind?
    /// A false detection: leave it out of every measurement.
    public var removed: Bool?

    public init(surfaceId: UUID, widthM: Double? = nil, heightM: Double? = nil,
                kind: SurfaceKind? = nil, removed: Bool? = nil) {
        self.surfaceId = surfaceId
        self.widthM = widthM
        self.heightM = heightM
        self.kind = kind
        self.removed = removed
    }

    public var isEmpty: Bool { widthM == nil && heightM == nil && kind == nil && removed != true }
    var isRemoved: Bool { removed == true }
    var hasSize: Bool { widthM != nil || heightM != nil }
}

public struct Room: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    /// Saved `CapturedRoom` JSON, relative to the room's folder.
    public var scanFile: String?
    public var geometry: ScanGeometry
    public var overrides: [SurfaceOverride]
    /// Furniture the painter has chosen to paint.
    public var furniture: [FurniturePaint]

    public init(
        id: UUID = UUID(), name: String, createdAt: Date = Date(),
        scanFile: String? = nil, geometry: ScanGeometry, overrides: [SurfaceOverride] = [],
        furniture: [FurniturePaint] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.scanFile = scanFile
        self.geometry = geometry
        self.overrides = overrides
        self.furniture = furniture
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, scanFile, geometry, overrides, furniture
    }

    // Rooms saved before furniture painting existed have no "furniture" key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        scanFile = try c.decodeIfPresent(String.self, forKey: .scanFile)
        geometry = try c.decode(ScanGeometry.self, forKey: .geometry)
        overrides = try c.decodeIfPresent([SurfaceOverride].self, forKey: .overrides) ?? []
        furniture = try c.decodeIfPresent([FurniturePaint].self, forKey: .furniture) ?? []
    }

    public func measure() -> RoomMeasurements {
        MeasurementEngine.measure(geometry, overrides: overrides, furniture: furniture)
    }

    /// Paint a piece of furniture or not, optionally with a measured area (nil = estimate).
    public mutating func setFurniture(_ objectId: UUID, include: Bool, areaM2: Double? = nil) {
        furniture.removeAll { $0.objectId == objectId }
        if include || areaM2 != nil {
            furniture.append(FurniturePaint(objectId: objectId, include: include, areaM2: areaM2))
        }
    }

    public var surfaces: [Surface] { measure().surfaces }

    public func override(for surfaceId: UUID) -> SurfaceOverride? {
        overrides.first { $0.surfaceId == surfaceId }
    }

    public mutating func setOverride(_ override: SurfaceOverride?, for surfaceId: UUID) {
        overrides.removeAll { $0.surfaceId == surfaceId }
        if var override, !override.isEmpty {
            override.surfaceId = surfaceId
            overrides.append(override)
        }
    }

    /// The surface as RoomPlan reported it, before any corrections.
    public func scannedSurface(_ id: UUID) -> ScannedSurface? {
        (geometry.walls + geometry.doors + geometry.windows + geometry.openings).first { $0.id == id }
    }

    /// Detections the painter removed, so they can be put back.
    public var removedSurfaces: [ScannedSurface] {
        let ids = Set(overrides.filter(\.isRemoved).map(\.surfaceId))
        return (geometry.walls + geometry.doors + geometry.windows + geometry.openings).filter { ids.contains($0.id) }
    }
}

public enum AreaSource: String, Codable, Sendable {
    /// RoomPlan's own floor outline.
    case scannedFloor
    /// Corners where the wall planes intersect.
    case wallOutline
    /// Walls don't close into a loop and RoomPlan found no floor.
    case unavailable
}

public struct RoomSummary: Codable, Equatable, Sendable {
    public var wallCount = 0
    public var doorCount = 0
    public var windowCount = 0
    public var openingCount = 0
    public var wallGrossM2 = 0.0
    public var openingsM2 = 0.0
    public var wallPaintM2 = 0.0
    public var floorM2: Double?
    /// Assumes a flat ceiling the same shape as the floor.
    public var ceilingM2: Double?
    public var floorSource = AreaSource.unavailable
    public var perimeterM = 0.0
    public var ceilingHeightM = 0.0
    public var minWallHeightM = 0.0
    public var maxWallHeightM = 0.0
    /// Perimeter less doorways and floor-level openings.
    public var skirtingM = 0.0
    /// Architraves, one side: two legs and a head per door.
    public var doorTrimM = 0.0
    /// Four sides per window.
    public var windowTrimM = 0.0
    public var gapCount = 0
    /// Furniture the painter chose to paint, kept apart from walls: it's joinery
    /// work, usually priced differently.
    public var furniturePaintM2 = 0.0
    public var furniturePaintCount = 0

    public init() {}

    public var isClosed: Bool { wallCount >= 3 && gapCount == 0 }
}

public struct PlanSegment: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: SurfaceKind
    /// "A" for walls, "D1"/"W1" for openings.
    public var shortLabel: String
    public var start: Vec2
    public var end: Vec2
    public var lengthM: Double
    public var needsAttention: Bool

    public var midpoint: Vec2 { (start + end) / 2 }
}

/// Top-down drawing data in world metres (x → right, z → down).
public struct FloorPlan: Equatable, Sendable {
    public var walls: [PlanSegment] = []
    public var openings: [PlanSegment] = []
    public var floorOutline: [Vec2] = []
    /// Wall ends that don't meet another wall: gaps in the outline.
    public var openEnds: [Vec2] = []
    /// Furniture footprints.
    public var objects: [PlanObject] = []

    public init() {}

    public var allPoints: [Vec2] {
        walls.flatMap { [$0.start, $0.end] } + openings.flatMap { [$0.start, $0.end] } + floorOutline
    }
}

public struct PlanObject: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var corners: [Vec2]
    public var isPainted: Bool
}

public struct RoomMeasurements: Equatable, Sendable {
    public var surfaces: [Surface]
    public var summary: RoomSummary
    public var plan: FloorPlan
    /// Furniture that could be painted (appliances left out).
    public var furniture: [FurnitureItem] = []

    public var walls: [Surface] { surfaces.filter { $0.kind == .wall } }
    public var openingSurfaces: [Surface] { surfaces.filter { [.door, .window, .opening].contains($0.kind) } }
    public var ceiling: Surface? { surfaces.first { $0.kind == .ceiling } }

    public func openings(onWall wallId: UUID) -> [Surface] {
        openingSurfaces.filter { $0.wallId == wallId }
    }

    public func surface(_ id: UUID) -> Surface? { surfaces.first { $0.id == id } }
}
