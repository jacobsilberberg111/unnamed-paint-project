import Foundation
import Observation
import RoomPlan
import ScanCore

/// Saves each room in Documents/Rooms/<id>/ as room.json (our model) plus
/// capturedRoom.json (RoomPlan's raw result). Documents is visible in the Files
/// app, so scans can be copied off the iPad and loaded on another device.
@MainActor
@Observable
final class RoomStore {
    private(set) var rooms: [Room] = []
    let directory: URL

    private static let roomFileName = "room.json"

    init(directory: URL = URL.documentsDirectory.appending(path: "Rooms", directoryHint: .isDirectory)) {
        self.directory = directory
        reload()
    }

    func folder(for room: Room) -> URL {
        directory.appending(path: room.id.uuidString, directoryHint: .isDirectory)
    }

    func roomFileURL(for room: Room) -> URL {
        folder(for: room).appending(path: Self.roomFileName)
    }

    /// The saved RoomPlan JSON, if this room has one on disk.
    func scanFileURL(for room: Room) -> URL? {
        guard let name = room.scanFile else { return nil }
        let url = folder(for: room).appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func room(_ id: Room.ID) -> Room? {
        rooms.first { $0.id == id }
    }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let folders = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        rooms = folders
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appending(path: Self.roomFileName)) else { return nil }
                return try? Self.decoder.decode(Room.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ room: Room) throws {
        try FileManager.default.createDirectory(at: folder(for: room), withIntermediateDirectories: true)
        try Self.encoder.encode(room).write(to: roomFileURL(for: room), options: .atomic)
        if let i = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[i] = room
        } else {
            rooms.insert(room, at: 0)
        }
    }

    @discardableResult
    func add(captured: CapturedRoom, name: String) throws -> Room {
        try add(Room(captured: captured, name: name), captured: captured)
    }

    @discardableResult
    func add(_ room: Room, captured: CapturedRoom) throws -> Room {
        try writeScan(try JSONEncoder().encode(captured), for: room)
        try save(room)
        return room
    }

    func delete(_ room: Room) {
        try? FileManager.default.removeItem(at: folder(for: room))
        rooms.removeAll { $0.id == room.id }
    }

    /// Accepts either a room.json from this app or a raw CapturedRoom JSON
    /// (e.g. from Apple's RoomPlan sample app).
    @discardableResult
    func importFile(at url: URL) throws -> Room {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        if let room = try? Self.decoder.decode(Room.self, from: data) {
            try save(room)
            return room
        }
        guard let captured = try? JSONDecoder().decode(CapturedRoom.self, from: data) else {
            throw ImportError.notAScan
        }
        let room = Room(captured: captured, name: url.deletingPathExtension().lastPathComponent)
        try writeScan(data, for: room)
        try save(room)
        return room
    }

    private func writeScan(_ data: Data, for room: Room) throws {
        guard let name = room.scanFile else { return }
        try FileManager.default.createDirectory(at: folder(for: room), withIntermediateDirectories: true)
        try data.write(to: folder(for: room).appending(path: name), options: .atomic)
    }

    enum ImportError: LocalizedError {
        case notAScan
        var errorDescription: String? { "That file isn't a room scan. Pick a room.json from this app or a RoomPlan CapturedRoom JSON." }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
