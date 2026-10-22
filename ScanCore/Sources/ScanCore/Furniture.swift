import Foundation

/// The painter's choices for one piece of furniture: paint it (optionally with a
/// measured area), and whether it's built in so the wall behind isn't painted.
public struct FurniturePaint: Codable, Equatable, Sendable {
    public var objectId: UUID
    public var include: Bool
    public var areaM2: Double?
    public var builtIn: Bool?

    public init(objectId: UUID, include: Bool, areaM2: Double? = nil, builtIn: Bool? = nil) {
        self.objectId = objectId
        self.include = include
        self.areaM2 = areaM2
        self.builtIn = builtIn
    }
}

/// One piece of furniture that could be painted, with its paintable area.
public struct FurnitureItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// RoomPlan's category, e.g. "storage".
    public var category: String
    /// "Cabinet 1", "Desk / table 2"…
    public var label: String
    public var widthM: Double
    public var heightM: Double
    public var depthM: Double
    /// Front, exposed sides and top of its outline. Faces against a wall and the
    /// underside aren't counted.
    public var estimatedAreaM2: Double
    /// The measured area if the painter entered one, otherwise the estimate.
    public var paintAreaM2: Double
    public var facesAgainstWall: Int
    public var isPainted: Bool
    public var isAreaMeasured: Bool
    /// Built-in joinery: the wall behind it is taken off the paint area.
    public var isBuiltIn: Bool
    /// Walls it covers when built in, and how much of them.
    public var coveredWallIds: [UUID]
    public var coveredWallM2: Double
}

enum FurnitureEstimator {
    /// Never painted, so not offered.
    static let appliances: Set<String> = [
        "television", "refrigerator", "oven", "dishwasher", "washerDryer", "stove", "sink", "toilet", "bathtub",
    ]
    /// A face this close to a wall, and facing it, is treated as against the wall.
    static let wallContact = 0.15

    static func name(for category: String) -> String {
        switch category {
        case "storage": return "Cabinet"
        case "table": return "Desk / table"
        case "chair": return "Chair"
        case "bed": return "Bed"
        case "sofa": return "Sofa"
        case "fireplace": return "Fireplace"
        case "stairs": return "Stairs"
        default:
            let spaced = category.reduce(into: "") { s, ch in
                if ch.isUppercase, !s.isEmpty { s.append(" ") }
                s.append(ch)
            }
            return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
        }
    }

    static func items(_ objects: [ScannedObject], walls: [ScannedSurface], choices: [FurniturePaint],
                      covers: [UUID: (walls: [UUID], area: Double)] = [:]) -> [FurnitureItem] {
        let choiceById = Dictionary(choices.map { ($0.objectId, $0) }, uniquingKeysWith: { _, last in last })
        var counters: [String: Int] = [:]
        return objects.filter { !appliances.contains($0.category) }.map { o in
            let name = name(for: o.category)
            counters[name, default: 0] += 1
            let (area, against) = exposedArea(o, walls: walls)
            let choice = choiceById[o.id]
            return FurnitureItem(
                id: o.id, category: o.category, label: "\(name) \(counters[name]!)",
                widthM: o.dimensions.x, heightM: o.dimensions.y, depthM: o.dimensions.z,
                estimatedAreaM2: area,
                paintAreaM2: choice?.areaM2 ?? area,
                facesAgainstWall: against,
                isPainted: choice?.include ?? false,
                isAreaMeasured: choice?.areaM2 != nil,
                isBuiltIn: choice?.builtIn ?? false,
                coveredWallIds: covers[o.id]?.walls ?? [],
                coveredWallM2: covers[o.id]?.area ?? 0
            )
        }
    }

    /// Top plus every vertical face that isn't against a wall.
    static func exposedArea(_ o: ScannedObject, walls: [ScannedSurface]) -> (area: Double, facesAgainstWall: Int) {
        let w = o.dimensions.x, h = o.dimensions.y, d = o.dimensions.z
        let x = Vec3(o.xAxis.x, 0, o.xAxis.z).normalized
        let z = Vec3(o.zAxis.x, 0, o.zAxis.z).normalized
        let faces: [(normal: Vec3, offset: Double, area: Double)] = [
            (x, w / 2, d * h), (x * -1, w / 2, d * h),
            (z, d / 2, w * h), (z * -1, d / 2, w * h),
        ]
        var area = w * d
        var against = 0
        for face in faces {
            let center = o.center + face.normal * face.offset
            let touching = walls.contains { wall in
                let n = wall.normal.normalized
                let rel = center - wall.center
                return abs(face.normal.dot(n)) > 0.9
                    && abs(rel.dot(n)) < wallContact
                    && abs(rel.dot(wall.xAxis.normalized)) <= wall.dimensions.x / 2 + 0.1
            }
            if touching { against += 1 } else { area += face.area }
        }
        return (area, against)
    }
}
