import RoomPlan
import ScanCore
import SwiftUI

/// Tips → live scan → processing. Hands the saved room back when done.
struct ScanFlowView: View {
    let onFinish: (Room) -> Void

    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var scan = ScanSession()

    var body: some View {
        Group {
            switch scan.phase {
            case .tips:
                ScanTipsView(roomName: $scan.roomName, onStart: { scan.start() }, onCancel: { dismiss() })
            case .scanning, .processing:
                ScanView(scan: scan, onCancel: {
                    scan.cancel()
                    dismiss()
                })
            case .failed(let message):
                ScanFailedView(message: message, onRetry: { scan.start() }, onClose: { dismiss() })
            }
        }
        .onAppear {
            scan.onCaptured = { captured in
                do {
                    let room = try store.add(captured: captured, name: scan.roomName)
                    onFinish(room)
                } catch {
                    scan.fail("Couldn't save the scan: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct ScanTipsView: View {
    @Binding var roomName: String
    let onStart: () -> Void
    let onCancel: () -> Void

    private struct Tip: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let tips = [
        Tip(symbol: "lightbulb.max.fill", title: "Lights on, curtains open", detail: "LiDAR and the camera both need light to measure accurately."),
        Tip(symbol: "figure.stand", title: "Start in a corner", detail: "Hold the iPad upright at chest height, screen facing you."),
        Tip(symbol: "figure.walk", title: "Walk the walls slowly", detail: "Go all the way round. Each wall draws in as it's measured."),
        Tip(symbol: "arrow.up.and.down", title: "Tilt up and down on every wall", detail: "Catch the ceiling line and the skirting so heights are exact."),
        Tip(symbol: "door.left.hand.open", title: "Point at every door and window", detail: "They're subtracted from the paint area, so each needs to be seen."),
        Tip(symbol: "sofa.fill", title: "Clutter can fool it", detail: "Wardrobes, drum kits and shelving against a wall sometimes read as windows. You can fix or remove any detection afterwards."),
        Tip(symbol: "map.fill", title: "Watch the map", detail: "Red dots are gaps. Finish back where you started, with no red dots."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room name").font(.headline)
                        TextField("e.g. Lounge (optional)", text: $roomName)
                            .font(.title3)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(tips) { tip in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: tip.symbol)
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                    .frame(width: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tip.title).font(.title3.weight(.semibold))
                                    Text(tip.detail).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Text("Mirrors and large glass can confuse the scanner. You can correct any wall with a tape measurement afterwards.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(action: onStart) {
                        Label("Start scanning", systemImage: "viewfinder")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Before you scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

struct ScanFailedView: View {
    let message: String
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("The scan stopped").font(.title.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                Button("Scan again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: 520)
    }
}
