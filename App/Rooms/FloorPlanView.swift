import ScanCore
import SwiftUI

/// Top-down drawing of the room: walls, doors, windows, furniture, gaps and (while
/// scanning) where the painter is standing.
struct FloorPlanView: View {
    let plan: FloorPlan
    var pose: DevicePose? = nil
    var showDimensions = true
    var highlighted: UUID? = nil
    /// Thin lines and no labels, for small previews.
    var compact = false

    private var animated: Bool { pose != nil || !plan.openEnds.isEmpty }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            Canvas { context, size in
                draw(in: &context, size: size, pulse: pulse)
            }
        }
        .accessibilityLabel("Floor plan")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, pulse: Double) {
        var points = plan.allPoints
        if let pose { points.append(pose.position) }
        let padding: CGFloat = compact ? 12 : showDimensions ? 44 : 20
        guard let fit = PlanFit(points: points, size: size, padding: padding) else {
            context.draw(
                Text(compact ? "No walls" : "Walls appear here as you scan")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
        }
        let lineScale: CGFloat = compact ? 0.6 : 1

        // Floor
        if plan.floorOutline.count >= 3 {
            var floor = Path()
            floor.addLines(plan.floorOutline.map(fit.point))
            floor.closeSubpath()
            let box = floor.boundingRect
            context.fill(floor, with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.22), Theme.accent2.opacity(0.10)]),
                startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)
            ))
        }

        // Furniture: painted pieces in the accent colour, the rest faint
        for object in plan.objects where object.corners.count >= 3 {
            var footprint = Path()
            footprint.addLines(object.corners.map(fit.point))
            footprint.closeSubpath()
            if object.isPainted {
                context.fill(footprint, with: .color(Theme.accent.opacity(0.35)))
                context.stroke(footprint, with: .color(Theme.accent), lineWidth: 1.5)
            } else {
                context.fill(footprint, with: .color(.white.opacity(0.07)))
                context.stroke(footprint, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }

        // Walls, with a soft glow underneath
        for wall in plan.walls {
            let isHighlighted = wall.id == highlighted
            let color: Color = isHighlighted ? Theme.accent : wall.needsAttention ? Theme.warn : .white
            let path = segmentPath(wall, fit)
            context.stroke(path, with: .color(color.opacity(0.25)),
                           style: StrokeStyle(lineWidth: (isHighlighted ? 16 : 11) * lineScale, lineCap: .round))
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: (isHighlighted ? 6 : 4) * lineScale, lineCap: .round))
        }

        // Doors and windows
        for opening in plan.openings {
            var color: Color
            switch opening.kind {
            case .door: color = Theme.door
            case .window: color = Theme.window
            default: color = .gray
            }
            if opening.needsAttention { color = Theme.warn }
            context.stroke(segmentPath(opening, fit), with: .color(color),
                           style: StrokeStyle(lineWidth: 7 * lineScale, lineCap: .butt))
        }

        // Labels
        if showDimensions && !compact {
            let centre = plan.walls.isEmpty ? Vec2.zero
                : plan.walls.map(\.midpoint).reduce(Vec2.zero, +) / Double(plan.walls.count)
            for wall in plan.walls {
                let mid = fit.point(wall.midpoint)
                let inward = fit.point(centre)
                let dx = inward.x - mid.x, dy = inward.y - mid.y
                let len = max(1, (dx * dx + dy * dy).squareRoot())
                let at = CGPoint(x: mid.x + dx / len * 26, y: mid.y + dy / len * 26)
                chip("\(wall.shortLabel)  \(Units.metres(wall.lengthM))",
                     color: wall.needsAttention ? Theme.warn : .white, at: at, in: &context)
            }
        }

        // Gaps: pulsing red dots
        for end in plan.openEnds {
            let p = fit.point(end)
            let r = 8 + 6 * pulse
            context.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.8, y: p.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                         with: .color(Theme.bad.opacity(0.18 * (1 - pulse))))
            let dot = Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
            context.fill(dot, with: .color(Theme.bad))
            context.stroke(dot, with: .color(.white), lineWidth: 2)
        }

        if let pose {
            drawPose(pose, fit: fit, pulse: pulse, in: &context)
        }
    }

    private func chip(_ text: String, color: Color, at point: CGPoint, in context: inout GraphicsContext) {
        let resolved = context.resolve(Text(text).font(.caption2.weight(.bold)).foregroundStyle(color))
        let size = resolved.measure(in: CGSize(width: 240, height: 40))
        let rect = CGRect(x: point.x - size.width / 2 - 8, y: point.y - size.height / 2 - 4,
                          width: size.width + 16, height: size.height + 8)
        let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        context.fill(shape, with: .color(Theme.background.opacity(0.85)))
        context.stroke(shape, with: .color(.white.opacity(0.12)), lineWidth: 1)
        context.draw(resolved, at: point)
    }

    private func segmentPath(_ segment: PlanSegment, _ fit: PlanFit) -> Path {
        var path = Path()
        path.move(to: fit.point(segment.start))
        path.addLine(to: fit.point(segment.end))
        return path
    }

    private func drawPose(_ pose: DevicePose, fit: PlanFit, pulse: Double, in context: inout GraphicsContext) {
        let p = fit.point(pose.position)
        let f = pose.forward.normalized
        guard f.length > 0.5 else { return }
        let fx = CGFloat(f.x), fy = CGFloat(f.y)
        let rx = -fy, ry = fx

        // Field-of-view wedge
        var cone = Path()
        cone.move(to: p)
        cone.addLine(to: CGPoint(x: p.x + fx * 60 + rx * 34, y: p.y + fy * 60 + ry * 34))
        cone.addLine(to: CGPoint(x: p.x + fx * 60 - rx * 34, y: p.y + fy * 60 - ry * 34))
        cone.closeSubpath()
        context.fill(cone, with: .linearGradient(
            Gradient(colors: [Theme.accent.opacity(0.45), Theme.accent.opacity(0)]),
            startPoint: p, endPoint: CGPoint(x: p.x + fx * 60, y: p.y + fy * 60)
        ))

        let r = 16 + 4 * pulse
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Theme.accent.opacity(0.18)))
        let dot = Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
        context.fill(dot, with: .color(Theme.accent))
        context.stroke(dot, with: .color(.white), lineWidth: 2.5)
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
