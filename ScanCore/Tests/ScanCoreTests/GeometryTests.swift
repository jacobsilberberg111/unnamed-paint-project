import XCTest
@testable import ScanCore

final class GeometryTests: XCTestCase {
    func testNewellAreaIgnoresOrientation() {
        let square = [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 3, 0), Vec3(0, 3, 0)]
        XCTAssertEqual(Geometry.area(of: square), 6, accuracy: 1e-12)
        // Same square standing up in the x/z plane, reversed winding.
        let upright = [Vec3(0, 0, 0), Vec3(0, 0, 3), Vec3(2, 0, 3), Vec3(2, 0, 0)]
        XCTAssertEqual(Geometry.area(of: upright), 6, accuracy: 1e-12)
    }

    func testShoelace() {
        let l = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 2), Vec2(2, 2), Vec2(2, 3), Vec2(0, 3)]
        XCTAssertEqual(Geometry.area(of: l), 10, accuracy: 1e-12)
    }

    func testUnionArea() {
        let a = Rect2(minX: 0, minY: 0, maxX: 2, maxY: 2)
        let b = Rect2(minX: 1, minY: 1, maxX: 3, maxY: 3)
        let c = Rect2(minX: 10, minY: 10, maxX: 11, maxY: 11)
        XCTAssertEqual(Geometry.unionArea([a, b]), 7, accuracy: 1e-12)
        XCTAssertEqual(Geometry.unionArea([a, a, a]), 4, accuracy: 1e-12)
        XCTAssertEqual(Geometry.unionArea([a, b, c]), 8, accuracy: 1e-12)
        XCTAssertEqual(Geometry.unionArea([]), 0)
    }

    func testSegmentDistance() {
        XCTAssertEqual(Geometry.distance(from: Vec2(1, 1), toSegment: Vec2(0, 0), Vec2(2, 0)), 1, accuracy: 1e-12)
        XCTAssertEqual(Geometry.distance(from: Vec2(3, 0), toSegment: Vec2(0, 0), Vec2(2, 0)), 1, accuracy: 1e-12)
    }

    func testMedian() {
        XCTAssertEqual(Geometry.median([2.4, 2.5, 2.3]), 2.4)
        XCTAssertEqual(Geometry.median([2.4, 2.6]) ?? 0, 2.5, accuracy: 1e-12)
        XCTAssertNil(Geometry.median([]))
    }
}
