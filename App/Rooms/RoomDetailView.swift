import ScanCore
import SwiftUI

/// All measurements for one scanned room. Tap any wall, door or window to correct it.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var room: Room
    @State private var editing: Surface?
    @State private var editingFurniture: FurnitureItem?
    @State private var saveError: String?

    init(room: Room) {
        _room = State(initialValue: room)
    }

    var body: some View {
        let m = room.measure()
        ScrollView {
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 20) { overview(m) }
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 20) { details(m) }
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 20) {
                        overview(m)
                        details(m)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1300)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(BackdropView())
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { shareMenu(m) }
        .sheet(item: $editing) { surface in
            SurfaceEditSheet(
                surface: surface,
                originalKind: room.scannedSurface(surface.id)?.kind ?? surface.kind,
                existing: room.override(for: surface.id)
            ) { override in
                room.setOverride(override, for: surface.id)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingFurniture) { item in
            FurnitureEditSheet(item: item) { include, builtIn, area in
                room.updateFurniture(item.id) {
                    $0.include = include
                    $0.builtIn = builtIn ? true : nil
                    $0.areaM2 = area
                }
            }
            .presentationDetents([.medium])
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

    // MARK: Left column

    @ViewBuilder
    private func overview(_ m: RoomMeasurements) -> some View {
        Hero(name: $room.name, summary: m.summary, date: room.createdAt)
        FloorPlanView(plan: m.plan)
            .frame(height: sizeClass == .regular ? 380 : 300)
            .card(padding: 8)
        StatsGrid(summary: m.summary)
        if let check = room.tapeCheck {
            TapeCheckCard(check: check)
        }
    }

    // MARK: Right column

    @ViewBuilder
    private func details(_ m: RoomMeasurements) -> some View {
        ListCard(title: "Walls", footer: "Tap a wall to enter a tape measurement, or remove it if it isn't real.") {
            ForEach(Array(m.walls.enumerated()), id: \.element.id) { index, wall in
                if index > 0 { Divider().overlay(Theme.stroke) }
                Button { editing = wall } label: {
                    WallRow(wall: wall, openings: m.openings(onWall: wall.id),
                            builtIns: m.furniture.filter { $0.coveredWallIds.contains(wall.id) })
                }
                .buttonStyle(PressableStyle())
            }
        }

        if !m.openingSurfaces.isEmpty {
            ListCard(title: "Doors & windows", footer: "Tap one to fix what it is or remove a false detection.") {
                ForEach(Array(m.openingSurfaces.enumerated()), id: \.element.id) { index, opening in
                    if index > 0 { Divider().overlay(Theme.stroke) }
                    Button { editing = opening } label: {
                        OpeningRow(opening: opening, wallLabel: opening.wallId.flatMap { m.surface($0)?.label })
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }

        if !m.furniture.isEmpty {
            ListCard(title: "Furniture", footer: "Tap built-in cupboards and wardrobes so the wall behind them isn't counted. You can also add a piece you're painting; it's totalled separately from the walls.") {
                ForEach(Array(m.furniture.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Theme.stroke) }
                    FurnitureRow(item: item) { editingFurniture = item }
                }
            }
        }

        if !room.removedSurfaces.isEmpty {
            ListCard(title: "Removed", footer: "Left out of every measurement.") {
                ForEach(Array(room.removedSurfaces.enumerated()), id: \.element.id) { index, removed in
                    if index > 0 { Divider().overlay(Theme.stroke) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(removed.kind.rawValue.capitalized).font(.headline)
                            Text(Units.size(removed.width, removed.height))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Put back") { room.setOverride(nil, for: removed.id) }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        Label("LiDAR is typically within a few centimetres, not tape-exact. Ceiling area assumes a flat ceiling. Tape-check anything that matters for the price.",
              systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    @ToolbarContentBuilder
    private func shareMenu(_ m: RoomMeasurements) -> some ToolbarContent {
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
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Pieces

private struct Hero: View {
    @Binding var name: String
    let summary: RoomSummary
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Room name", text: $name)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                if summary.isClosed {
                    Pill(text: "Outline complete", color: Theme.good, symbol: "checkmark.seal.fill")
                } else {
                    Pill(text: "\(summary.gapCount) gap\(summary.gapCount == 1 ? "" : "s") in outline", color: Theme.warn, symbol: "exclamationmark.triangle.fill")
                }
                Text(date, format: .dateTime.day().month(.wide).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", summary.wallPaintM2))
                        .font(.number(72, weight: .heavy))
                        .foregroundStyle(Theme.gradient)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: summary.wallPaintM2)
                    Text("m²")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text("of wall to paint · \(Units.squareMetres(summary.wallGrossM2)) less \(Units.squareMetres(summary.openingsM2)) of doors and windows"
                     + (summary.builtInCoveredM2 > 0 ? " and \(Units.squareMetres(summary.builtInCoveredM2)) behind built-ins" : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 22)
    }
}

private struct StatsGrid: View {
    let summary: RoomSummary

    var body: some View {
        let s = summary
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(title: "Ceiling", value: s.ceilingM2.map(Units.squareMetres) ?? "—", detail: s.floorSource.description)
            StatTile(title: "Floor", value: s.floorM2.map(Units.squareMetres) ?? "—")
            StatTile(title: "Ceiling height", value: Units.metres(s.ceilingHeightM),
                     detail: s.maxWallHeightM - s.minWallHeightM > 0.02 ? "\(Units.metres(s.minWallHeightM)) to \(Units.metres(s.maxWallHeightM))" : nil)
            StatTile(title: "Perimeter", value: Units.metres(s.perimeterM))
            StatTile(title: "Skirting", value: Units.metres(s.skirtingM))
            StatTile(title: "Door frames", value: Units.metres(s.doorTrimM), detail: "\(s.doorCount) door\(s.doorCount == 1 ? "" : "s"), one side")
            StatTile(title: "Window frames", value: Units.metres(s.windowTrimM), detail: "\(s.windowCount) window\(s.windowCount == 1 ? "" : "s")")
            if s.furniturePaintCount > 0 {
                StatTile(title: "Furniture to paint", value: Units.squareMetres(s.furniturePaintM2),
                         detail: "\(s.furniturePaintCount) piece\(s.furniturePaintCount == 1 ? "" : "s")")
            }
        }
    }
}

/// A titled card holding a list of rows.
private struct ListCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionTitle().padding(.horizontal, 4)
            VStack(spacing: 10) { content }
                .card(padding: 16)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct WallRow: View {
    let wall: Surface
    let openings: [Surface]
    var builtIns: [FurnitureItem] = []

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Badge(text: String(wall.label.dropFirst("Wall ".count)), filled: !wall.flags.contains(where: \.isWarning))
            VStack(alignment: .leading, spacing: 5) {
                Text(Units.size(wall.widthM, wall.heightM))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if !openings.isEmpty || !builtIns.isEmpty {
                    Text("less " + (openings.map(\.label) + builtIns.map(\.label)).joined(separator: ", ")
                         + " · \(Units.squareMetres(wall.openingsM2 + wall.coveredM2))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                FlagPills(flags: wall.flags)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f", wall.paintAreaM2))
                    .font(.number(24))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("m²")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct OpeningRow: View {
    let opening: Surface
    let wallLabel: String?

    private var symbol: String {
        switch opening.kind {
        case .door: return "door.left.hand.closed"
        case .window: return "window.vertical.closed"
        default: return "rectangle.portrait.dashed"
        }
    }

    private var color: Color {
        opening.flags.contains(where: \.isWarning) ? Theme.warn
            : opening.kind == .door ? Theme.door : opening.kind == .window ? Theme.window : .gray
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(opening.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(wallLabel ?? "Not on a wall")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlagPills(flags: opening.flags.filter { $0 != .notOnAWall })
            }
            Spacer(minLength: 8)
            Text(Units.size(opening.widthM, opening.heightM))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct FlagPills: View {
    let flags: [SurfaceFlag]

    var body: some View {
        if !flags.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { pills }
                VStack(alignment: .leading, spacing: 4) { pills }
            }
        }
    }

    private var pills: some View {
        ForEach(flags, id: \.self) { flag in
            Pill(text: flag.description, color: flag.isWarning ? Theme.warn : Theme.window)
        }
    }
}

private struct FurnitureRow: View {
    let item: FurnitureItem
    let onEdit: () -> Void

    private var symbol: String {
        switch item.category {
        case "storage": return "cabinet.fill"
        case "table": return "table.furniture.fill"
        case "chair": return "chair.fill"
        case "bed": return "bed.double.fill"
        case "sofa": return "sofa.fill"
        case "fireplace": return "fireplace.fill"
        case "stairs": return "stairs"
        default: return "shippingbox.fill"
        }
    }

    private var active: Bool { item.isPainted || item.isBuiltIn }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background {
                        if active {
                            Circle().fill(Theme.gradient)
                        } else {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(String(format: "%.2f × %.2f × %.2f m", item.widthM, item.heightM, item.depthM))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if active {
                        HStack(spacing: 6) {
                            if item.isBuiltIn {
                                Pill(text: "Built in · \(Units.squareMetres(item.coveredWallM2)) of wall skipped", color: Theme.window)
                            }
                            if item.isPainted {
                                Pill(text: "Painting · \(Units.squareMetres(item.paintAreaM2))", color: Theme.accent)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(PressableStyle())
    }
}

private struct TapeCheckCard: View {
    let check: TapeCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tape check").sectionTitle()
            HStack(spacing: 12) {
                stat("Average", String(format: "%.1f cm", check.meanAbsErrorM * 100))
                stat("Worst", Units.centimetres(check.worst.errorM))
                stat("Bias", Units.centimetres(check.meanErrorM))
            }
            VStack(spacing: 8) {
                ForEach(Array(check.samples.enumerated()), id: \.offset) { _, sample in
                    HStack {
                        Text(sample.name)
                        Spacer()
                        Text("\(Units.metres(sample.lidarM)) vs \(Units.metres(sample.tapeM))")
                            .foregroundStyle(.secondary)
                        Text(Units.centimetres(sample.errorM))
                            .fontWeight(.semibold)
                            .foregroundStyle(abs(sample.errorM) <= 0.02 ? Theme.good : Theme.warn)
                            .frame(width: 76, alignment: .trailing)
                    }
                    .font(.callout.monospacedDigit())
                }
            }
            Text("LiDAR minus tape, for every dimension you've corrected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.number(22)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
