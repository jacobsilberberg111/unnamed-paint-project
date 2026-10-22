import Foundation
import RoomPlan
import ScanCore
import simd

// Copies RoomPlan's results into ScanCore's plain types. This is the only place
// that knows RoomPlan's data layout.

extension ScanGeometry {
    init(_ room: CapturedRoom) {
        self.init(
            walls: room.walls.map { ScannedSurface($0, kind: .wall) },
            doors: room.doors.map { ScannedSurface($0, kind: .door) },
            windows: room.windows.map { ScannedSurface($0, kind: .window) },
            openings: room.openings.map { ScannedSurface($0, kind: .opening) },
            floors: room.floors.map { ScannedSurface($0, kind: .floor) },
            roomType: room.sections.first.map { String(describing: $0.label) }
        )
    }
}

extension ScannedSurface {
    init(_ s: CapturedRoom.Surface, kind: SurfaceKind) {
        let t = s.transform
        var isOpen: Bool?
        if case let .door(open) = s.category { isOpen = open }
        var curveLength: Double?
        if let curve = s.curve {
            let sweep = curve.endAngle.converted(to: .radians).value - curve.startAngle.converted(to: .radians).value
            curveLength = Double(curve.radius) * abs(sweep)
        }
        self.init(
            id: s.identifier,
            kind: kind,
            dimensions: vec3(s.dimensions),
            center: vec3(t.columns.3),
            xAxis: vec3(t.columns.0),
            yAxis: vec3(t.columns.1),
            normal: vec3(t.columns.2),
            polygon: s.polygonCorners.map { vec3($0) },
            curveLength: curveLength,
            parentId: s.parentIdentifier,
            confidence: ScanConfidence(s.confidence),
            completedEdges: Set(s.completedEdges.compactMap { SurfaceEdge($0) }),
            isOpen: isOpen
        )
    }
}

extension ScanConfidence {
    init(_ c: CapturedRoom.Confidence) {
        switch c {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        @unknown default: self = .medium
        }
    }
}

extension SurfaceEdge {
    init?(_ e: CapturedRoom.Surface.Edge) {
        switch e {
        case .top: self = .top
        case .bottom: self = .bottom
        case .left: self = .left
        case .right: self = .right
        @unknown default: return nil
        }
    }
}

extension Room {
    static let capturedRoomFileName = "capturedRoom.json"

    init(captured: CapturedRoom, name: String) {
        let geometry = ScanGeometry(captured)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            name: trimmed.isEmpty ? (geometry.roomTypeName ?? "Room") : trimmed,
            scanFile: Room.capturedRoomFileName,
            geometry: geometry
        )
    }
}

private func vec3(_ v: simd_float3) -> Vec3 { Vec3(Double(v.x), Double(v.y), Double(v.z)) }
private func vec3(_ v: simd_float4) -> Vec3 { Vec3(Double(v.x), Double(v.y), Double(v.z)) }
