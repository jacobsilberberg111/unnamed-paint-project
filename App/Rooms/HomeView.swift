import RoomPlan
import ScanCore
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(RoomStore.self) private var store
    @State private var path: [Room.ID] = []
    @State private var isScanning = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private let canScan = RoomCaptureSession.isSupported

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    scanCard
                    roomsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(BackdropView())
            .navigationDestination(for: Room.ID.self) { id in
                if let room = store.room(id) {
                    RoomDetailView(room: room)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Load scan file…", systemImage: "folder") { isImporting = true }
                        Button("Add demo room", systemImage: "cube.transparent") { addDemoRoom() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    let room = try store.importFile(at: result.get())
                    path.append(room.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                ScanFlowView { room in
                    isScanning = false
                    path.append(room.id)
                }
            }
            .alert("Couldn't open that", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scan to Quote")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Walk the room. Every wall, door and window, measured.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var scanCard: some View {
        Button {
            isScanning = true
        } label: {
            HStack(spacing: 20) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                    .frame(width: 72, height: 72)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan a room")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(canScan ? "LiDAR maps it as you walk" : "This device has no LiDAR scanner")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.title2.weight(.bold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .foregroundStyle(.white)
            .padding(22)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Theme.accent2.opacity(0.35), radius: 30, y: 14)
        }
        .buttonStyle(PressableStyle())
        .disabled(!canScan)
        .opacity(canScan ? 1 : 0.45)
    }

    @ViewBuilder
    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your rooms").sectionTitle()
            if store.rooms.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No rooms yet")
                        .font(.headline)
                    Text(canScan ? "Scan one to see it here." : "Open ⋯ to load a scan file or the demo room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .card()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(store.rooms) { room in
                        NavigationLink(value: room.id) {
                            RoomCard(room: room)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(room) }
                        }
                    }
                }
            }
        }
    }

    private func addDemoRoom() {
        do {
            let room = Room.sample
            try store.save(room)
            path.append(room.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RoomCard: View {
    let room: Room

    var body: some View {
        let m = room.measure()
        VStack(alignment: .leading, spacing: 14) {
            FloorPlanView(plan: m.plan, showDimensions: false, compact: true)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(room.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.1f", m.summary.wallPaintM2))
                        .font(.number(26))
                        .foregroundStyle(Theme.gradient)
                    Text("m² walls")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

/// Subtle shrink on press, for cards that act as buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
