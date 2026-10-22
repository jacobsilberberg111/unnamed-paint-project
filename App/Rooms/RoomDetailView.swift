import ScanCore
import SwiftUI

/// All measurements for one scanned room. Tap any wall, door or window to correct it
/// with a tape measurement.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    @State private var room: Room
    @State private var editing: Surface?
    @State private var saveError: String?

    init(room: Room) {
        _room = State(initialValue: room)
    }

    var body: some View {
        let m = room.measure()
        List {
            Section {
                TextField("Room name", text: $room.name)
                    .font(.title2.bold())
                OutlineStatus(summary: m.summary)
            }

            Section("Summary") {
                SummaryGrid(summary: m.summary)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section("Floor plan") {
                FloorPlanView(plan: m.plan)
                    .frame(height: 340)
            }

            if let check = room.tapeCheck {
                Section {
                    TapeCheckView(check: check)
                } header: {
                    Text("Tape check")
                } footer: {
                    Text("LiDAR minus tape, for every dimension you've corrected.")
                }
            }

            Section {
                ForEach(m.walls) { wall in
                    Button { editing = wall } label: {
                        WallRow(wall: wall, openings: m.openings(onWall: wall.id))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Walls")
            } footer: {
                Text("Tap a wall to enter a tape measurement.")
            }

            if !m.openingSurfaces.isEmpty {
                Section("Doors, windows and openings") {
                    ForEach(m.openingSurfaces) { opening in
                        Button { editing = opening } label: {
                            OpeningRow(opening: opening, wallLabel: opening.wallId.flatMap { m.surface($0)?.label })
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Text("LiDAR measurements are typically within a few centimetres, not tape-exact. Ceiling area assumes a flat ceiling the same shape as the floor. Tape-check anything that matters for the price.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: m.textReport(roomName: room.name, dateText: room.createdAt.formatted(date: .abbreviated, time: .omitted))) {
                        Label("Share measurements", systemImage: "doc.plaintext")
                    }
                    ShareLink(item: store.roomFileURL(for: room)) {
                        Label("Share room file", systemImage: "doc")
                    }
                    if let scanURL = store.scanFileURL(for: room) {
                        ShareLink(item: scanURL) {
                            Label("Share RoomPlan scan", systemImage: "cube.transparent")
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $editing) { surface in
            SurfaceEditSheet(surface: surface) { override in
                room.setOverride(override, for: surface.id)
            }
        }
        .onChange(of: room) { _, updated in
            do {
                try store.save(updated)
            } catch {
                saveError = error.localizedDescription
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }
}

private struct OutlineStatus: View {
    let summary: RoomSummary

    var body: some View {
        if summary.isClosed {
            Label("Walls close into a complete outline", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            Label("Outline has \(summary.gapCount) loose wall end\(summary.gapCount == 1 ? "" : "s"): some areas may be missing", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct SummaryGrid: View {
    let summary: RoomSummary

    var body: some View {
        let s = summary
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
            Tile(title: "Wall paint area", value: Units.squareMetres(s.wallPaintM2),
                 detail: "\(Units.squareMetres(s.wallGrossM2)) less \(Units.squareMetres(s.openingsM2)) openings", prominent: true)
            Tile(title: "Ceiling", value: s.ceilingM2.map(Units.squareMetres) ?? "—", detail: s.floorSource.description, prominent: true)
            Tile(title: "Floor", value: s.floorM2.map(Units.squareMetres) ?? "—")
            Tile(title: "Ceiling height", value: Units.metres(s.ceilingHeightM),
                 detail: s.maxWallHeightM - s.minWallHeightM > 0.02 ? "\(Units.metres(s.minWallHeightM)) to \(Units.metres(s.maxWallHeightM))" : nil)
            Tile(title: "Perimeter", value: Units.metres(s.perimeterM))
            Tile(title: "Skirting", value: Units.metres(s.skirtingM))
            Tile(title: "Door frames", value: Units.metres(s.doorTrimM), detail: "\(s.doorCount) door\(s.doorCount == 1 ? "" : "s"), one side")
            Tile(title: "Window frames", value: Units.metres(s.windowTrimM), detail: "\(s.windowCount) window\(s.windowCount == 1 ? "" : "s")")
        }
    }
}

private struct Tile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .title.bold() : .title2.weight(.semibold))
                .monospacedDigit()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WallRow: View {
    let wall: Surface
    let openings: [Surface]

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wall.label).font(.headline)
                Text(Units.size(wall.widthM, wall.heightM))
                    .monospacedDigit()
                if !openings.isEmpty {
                    Text("Less " + openings.map(\.label).joined(separator: ", ") + ": \(Units.squareMetres(wall.openingsM2))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                FlagList(flags: wall.flags)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Units.squareMetres(wall.paintAreaM2))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("to paint").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct OpeningRow: View {
    let opening: Surface
    let wallLabel: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(opening.label).font(.headline)
                Text(wallLabel ?? "Not on a wall").font(.caption).foregroundStyle(.secondary)
                FlagList(flags: opening.flags.filter { $0 != .notOnAWall })
            }
            Spacer()
            Text(Units.size(opening.widthM, opening.heightM))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct FlagList: View {
    let flags: [SurfaceFlag]

    var body: some View {
        if !flags.isEmpty {
            HStack(spacing: 6) {
                ForEach(flags, id: \.self) { flag in
                    Text(flag.description)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((flag.isWarning ? Color.orange : Color.accentColor).opacity(0.15), in: Capsule())
                        .foregroundStyle(flag.isWarning ? Color.orange : Color.accentColor)
                }
            }
        }
    }
}

private struct TapeCheckView: View {
    let check: TapeCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                stat("Average error", String(format: "%.1f cm", check.meanAbsErrorM * 100))
                stat("Worst", Units.centimetres(check.worst.errorM))
                stat("Bias", Units.centimetres(check.meanErrorM))
            }
            ForEach(Array(check.samples.enumerated()), id: \.offset) { _, sample in
                HStack {
                    Text(sample.name)
                    Spacer()
                    Text("\(Units.metres(sample.lidarM)) vs \(Units.metres(sample.tapeM))")
                        .foregroundStyle(.secondary)
                    Text(Units.centimetres(sample.errorM))
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.callout.monospacedDigit())
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}
