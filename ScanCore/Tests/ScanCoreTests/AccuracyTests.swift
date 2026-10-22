import XCTest
@testable import ScanCore

/// Ground-truth tests: build rooms with known true dimensions, feed them in the way
/// RoomPlan would describe them (optionally with scanner-like noise), and check the
/// numbers that come out. Seeded, so failures reproduce.
final class AccuracyTests: XCTestCase {
    private let up = Vec3(0, 1, 0)

    // MARK: Room builders

    /// Walls along a closed plan polygon (x, z), listed clockwise as seen on screen.
    private func walls(around corners: [Vec2], height: Double) -> [ScannedSurface] {
        corners.indices.map { i in
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let dir = Vec3(b.x - a.x, 0, b.y - a.y)
            let x = dir.normalized
            return ScannedSurface(
                kind: .wall, dimensions: Vec3(dir.length, height, 0),
                center: Vec3((a.x + b.x) / 2, height / 2, (a.y + b.y) / 2),
                xAxis: x, yAxis: up, normal: x.cross(up)
            )
        }
    }

    private func rectangle(width: Double, depth: Double, yaw: Double, offset: Vec2) -> [Vec2] {
        let local = [Vec2(-width / 2, -depth / 2), Vec2(width / 2, -depth / 2), Vec2(width / 2, depth / 2), Vec2(-width / 2, depth / 2)]
        return local.map { rotate($0, yaw) + offset }
    }

    private func rotate(_ p: Vec2, _ a: Double) -> Vec2 {
        Vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a))
    }

    private func opening(_ kind: SurfaceKind, on wall: ScannedSurface, u: Double, bottom: Double, width: Double, height: Double) -> ScannedSurface {
        let floorY = wall.center.y - wall.height / 2
        let center = Vec3(wall.center.x, floorY + bottom + height / 2, wall.center.z) + wall.xAxis.normalized * u
        return ScannedSurface(kind: kind, dimensions: Vec3(width, height, 0), center: center,
                              xAxis: wall.xAxis, yAxis: up, normal: wall.normal, parentId: wall.id)
    }

    // MARK: Exact input → exact output

    func testRandomRectangularRoomsAreExact() {
        var rng = SplitMix64(seed: 1)
        for _ in 0..<500 {
            let w = Double.random(in: 2...9, using: &rng)
            let d = Double.random(in: 2...9, using: &rng)
            let h = Double.random(in: 2.2...3.6, using: &rng)
            let yaw = Double.random(in: -Double.pi...Double.pi, using: &rng)
            let offset = Vec2(Double.random(in: -20...20, using: &rng), Double.random(in: -20...20, using: &rng))
            let ws = walls(around: rectangle(width: w, depth: d, yaw: yaw, offset: offset), height: h)

            // One door and one window, each fully inside a wall.
            let doorWall = ws[Int.random(in: 0..<4, using: &rng)]
            let doorW = Double.random(in: 0.6...min(1.2, doorWall.width - 0.2), using: &rng)
            let doorH = Double.random(in: 1.9...min(2.2, h - 0.05), using: &rng)
            let doorU = Double.random(in: -(doorWall.width - doorW) / 2...(doorWall.width - doorW) / 2, using: &rng)
            let door = opening(.door, on: doorWall, u: doorU, bottom: 0, width: doorW, height: doorH)

            let winWall = ws[Int.random(in: 0..<4, using: &rng)]
            let winW = Double.random(in: 0.5...min(2.0, winWall.width - 0.2), using: &rng)
            let winH = Double.random(in: 0.5...1.2, using: &rng)
            let winU = Double.random(in: -(winWall.width - winW) / 2...(winWall.width - winW) / 2, using: &rng)
            let window = opening(.window, on: winWall, u: winU, bottom: 0.9, width: winW, height: winH)

            // Window and door on the same wall may overlap; work out the true overlap.
            var overlap = 0.0
            if doorWall.id == winWall.id {
                let doorRect = Rect2(minX: doorU - doorW / 2, minY: 0, maxX: doorU + doorW / 2, maxY: doorH)
                let winRect = Rect2(minX: winU - winW / 2, minY: 0.9, maxX: winU + winW / 2, maxY: 0.9 + winH)
                overlap = doorRect.intersection(winRect)?.area ?? 0
            }

            let s = MeasurementEngine.measure(ScanGeometry(walls: ws.shuffled(using: &rng), doors: [door], windows: [window])).summary
            let gross = 2 * (w + d) * h
            let openings = doorW * doorH + winW * winH - overlap
            XCTAssertEqual(s.wallGrossM2, gross, accuracy: 1e-9)
            XCTAssertEqual(s.openingsM2, openings, accuracy: 1e-9)
            XCTAssertEqual(s.wallPaintM2, gross - openings, accuracy: 1e-9)
            XCTAssertEqual(s.floorM2 ?? -1, w * d, accuracy: 1e-9)
            XCTAssertEqual(s.perimeterM, 2 * (w + d), accuracy: 1e-9)
            XCTAssertEqual(s.ceilingHeightM, h, accuracy: 1e-9)
            XCTAssertEqual(s.skirtingM, 2 * (w + d) - doorW, accuracy: 1e-9)
            XCTAssertTrue(s.isClosed)
        }
    }

    func testRandomLShapedRoomsAreExact() {
        var rng = SplitMix64(seed: 2)
        for _ in 0..<300 {
            let w = Double.random(in: 4...10, using: &rng), d = Double.random(in: 4...10, using: &rng)
            let cutW = Double.random(in: 1...(w - 1.5), using: &rng), cutD = Double.random(in: 1...(d - 1.5), using: &rng)
            let yaw = Double.random(in: -Double.pi...Double.pi, using: &rng)
            // Clockwise on screen (y down): top-left, top-right, notch, bottom-left.
            let local = [Vec2(0, 0), Vec2(w, 0), Vec2(w, d - cutD), Vec2(w - cutW, d - cutD), Vec2(w - cutW, d), Vec2(0, d)]
            let corners = local.map { rotate($0, yaw) }
            let h = 2.7
            let s = MeasurementEngine.measure(ScanGeometry(walls: walls(around: corners, height: h))).summary
            XCTAssertEqual(s.wallCount, 6)
            XCTAssertEqual(s.floorM2 ?? -1, w * d - cutW * cutD, accuracy: 1e-9)
            XCTAssertEqual(s.perimeterM, 2 * (w + d), accuracy: 1e-9)
            XCTAssertEqual(s.wallGrossM2, 2 * (w + d) * h, accuracy: 1e-9)
        }
    }

    func testRandomAngledRoomsAreExact() {
        // Convex rooms with 5–8 walls at arbitrary angles (bay windows, angled corners).
        var rng = SplitMix64(seed: 3)
        for _ in 0..<300 {
            let n = Int.random(in: 5...8, using: &rng)
            let angles = (0..<n).map { _ in Double.random(in: 0..<(2 * Double.pi), using: &rng) }.sorted()
            // Keep corners at least ~25° apart so every wall is a sensible length.
            guard zip(angles, angles.dropFirst() + [angles[0] + 2 * .pi]).allSatisfy({ $1 - $0 > 0.45 }) else { continue }
            let rx = Double.random(in: 2...5, using: &rng), rz = Double.random(in: 2...5, using: &rng)
            let corners = angles.map { Vec2(rx * cos($0), rz * sin($0)) }
            let s = MeasurementEngine.measure(ScanGeometry(walls: walls(around: corners, height: 2.5))).summary
            let truePerimeter = corners.indices.map { corners[$0].distance(to: corners[($0 + 1) % n]) }.reduce(0, +)
            XCTAssertTrue(s.isClosed)
            XCTAssertEqual(s.floorM2 ?? -1, Geometry.area(of: corners), accuracy: 1e-9)
            XCTAssertEqual(s.perimeterM, truePerimeter, accuracy: 1e-9)
        }
    }

    func testMovingTheWholeScanChangesNothing() {
        // ARKit's world origin is wherever the scan started; results must not depend on it.
        let base = ScanGeometry.sampleLounge
        let reference = MeasurementEngine.measure(base).summary
        var rng = SplitMix64(seed: 4)
        for _ in 0..<100 {
            let yaw = Double.random(in: -Double.pi...Double.pi, using: &rng)
            let shift = Vec3(Double.random(in: -50...50, using: &rng), Double.random(in: -2...2, using: &rng), Double.random(in: -50...50, using: &rng))
            func move(_ s: ScannedSurface) -> ScannedSurface {
                func r(_ v: Vec3) -> Vec3 { Vec3(v.x * cos(yaw) - v.z * sin(yaw), v.y, v.x * sin(yaw) + v.z * cos(yaw)) }
                var s = s
                s.center = r(s.center) + shift
                s.xAxis = r(s.xAxis)
                s.yAxis = r(s.yAxis)
                s.normal = r(s.normal)
                return s
            }
            let moved = ScanGeometry(walls: base.walls.map(move), doors: base.doors.map(move),
                                     windows: base.windows.map(move), floors: base.floors.map(move))
            let s = MeasurementEngine.measure(moved).summary
            XCTAssertEqual(s.wallPaintM2, reference.wallPaintM2, accuracy: 1e-9)
            XCTAssertEqual(s.floorM2 ?? -1, reference.floorM2 ?? -2, accuracy: 1e-9)
            XCTAssertEqual(s.skirtingM, reference.skirtingM, accuracy: 1e-9)
            XCTAssertEqual(s.perimeterM, reference.perimeterM, accuracy: 1e-9)
        }
    }

    // MARK: Scanner-like noise

    /// Simulates what LiDAR gets wrong: wall *ends* off by up to ±6 cm each, wall
    /// faces off by up to ±5 mm and ±0.3°, heights off by up to ±2 cm.
    private func noisy(_ wall: ScannedSurface, _ rng: inout SplitMix64, endNoise: Double = 0.06,
                       planeNoise: Double = 0.005, angleNoise: Double = 0.3 * .pi / 180, heightNoise: Double = 0.02) -> ScannedSurface {
        var w = wall
        let startShift = Double.random(in: -endNoise...endNoise, using: &rng)
        let endShift = Double.random(in: -endNoise...endNoise, using: &rng)
        w.dimensions.x += endShift - startShift
        w.center += w.xAxis.normalized * ((startShift + endShift) / 2)
        w.center += w.normal.normalized * Double.random(in: -planeNoise...planeNoise, using: &rng)
        let a = Double.random(in: -angleNoise...angleNoise, using: &rng)
        func r(_ v: Vec3) -> Vec3 { Vec3(v.x * cos(a) - v.z * sin(a), v.y, v.x * sin(a) + v.z * cos(a)) }
        w.xAxis = r(w.xAxis)
        w.normal = r(w.normal)
        let dh = Double.random(in: -heightNoise...heightNoise, using: &rng)
        w.dimensions.y += dh
        w.center.y += dh / 2
        return w
    }

    func testCornerRefinementBeatsRawWallLengths() {
        var rng = SplitMix64(seed: 5)
        var rawErrors: [Double] = [], refinedErrors: [Double] = []
        var rawAreaErrors: [Double] = [], refinedAreaErrors: [Double] = []
        for _ in 0..<400 {
            let w = Double.random(in: 2.5...7, using: &rng), d = Double.random(in: 2.5...7, using: &rng), h = 2.4
            let truth = walls(around: rectangle(width: w, depth: d, yaw: Double.random(in: -3...3, using: &rng), offset: .zero), height: h)
            let scanned = truth.map { noisy($0, &rng) }
            let m = MeasurementEngine.measure(ScanGeometry(walls: scanned))
            XCTAssertTrue(m.summary.isClosed)
            for t in truth {
                let i = truth.firstIndex { $0.id == t.id }!
                let surface = m.surface(t.id)!
                rawErrors.append(abs(scanned[i].dimensions.x - t.width))
                refinedErrors.append(abs(surface.widthM - t.width))
            }
            let rawArea = scanned.map { $0.dimensions.x * $0.height }.reduce(0, +)
            rawAreaErrors.append(abs(rawArea - 2 * (w + d) * h) / (2 * (w + d) * h))
            refinedAreaErrors.append(abs(m.summary.wallGrossM2 - 2 * (w + d) * h) / (2 * (w + d) * h))
            XCTAssertEqual(m.summary.floorM2 ?? -1, w * d, accuracy: w * d * 0.01)
        }
        let rawMean = rawErrors.reduce(0, +) / Double(rawErrors.count)
        let refinedMean = refinedErrors.reduce(0, +) / Double(refinedErrors.count)
        let refinedMax = refinedErrors.max()!
        print(String(format: "Wall length error: raw mean %.1f cm → refined mean %.1f cm (max %.1f cm)",
                     rawMean * 100, refinedMean * 100, refinedMax * 100))
        print(String(format: "Wall area error: raw mean %.2f%% → refined mean %.2f%% (max %.2f%%)",
                     rawAreaErrors.reduce(0, +) / Double(rawAreaErrors.count) * 100,
                     refinedAreaErrors.reduce(0, +) / Double(refinedAreaErrors.count) * 100,
                     refinedAreaErrors.max()! * 100))
        XCTAssertLessThan(refinedMean, rawMean / 3)
        // What's left is mostly the ±0.3° face-angle noise, which moves the far end of a
        // 7 m wall by ~2 cm; plane intersection can't remove that.
        XCTAssertLessThan(refinedMax, 0.04)
    }

    func testHeightConsensusRemovesNoise() {
        var rng = SplitMix64(seed: 6)
        let truth = walls(around: rectangle(width: 4, depth: 3, yaw: 0.3, offset: .zero), height: 2.42)
        let scanned = truth.map { noisy($0, &rng, endNoise: 0, planeNoise: 0, angleNoise: 0, heightNoise: 0.015) }
        let m = MeasurementEngine.measure(ScanGeometry(walls: scanned))
        // Every wall gets the same consensus height, within the noise of the truth.
        let heights = Set(m.walls.map(\.heightM))
        XCTAssertEqual(heights.count, 1)
        XCTAssertEqual(heights.first!, 2.42, accuracy: 0.015)
    }

    func testWallMissingCeilingLineTakesRoomHeight() {
        var ws = walls(around: rectangle(width: 4, depth: 3, yaw: 0, offset: .zero), height: 2.4)
        // Painter never tilted up on this wall: RoomPlan stopped it at 2.05 m.
        ws[1].dimensions.y = 2.05
        ws[1].center.y = 2.05 / 2
        ws[1].completedEdges = [.bottom, .left, .right]
        let window = opening(.window, on: ws[1], u: 0, bottom: 0.9, width: 1.0, height: 1.0)
        let m = MeasurementEngine.measure(ScanGeometry(walls: ws, windows: [window]))
        let wall = m.surface(ws[1].id)!
        XCTAssertEqual(wall.heightM, 2.4, accuracy: 1e-9)
        XCTAssertEqual(wall.grossAreaM2, 3 * 2.4, accuracy: 1e-9)
        XCTAssertEqual(wall.openingsM2, 1.0, accuracy: 1e-9) // window stays where it is
        XCTAssertTrue(wall.flags.contains(.heightFromRoom))
        XCTAssertTrue(wall.flags.contains(.ceilingLineMissed))
    }

    func testGenuinelyDifferentHeightIsKept() {
        // A wall that is really lower (fully scanned, top edge seen) isn't forced to match.
        var ws = walls(around: rectangle(width: 4, depth: 3, yaw: 0, offset: .zero), height: 2.4)
        ws[2].dimensions.y = 2.1
        ws[2].center.y = 1.05
        let m = MeasurementEngine.measure(ScanGeometry(walls: ws))
        XCTAssertEqual(m.surface(ws[2].id)!.heightM, 2.1, accuracy: 1e-9)
        XCTAssertFalse(m.surface(ws[2].id)!.flags.contains(.heightFromRoom))
    }

    func testTapeCheckReportsLidarError() {
        var room = Room.sample
        let wall = room.geometry.walls[0]
        room.setOverride(SizeOverride(surfaceId: wall.id, widthM: wall.width + 0.012, heightM: wall.height - 0.004), for: wall.id)
        let check = room.tapeCheck!
        XCTAssertEqual(check.samples.count, 2)
        XCTAssertEqual(check.worst.errorM, -0.012, accuracy: 1e-9)
        XCTAssertEqual(check.meanAbsErrorM, 0.008, accuracy: 1e-9)
        XCTAssertEqual(check.meanErrorM, -0.004, accuracy: 1e-9)
        XCTAssertNil(Room.sample.tapeCheck)
    }
}

/// Small deterministic RNG so random tests reproduce exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
