import XCTest
@testable import ScanCore

final class CoverageTests: XCTestCase {
    private let up = Vec3(0, 1, 0)

    private func wall(_ center: Vec3, along x: Vec3, length: Double, height: Double = 2.4,
                      confidence: ScanConfidence = .high) -> ScannedSurface {
        var c = center
        c.y = height / 2
        return ScannedSurface(kind: .wall, dimensions: Vec3(length, height, 0), center: c,
                              xAxis: x, yAxis: up, normal: x.cross(up), confidence: confidence)
    }

    private func walls(northHeight: Double = 2.4, eastConfidence: ScanConfidence = .high) -> [ScannedSurface] {
        [wall(Vec3(0, 0, -1.5), along: Vec3(1, 0, 0), length: 4, height: northHeight),
         wall(Vec3(2, 0, 0), along: Vec3(0, 0, 1), length: 3, confidence: eastConfidence),
         wall(Vec3(0, 0, 1.5), along: Vec3(-1, 0, 0), length: 4),
         wall(Vec3(-2, 0, 0), along: Vec3(0, 0, -1), length: 3)]
    }

    func testGuidanceProgression() {
        XCTAssertEqual(CoverageReport.empty.next, .findFirstWall)

        let all = walls()
        XCTAssertEqual(Coverage.analyse(ScanGeometry(walls: Array(all.prefix(2)))).next, .keepGoing(wallsFound: 2))

        let open = Coverage.analyse(ScanGeometry(walls: Array(all.prefix(3))))
        XCTAssertEqual(open.next, .closeGap)
        XCTAssertEqual(open.openEndCount, 2)
        XCTAssertEqual(open.plan.openEnds.count, 2)
        XCTAssertFalse(open.isReadyToFinish)

        let shaky = Coverage.analyse(ScanGeometry(walls: walls(eastConfidence: .low)))
        XCTAssertEqual(shaky.next, .rescan(wall: "B"))
        XCTAssertTrue(shaky.isReadyToFinish)

        let done = Coverage.analyse(ScanGeometry(walls: all))
        XCTAssertEqual(done.next, .complete)
        XCTAssertTrue(done.isReadyToFinish)
        // No door was found, so the finish prompt still mentions it.
        XCTAssertEqual(done.outstandingIssues.count, 1)
    }

    func testShortWallHintComesFromHeightsAndDoesNotBlockFinishing() {
        let short = Coverage.analyse(ScanGeometry(walls: walls(northHeight: 2.28)))
        XCTAssertEqual(short.next, .ceilingLine(wall: "A", shortByCm: 12))
        XCTAssertEqual(short.shortWalls, ["A"])
        XCTAssertTrue(short.isReadyToFinish)

        // A couple of centimetres is scan noise, not a missed ceiling line.
        let noisy = Coverage.analyse(ScanGeometry(walls: walls(northHeight: 2.37)))
        XCTAssertEqual(noisy.next, .complete)
        XCTAssertEqual(noisy.shortWalls, [])
    }

    func testRetypedAndRemovedDetectionsCountCorrectly() {
        let ws = walls()
        let fake = ScannedSurface(kind: .window, dimensions: Vec3(1, 1, 0), center: Vec3(0, 1.5, -1.5),
                                  xAxis: Vec3(1, 0, 0), yAxis: up, normal: Vec3(0, 0, 1), parentId: ws[0].id)
        let g = ScanGeometry(walls: ws, windows: [fake])
        XCTAssertEqual(Coverage.analyse(g).windowCount, 1)
        XCTAssertEqual(MeasurementEngine.measure(g, overrides: [SurfaceOverride(surfaceId: fake.id, removed: true)]).summary.windowCount, 0)
    }

    func testIssueWording() {
        XCTAssertEqual(Coverage.list(["A"]), "Wall A")
        XCTAssertEqual(Coverage.list(["A", "C"]), "Walls A and C")
        XCTAssertEqual(Coverage.list(["A", "B", "C"]), "Walls A, B and C")
    }
}
