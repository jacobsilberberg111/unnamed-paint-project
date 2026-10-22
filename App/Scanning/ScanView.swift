import ScanCore
import SwiftUI

/// Full-screen RoomPlan view with the guidance HUD on top.
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

            if scan.phase == .scanning {
                hud
            } else {
                ProcessingOverlay()
            }
        }
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
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .accessibilityLabel("Cancel scan")

                GuidanceBanner(instruction: scan.instruction, guidance: coverage.next)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)

                Color.clear.frame(width: 56, height: 56)
            }

            Spacer()

            if sizeClass == .regular {
                HStack(alignment: .bottom, spacing: 16) {
                    ScanChecklist(coverage: coverage)
                        .frame(width: 300)
                    Spacer()
                    doneButton.frame(width: 260)
                    Spacer()
                    miniMap.frame(width: 320, height: 260)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ScanChecklist(coverage: coverage)
                    miniMap.frame(width: 170, height: 170)
                }
                doneButton
            }
        }
        .padding()
    }

    private var miniMap: some View {
        FloorPlanView(plan: coverage.plan, pose: scan.pose, showDimensions: sizeClass == .regular)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var doneButton: some View {
        Button {
            if coverage.isReadyToFinish {
                scan.finish()
            } else {
                confirmFinish = true
            }
        } label: {
            Label("Done", systemImage: coverage.isReadyToFinish ? "checkmark.circle.fill" : "checkmark")
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(coverage.isReadyToFinish ? Color.green : Color.accentColor)
        .disabled(coverage.wallCount == 0)
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
        let tint: Color = coaching ? .orange : guidance.tint

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.bold))
                Text(detail).font(.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.6), lineWidth: 2))
        .animation(.easeInOut(duration: 0.2), value: title)
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
        case .floorLine: return "arrow.down.to.line"
        case .complete: return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .complete: return .green
        case .closeGap: return .red
        case .ceilingLine, .floorLine, .rescan: return .orange
        case .findFirstWall, .keepGoing: return .accentColor
        }
    }
}

struct ScanChecklist: View {
    let coverage: CoverageReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Walls", "\(coverage.wallCount)", done: coverage.wallCount >= 3)
            row("Corners joined",
                coverage.wallCount < 3 ? "—" : coverage.openEndCount == 0 ? "All" : "\(coverage.openEndCount) loose",
                done: coverage.isClosed)
            if coverage.edgeInfoAvailable {
                row("Ceiling line",
                    coverage.wallsMissingCeilingLine.isEmpty ? "All walls" : "Missing \(coverage.wallsMissingCeilingLine.joined(separator: ", "))",
                    done: coverage.wallCount > 0 && coverage.wallsMissingCeilingLine.isEmpty)
            }
            row("Doors", "\(coverage.doorCount)", done: coverage.doorCount + coverage.openingCount > 0)
            row("Windows", "\(coverage.windowCount)", done: nil)
        }
        .font(.headline)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ title: String, _ value: String, done: Bool?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done == true ? "checkmark.circle.fill" : done == false ? "circle.dashed" : "circle.fill")
                .foregroundStyle(done == true ? Color.green : Color.secondary)
                .imageScale(done == nil ? .small : .medium)
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ProcessingOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Building your room…").font(.title2.weight(.semibold))
            Text("Squaring up walls and measuring every surface.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}
