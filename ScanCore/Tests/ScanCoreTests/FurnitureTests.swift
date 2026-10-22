import XCTest
@testable import ScanCore

final class FurnitureTests: XCTestCase {
    private let up = Vec3(0, 1, 0)

    /// 4 × 3 m room; north wall at z = -1.5, east wall at x = 2.
    private func room() -> [ScannedSurface] {
        let corners = [Vec2(-2, -1.5), Vec2(2, -1.5), Vec2(2, 1.5), Vec2(-2, 1.5)]
        return corners.indices.map { i in
            let a = corners[i], b = corners[(i + 1) % 4]
            let x = Vec3(b.x - a.x, 0, b.y - a.y).normalized
            return ScannedSurface(kind: .wall, dimensions: Vec3(a.distance(to: b), 2.4, 0),
                                  center: Vec3((a.x + b.x) / 2, 1.2, (a.y + b.y) / 2),
                                  xAxis: x, yAxis: up, normal: x.cross(up))
        }
    }

    private func object(_ category: String, w: Double, h: Double, d: Double, at p: Vec2, yaw: Double = 0) -> ScannedObject {
        ScannedObject(category: category, dimensions: Vec3(w, h, d), center: Vec3(p.x, h / 2, p.y),
                      xAxis: Vec3(cos(yaw), 0, sin(yaw)), zAxis: Vec3(-sin(yaw), 0, cos(yaw)))
    }

    func testWardrobeAgainstWallSkipsItsBack() {
        // 1.8 wide, 2.1 high, 0.6 deep, back flat against the north wall.
        let wardrobe = object("storage", w: 1.8, h: 2.1, d: 0.6, at: Vec2(0, -1.5 + 0.3))
        let item = MeasurementEngine.measure(ScanGeometry(walls: room(), objects: [wardrobe])).furniture[0]
        XCTAssertEqual(item.label, "Cabinet 1")
        XCTAssertEqual(item.facesAgainstWall, 1)
        // Front + two sides + top.
        XCTAssertEqual(item.estimatedAreaM2, 1.8 * 2.1 + 2 * 0.6 * 2.1 + 1.8 * 0.6, accuracy: 1e-9)
    }

    func testCornerUnitSkipsTwoFaces() {
        // Tucked into the north-east corner.
        let unit = object("storage", w: 1.0, h: 0.9, d: 0.5, at: Vec2(2 - 0.5, -1.5 + 0.25))
        let item = MeasurementEngine.measure(ScanGeometry(walls: room(), objects: [unit])).furniture[0]
        XCTAssertEqual(item.facesAgainstWall, 2)
        XCTAssertEqual(item.estimatedAreaM2, 1.0 * 0.9 + 0.5 * 0.9 + 1.0 * 0.5, accuracy: 1e-9)
    }

    func testFreestandingDeskCountsAllSides() {
        let desk = object("table", w: 1.4, h: 0.75, d: 0.7, at: Vec2(0, 0), yaw: 0.3)
        let item = MeasurementEngine.measure(ScanGeometry(walls: room(), objects: [desk])).furniture[0]
        XCTAssertEqual(item.label, "Desk / table 1")
        XCTAssertEqual(item.facesAgainstWall, 0)
        XCTAssertEqual(item.estimatedAreaM2, 2 * 1.4 * 0.75 + 2 * 0.7 * 0.75 + 1.4 * 0.7, accuracy: 1e-9)
    }

    func testPaintingIsOptInAndSeparateFromWalls() {
        let wardrobe = object("storage", w: 1.8, h: 2.1, d: 0.6, at: Vec2(0, -1.2))
        let bedside = object("storage", w: 0.5, h: 0.6, d: 0.4, at: Vec2(-1.5, 1.3))
        let tv = object("television", w: 1.2, h: 0.7, d: 0.1, at: Vec2(1.9, 0))
        var r = Room(name: "Bedroom", geometry: ScanGeometry(walls: room(), objects: [wardrobe, bedside, tv]))

        let before = r.measure()
        XCTAssertEqual(before.furniture.map(\.label), ["Cabinet 1", "Cabinet 2"]) // TV not offered
        XCTAssertEqual(before.summary.furniturePaintM2, 0)
        XCTAssertFalse(before.plan.objects.contains(where: \.isPainted))
        let walls = before.summary.wallPaintM2

        r.setFurniture(wardrobe.id, include: true)
        let painted = r.measure()
        XCTAssertEqual(painted.summary.furniturePaintCount, 1)
        XCTAssertEqual(painted.summary.furniturePaintM2, painted.furniture[0].estimatedAreaM2, accuracy: 1e-9)
        XCTAssertEqual(painted.summary.wallPaintM2, walls, accuracy: 1e-9) // walls untouched
        XCTAssertTrue(painted.plan.objects.first { $0.id == wardrobe.id }!.isPainted)

        // A measured area replaces the estimate.
        r.setFurniture(wardrobe.id, include: true, areaM2: 6.0)
        XCTAssertEqual(r.measure().summary.furniturePaintM2, 6.0, accuracy: 1e-9)
        XCTAssertTrue(r.measure().furniture[0].isAreaMeasured)

        r.setFurniture(wardrobe.id, include: false)
        XCTAssertEqual(r.measure().summary.furniturePaintM2, 0)
        XCTAssertTrue(r.furniture.isEmpty)
    }

    func testBuiltInCupboardHidesWallAndSkirting() {
        // Floor-to-ceiling cupboards, 1.5 m wide, against the north wall.
        let cupboards = object("storage", w: 1.5, h: 2.4, d: 0.6, at: Vec2(0.5, -1.5 + 0.3))
        let ws = room()
        var r = Room(name: "Bedroom", geometry: ScanGeometry(walls: ws, objects: [cupboards]))
        let before = r.measure()

        r.updateFurniture(cupboards.id) { $0.builtIn = true }
        let after = r.measure()
        let north = after.surface(ws[0].id)!
        XCTAssertEqual(north.coveredM2, 1.5 * 2.4, accuracy: 1e-9)
        XCTAssertEqual(after.summary.wallPaintM2, before.summary.wallPaintM2 - 3.6, accuracy: 1e-9)
        XCTAssertEqual(after.summary.builtInCoveredM2, 3.6, accuracy: 1e-9)
        XCTAssertEqual(after.summary.skirtingM, before.summary.skirtingM - 1.5, accuracy: 1e-9)
        XCTAssertEqual(after.furniture[0].coveredWallIds, [ws[0].id])
        XCTAssertTrue(after.furniture[0].isBuiltIn)
        XCTAssertFalse(after.furniture[0].isPainted) // built in isn't the same as painting it
        XCTAssertTrue(after.plan.objects[0].isBuiltIn)

        r.updateFurniture(cupboards.id) { $0.builtIn = false }
        XCTAssertEqual(r.measure().summary.wallPaintM2, before.summary.wallPaintM2, accuracy: 1e-9)
        XCTAssertTrue(r.furniture.isEmpty)
    }

    func testCornerBuiltInCoversBothWalls() {
        // 1.0 wide, 0.6 deep, 2.0 high, in the north-east corner.
        let unit = object("storage", w: 1.0, h: 2.0, d: 0.6, at: Vec2(2 - 0.5, -1.5 + 0.3))
        let ws = room()
        var r = Room(name: "T", geometry: ScanGeometry(walls: ws, objects: [unit]))
        r.updateFurniture(unit.id) { $0.builtIn = true }
        let m = r.measure()
        XCTAssertEqual(m.surface(ws[0].id)!.coveredM2, 1.0 * 2.0, accuracy: 1e-9) // north: its back
        XCTAssertEqual(m.surface(ws[1].id)!.coveredM2, 0.6 * 2.0, accuracy: 1e-9) // east: its side
        XCTAssertEqual(m.furniture[0].coveredWallM2, 3.2, accuracy: 1e-9)
    }

    func testBuiltInOverlappingDoorIsCountedOnce() {
        let ws = room()
        let north = ws[0]
        let door = ScannedSurface(kind: .door, dimensions: Vec3(0.8, 2.0, 0), center: Vec3(-1.0, 1.0, -1.5),
                                  xAxis: north.xAxis, yAxis: up, normal: north.normal, parentId: north.id)
        // Door spans x -1.4…-0.6; cupboard spans -0.8…0.2, so they overlap by 0.2 m.
        let unit = object("storage", w: 1.0, h: 2.0, d: 0.5, at: Vec2(-0.3, -1.5 + 0.25))
        var r = Room(name: "T", geometry: ScanGeometry(walls: ws, doors: [door], objects: [unit]))
        r.updateFurniture(unit.id) { $0.builtIn = true }
        let wall = r.measure().surface(north.id)!
        XCTAssertEqual(wall.openingsM2, 1.6, accuracy: 1e-9)
        XCTAssertEqual(wall.coveredM2, 2.0 - 0.2 * 2.0, accuracy: 1e-9)
    }

    func testFreestandingFurnitureCannotHideWall() {
        let desk = object("table", w: 1.4, h: 0.75, d: 0.7, at: Vec2(0, 0))
        var r = Room(name: "T", geometry: ScanGeometry(walls: room(), objects: [desk]))
        r.updateFurniture(desk.id) { $0.builtIn = true }
        XCTAssertEqual(r.measure().summary.builtInCoveredM2, 0)
    }

    func testRoomsSavedBeforeFurniturePaintingStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Room.sample)) as! [String: Any]
        json.removeValue(forKey: "furniture")
        let room = try JSONDecoder().decode(Room.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(room.furniture.isEmpty)

        var withChoice = Room.sample
        withChoice.setFurniture(UUID(), include: true, areaM2: 2)
        let decoded = try JSONDecoder().decode(Room.self, from: JSONEncoder().encode(withChoice))
        XCTAssertEqual(decoded.furniture, withChoice.furniture)
    }
}
