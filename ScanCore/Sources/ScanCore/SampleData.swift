import Foundation

extension ScanGeometry {
    /// A 4.2 × 3.6 m lounge, 2.44 m ceiling, one door and two windows. For building
    /// screens in the Simulator or on devices without LiDAR.
    public static var sampleLounge: ScanGeometry {
        let h = 2.44, w = 4.2, d = 3.6
        func wall(_ center: Vec3, along x: Vec3, length: Double) -> ScannedSurface {
            let up = Vec3(0, 1, 0)
            return ScannedSurface(
                kind: .wall, dimensions: Vec3(length, h, 0), center: center,
                xAxis: x, yAxis: up, normal: x.cross(up)
            )
        }
        let north = wall(Vec3(0, h / 2, -d / 2), along: Vec3(1, 0, 0), length: w)
        let east = wall(Vec3(w / 2, h / 2, 0), along: Vec3(0, 0, 1), length: d)
        let south = wall(Vec3(0, h / 2, d / 2), along: Vec3(-1, 0, 0), length: w)
        let west = wall(Vec3(-w / 2, h / 2, 0), along: Vec3(0, 0, -1), length: d)

        func opening(_ kind: SurfaceKind, on wall: ScannedSurface, u: Double, bottom: Double, size: (Double, Double)) -> ScannedSurface {
            let x = wall.xAxis.normalized
            let center = Vec3(wall.center.x, bottom + size.1 / 2, wall.center.z) + x * u
            return ScannedSurface(
                kind: kind, dimensions: Vec3(size.0, size.1, 0), center: center,
                xAxis: wall.xAxis, yAxis: wall.yAxis, normal: wall.normal, parentId: wall.id
            )
        }

        return ScanGeometry(
            walls: [north, east, south, west],
            doors: [opening(.door, on: south, u: 1.2, bottom: 0, size: (0.82, 2.04))],
            windows: [
                opening(.window, on: north, u: -0.6, bottom: 0.9, size: (1.5, 1.2)),
                opening(.window, on: east, u: 0, bottom: 0.9, size: (1.2, 1.2)),
            ],
            floors: [ScannedSurface(
                kind: .floor, dimensions: Vec3(w, d, 0), center: .zero,
                xAxis: Vec3(1, 0, 0), yAxis: Vec3(0, 0, 1), normal: Vec3(0, -1, 0),
                polygon: [Vec3(-w / 2, -d / 2, 0), Vec3(w / 2, -d / 2, 0), Vec3(w / 2, d / 2, 0), Vec3(-w / 2, d / 2, 0)]
            )],
            roomType: "livingRoom"
        )
    }
}

extension Room {
    public static var sample: Room {
        Room(name: "Demo lounge", geometry: .sampleLounge)
    }
}
