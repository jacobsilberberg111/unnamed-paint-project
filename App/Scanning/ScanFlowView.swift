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
            case .review:
                WallFeatureReviewView(items: scan.unsure, autoAdded: scan.autoAdded) { choices in
                    guard var room = scan.pendingRoom else { return }
                    for item in scan.unsure {
                        if let kind = choices[item.id] ?? item.verdict.kind { room.add(item.surface(as: kind)) }
                    }
                    scan.pendingRoom = room
                    save()
                }
            case .failed(let message):
                ScanFailedView(message: message, onRetry: { scan.start() }, onClose: { dismiss() })
            }
        }
        .onAppear {
            scan.onCaptured = { captured in
                // Add what the camera is sure of; only stop to ask if something's unclear.
                scan.review(Room(captured: captured, name: scan.roomName), captured: captured)
                if scan.unsure.isEmpty { save() }
            }
        }
    }

    private func save() {
        guard let room = scan.pendingRoom, let captured = scan.pendingCapture else { return }
        do {
            onFinish(try store.add(room, captured: captured))
        } catch {
            scan.fail("Couldn't save the scan: \(error.localizedDescription)")
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
        Tip(symbol: "door.left.hand.open", title: "Walk up to every door and window", detail: "Get within about 2 m so each fits on screen. The camera double-checks them, even dark windows at night, and spots pinboards and mirrors too."),
        Tip(symbol: "sofa.fill", title: "Clutter can fool it", detail: "Wardrobes, drum kits and shelving against a wall sometimes read as windows. You can fix or remove any detection afterwards."),
        Tip(symbol: "map.fill", title: "Watch the map", detail: "Red dots are gaps. Finish back where you started, with no red dots."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before you scan")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                        Text("Two minutes of walking gets every measurement.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Room name").sectionTitle()
                        TextField("", text: $roomName, prompt: Text("e.g. Lounge (optional)").foregroundStyle(.white.opacity(0.35)))
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 18)
                            .frame(height: 56)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
                            .submitLabel(.done)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: tip.symbol)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Text("\(index + 1)")
                                        .font(.number(11, weight: .heavy))
                                        .foregroundStyle(Theme.background)
                                        .frame(width: 18, height: 18)
                                        .background(.white, in: Circle())
                                        .offset(x: 6, y: -6)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tip.title).font(.headline)
                                    Text(tip.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .card(padding: 16, cornerRadius: 20)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 100)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(BackdropView())
            .safeAreaInset(edge: .bottom) {
                Button(action: onStart) {
                    Label("Start scanning", systemImage: "viewfinder")
                }
                .buttonStyle(GradientButtonStyle())
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
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
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Theme.warn.gradient, in: Circle())
            Text("The scan stopped")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Scan again", action: onRetry)
                .buttonStyle(GradientButtonStyle())
                .padding(.top, 8)
            Button("Close", action: onClose)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackdropView())
    }
}
