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
            List {
                Section {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan a room", systemImage: "viewfinder")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canScan)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if !canScan {
                        Text("This device has no LiDAR scanner. You can still open saved scans or the demo room.")
                    }
                }

                Section("Rooms") {
                    if store.rooms.isEmpty {
                        Text("No rooms yet. Scan one, or load a saved scan file.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.rooms) { room in
                        NavigationLink(value: room.id) {
                            RoomRow(room: room)
                        }
                    }
                    .onDelete { offsets in
                        for room in offsets.map({ store.rooms[$0] }) { store.delete(room) }
                    }
                }
            }
            .navigationTitle("Scan to Quote")
            .navigationDestination(for: Room.ID.self) { id in
                if let room = store.room(id) {
                    RoomDetailView(room: room)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Load scan file…", systemImage: "folder") { isImporting = true }
                        Button("Add demo room", systemImage: "cube") { addDemoRoom() }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
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

private struct RoomRow: View {
    let room: Room

    var body: some View {
        let s = room.measure().summary
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name).font(.headline)
            Text("\(Units.squareMetres(s.wallPaintM2)) walls · \(s.ceilingM2.map(Units.squareMetres) ?? "no ceiling") ceiling")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(room.createdAt, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
