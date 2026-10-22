import Foundation

/// The single most useful thing for the painter to do next while scanning.
public enum ScanGuidance: Equatable, Sendable {
    case findFirstWall
    case keepGoing(wallsFound: Int)
    case closeGap
    case ceilingLine(wall: String, shortByCm: Int)
    case rescan(wall: String)
    case complete

    public var title: String {
        switch self {
        case .findFirstWall: return "Point at a wall"
        case .keepGoing: return "Keep following the walls"
        case .closeGap: return "Close the gap"
        case .ceilingLine(let wall, _): return "Tilt up on Wall \(wall)"
        case .rescan(let wall): return "Rescan Wall \(wall)"
        case .complete: return "Room looks complete"
        }
    }

    public var detail: String {
        switch self {
        case .findFirstWall:
            return "Start in a corner and aim at the nearest wall. It turns solid once it's mapped."
        case .keepGoing(let found):
            return "Walk slowly along the walls, round the whole room. \(found) found so far."
        case .closeGap:
            return "A red dot on the map is a wall end that doesn't meet anything. Walk over and sweep that corner. If it's an archway with no wall, you can finish anyway."
        case .ceilingLine(let wall, let cm):
            return "Wall \(wall) is coming up \(cm) cm shorter than the others. Sweep along where it meets the ceiling, or tap Done and the room's height will be used."
        case .rescan(let wall):
            return "The scanner isn't sure about Wall \(wall). Point at it again slowly from a metre or two away."
        case .complete:
            return "Every wall joins up. Sweep each door and window once more, then tap Done."
        }
    }
}

/// Live scan progress, recomputed on every RoomPlan update.
public struct CoverageReport: Equatable, Sendable {
    public var wallCount: Int
    public var doorCount: Int
    public var windowCount: Int
    public var openingCount: Int
    public var openEndCount: Int
    /// Walls clearly shorter than the room, worst first: probably a missed ceiling line.
    public var shortWalls: [String]
    public var lowConfidenceWalls: [String]
    public var plan: FloorPlan
    public var next: ScanGuidance

    public static let empty = Coverage.analyse(ScanGeometry())

    public var isClosed: Bool { wallCount >= 3 && openEndCount == 0 }
    /// Hints about heights and confidence never block finishing: the measurement
    /// engine copes with both, and a hint that can't be cleared is worse than none.
    public var isReadyToFinish: Bool { isClosed }

    /// What's still wrong, worded for a "finish anyway?" prompt.
    public var outstandingIssues: [String] {
        var issues: [String] = []
        if wallCount < 3 {
            issues.append("Only \(wallCount) wall\(wallCount == 1 ? "" : "s") found.")
        }
        if openEndCount > 0 {
            issues.append("The outline has \(openEndCount) loose wall end\(openEndCount == 1 ? "" : "s"), so floor and ceiling areas may be missing.")
        }
        if wallCount >= 3, doorCount == 0, openingCount == 0 {
            issues.append("No door found. If there is one, aim at it so it's taken off the paint area.")
        }
        return issues
    }
}

public enum Coverage {
    /// A wall this much shorter than the room is worth a live "tilt up" hint.
    static let shortWallHint = 0.05

    public static func analyse(_ geometry: ScanGeometry) -> CoverageReport {
        let m = MeasurementEngine.measure(geometry)
        let walls = m.walls
        func letter(_ s: Surface) -> String { String(s.label.dropFirst("Wall ".count)) }

        // Compare raw heights (before the engine fills in short walls) with the room's.
        let ordered = MeasurementEngine.clockwise(geometry.walls)
        let sloped = ordered.map(MeasurementEngine.isSloped)
        var short: [(label: String, by: Double)] = []
        if walls.count >= 3, let reference = MeasurementEngine.referenceHeight(ordered, sloped: sloped) {
            for (i, wall) in ordered.enumerated() where !sloped[i] {
                let by = reference - wall.height
                if by >= shortWallHint { short.append((MeasurementEngine.wallLabel(i), by)) }
            }
        }
        short.sort { $0.by > $1.by }
        let lowConfidence = walls.filter { $0.flags.contains(.lowConfidence) }.map(letter)
        let openEnds = m.summary.gapCount

        let next: ScanGuidance
        if walls.isEmpty {
            next = .findFirstWall
        } else if walls.count < 3 {
            next = .keepGoing(wallsFound: walls.count)
        } else if openEnds > 0 {
            next = .closeGap
        } else if let worst = short.first {
            next = .ceilingLine(wall: worst.label, shortByCm: Int((worst.by * 100).rounded()))
        } else if let wall = lowConfidence.first {
            next = .rescan(wall: wall)
        } else {
            next = .complete
        }

        return CoverageReport(
            wallCount: walls.count,
            doorCount: m.summary.doorCount,
            windowCount: m.summary.windowCount,
            openingCount: m.summary.openingCount,
            openEndCount: openEnds,
            shortWalls: short.map(\.label),
            lowConfidenceWalls: lowConfidence,
            plan: m.plan,
            next: next
        )
    }

    /// ["A"] → "Wall A"; ["A", "C"] → "Walls A and C"; ["A", "B", "C"] → "Walls A, B and C".
    static func list(_ labels: [String]) -> String {
        switch labels.count {
        case 0: return ""
        case 1: return "Wall \(labels[0])"
        default: return "Walls " + labels.dropLast().joined(separator: ", ") + " and " + labels.last!
        }
    }
}
