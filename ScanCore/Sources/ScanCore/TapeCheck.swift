import Foundation

/// How far LiDAR was from the painter's tape on every dimension they've measured.
/// This is the real-world accuracy check: scan a room, tape a few walls, read this.
public struct TapeCheck: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var name: String        // "Wall B width"
        public var lidarM: Double
        public var tapeM: Double
        /// LiDAR minus tape. Negative means the scan came up short.
        public var errorM: Double { lidarM - tapeM }
    }

    public var samples: [Sample]

    public var meanAbsErrorM: Double { samples.map { abs($0.errorM) }.reduce(0, +) / Double(samples.count) }
    /// Average signed error. Consistently negative or positive means a bias, not noise.
    public var meanErrorM: Double { samples.map(\.errorM).reduce(0, +) / Double(samples.count) }
    public var worst: Sample { samples.max { abs($0.errorM) < abs($1.errorM) }! }
}

extension Room {
    /// nil until at least one dimension has been tape-measured.
    public var tapeCheck: TapeCheck? {
        // Compare against the app's best LiDAR figure (after corner and height refinement),
        // which is what the painter saw before typing in the tape value.
        let measured = measure()
        var samples: [TapeCheck.Sample] = []
        for o in overrides {
            guard let s = measured.surface(o.surfaceId) else { continue }
            if let w = o.widthM { samples.append(.init(name: "\(s.label) width", lidarM: s.scannedWidthM, tapeM: w)) }
            if let h = o.heightM { samples.append(.init(name: "\(s.label) height", lidarM: s.scannedHeightM, tapeM: h)) }
        }
        return samples.isEmpty ? nil : TapeCheck(samples: samples)
    }
}

extension Units {
    /// Signed centimetres, e.g. "-1.2 cm".
    public static func centimetres(_ m: Double) -> String { String(format: "%+.1f cm", m * 100) }
}
