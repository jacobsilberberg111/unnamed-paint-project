import Foundation

/// The single most useful thing for the painter to do next while scanning.
public enum ScanGuidance: Equatable, Sendable {
    case findFirstWall
    case keepGoing(wallsFound: Int)
    case closeGap
    case ceilingLine(wall: String)
    case rescan(wall: String)
    case floorLine(wall: String)
    case complete

    public var title: String {
        switch self {
        case .findFirstWall: return "Point at a wall"
        case .keepGoing: return "Keep following the walls"
        case .closeGap: return "Close the gap"
        case .ceilingLine(let wall): return "Tilt up on Wall \(wall)"
        case .rescan(let wall): return "Rescan Wall \(wall)"
        case .floorLine(let wall): return "Tilt down on Wall \(wall)"
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
        case .ceilingLine(let wall):
            return "Aim at the line where Wall \(wall) meets the ceiling, end to end, so its height is exact."
        case .rescan(let wall):
            return "The scanner isn't sure about Wall \(wall). Point at it again slowly from a metre or two away."
        case .floorLine(let wall):
            return "Aim at the bottom of Wall \(wall) where it meets the floor."
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
    /// Labels of walls whose ceiling line hasn't been scanned. Empty when RoomPlan
    /// gives no edge information.
    public var wallsMissingCeilingLine: [String]
    public var wallsMissingFloorLine: [String]
    public var lowConfidenceWalls: [String]
    public var edgeInfoAvailable: Bool
    public var plan: FloorPlan
    public var next: ScanGuidance

    public static let empty = Coverage.analyse(ScanGeometry())

    public var isClosed: Bool { wallCount >= 3 && openEndCount == 0 }
    public var isReadyToFinish: Bool { next == .complete }

    /// What's still wrong, worded for a "finish anyway?" prompt.
    public var outstandingIssues: [String] {
        var issues: [String] = []
        if wallCount < 3 {
            issues.append("Only \(wallCount) wall\(wallCount == 1 ? "" : "s") found.")
        }
        if openEndCount > 0 {
            issues.append("The outline has \(openEndCount) loose wall end\(openEndCount == 1 ? "" : "s"), so floor and ceiling areas may be missing.")
        }
        if !wallsMissingCeilingLine.isEmpty {
            issues.append("Ceiling line not scanned on \(Coverage.list(wallsMissingCeilingLine)): heights may be short.")
        }
        if !lowConfidenceWalls.isEmpty {
            issues.append("Low confidence on \(Coverage.list(lowConfidenceWalls)).")
        }
        if wallCount >= 3, doorCount == 0, openingCount == 0 {
            issues.append("No door found. If there is one, aim at it so it's taken off the paint area.")
        }
        return issues
    }
}

public enum Coverage {
    public static func analyse(_ geometry: ScanGeometry) -> CoverageReport {
        let m = MeasurementEngine.measure(geometry)
        let walls = m.walls
        func labels(_ flag: SurfaceFlag) -> [String] {
            walls.filter { $0.flags.contains(flag) }.map { String($0.label.dropFirst("Wall ".count)) }
        }
        let missingTop = labels(.ceilingLineMissed)
        let missingBottom = labels(.floorLineMissed)
        let lowConfidence = labels(.lowConfidence)
        let openEnds = m.summary.gapCount

        let next: ScanGuidance
        if walls.isEmpty {
            next = .findFirstWall
        } else if walls.count < 3 {
            next = .keepGoing(wallsFound: walls.count)
        } else if openEnds > 0 {
            next = .closeGap
        } else if let wall = missingTop.first {
            next = .ceilingLine(wall: wall)
        } else if let wall = lowConfidence.first {
            next = .rescan(wall: wall)
        } else if let wall = missingBottom.first {
            next = .floorLine(wall: wall)
        } else {
            next = .complete
        }

        return CoverageReport(
            wallCount: walls.count,
            doorCount: geometry.doors.count,
            windowCount: geometry.windows.count,
            openingCount: geometry.openings.count,
            openEndCount: openEnds,
            wallsMissingCeilingLine: missingTop,
            wallsMissingFloorLine: missingBottom,
            lowConfidenceWalls: lowConfidence,
            edgeInfoAvailable: geometry.walls.contains { !$0.completedEdges.isEmpty },
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
