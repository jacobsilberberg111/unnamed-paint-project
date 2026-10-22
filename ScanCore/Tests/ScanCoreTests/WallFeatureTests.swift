import XCTest
@testable import ScanCore

final class WallFeatureTests: XCTestCase {
    private let up = Vec3(0, 1, 0)

    /// 4 × 3 m room, 2.7 m high. North wall at z = -1.5 facing into the room.
    private func room() -> [ScannedSurface] {
        let h = 2.7
        let corners = [Vec2(-2, -1.5), Vec2(2, -1.5), Vec2(2, 1.5), Vec2(-2, 1.5)]
        return corners.indices.map { i in
            let a = corners[i], b = corners[(i + 1) % 4]
            let x = Vec3(b.x - a.x, 0, b.y - a.y).normalized
            return ScannedSurface(kind: .wall, dimensions: Vec3(a.distance(to: b), h, 0),
                                  center: Vec3((a.x + b.x) / 2, h / 2, (a.y + b.y) / 2),
                                  xAxis: x, yAxis: up, normal: x.cross(up))
        }
    }

    private let camera = Vec3(0.3, 1.4, 1.0)

    private func rays(to points: [Vec3], from origin: Vec3? = nil) -> [Ray] {
        points.map { Ray(origin: origin ?? camera, direction: ($0 - (origin ?? camera)).normalized) }
    }

    /// A rectangle on the north wall, corners clockwise from top-left as seen from the room.
    private func northRect(x: Double, bottom: Double, width: Double, height: Double) -> [Vec3] {
        [Vec3(x, bottom + height, -1.5), Vec3(x + width, bottom + height, -1.5),
         Vec3(x + width, bottom, -1.5), Vec3(x, bottom, -1.5)]
    }

    private func observe(_ corners: [Vec3], contrast: Double? = nil) -> WallFeatureObservation? {
        let mid = corners.reduce(Vec3.zero, +) / 4
        return WallFeatureGeometry.observe(corners: rays(to: corners), center: rays(to: [mid])[0],
                                           walls: room(), apparentSize: 0.2, contrast: contrast)
    }

    func testRectangleOnWallIsPlacedAtRealSize() throws {
        let o = try XCTUnwrap(observe(northRect(x: -1.1, bottom: 1.0, width: 1.2, height: 1.0)))
        XCTAssertEqual(o.width, 1.2, accuracy: 1e-9)
        XCTAssertEqual(o.height, 1.0, accuracy: 1e-9)
        XCTAssertEqual(o.bottom, 1.0, accuracy: 1e-9)
        XCTAssertEqual(o.floorY, 0, accuracy: 1e-9)
        XCTAssertEqual(o.ceilingY, 2.7, accuracy: 1e-9)
        XCTAssertEqual(o.center.x, -0.5, accuracy: 1e-9)
        XCTAssertEqual(o.center.z, -1.5, accuracy: 1e-9)
    }

    func testRectangleOnADeskIsRejected() {
        // A tabletop seen at an angle projects onto the wall as a trapezoid.
        let desk = [Vec3(-0.5, 0.75, -1.0), Vec3(0.5, 0.75, -1.0), Vec3(0.5, 0.75, -0.4), Vec3(-0.5, 0.75, -0.4)]
        XCTAssertNil(observe(desk))
    }

    func testTrackerMergesSightingsAndNeedsSeveral() {
        var tracker = WallFeatureTracker()
        let base = northRect(x: -1.1, bottom: 1.0, width: 1.2, height: 1.0)
        let first = tracker.add(observe(base, contrast: 0.3)!)
        XCTAssertTrue(first.isBestView)
        XCTAssertTrue(tracker.confirmed.isEmpty)
        // Slightly jittered sightings of the same window.
        for dx in [0.02, -0.01] {
            let jittered = base.map { $0 + Vec3(dx, 0, 0) }
            XCTAssertEqual(tracker.add(observe(jittered, contrast: 0.35)!).id, first.id)
        }
        XCTAssertEqual(tracker.candidates.count, 1)
        XCTAssertEqual(tracker.confirmed.count, 1)
        XCTAssertEqual(tracker.confirmed[0].center.x, -0.5 + 0.01 / 3, accuracy: 1e-9)
        // Something else entirely is a new candidate.
        tracker.add(observe(northRect(x: 0.8, bottom: 1.2, width: 0.6, height: 0.9))!)
        XCTAssertEqual(tracker.candidates.count, 2)
    }

    func testVisionLabelMapping() {
        XCTAssertEqual(FeatureLabel.from(identifier: "window"), .window)
        XCTAssertEqual(FeatureLabel.from(identifier: "bulletin_board"), .board)
        XCTAssertEqual(FeatureLabel.from(identifier: "mirror"), .board)
        XCTAssertEqual(FeatureLabel.from(identifier: "door"), .door)
        XCTAssertEqual(FeatureLabel.from(identifier: "outdoor"), nil) // not a door
        XCTAssertEqual(FeatureLabel.from(identifier: "poster"), .picture)
        XCTAssertEqual(FeatureLabel.from(identifier: "skateboard"), nil)
    }

    private func candidate(bottom: Double, width: Double, height: Double, contrast: Double? = nil,
                           labels: [FeatureLabel: Double] = [:]) -> WallFeatureCandidate {
        var t = WallFeatureTracker()
        let o = observe(northRect(x: -1.0, bottom: bottom, width: width, height: height), contrast: contrast)!
        for _ in 0..<3 { t.add(o) }
        let id = t.candidates[0].id
        t.addLabels(labels, for: id)
        return t.candidates[0]
    }

    func testClassifierIsSureOnlyWhenSignalsAgree() {
        // Floor-to-ceiling glass at night: dark against a lit wall.
        let glass = WallFeatureClassifier.classify(candidate(bottom: 0, width: 2.0, height: 2.7, contrast: 0.25))
        XCTAssertEqual(glass.kind, .window)
        XCTAssertTrue(glass.isConfident)

        // A dark window on the wall, with the classifier agreeing.
        let window = WallFeatureClassifier.classify(candidate(bottom: 0.9, width: 1.2, height: 1.2, contrast: 0.3, labels: [.window: 0.6]))
        XCTAssertEqual(window.kind, .window)
        XCTAssertTrue(window.isConfident)

        // Pinboard: the classifier knows it.
        let pinboard = WallFeatureClassifier.classify(candidate(bottom: 1.0, width: 0.9, height: 0.6, contrast: 0.8, labels: [.board: 0.55]))
        XCTAssertEqual(pinboard.kind, .noPaint)
        XCTAssertTrue(pinboard.isConfident)

        // A poster comes down, so the wall stays painted.
        let poster = WallFeatureClassifier.classify(candidate(bottom: 1.1, width: 0.6, height: 0.9, contrast: 1.1, labels: [.picture: 0.5]))
        XCTAssertNil(poster.kind)
        XCTAssertTrue(poster.isConfident)

        // Door-sized at floor level but nothing else to go on: ask.
        let maybeDoor = WallFeatureClassifier.classify(candidate(bottom: 0, width: 0.85, height: 2.05, contrast: 1.0))
        XCTAssertEqual(maybeDoor.kind, .door)
        XCTAssertFalse(maybeDoor.isConfident)

        // Something flat with no clues: ask, defaulting to leaving the wall alone.
        let unknown = WallFeatureClassifier.classify(candidate(bottom: 1.0, width: 0.9, height: 0.6, contrast: 0.9))
        XCTAssertNil(unknown.kind)
        XCTAssertFalse(unknown.isConfident)
    }

    func testPostersAreNeverAutoAddedAsWindows() {
        // From a real scan: two posters were added as windows on brightness alone.
        let darkPoster = WallFeatureClassifier.classify(candidate(bottom: 1.0, width: 0.6, height: 0.9, contrast: 0.3))
        XCTAssertFalse(darkPoster.isConfident)
        XCTAssertNil(darkPoster.kind)
        // A white poster on a navy feature wall.
        let lightPoster = WallFeatureClassifier.classify(candidate(bottom: 1.1, width: 0.5, height: 0.7, contrast: 2.6))
        XCTAssertFalse(lightPoster.isConfident)
        XCTAssertNil(lightPoster.kind)
        // But if the classifier also says window, it's a window.
        let window = WallFeatureClassifier.classify(candidate(bottom: 1.0, width: 0.6, height: 0.9, contrast: 0.3, labels: [.window: 0.35]))
        XCTAssertEqual(window.kind, .window)
        XCTAssertTrue(window.isConfident)
    }

    func testSuggestionsSkipWhatRoomPlanFoundAndFurniture() {
        let ws = room()
        let north = ws[0]
        let existing = ScannedSurface(kind: .window, dimensions: Vec3(1.2, 1.0, 0), center: Vec3(-0.5, 1.5, -1.5),
                                      xAxis: north.xAxis, yAxis: up, normal: north.normal, parentId: north.id)
        let wardrobe = ScannedObject(category: "storage", dimensions: Vec3(1.0, 2.2, 0.6),
                                     center: Vec3(1.3, 1.1, -1.5 + 0.3))
        var tracker = WallFeatureTracker()
        let already = observe(northRect(x: -1.1, bottom: 1.0, width: 1.2, height: 1.0), contrast: 0.3)!
        let cupboardDoor = observe(northRect(x: 0.85, bottom: 0.1, width: 0.9, height: 2.0))!
        let missed = WallFeatureGeometry.observe(
            corners: rays(to: [Vec3(2, 2.7, -1.0), Vec3(2, 2.7, 0.8), Vec3(2, 0, 0.8), Vec3(2, 0, -1.0)]),
            center: rays(to: [Vec3(2, 1.35, -0.1)])[0], walls: ws, apparentSize: 0.3, contrast: 0.2)!
        for _ in 0..<3 { tracker.add(already); tracker.add(cupboardDoor); tracker.add(missed) }

        let g = ScanGeometry(walls: ws, windows: [existing], objects: [wardrobe])
        let suggestions = WallFeatureSuggester.suggestions(tracker.confirmed, in: g)
        XCTAssertEqual(suggestions.count, 1)
        let s = suggestions[0]
        XCTAssertEqual(s.wallId, ws[1].id) // east wall
        XCTAssertEqual(s.wallLabel, "Wall B")
        XCTAssertEqual(s.width, 1.8, accuracy: 1e-9)
        XCTAssertEqual(s.height, 2.7, accuracy: 1e-9)
        XCTAssertEqual(s.verdict.kind, .window)
        XCTAssertTrue(s.verdict.isConfident)

        // Applied automatically: the floor-to-ceiling window comes off Wall B.
        var r = Room(name: "Brother's room", geometry: g)
        let before = r.measure().summary.wallPaintM2
        let unsure = r.applyConfident(suggestions)
        XCTAssertTrue(unsure.isEmpty)
        let m = r.measure()
        XCTAssertEqual(m.summary.wallPaintM2, before - 1.8 * 2.7, accuracy: 1e-9)
        XCTAssertEqual(m.summary.windowCount, 2)
        XCTAssertTrue(m.surface(s.id)!.flags.contains(.foundByCamera))
    }

    func testNoPaintPatchSubtractsAreaOnly() {
        let ws = room()
        var r = Room(name: "T", geometry: ScanGeometry(walls: ws))
        let before = r.measure().summary
        let pinboard = ScannedSurface(kind: .noPaint, dimensions: Vec3(0.9, 0.6, 0), center: Vec3(0, 1.4, -1.5),
                                      xAxis: ws[0].xAxis, yAxis: up, normal: ws[0].normal, parentId: ws[0].id)
        r.add(pinboard)
        let after = r.measure()
        XCTAssertEqual(after.summary.wallPaintM2, before.wallPaintM2 - 0.54, accuracy: 1e-9)
        XCTAssertEqual(after.summary.skirtingM, before.skirtingM, accuracy: 1e-9)
        XCTAssertEqual(after.summary.windowTrimM, 0)
        XCTAssertEqual(after.summary.doorCount + after.summary.windowCount + after.summary.openingCount, 0)
        XCTAssertEqual(after.surface(pinboard.id)?.label, "Not painted 1")
    }

    func testRoomsSavedBeforeNoPaintStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Room.sample)) as! [String: Any]
        var geometry = json["geometry"] as! [String: Any]
        geometry.removeValue(forKey: "noPaint")
        json["geometry"] = geometry
        let room = try JSONDecoder().decode(Room.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(room.geometry.noPaint.isEmpty)
    }
}
