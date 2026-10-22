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
