import ARKit
import Foundation
import Observation
import RoomPlan
import ScanCore

/// Where the iPad is and which way it's facing, in plan coordinates.
struct DevicePose: Equatable {
    var position: Vec2
    var forward: Vec2
}

/// RoomPlan's live coaching, reworded for a painter at arm's length.
enum ScanInstruction: Equatable {
    case normal, moveCloser, moveAway, slowDown, moreLight, moreTexture

    init(_ instruction: RoomCaptureSession.Instruction) {
        switch instruction {
        case .normal: self = .normal
        case .moveCloseToWall: self = .moveCloser
        case .moveAwayFromWall: self = .moveAway
        case .slowDown: self = .slowDown
        case .turnOnLight: self = .moreLight
        case .lowTexture: self = .moreTexture
        @unknown default: self = .normal
        }
    }

    var title: String {
        switch self {
        case .normal: return ""
        case .moveCloser: return "Move closer to the wall"
        case .moveAway: return "Step back from the wall"
        case .slowDown: return "Slow down"
        case .moreLight: return "Turn on more lights"
        case .moreTexture: return "Aim at something with more detail"
        }
    }

    var detail: String {
        switch self {
        case .normal: return ""
        case .moveCloser: return "Stay within about 4 metres of what you're scanning."
        case .moveAway: return "Too close to measure. Back off half a metre."
        case .slowDown: return "Move the iPad slowly and steadily."
        case .moreLight: return "It's too dark to scan accurately. Open curtains or switch lights on."
        case .moreTexture: return "Plain surfaces are hard to track. Include an edge, corner or object in view."
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "checkmark"
        case .moveCloser: return "arrow.up.forward"
        case .moveAway: return "arrow.down.backward"
        case .slowDown: return "tortoise.fill"
        case .moreLight: return "lightbulb.fill"
        case .moreTexture: return "square.grid.3x3.fill"
        }
    }
}

@MainActor
@Observable
final class ScanSession {
    enum Phase: Equatable {
        case tips, scanning, processing, review, failed(String)
    }

    var phase: Phase = .tips
    var roomName = ""
    var instruction: ScanInstruction = .normal
    var coverage: CoverageReport = .empty
    var pose: DevicePose?
    /// Rectangles the camera has spotted on the walls so far.
    var spottedCount = 0
    /// After the scan: the room, and the spotted things the app wasn't sure about.
    var pendingRoom: Room?
    var unsure: [WallFeatureSuggestion] = []
    /// How many spotted things were added without asking.
    var autoAdded = 0

    @ObservationIgnored let detector = WallFeatureDetector()
    /// Walls from the latest live update, for placing what the camera sees.
    @ObservationIgnored private(set) var liveWalls: [ScannedSurface] = []
    @ObservationIgnored var pendingCapture: CapturedRoom?
    @ObservationIgnored weak var controller: RoomCaptureViewController?
    /// Called once with RoomPlan's final, processed room.
    @ObservationIgnored var onCaptured: ((CapturedRoom) -> Void)?

    func start() {
        coverage = .empty
        instruction = .normal
        pose = nil
        spottedCount = 0
        liveWalls = []
        pendingRoom = nil
        pendingCapture = nil
        unsure = []
        detector.reset()
        phase = .scanning
    }

    func update(_ geometry: ScanGeometry) {
        guard phase == .scanning else { return }
        coverage = Coverage.analyse(geometry)
        liveWalls = geometry.walls
    }

    /// Called a few times a second with the latest camera frame.
    func look(at frame: ARFrame) {
        guard phase == .scanning else { return }
        detector.submit(frame, walls: liveWalls)
        let count = detector.confirmed.count
        if count != spottedCount { spottedCount = count }
    }

    /// Room scanned and processed: add what the camera is sure of, ask about the rest.
    func review(_ room: Room, captured: CapturedRoom) {
        var room = room
        let suggestions = WallFeatureSuggester.suggestions(detector.confirmed, in: room.geometry)
        unsure = room.applyConfident(suggestions)
        autoAdded = suggestions.filter { $0.verdict.isConfident && $0.verdict.kind != nil }.count
        pendingRoom = room
        pendingCapture = captured
        phase = .review
    }

    func finish() {
        guard phase == .scanning else { return }
        phase = .processing
        instruction = .normal
        controller?.finishCapture()
    }

    func cancel() {
        controller?.cancelCapture()
    }

    func captured(_ room: CapturedRoom) {
        guard phase == .processing || phase == .scanning else { return }
        onCaptured?(room)
    }

    func fail(_ message: String) {
        guard phase == .scanning || phase == .processing || phase == .review else { return }
        phase = .failed(message)
    }
}
