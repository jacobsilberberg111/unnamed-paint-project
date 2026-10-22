import Foundation

/// Display formatting. Lengths to the centimetre, areas to 0.1 m² (per the spec).
public enum Units {
    public static func metres(_ m: Double) -> String { String(format: "%.2f m", m) }
    public static func squareMetres(_ m2: Double) -> String { String(format: "%.1f m²", m2) }
    public static func size(_ w: Double, _ h: Double) -> String { String(format: "%.2f × %.2f m", w, h) }
}

extension SurfaceFlag {
    public var description: String {
        switch self {
        case .tapeMeasured: return "Tape-measured"
        case .lowConfidence: return "Low scan confidence"
        case .heightFromRoom: return "Short scan: used room height"
        case .nearFurniture: return "Furniture in front: check it's real"
        case .tinyWall: return "Tiny wall: remove if not real"
        case .typeCorrected: return "Type corrected"
        case .curved: return "Curved"
        case .sloped: return "Sloped / not rectangular"
        case .notOnAWall: return "Not matched to a wall"
        }
    }

    /// Flags that mean the number may be off and is worth a tape check.
    public var isWarning: Bool {
        switch self {
        case .lowConfidence, .heightFromRoom, .nearFurniture, .tinyWall, .notOnAWall: return true
        case .tapeMeasured, .typeCorrected, .curved, .sloped: return false
        }
    }
}

extension AreaSource {
    public var description: String {
        switch self {
        case .scannedFloor: return "from the scanned floor"
        case .wallOutline: return "from the wall corners"
        case .unavailable: return "not available: the walls don't close into a loop"
        }
    }
}

extension RoomMeasurements {
    /// Plain-text measurement sheet for sharing before the quote exists.
    public func textReport(roomName: String, dateText: String? = nil) -> String {
        let s = summary
        var lines: [String] = []
        lines.append(dateText.map { "\(roomName) (scanned \($0))" } ?? roomName)
        lines.append("")
        lines.append("Wall paint area: \(Units.squareMetres(s.wallPaintM2)) (\(Units.squareMetres(s.wallGrossM2)) gross, less \(Units.squareMetres(s.openingsM2)) of doors and windows)")
        if let c = s.ceilingM2 { lines.append("Ceiling: \(Units.squareMetres(c)) (\(s.floorSource.description), assumes flat)") }
        if let f = s.floorM2 { lines.append("Floor: \(Units.squareMetres(f))") }
        lines.append("Perimeter: \(Units.metres(s.perimeterM)) · Ceiling height: \(Units.metres(s.ceilingHeightM))")
        lines.append("Skirting: \(Units.metres(s.skirtingM)) · Door frames: \(Units.metres(s.doorTrimM)) · Window frames: \(Units.metres(s.windowTrimM))")
        lines.append("\(s.wallCount) walls, \(s.doorCount) doors, \(s.windowCount) windows, \(s.openingCount) openings")
        if !s.isClosed { lines.append("Warning: the wall outline isn't closed (\(s.gapCount) loose ends).") }
        lines.append("")
        for w in walls {
            var line = "\(w.label): \(Units.size(w.widthM, w.heightM)), \(Units.squareMetres(w.grossAreaM2))"
            if w.openingsM2 > 0 { line += " less \(Units.squareMetres(w.openingsM2))" }
            line += " = \(Units.squareMetres(w.paintAreaM2))"
            if !w.flags.isEmpty { line += " [\(w.flags.map(\.description).joined(separator: ", "))]" }
            lines.append(line)
        }
        let openings = openingSurfaces
        if !openings.isEmpty { lines.append("") }
        for o in openings {
            let wall = o.wallId.flatMap { surface($0)?.label } ?? "no wall"
            var line = "\(o.label) (\(wall)): \(Units.size(o.widthM, o.heightM))"
            if !o.flags.isEmpty { line += " [\(o.flags.map(\.description).joined(separator: ", "))]" }
            lines.append(line)
        }
        lines.append("")
        lines.append("Measured by LiDAR: typically within a few centimetres. Tape-check anything critical.")
        return lines.joined(separator: "\n")
    }
}
