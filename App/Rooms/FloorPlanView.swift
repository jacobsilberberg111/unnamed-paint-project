import ScanCore
import SwiftUI

/// Top-down drawing of the room: walls, doors, windows, gaps and (while scanning)
/// where the painter is standing.
struct FloorPlanView: View {
    let plan: FloorPlan
    var pose: DevicePose? = nil
    var showDimensions = true
    var highlighted: UUID? = nil

    var body: some View {
        Canvas { context, size in
            var points = plan.allPoints
            if let pose { points.append(pose.position) }
            guard let fit = PlanFit(points: points, size: size, padding: showDimensions ? 40 : 18) else {
                context.draw(
                    Text("Walls appear here as you scan").font(.footnote).foregroundStyle(.secondary),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
                return
            }

            if plan.floorOutline.count >= 3 {
                var floor = Path()
                floor.addLines(plan.floorOutline.map(fit.point))
                floor.closeSubpath()
                context.fill(floor, with: .color(.accentColor.opacity(0.10)))
            }

            for corners in plan.objects where corners.count >= 3 {
                var footprint = Path()
                footprint.addLines(corners.map(fit.point))
                footprint.closeSubpath()
                context.fill(footprint, with: .color(.secondary.opacity(0.18)))
                context.stroke(footprint, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            }

            for wall in plan.walls {
                let isHighlighted = wall.id == highlighted
                let color: Color = isHighlighted ? .accentColor : wall.needsAttention ? .orange : .primary
                context.stroke(
                    segmentPath(wall, fit),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: isHighlighted ? 7 : 4, lineCap: .round)
                )
            }

            for opening in plan.openings {
                var color: Color
                switch opening.kind {
                case .door: color = .brown
                case .window: color = .cyan
                default: color = .gray
                }
                if opening.needsAttention { color = .orange }
                context.stroke(
                    segmentPath(opening, fit),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 8, lineCap: .butt)
                )
            }

            if showDimensions {
                let centre = plan.walls.isEmpty ? Vec2.zero
                    : plan.walls.map(\.midpoint).reduce(Vec2.zero, +) / Double(plan.walls.count)
                for wall in plan.walls {
                    let mid = fit.point(wall.midpoint)
                    let inward = fit.point(centre)
                    let dx = inward.x - mid.x, dy = inward.y - mid.y
                    let len = max(1, (dx * dx + dy * dy).squareRoot())
                    let at = CGPoint(x: mid.x + dx / len * 24, y: mid.y + dy / len * 24)
                    context.draw(
                        Text("\(wall.shortLabel)  \(Units.metres(wall.lengthM))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(wall.needsAttention ? Color.orange : Color.primary),
                        at: at
                    )
                }
            }

            for end in plan.openEnds {
                let p = fit.point(end)
                let dot = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
                context.fill(dot, with: .color(.red))
                context.stroke(dot, with: .color(.white), lineWidth: 2)
            }

            if let pose {
                drawPose(pose, fit: fit, in: &context)
            }
        }
        .accessibilityLabel("Floor plan")
    }

    private func segmentPath(_ segment: PlanSegment, _ fit: PlanFit) -> Path {
        var path = Path()
        path.move(to: fit.point(segment.start))
        path.addLine(to: fit.point(segment.end))
        return path
    }

    private func drawPose(_ pose: DevicePose, fit: PlanFit, in context: inout GraphicsContext) {
        let p = fit.point(pose.position)
        let f = pose.forward.normalized
        guard f.length > 0.5 else { return }
        let fx = CGFloat(f.x), fy = CGFloat(f.y)
        let rx = -fy, ry = fx
        var arrow = Path()
        arrow.move(to: CGPoint(x: p.x + fx * 16, y: p.y + fy * 16))
        arrow.addLine(to: CGPoint(x: p.x - fx * 9 + rx * 10, y: p.y - fy * 9 + ry * 10))
        arrow.addLine(to: CGPoint(x: p.x - fx * 4, y: p.y - fy * 4))
        arrow.addLine(to: CGPoint(x: p.x - fx * 9 - rx * 10, y: p.y - fy * 9 - ry * 10))
        arrow.closeSubpath()
        let halo = Path(ellipseIn: CGRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40))
        context.fill(halo, with: .color(.blue.opacity(0.18)))
        context.fill(arrow, with: .color(.blue))
        context.stroke(arrow, with: .color(.white), lineWidth: 1.5)
    }
}

/// Scales plan metres into the view, keeping the aspect ratio and centring it.
struct PlanFit {
    private let minX: Double
    private let minY: Double
    private let scale: Double
    private let offsetX: Double
    private let offsetY: Double

    init?(points: [Vec2], size: CGSize, padding: CGFloat) {
        let width = Double(size.width - 2 * padding), height = Double(size.height - 2 * padding)
        guard !points.isEmpty, width > 10, height > 10 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let spanX = max(maxX - minX, 1), spanY = max(maxY - minY, 1)
        let scale = min(width / spanX, height / spanY)
        self.minX = minX - (spanX - (maxX - minX)) / 2
        self.minY = minY - (spanY - (maxY - minY)) / 2
        self.scale = scale
        offsetX = Double(padding) + (width - spanX * scale) / 2
        offsetY = Double(padding) + (height - spanY * scale) / 2
    }

    func point(_ p: Vec2) -> CGPoint {
        CGPoint(x: offsetX + (p.x - minX) * scale, y: offsetY + (p.y - minY) * scale)
    }
}
