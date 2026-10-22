import XCTest
@testable import ScanCore

final class MeasurementEngineTests: XCTestCase {
    private let up = Vec3(0, 1, 0)

    private func wall(_ center: Vec3, along x: Vec3, length: Double, height: Double = 2.4,
                      polygon: [Vec3] = [], edges: Set<SurfaceEdge> = Set(SurfaceEdge.allCases),
                      confidence: ScanConfidence = .high) -> ScannedSurface {
        ScannedSurface(kind: .wall, dimensions: Vec3(length, height, 0), center: center,
                       xAxis: x, yAxis: up, normal: x.cross(up), polygon: polygon,
                       confidence: confidence, completedEdges: edges)
    }

    private func opening(_ kind: SurfaceKind, on wall: ScannedSurface, u: Double, bottom: Double,
                         width: Double, height: Double, linked: Bool = true, offPlane: Double = 0) -> ScannedSurface {
        let center = Vec3(wall.center.x, bottom + height / 2, wall.center.z)
            + wall.xAxis.normalized * u + wall.normal.normalized * offPlane
        return ScannedSurface(kind: kind, dimensions: Vec3(width, height, 0), center: center,
                              xAxis: wall.xAxis, yAxis: up, normal: wall.normal,
                              parentId: linked ? wall.id : nil)
    }

    /// 4 × 3 m room, 2.4 m high. North wall at z = -1.5.
    private func box() -> (north: ScannedSurface, east: ScannedSurface, south: ScannedSurface, west: ScannedSurface) {
        (wall(Vec3(0, 1.2, -1.5), along: Vec3(1, 0, 0), length: 4),
         wall(Vec3(2, 1.2, 0), along: Vec3(0, 0, 1), length: 3),
         wall(Vec3(0, 1.2, 1.5), along: Vec3(-1, 0, 0), length: 4),
         wall(Vec3(-2, 1.2, 0), along: Vec3(0, 0, -1), length: 3))
    }

    func testRectangularRoomTotals() {
        let b = box()
        let door = opening(.door, on: b.south, u: 0.5, bottom: 0, width: 0.82, height: 2.04)
        // Window not linked by RoomPlan: must be matched to the north wall geometrically.
        let window = opening(.window, on: b.north, u: -1, bottom: 1, width: 1.2, height: 1.0, linked: false, offPlane: 0.05)
        let g = ScanGeometry(walls: [b.west, b.south, b.north, b.east], doors: [door], windows: [window])
        let m = MeasurementEngine.measure(g)
        let s = m.summary

        XCTAssertEqual(s.wallCount, 4)
        XCTAssertEqual(s.wallGrossM2, 33.6, accuracy: 1e-9)
        XCTAssertEqual(s.openingsM2, 2.8728, accuracy: 1e-9)
        XCTAssertEqual(s.wallPaintM2, 30.7272, accuracy: 1e-9)
        XCTAssertEqual(s.perimeterM, 14, accuracy: 1e-9)
        XCTAssertEqual(s.ceilingHeightM, 2.4, accuracy: 1e-9)
        XCTAssertEqual(s.floorSource, .wallOutline)
        XCTAssertEqual(s.floorM2 ?? 0, 12, accuracy: 1e-9)
        XCTAssertEqual(s.ceilingM2 ?? 0, 12, accuracy: 1e-9)
        XCTAssertEqual(s.skirtingM, 14 - 0.82, accuracy: 1e-9)
        XCTAssertEqual(s.doorTrimM, 4.9, accuracy: 1e-9)
        XCTAssertEqual(s.windowTrimM, 4.4, accuracy: 1e-9)
        XCTAssertTrue(s.isClosed)
        XCTAssertEqual(m.plan.floorOutline.count, 4)

        // Labels run clockwise from the top of the plan: north, east, south, west.
        XCTAssertEqual(m.walls.map(\.label), ["Wall A", "Wall B", "Wall C", "Wall D"])
        XCTAssertEqual(m.walls.map(\.id), [b.north.id, b.east.id, b.south.id, b.west.id])
        XCTAssertEqual(m.surface(window.id)?.wallId, b.north.id)
        XCTAssertEqual(m.surface(door.id)?.wallId, b.south.id)
        XCTAssertEqual(m.surface(b.north.id)?.openingsM2 ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertEqual(m.ceiling?.grossAreaM2 ?? 0, 12, accuracy: 1e-9)
    }

    func testOverlappingOpeningsCountedOnce() {
        let b = box()
        // RoomPlan sometimes reports a door and an opening in the same place.
        let door = opening(.door, on: b.north, u: 0, bottom: 0, width: 0.9, height: 2.0)
        let dup = opening(.opening, on: b.north, u: 0.1, bottom: 0, width: 0.9, height: 2.0)
        let g = ScanGeometry(walls: [b.north, b.east, b.south, b.west], doors: [door], openings: [dup])
        let north = MeasurementEngine.measure(g).surface(b.north.id)!
        XCTAssertEqual(north.openingsM2, 1.0 * 2.0, accuracy: 1e-9) // union spans 1.0 m wide
    }

    func testOpeningClippedToWall() {
        let b = box()
        // 1 m window centred 0.2 m in from the wall end: 0.3 m of it hangs past the corner.
        let window = opening(.window, on: b.east, u: 1.3, bottom: 1, width: 1.0, height: 1.0)
        let g = ScanGeometry(walls: [b.north, b.east, b.south, b.west], windows: [window])
        let east = MeasurementEngine.measure(g).surface(b.east.id)!
        XCTAssertEqual(east.openingsM2, 0.7, accuracy: 1e-9)
    }

    func testTapeOverrideRescalesWallAndKeepsOpenings() {
        let b = box()
        let window = opening(.window, on: b.north, u: 0, bottom: 1, width: 1.2, height: 1.0)
        var room = Room(name: "Test", geometry: ScanGeometry(walls: [b.north, b.east, b.south, b.west], windows: [window]))
        room.setOverride(SizeOverride(surfaceId: b.north.id, widthM: 4.05, heightM: 2.41), for: b.north.id)
        let m = room.measure()
        let north = m.surface(b.north.id)!
        XCTAssertEqual(north.widthM, 4.05)
        XCTAssertEqual(north.heightM, 2.41)
        XCTAssertEqual(north.scannedWidthM, 4)
        XCTAssertEqual(north.grossAreaM2, 4.05 * 2.41, accuracy: 1e-9)
        XCTAssertEqual(north.openingsM2, 1.2, accuracy: 1e-9)
        XCTAssertTrue(north.flags.contains(.tapeMeasured))
        XCTAssertEqual(m.summary.perimeterM, 14.05, accuracy: 1e-9)

        // Window override flows into the wall it sits in.
        room.setOverride(SizeOverride(surfaceId: window.id, widthM: 1.0), for: window.id)
        XCTAssertEqual(room.measure().surface(b.north.id)!.openingsM2, 1.0, accuracy: 1e-9)

        // Clearing returns to the LiDAR value.
        room.setOverride(nil, for: b.north.id)
        XCTAssertEqual(room.measure().surface(b.north.id)!.widthM, 4)
    }

    func testGableWallUsesPolygonArea() {
        // 4 m wide, 2.4 m to the eaves, 3.4 m at the ridge.
        let poly = [Vec3(-2, -1.7, 0), Vec3(2, -1.7, 0), Vec3(2, 0.7, 0), Vec3(0, 1.7, 0), Vec3(-2, 0.7, 0)]
        let gable = wall(Vec3(0, 1.7, -1.5), along: Vec3(1, 0, 0), length: 4, height: 3.4, polygon: poly)
        let s = MeasurementEngine.measure(ScanGeometry(walls: [gable])).walls[0]
        XCTAssertEqual(s.grossAreaM2, 11.6, accuracy: 1e-9)
        XCTAssertTrue(s.flags.contains(.sloped))
    }

    func testCurvedWallUsesArcLength() {
        var curved = wall(Vec3(0, 1.2, 0), along: Vec3(1, 0, 0), length: 2.0)
        curved.curveLength = .pi // half circle, radius 1
        let s = MeasurementEngine.measure(ScanGeometry(walls: [curved])).walls[0]
        XCTAssertEqual(s.widthM, .pi, accuracy: 1e-9)
        XCTAssertEqual(s.grossAreaM2, .pi * 2.4, accuracy: 1e-9)
        XCTAssertTrue(s.flags.contains(.curved))
    }

    func testScannedFloorUsedWhenWallsDontCloseAndWorksInAnyOrientation() {
        let b = box()
        // L-shaped floor polygon in the floor's local space, with local axes rotated 30°.
        let poly = [Vec3(0, 0, 0), Vec3(4, 0, 0), Vec3(4, 2, 0), Vec3(2, 2, 0), Vec3(2, 3, 0), Vec3(0, 3, 0)]
        let a = Double.pi / 6
        let x = Vec3(cos(a), 0, sin(a)), y = Vec3(-sin(a), 0, cos(a))
        let floor = ScannedSurface(kind: .floor, dimensions: Vec3(4, 3, 0), center: .zero,
                                   xAxis: x, yAxis: y, normal: x.cross(y), polygon: poly)
        // Only three walls: no closed outline, so RoomPlan's floor is used.
        let m = MeasurementEngine.measure(ScanGeometry(walls: [b.north, b.east, b.south], floors: [floor]))
        XCTAssertEqual(m.summary.floorSource, .scannedFloor)
        XCTAssertEqual(m.summary.floorM2 ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(Geometry.area(of: m.plan.floorOutline), 10, accuracy: 1e-9)

        // With all four walls the wall-corner outline takes over.
        let closed = MeasurementEngine.measure(ScanGeometry(walls: [b.north, b.east, b.south, b.west], floors: [floor]))
        XCTAssertEqual(closed.summary.floorSource, .wallOutline)
        XCTAssertEqual(closed.summary.floorM2 ?? 0, 12, accuracy: 1e-9)
    }

    func testFloorWithoutPolygonUsesFlatAxes() {
        // RoomPlan-style floor: local z is up, so dimensions are (x, y) in plan.
        let floor = ScannedSurface(kind: .floor, dimensions: Vec3(4, 3, 0), center: .zero,
                                   xAxis: Vec3(1, 0, 0), yAxis: Vec3(0, 0, 1), normal: Vec3(0, -1, 0))
        let m = MeasurementEngine.measure(ScanGeometry(floors: [floor]))
        XCTAssertEqual(m.summary.floorM2 ?? 0, 12, accuracy: 1e-9)
    }

    func testOpenRoomHasGapsAndNoOutline() {
        let b = box()
        let m = MeasurementEngine.measure(ScanGeometry(walls: [b.north, b.east, b.south]))
        XCTAssertEqual(m.summary.gapCount, 2)
        XCTAssertFalse(m.summary.isClosed)
        XCTAssertEqual(m.summary.floorSource, .unavailable)
        XCTAssertNil(m.summary.ceilingM2)
        XCTAssertNil(m.ceiling)
    }

    func testTJunctionIsNotAGap() {
        let b = box()
        // A short nib wall sticking into the room from the middle of the north wall.
        let nib = wall(Vec3(0, 1.2, -1.0), along: Vec3(0, 0, 1), length: 1.0)
        let m = MeasurementEngine.measure(ScanGeometry(walls: [b.north, b.east, b.south, b.west, nib]))
        // The far end of the nib is free-standing; its root on the north wall is joined.
        XCTAssertEqual(m.summary.gapCount, 1)
    }

    func testSloppyCornersStillCloseTheLoop() {
        // Live scans: corners a few cm apart.
        let b = box()
        var east = b.east
        east.center += Vec3(0.08, 0, 0.05)
        let m = MeasurementEngine.measure(ScanGeometry(walls: [b.north, east, b.south, b.west]))
        XCTAssertTrue(m.summary.isClosed)
        XCTAssertEqual(m.summary.floorM2 ?? 0, 12, accuracy: 0.4)
    }

    func testOpeningOffAnyWallIsNotSubtracted() {
        let b = box()
        let stray = ScannedSurface(kind: .window, dimensions: Vec3(1, 1, 0), center: Vec3(0, 1.5, 0),
                                   xAxis: Vec3(1, 0, 0), yAxis: up, normal: Vec3(0, 0, 1))
        let m = MeasurementEngine.measure(ScanGeometry(walls: [b.north, b.east, b.south, b.west], windows: [stray]))
        XCTAssertEqual(m.summary.openingsM2, 0)
        XCTAssertEqual(m.surface(stray.id)?.flags, [.notOnAWall])
    }

    func testSampleRoom() {
        let m = Room.sample.measure()
        XCTAssertEqual(m.summary.wallCount, 4)
        XCTAssertTrue(m.summary.isClosed)
        XCTAssertEqual(m.summary.floorM2 ?? 0, 15.12, accuracy: 1e-9)
        XCTAssertEqual(m.summary.openingsM2, 1.6728 + 1.8 + 1.44, accuracy: 1e-9)
        XCTAssertEqual(Room.sample.geometry.roomTypeName, "Living room")
        XCTAssertFalse(m.textReport(roomName: "Demo").isEmpty)
    }

    func testRoomRoundTripsThroughJSON() throws {
        var room = Room.sample
        room.setOverride(SizeOverride(surfaceId: room.geometry.walls[0].id, widthM: 4.1), for: room.geometry.walls[0].id)
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        XCTAssertEqual(decoded, room)
        XCTAssertEqual(decoded.measure(), room.measure())
    }
}
