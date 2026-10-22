import XCTest
@testable import ScanCore

final class CoverageTests: XCTestCase {
    private let up = Vec3(0, 1, 0)

    private func wall(_ center: Vec3, along x: Vec3, length: Double,
                      edges: Set<SurfaceEdge> = Set(SurfaceEdge.allCases),
                      confidence: ScanConfidence = .high) -> ScannedSurface {
        ScannedSurface(kind: .wall, dimensions: Vec3(length, 2.4, 0), center: center,
                       xAxis: x, yAxis: up, normal: x.cross(up), confidence: confidence, completedEdges: edges)
    }

    private func walls(northEdges: Set<SurfaceEdge> = Set(SurfaceEdge.allCases),
                       eastConfidence: ScanConfidence = .high) -> [ScannedSurface] {
        [wall(Vec3(0, 1.2, -1.5), along: Vec3(1, 0, 0), length: 4, edges: northEdges),
         wall(Vec3(2, 1.2, 0), along: Vec3(0, 0, 1), length: 3, confidence: eastConfidence),
         wall(Vec3(0, 1.2, 1.5), along: Vec3(-1, 0, 0), length: 4),
         wall(Vec3(-2, 1.2, 0), along: Vec3(0, 0, -1), length: 3)]
    }

    func testGuidanceProgression() {
        XCTAssertEqual(CoverageReport.empty.next, .findFirstWall)

        let all = walls()
        XCTAssertEqual(Coverage.analyse(ScanGeometry(walls: Array(all.prefix(2)))).next, .keepGoing(wallsFound: 2))

        let open = Coverage.analyse(ScanGeometry(walls: Array(all.prefix(3))))
        XCTAssertEqual(open.next, .closeGap)
        XCTAssertEqual(open.openEndCount, 2)
        XCTAssertEqual(open.plan.openEnds.count, 2)
        XCTAssertFalse(open.isClosed)

        let noCeiling = Coverage.analyse(ScanGeometry(walls: walls(northEdges: [.bottom, .left, .right])))
        XCTAssertEqual(noCeiling.next, .ceilingLine(wall: "A"))
        XCTAssertEqual(noCeiling.wallsMissingCeilingLine, ["A"])

        let shaky = Coverage.analyse(ScanGeometry(walls: walls(eastConfidence: .low)))
        XCTAssertEqual(shaky.next, .rescan(wall: "B"))

        let done = Coverage.analyse(ScanGeometry(walls: all))
        XCTAssertEqual(done.next, .complete)
        XCTAssertTrue(done.isReadyToFinish)
        // No door was found, so the finish prompt still mentions it.
        XCTAssertEqual(done.outstandingIssues.count, 1)
    }

    func testNoEdgeInfoMeansNoCeilingNagging() {
        // If RoomPlan reports no completed edges on any wall, treat the signal as absent.
        let bare = walls().map { w -> ScannedSurface in
            var w = w
            w.completedEdges = []
            return w
        }
        let report = Coverage.analyse(ScanGeometry(walls: bare))
        XCTAssertFalse(report.edgeInfoAvailable)
        XCTAssertEqual(report.wallsMissingCeilingLine, [])
        XCTAssertEqual(report.next, .complete)
    }

    func testIssueWording() {
        XCTAssertEqual(Coverage.list(["A"]), "Wall A")
        XCTAssertEqual(Coverage.list(["A", "C"]), "Walls A and C")
        XCTAssertEqual(Coverage.list(["A", "B", "C"]), "Walls A, B and C")
    }
}
