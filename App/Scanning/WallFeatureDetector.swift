import ARKit
import CoreImage
import ScanCore
import UIKit
import Vision

/// Watches the camera while the room is scanned for flat rectangles on the walls:
/// windows RoomPlan missed, pinboards, mirrors. Each sighting is placed on the
/// LiDAR-measured wall for its real size; the clearest view of each is photographed and
/// run through Apple's on-device image classifier.
final class WallFeatureDetector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "WallFeatureDetector", qos: .utility)
    private let lock = NSLock()
    private var tracker = WallFeatureTracker()
    private var busy = false
    private let context = CIContext()

    var confirmed: [WallFeatureCandidate] {
        lock.lock()
        defer { lock.unlock() }
        return tracker.confirmed
    }

    func reset() {
        lock.lock()
        tracker = WallFeatureTracker()
        lock.unlock()
    }

    /// Looks at one camera frame, unless the previous one is still being processed.
    func submit(_ frame: ARFrame, walls: [ScannedSurface]) {
        guard !walls.isEmpty else { return }
        lock.lock()
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()
        queue.async { [self] in
            process(frame, walls: walls)
            lock.lock()
            busy = false
            lock.unlock()
        }
    }

    private func process(_ frame: ARFrame, walls: [ScannedSurface]) {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.15
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 20
        request.minimumSize = 0.12
        request.minimumConfidence = 0.6
        request.maximumObservations = 6
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .up)
        guard (try? handler.perform([request])) != nil, let quads = request.results else { return }

        for quad in quads {
            let corners = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
            // Cut off by the edge of the picture: its size would be wrong.
            guard corners.allSatisfy({ $0.x > 0.02 && $0.x < 0.98 && $0.y > 0.02 && $0.y < 0.98 }) else { continue }
            let mid = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
            guard let observation = WallFeatureGeometry.observe(
                corners: corners.map { ray(frame, $0) },
                center: ray(frame, mid),
                walls: walls,
                apparentSize: Double(quad.boundingBox.width * quad.boundingBox.height),
                contrast: contrast(frame.capturedImage, corners: corners)
            ) else { continue }

            lock.lock()
            let (id, isBestView) = tracker.add(observation)
            lock.unlock()

            if isBestView, let crop = straightenedCrop(frame, corners: corners) {
                let labels = classify(crop)
                let jpeg = jpegThumbnail(crop)
                lock.lock()
                if let jpeg { tracker.setThumbnail(jpeg, for: id) }
                tracker.addLabels(labels, for: id)
                lock.unlock()
            }
        }
    }

    /// A ray from the camera through a point given in Vision's normalised coordinates
    /// (origin bottom-left). ARKit's own query handles the lens maths.
    private func ray(_ frame: ARFrame, _ p: CGPoint) -> Ray {
        let q = frame.raycastQuery(from: CGPoint(x: p.x, y: 1 - p.y), allowing: .estimatedPlane, alignment: .any)
        return Ray(origin: Vec3(Double(q.origin.x), Double(q.origin.y), Double(q.origin.z)),
                   direction: Vec3(Double(q.direction.x), Double(q.direction.y), Double(q.direction.z)))
    }

    /// Mean brightness inside the quad divided by a ring just outside it, from the
    /// camera's luma plane.
    private func contrast(_ buffer: CVPixelBuffer, corners: [CGPoint]) -> Double? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        func sample(_ p: CGPoint) -> Double? {
            guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return nil }
            let x = min(width - 1, Int(p.x * CGFloat(width)))
            let y = min(height - 1, Int((1 - p.y) * CGFloat(height)))
            return Double(luma[y * rowBytes + x])
        }
        // Point at (s, t) across the quad: s along the top/bottom edges, t top to bottom.
        func at(_ s: CGFloat, _ t: CGFloat, _ q: [CGPoint]) -> CGPoint {
            let top = CGPoint(x: q[0].x + (q[1].x - q[0].x) * s, y: q[0].y + (q[1].y - q[0].y) * s)
            let bottom = CGPoint(x: q[3].x + (q[2].x - q[3].x) * s, y: q[3].y + (q[2].y - q[3].y) * s)
            return CGPoint(x: top.x + (bottom.x - top.x) * t, y: top.y + (bottom.y - top.y) * t)
        }
        let steps: [CGFloat] = [0.15, 0.3, 0.45, 0.6, 0.75, 0.85]
        let inside = steps.flatMap { s in steps.compactMap { t in sample(at(s, t, corners)) } }

        // The same quad grown by 30% around its centre; sample its outline.
        let c = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        let grown = corners.map { CGPoint(x: c.x + ($0.x - c.x) * 1.3, y: c.y + ($0.y - c.y) * 1.3) }
        let edge: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        let ring = edge.flatMap { s in [sample(at(s, 0, grown)), sample(at(s, 1, grown)), sample(at(0, s, grown)), sample(at(1, s, grown))] }
            .compactMap { $0 }

        guard inside.count >= 10, ring.count >= 8 else { return nil }
        let insideMean = inside.reduce(0, +) / Double(inside.count)
        let ringMean = ring.reduce(0, +) / Double(ring.count)
        return insideMean / max(ringMean, 1)
    }

    /// The quad, flattened to a straight-on view and turned so world-up is up.
    private func straightenedCrop(_ frame: ARFrame, corners: [CGPoint]) -> CIImage? {
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let size = image.extent.size
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: p.x * size.width, y: p.y * size.height) }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(vector(corners[0]), forKey: "inputTopLeft")
        filter.setValue(vector(corners[1]), forKey: "inputTopRight")
        filter.setValue(vector(corners[2]), forKey: "inputBottomRight")
        filter.setValue(vector(corners[3]), forKey: "inputBottomLeft")
        guard var output = filter.outputImage else { return nil }

        // Which way is up in the picture depends on how the iPad is held.
        let t = frame.camera.transform
        let upAlongX = Double(t.columns.0.y), upAlongY = Double(t.columns.1.y)
        let angle = atan2(upAlongX, upAlongY)
        let quarterTurns = (angle / (.pi / 2)).rounded() * (.pi / 2)
        output = output.transformed(by: CGAffineTransform(rotationAngle: CGFloat(quarterTurns)))
        output = output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
        return output
    }

    /// Apple's built-in image classifier, reduced to the labels that matter here.
    private func classify(_ crop: CIImage) -> [FeatureLabel: Double] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(ciImage: crop, options: [:])
        guard (try? handler.perform([request])) != nil, let results = request.results else { return [:] }
        var labels: [FeatureLabel: Double] = [:]
        for observation in results where observation.confidence >= 0.1 {
            guard let label = FeatureLabel.from(identifier: observation.identifier) else { continue }
            labels[label] = max(labels[label] ?? 0, Double(observation.confidence))
        }
        return labels
    }

    private func jpegThumbnail(_ crop: CIImage) -> Data? {
        let scale = min(1, 360 / max(crop.extent.width, crop.extent.height, 1))
        let small = crop.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(small, from: small.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }
}
