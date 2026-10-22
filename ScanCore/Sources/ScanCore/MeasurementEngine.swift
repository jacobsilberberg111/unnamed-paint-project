import Foundation

/// Turns raw scan geometry (plus any tape-measure corrections) into paintable areas,
/// trim lengths and a floor plan. Pure and deterministic: same input, same numbers.
///
/// Two accuracy refinements run on top of RoomPlan's numbers:
///  - Corners from plane intersections. LiDAR pins down where a wall's face is very
///    well (a plane fitted to thousands of points) but where the wall *ends* less well.
///    When the walls close into a loop, each corner is where the two neighbouring wall
///    planes intersect, and wall lengths and floor area come from those corners.
///  - Consensus ceiling height. Walls within a few cm of the room's median height are
///    snapped to it (that spread is scan noise). A wall that comes up clearly shorter
///    than the rest almost always had its ceiling line missed, so it takes the room's
///    height and is flagged for a tape check.
public enum MeasurementEngine {
    /// Wall ends closer than this count as meeting at a corner.
    public static let cornerTolerance = 0.3
    /// Wall heights within this of the room's median are treated as noise and snapped to it.
    public static let heightConsensusTolerance = 0.03
    /// A door whose top is closer than this to the ceiling gets a height check.
    static let doorCeilingGap = 0.15
    /// Furniture "in front of" a door or window is within this of its wall…
    static let furnitureDepth = 0.5
    /// …and covers at least this share of its width.
    static let furnitureCoverage = 0.5
    /// How far an opening's centre can sit off a wall's plane and still belong to it.
    static let openingPlaneTolerance = 0.35
    /// An opening whose bottom is within this of the floor breaks the skirting.
    static let floorLevelTolerance = 0.15
    /// Polygon walls with less than this share of width × height are flagged as sloped.
    static let slopedThreshold = 0.97
    /// A plane-intersection corner further than this from where the wall ends actually
    /// meet is distrusted (bad plane fit), and the ends' midpoint is used instead.
    static let maxCornerShift = 0.3
    /// Refined lengths further than this from RoomPlan's own figure are ignored.
    static let maxLengthCorrection = 0.15
    /// Neighbouring walls closer to parallel than this can't be intersected reliably.
    static let minCornerAngle = 10.0 * Double.pi / 180

    public static func measure(_ g: ScanGeometry, overrides: [SurfaceOverride] = [],
                               furniture choices: [FurniturePaint] = []) -> RoomMeasurements {
        let overrideById = Dictionary(overrides.map { ($0.surfaceId, $0) }, uniquingKeysWith: { _, last in last })
        func kept(_ s: ScannedSurface) -> Bool { overrideById[s.id]?.isRemoved != true }
        // Painter's type corrections: a "window" that's really a door, and so on.
        func retyped(_ s: ScannedSurface) -> ScannedSurface {
            guard let kind = overrideById[s.id]?.kind, kind != s.kind, [.door, .window, .opening, .noPaint].contains(kind) else { return s }
            var s = s
            s.kind = kind
            return s
        }

        let walls = clockwise(g.walls.filter(kept))
        let graph = WallGraph(walls)
        let wallsWithOpenEnds = Set(graph.openEnds.map(\.wall))
        let corners = graph.loop.map { refinedCorners($0, walls: walls) }
        let sloped = walls.map(isSloped)
        let heights = consensusHeights(walls, sloped: sloped)
        let openingsIn = (g.doors + g.windows + g.openings + g.noPaint).filter(kept).map(retyped)

        let builtInIds = Set(choices.filter { $0.builtIn == true }.map(\.objectId))
        let builtIns = g.objects.filter { builtInIds.contains($0.id) && !FurnitureEstimator.appliances.contains($0.category) }

        let frames = walls.indices.map { i in
            WallFrame(
                wall: walls[i], index: i,
                ends: corners?.ends[i],
                lidarHeight: heights[i].height,
                override: overrideById[walls[i].id]
            )
        }

        // Doors, windows and openings, each placed on its wall.
        var placed: [PlacedOpening] = []
        for o in openingsIn {
            let ov = overrideById[o.id]
            let w = ov?.widthM ?? o.width
            let h = ov?.heightM ?? o.height
            var p = PlacedOpening(surface: o, frame: nil, width: w, height: h, clipped: nil, u: 0, tapeMeasured: ov?.hasSize ?? false)
            if let frame = wallFrame(for: o, in: frames) {
                let local = frame.local(o.center)
                p.frame = frame
                p.u = local.x
                p.clipped = Rect2(center: local, width: w, height: h).intersection(frame.rect)
            }
            placed.append(p)
        }
        placed.sort { a, b in
            let ai = a.frame?.index ?? Int.max, bi = b.frame?.index ?? Int.max
            return ai != bi ? ai < bi : a.u < b.u
        }

        // Wall hidden behind built-in cupboards, per wall, in each wall's face coordinates.
        var coverRects = [[Rect2]](repeating: [], count: frames.count)
        var covers: [UUID: (walls: [UUID], area: Double)] = [:]
        for o in builtIns {
            for frame in frames {
                guard let rect = cover(o, on: frame) else { continue }
                coverRects[frame.index].append(rect)
                covers[o.id, default: ([], 0)].walls.append(frame.wall.id)
                covers[o.id, default: ([], 0)].area += rect.area
            }
        }

        var surfaces: [Surface] = []
        var plan = FloorPlan()
        var summary = RoomSummary()

        // Walls
        for frame in frames {
            let wall = frame.wall
            let i = frame.index
            var flags: [SurfaceFlag] = []
            let baseArea: Double
            if wall.isCurved {
                flags.append(.curved)
                baseArea = frame.lidarWidth * frame.lidarHeight
            } else if sloped[i] {
                flags.append(.sloped)
                baseArea = Geometry.area(of: wall.polygon) * frame.lidarWidth / wall.dimensions.x
            } else {
                baseArea = frame.lidarWidth * frame.lidarHeight
            }
            if frame.tapeMeasured { flags.append(.tapeMeasured) }
            if wall.confidence == .low { flags.append(.lowConfidence) }
            if wall.dimensions.x < cornerTolerance { flags.append(.tinyWall) }
            // A tape-measured height replaces the guess, so the warning no longer applies.
            if heights[i].fromRoom, overrideById[wall.id]?.heightM == nil { flags.append(.heightFromRoom) }

            let openingRects = placed.filter { $0.frame?.index == i }.compactMap(\.clipped)
            let openingsArea = Geometry.unionArea(openingRects)
            // Counted once where a built-in overlaps a door or window.
            let coveredArea = coverRects[i].isEmpty ? 0 : Geometry.unionArea(openingRects + coverRects[i]) - openingsArea
            surfaces.append(Surface(
                id: wall.id, kind: .wall, label: "Wall \(frame.shortLabel)",
                widthM: frame.width, heightM: frame.height,
                grossAreaM2: baseArea * frame.scaleX * frame.scaleY,
                openingsM2: openingsArea,
                coveredM2: coveredArea,
                scannedWidthM: frame.lidarWidth, scannedHeightM: frame.lidarHeight,
                flags: flags
            ))

            plan.walls.append(PlanSegment(
                id: wall.id, kind: .wall, shortLabel: frame.shortLabel,
                start: frame.planEnds.start, end: frame.planEnds.end,
                lengthM: frame.width,
                needsAttention: wallsWithOpenEnds.contains(i)
                    || flags.contains(.lowConfidence) || flags.contains(.heightFromRoom) || flags.contains(.tinyWall)
            ))
        }

        // Openings
        var counters: [SurfaceKind: Int] = [:]
        for p in placed {
            let kind = p.surface.kind
            counters[kind, default: 0] += 1
            let n = counters[kind]!
            let (name, short): (String, String)
            switch kind {
            case .door: (name, short) = ("Door", "D")
            case .window: (name, short) = ("Window", "W")
            case .noPaint: (name, short) = ("Not painted", "N")
            default: (name, short) = ("Opening", "O")
            }
            var flags: [SurfaceFlag] = []
            if p.tapeMeasured { flags.append(.tapeMeasured) }
            if overrideById[p.surface.id]?.kind != nil { flags.append(.typeCorrected) }
            if p.surface.spotted == true { flags.append(.foundByCamera) }
            if p.surface.confidence == .low { flags.append(.lowConfidence) }
            if p.frame == nil { flags.append(.notOnAWall) }
            if kind == .door, !p.tapeMeasured, let frame = p.frame, let clipped = p.clipped,
               frame.rect.maxY - clipped.maxY < doorCeilingGap {
                flags.append(.nearCeiling)
            }
            let bottom = p.surface.center.y - p.surface.height / 2
            if kind != .noPaint, g.objects.contains(where: { $0.blocks(p.surface, width: p.surface.width, bottom: bottom, top: bottom + p.surface.height,
                                                      depth: furnitureDepth, coverage: furnitureCoverage) }) {
                flags.append(.nearFurniture)
            }
            surfaces.append(Surface(
                id: p.surface.id, kind: kind, label: "\(name) \(n)",
                widthM: p.width, heightM: p.height, grossAreaM2: p.width * p.height,
                wallId: p.frame?.wall.id,
                scannedWidthM: p.surface.width, scannedHeightM: p.surface.height,
                flags: flags
            ))
            let ends = p.surface.planEndpoints
            plan.openings.append(PlanSegment(
                id: p.surface.id, kind: kind, shortLabel: "\(short)\(n)", start: ends.start, end: ends.end,
                lengthM: p.width, needsAttention: p.frame == nil || flags.contains(.nearFurniture)
            ))
            switch kind {
            case .door: summary.doorTrimM += 2 * p.height + p.width
            case .window: summary.windowTrimM += 2 * (p.width + p.height)
            default: break
            }
        }

        // Floor and ceiling: the wall-corner outline when the walls close, else RoomPlan's floor.
        if let outline = corners?.outline {
            summary.floorM2 = Geometry.area(of: outline)
            summary.floorSource = .wallOutline
            plan.floorOutline = outline
        } else if !g.floors.isEmpty {
            let shapes = g.floors.map(floorShape)
            summary.floorM2 = shapes.map(\.area).reduce(0, +)
            summary.floorSource = .scannedFloor
            plan.floorOutline = shapes.max { $0.area < $1.area }?.outline ?? []
        }
        summary.ceilingM2 = summary.floorM2
        if let ceiling = summary.ceilingM2, ceiling > 0 {
            let xs = plan.floorOutline.map(\.x), ys = plan.floorOutline.map(\.y)
            surfaces.append(Surface(
                id: Surface.ceilingID, kind: .ceiling, label: "Ceiling",
                widthM: (xs.max() ?? 0) - (xs.min() ?? 0), heightM: (ys.max() ?? 0) - (ys.min() ?? 0),
                grossAreaM2: ceiling
            ))
        }
        plan.openEnds = graph.openEnds.map(\.point)
        let furniture = FurnitureEstimator.items(g.objects, walls: walls, choices: choices, covers: covers)
        let painted = Set(furniture.filter(\.isPainted).map(\.id))
        plan.objects = g.objects.map {
            PlanObject(id: $0.id, corners: $0.planCorners, isPainted: painted.contains($0.id), isBuiltIn: builtInIds.contains($0.id))
        }
        summary.furniturePaintM2 = furniture.filter(\.isPainted).map(\.paintAreaM2).reduce(0, +)
        summary.furniturePaintCount = painted.count

        // Totals
        let wallSurfaces = surfaces.filter { $0.kind == .wall }
        let wallHeights = wallSurfaces.map(\.heightM)
        summary.wallCount = wallSurfaces.count
        summary.doorCount = openingsIn.filter { $0.kind == .door }.count
        summary.windowCount = openingsIn.filter { $0.kind == .window }.count
        summary.openingCount = openingsIn.filter { $0.kind == .opening }.count
        summary.wallGrossM2 = wallSurfaces.map(\.grossAreaM2).reduce(0, +)
        summary.openingsM2 = wallSurfaces.map(\.openingsM2).reduce(0, +)
        summary.wallPaintM2 = wallSurfaces.map(\.paintAreaM2).reduce(0, +)
        summary.builtInCoveredM2 = wallSurfaces.map(\.coveredM2).reduce(0, +)
        summary.perimeterM = wallSurfaces.map(\.widthM).reduce(0, +)
        summary.ceilingHeightM = Geometry.median(wallHeights) ?? 0
        summary.minWallHeightM = wallHeights.min() ?? 0
        summary.maxWallHeightM = wallHeights.max() ?? 0
        let doorways = placed.reduce(0.0) { total, p in
            guard let frame = p.frame, let clipped = p.clipped else { return total }
            guard p.surface.kind != .noPaint else { return total }
            let floorLevel = p.surface.kind == .door || clipped.minY - frame.rect.minY < floorLevelTolerance
            return floorLevel ? total + clipped.width : total
        }
        // Floor-standing built-ins hide the skirting behind them too.
        let hiddenSkirting = frames.reduce(0.0) { total, frame in
            total + coverRects[frame.index].filter { $0.minY - frame.rect.minY < floorLevelTolerance }.map(\.width).reduce(0, +)
        }
        summary.skirtingM = max(0, summary.perimeterM - doorways - hiddenSkirting)
        summary.gapCount = graph.openEnds.count

        return RoomMeasurements(surfaces: surfaces, summary: summary, plan: plan, furniture: furniture)
    }

    /// The patch of a wall a built-in covers, in the wall's face coordinates, or nil
    /// if it doesn't stand against that wall.
    static func cover(_ o: ScannedObject, on frame: WallFrame) -> Rect2? {
        let n = frame.wall.normal.normalized
        let ox = Vec3(o.xAxis.x, 0, o.xAxis.z).normalized, oz = Vec3(o.zAxis.x, 0, o.zAxis.z).normalized
        guard max(abs(ox.dot(n)), abs(oz.dot(n))) > 0.9 else { return nil }
        let corners = o.planCorners
        let gap = corners.map { abs((Vec3($0.x, frame.center.y, $0.y) - frame.center).dot(n)) }.min() ?? .infinity
        guard gap <= FurnitureEstimator.wallContact else { return nil }
        let bottom = o.center.y - o.dimensions.y / 2, top = o.center.y + o.dimensions.y / 2
        let pts = corners.flatMap { [frame.local(Vec3($0.x, bottom, $0.y)), frame.local(Vec3($0.x, top, $0.y))] }
        let rect = Rect2(minX: pts.map(\.x).min()!, minY: pts.map(\.y).min()!,
                         maxX: pts.map(\.x).max()!, maxY: pts.map(\.y).max()!)
        return rect.intersection(frame.rect)
    }

    // MARK: Refinements

    struct RefinedCorners {
        /// Per wall index: its two ends after refinement.
        var ends: [Int: (start: Vec2, end: Vec2)]
        /// Corner points in order round the room.
        var outline: [Vec2]
    }

    /// Each corner where two wall planes intersect, falling back to the midpoint of
    /// the two wall ends when the walls are near-parallel, curved or the fit disagrees.
    static func refinedCorners(_ joints: [WallGraph.Joint], walls: [ScannedSurface]) -> RefinedCorners {
        var ends: [Int: [Vec2?]] = [:]
        var outline: [Vec2] = []
        for joint in joints {
            let a = walls[joint.a], b = walls[joint.b]
            var corner = joint.midpoint
            if !a.isCurved, !b.isCurved, let x = intersect(a, b), x.distance(to: joint.midpoint) <= maxCornerShift {
                corner = x
            }
            outline.append(corner)
            ends[joint.a, default: [nil, nil]][joint.aSide] = corner
            ends[joint.b, default: [nil, nil]][joint.bSide] = corner
        }
        var result: [Int: (start: Vec2, end: Vec2)] = [:]
        for (wall, pair) in ends {
            if let start = pair[0], let end = pair[1] { result[wall] = (start, end) }
        }
        return RefinedCorners(ends: result, outline: outline)
    }

    /// Where two vertical wall planes cross, seen from above.
    static func intersect(_ a: ScannedSurface, _ b: ScannedSurface) -> Vec2? {
        let pa = a.center.plan, da = a.xAxis.plan.normalized
        let pb = b.center.plan, db = b.xAxis.plan.normalized
        let denom = da.x * db.y - da.y * db.x
        guard abs(denom) >= sin(minCornerAngle) else { return nil }
        let d = pb - pa
        let t = (d.x * db.y - d.y * db.x) / denom
        return pa + da * t
    }

    static func isSloped(_ wall: ScannedSurface) -> Bool {
        guard !wall.isCurved, wall.polygon.count >= 3 else { return false }
        let area = Geometry.area(of: wall.polygon)
        return area > 0.01 && area < wall.dimensions.x * wall.height * slopedThreshold
    }

    /// The room's ceiling height: median of the flat walls RoomPlan is confident about.
    static func referenceHeight(_ walls: [ScannedSurface], sloped: [Bool]) -> Double? {
        let flat = walls.indices.filter { !sloped[$0] }
        let trusted = flat.filter { walls[$0].confidence != .low }
        return Geometry.median((trusted.isEmpty ? flat : trusted).map { walls[$0].height })
    }

    /// Wall heights after snapping scan noise to the room's consensus ceiling height.
    /// A wall clearly shorter than the room is assumed to have had its ceiling line
    /// missed (it's far more common than a genuinely lower wall in one room) and gets
    /// the room's height, flagged. Taller walls are left alone.
    static func consensusHeights(_ walls: [ScannedSurface], sloped: [Bool]) -> [(height: Double, fromRoom: Bool)] {
        guard walls.count >= 3, let reference = referenceHeight(walls, sloped: sloped) else {
            return walls.map { (height: $0.height, fromRoom: false) }
        }
        return walls.indices.map { i in
            let h = walls[i].height
            if sloped[i] { return (h, false) }
            if abs(h - reference) <= heightConsensusTolerance { return (reference, false) }
            if h < reference { return (reference, true) }
            return (h, false)
        }
    }

    // MARK: Helpers

    /// Walls sorted clockwise (seen from above) starting from the top of the plan,
    /// so labels A, B, C… run round the room in order.
    static func clockwise(_ walls: [ScannedSurface]) -> [ScannedSurface] {
        guard walls.count > 1 else { return walls }
        let centers = walls.map { $0.center.plan }
        let c = centers.reduce(Vec2.zero, +) / Double(centers.count)
        func angle(_ p: Vec2) -> Double {
            // y grows downwards in plan space, so atan2 increases clockwise. Shift so 0 is straight up.
            var a = atan2(p.y - c.y, p.x - c.x) + .pi / 2
            if a < 0 { a += 2 * .pi }
            return a
        }
        return walls.sorted { angle($0.center.plan) < angle($1.center.plan) }
    }

    static func wallLabel(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return index < letters.count ? String(letters[index]) : "\(index + 1)"
    }

    static func wallFrame(for opening: ScannedSurface, in frames: [WallFrame]) -> WallFrame? {
        if let parent = opening.parentId, let frame = frames.first(where: { $0.wall.id == parent }) {
            return frame
        }
        var best: (frame: WallFrame, offPlane: Double)?
        for frame in frames {
            let d = opening.center - frame.wall.center
            let offPlane = abs(d.dot(frame.wall.normal.normalized))
            let u = d.dot(frame.wall.xAxis.normalized)
            let v = d.dot(frame.wall.yAxis.normalized)
            guard offPlane < openingPlaneTolerance,
                  abs(u) <= frame.wall.dimensions.x / 2 + 0.1,
                  abs(v) <= frame.wall.height / 2 + 0.1 else { continue }
            if offPlane < (best?.offPlane ?? .infinity) { best = (frame, offPlane) }
        }
        return best?.frame
    }

    static func floorShape(_ f: ScannedSurface) -> (area: Double, outline: [Vec2]) {
        if f.polygon.count >= 3 {
            return (Geometry.area(of: f.polygon), f.polygon.map { f.worldPoint($0).plan })
        }
        // No outline: treat it as a rectangle in whichever two local axes lie flat.
        let axes = [(f.xAxis.normalized, f.dimensions.x), (f.yAxis.normalized, f.dimensions.y), (f.normal.normalized, f.dimensions.z)]
        let up = axes.indices.max { abs(axes[$0].0.y) < abs(axes[$1].0.y) } ?? 2
        let flat = axes.indices.filter { $0 != up }.map { axes[$0] }
        let a = flat[0].0 * (flat[0].1 / 2), b = flat[1].0 * (flat[1].1 / 2)
        let c = f.center
        return (flat[0].1 * flat[1].1, [c + a + b, c - a + b, c - a - b, c + a - b].map(\.plan))
    }
}

/// A wall in measuring position: its refined LiDAR size plus any tape-measured size.
struct WallFrame {
    let wall: ScannedSurface
    let index: Int
    let shortLabel: String
    /// Plan ends after corner refinement.
    let planEnds: (start: Vec2, end: Vec2)
    /// Centre of the refined wall face, bottom edge kept where it was scanned.
    let center: Vec3
    /// Best LiDAR size, before any tape correction.
    let lidarWidth: Double
    let lidarHeight: Double
    /// Final size, after any tape correction.
    let width: Double
    let height: Double
    let scaleX: Double
    let scaleY: Double
    let tapeMeasured: Bool

    init(wall: ScannedSurface, index: Int, ends: (start: Vec2, end: Vec2)?, lidarHeight: Double, override: SurfaceOverride?) {
        self.wall = wall
        self.index = index
        shortLabel = MeasurementEngine.wallLabel(index)

        var planEnds = wall.planEndpoints
        var lidarWidth = wall.width
        var planCenter = wall.center.plan
        if !wall.isCurved, let ends {
            let length = ends.start.distance(to: ends.end)
            if abs(length - wall.dimensions.x) <= MeasurementEngine.maxLengthCorrection {
                planEnds = ends
                lidarWidth = length
                // Keep the centre on the wall's own plane.
                let dir = wall.xAxis.plan.normalized
                let mid = (ends.start + ends.end) / 2
                planCenter = wall.center.plan + dir * (mid - wall.center.plan).dot(dir)
            }
        }
        self.planEnds = planEnds
        self.lidarWidth = lidarWidth
        self.lidarHeight = lidarHeight
        let bottom = wall.center.y - wall.height / 2
        center = Vec3(planCenter.x, bottom + lidarHeight / 2, planCenter.y)

        width = override?.widthM ?? lidarWidth
        height = override?.heightM ?? lidarHeight
        scaleX = lidarWidth > 0 ? width / lidarWidth : 1
        scaleY = lidarHeight > 0 ? height / lidarHeight : 1
        tapeMeasured = override?.hasSize ?? false
    }

    /// The wall face, centred on the origin, in its final size.
    var rect: Rect2 { Rect2(center: .zero, width: width, height: height) }

    /// A world point in the wall's 2D face coordinates (u along the wall, v up, origin
    /// at the face centre), stretched by the same factor as any tape correction.
    /// Heights are measured from the floor so a taller wall grows upwards.
    func local(_ p: Vec3) -> Vec2 {
        let d = p - center
        let aboveFloor = d.dot(wall.yAxis.normalized) + lidarHeight / 2
        return Vec2(d.dot(wall.xAxis.normalized) * scaleX, aboveFloor * scaleY - height / 2)
    }
}

struct PlacedOpening {
    let surface: ScannedSurface
    var frame: WallFrame?
    let width: Double
    let height: Double
    /// The opening's face clipped to its wall, so a window running past a corner
    /// doesn't subtract area the wall doesn't have.
    var clipped: Rect2?
    var u: Double
    let tapeMeasured: Bool
}

/// How the walls connect when seen from above.
struct WallGraph {
    /// Where wall `a`'s end `aSide` (0 = start, 1 = end) meets wall `b`'s end `bSide`.
    struct Joint {
        let a: Int
        let aSide: Int
        let b: Int
        let bSide: Int
        let midpoint: Vec2
    }

    let openEnds: [(wall: Int, point: Vec2)]
    /// Corners in order round the room, when the walls chain into one closed loop.
    let loop: [Joint]?

    var outline: [Vec2]? { loop?.map(\.midpoint) }

    init(_ walls: [ScannedSurface], tolerance: Double = MeasurementEngine.cornerTolerance) {
        let ends = walls.map(\.planEndpoints)
        var open: [(wall: Int, point: Vec2)] = []
        for i in ends.indices {
            for p in [ends[i].start, ends[i].end] {
                // Meeting another wall's end or butting into its middle (a T-junction) both count.
                let joined = ends.indices.contains { j in
                    j != i && Geometry.distance(from: p, toSegment: ends[j].start, ends[j].end) < tolerance
                }
                if !joined { open.append((i, p)) }
            }
        }
        openEnds = open
        var loop = open.isEmpty ? Self.findLoop(ends, tolerance: tolerance) : nil
        // A sliver wall shorter than the join distance (RoomPlan sometimes adds a
        // 10–20 cm piece at a corner) has both ends within reach of the same
        // neighbours, so corners can't be paired. Retry with slivers left out of the
        // outline; they still count as walls for paint area.
        if loop == nil, open.isEmpty {
            let keep = ends.indices.filter { ends[$0].start.distance(to: ends[$0].end) >= tolerance }
            if keep.count >= 3, keep.count < ends.count, let sub = Self.findLoop(keep.map { ends[$0] }, tolerance: tolerance) {
                loop = sub.map { Joint(a: keep[$0.a], aSide: $0.aSide, b: keep[$0.b], bSide: $0.bSide, midpoint: $0.midpoint) }
            }
        }
        self.loop = loop
    }

    static func findLoop(_ ends: [(start: Vec2, end: Vec2)], tolerance: Double) -> [Joint]? {
        let n = ends.count
        guard n >= 3 else { return nil }
        func point(_ wall: Int, _ side: Int) -> Vec2 { side == 0 ? ends[wall].start : ends[wall].end }

        var link = [[(wall: Int, side: Int)?]](repeating: [nil, nil], count: n)
        for i in 0..<n {
            for s in 0..<2 {
                var best: (wall: Int, side: Int, d: Double)?
                for j in 0..<n where j != i {
                    for t in 0..<2 {
                        let d = point(i, s).distance(to: point(j, t))
                        if d < tolerance, d < (best?.d ?? .infinity) { best = (j, t, d) }
                    }
                }
                if let best { link[i][s] = (best.wall, best.side) }
            }
        }
        // Every corner must pair two wall ends with each other.
        for i in 0..<n {
            for s in 0..<2 {
                guard let l = link[i][s], let back = link[l.wall][l.side], back.wall == i, back.side == s else { return nil }
            }
        }

        var joints: [Joint] = []
        var visited = Set<Int>()
        var wall = 0, side = 1
        while !visited.contains(wall) {
            visited.insert(wall)
            guard let next = link[wall][side] else { return nil }
            joints.append(Joint(a: wall, aSide: side, b: next.wall, bSide: next.side,
                                midpoint: (point(wall, side) + point(next.wall, next.side)) / 2))
            wall = next.wall
            side = 1 - next.side
        }
        return wall == 0 && visited.count == n ? joints : nil
    }
}
