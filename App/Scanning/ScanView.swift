import ScanCore
import SwiftUI

/// Full-screen RoomPlan view with the guidance HUD floating on top.
struct ScanView: View {
    let scan: ScanSession
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var confirmFinish = false

    private var coverage: CoverageReport { scan.coverage }

    var body: some View {
        ZStack {
            RoomCaptureContainer(scan: scan)
                .ignoresSafeArea()

            // Darken the edges so the HUD reads over a bright room.
            LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if scan.phase == .scanning {
                hud
                    .transition(.opacity)
            } else {
                ProcessingOverlay()
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: scan.phase)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(.impact(weight: .light), trigger: coverage.wallCount)
        .sensoryFeedback(.success, trigger: coverage.isReadyToFinish) { _, ready in ready }
        .alert("Finish the scan?", isPresented: $confirmFinish) {
            Button("Keep scanning", role: .cancel) {}
            Button("Finish anyway") { scan.finish() }
        } message: {
            Text(coverage.outstandingIssues.joined(separator: "\n\n"))
        }
    }

    private var hud: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .glassPanel(cornerRadius: 28)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Cancel scan")

                GuidanceBanner(instruction: scan.instruction, guidance: coverage.next)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)

                Color.clear.frame(width: 56, height: 56)
            }

            Spacer()

            if sizeClass == .regular {
                HStack(alignment: .bottom, spacing: 16) {
                    ScanChecklist(coverage: coverage, scan: scan)
                        .frame(width: 300)
                    Spacer()
                    doneButton.frame(width: 280)
                    Spacer()
                    miniMap.frame(width: 340, height: 280)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ScanChecklist(coverage: coverage, scan: scan)
                    miniMap.frame(width: 170, height: 190)
                }
                doneButton
            }
        }
        .padding(20)
    }

    private var miniMap: some View {
        FloorPlanView(plan: coverage.plan, pose: scan.pose, showDimensions: sizeClass == .regular)
            .padding(6)
            .glassPanel()
    }

    private var doneButton: some View {
        Button {
            if coverage.isReadyToFinish {
                scan.finish()
            } else {
                confirmFinish = true
            }
        } label: {
            Label(coverage.isReadyToFinish ? "Done" : "Finish", systemImage: coverage.isReadyToFinish ? "checkmark.circle.fill" : "checkmark")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GradientButtonStyle(gradient: coverage.isReadyToFinish ? Theme.doneGradient : Theme.gradient))
        .disabled(coverage.wallCount == 0)
        .animation(.smooth, value: coverage.isReadyToFinish)
    }
}

/// The one thing to do right now. RoomPlan's own coaching wins over coverage hints.
struct GuidanceBanner: View {
    let instruction: ScanInstruction
    let guidance: ScanGuidance

    var body: some View {
        let coaching = instruction != .normal
        let title = coaching ? instruction.title : guidance.title
        let detail = coaching ? instruction.detail : guidance.detail
        let symbol = coaching ? instruction.symbol : guidance.symbol
        let tint: Color = coaching ? Theme.warn : guidance.tint

        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassPanel(cornerRadius: 28, tint: tint)
        .animation(.smooth, value: title)
    }
}

extension ScanGuidance {
    var symbol: String {
        switch self {
        case .findFirstWall: return "viewfinder"
        case .keepGoing: return "figure.walk"
        case .closeGap: return "smallcircle.filled.circle"
        case .ceilingLine: return "arrow.up.to.line"
        case .rescan: return "arrow.clockwise"
        case .complete: return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .complete: return Theme.good
        case .closeGap: return Theme.bad
        case .ceilingLine, .rescan: return Theme.warn
        case .findFirstWall, .keepGoing: return Theme.accent
        }
    }
}

struct ScanChecklist: View {
    let coverage: CoverageReport
    let scan: ScanSession

    private var checks: [Bool] {
        [coverage.wallCount >= 3, coverage.isClosed,
         coverage.wallCount >= 3 && coverage.shortWalls.isEmpty,
         coverage.doorCount + coverage.openingCount > 0]
    }

    var body: some View {
        let done = checks.filter { $0 }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressRing(progress: Double(done) / Double(checks.count))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Coverage").font(.caption.weight(.bold)).textCase(.uppercase).tracking(1).foregroundStyle(.white.opacity(0.6))
                    Text("\(done) of \(checks.count)").font(.number(18)).foregroundStyle(.white)
                }
            }
            row("Walls", "\(coverage.wallCount)", done: checks[0])
            row("Corners joined",
                coverage.wallCount < 3 ? "—" : coverage.openEndCount == 0 ? "All" : "\(coverage.openEndCount) loose",
                done: checks[1])
            row("Wall heights",
                coverage.wallCount < 3 ? "—" : coverage.shortWalls.isEmpty ? "Even" : "\(coverage.shortWalls.joined(separator: ", ")) short",
                done: checks[2])
            row("Doors", "\(coverage.doorCount)", done: checks[3])
            row("Windows", "\(coverage.windowCount)", done: nil)
            if scan.spottedCount > 0 {
                row("Spotted by camera", "\(scan.spottedCount)", done: nil)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(16)
        .glassPanel()
        .animation(.smooth, value: done)
    }

    private func row(_ title: String, _ value: String, done: Bool?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done == true ? "checkmark.circle.fill" : done == false ? "circle.dashed" : "circle.fill")
                .foregroundStyle(done == true ? Theme.good : Color.white.opacity(0.4))
                .imageScale(done == nil ? .small : .medium)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(progress >= 1 ? Theme.doneGradient : Theme.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: progress)
    }
}

struct ProcessingOverlay: View {
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                .onAppear { spin = true }
            Text("Building your room")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Squaring up walls and measuring every surface.")
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(36)
        .glassPanel(cornerRadius: 32)
    }
}
