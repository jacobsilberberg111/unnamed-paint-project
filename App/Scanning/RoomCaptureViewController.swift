import ARKit
import RoomPlan
import ScanCore
import SwiftUI
import UIKit

/// Hosts RoomPlan's live capture view and feeds every update into the ScanSession.
final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    private let scan: ScanSession
    private var captureView: RoomCaptureView?
    private var poseTimer: Timer?
    private var isRunning = false
    private var isCancelled = false

    init(scan: ScanSession) {
        self.scan = scan
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.captureSession.delegate = self
        captureView.delegate = self
        view.addSubview(captureView)
        self.captureView = captureView
        scan.controller = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCapture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isRunning { cancelCapture() }
        poseTimer?.invalidate()
    }

    private func startCapture() {
        guard !isRunning, let captureView else { return }
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)
        isRunning = true
        let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(publishPose), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        poseTimer = timer
    }

    /// Stops scanning; RoomPlan then processes the room and calls `captureView(didPresent:)`.
    func finishCapture() {
        guard isRunning else { return }
        isRunning = false
        poseTimer?.invalidate()
        captureView?.captureSession.stop()
    }

    func cancelCapture() {
        isCancelled = true
        finishCapture()
    }

    @objc private func publishPose() {
        guard let frame = captureView?.captureSession.arSession.currentFrame else { return }
        scan.look(at: frame)
        let t = frame.camera.transform
        // The camera looks down its local -z axis.
        scan.pose = DevicePose(
            position: Vec2(Double(t.columns.3.x), Double(t.columns.3.z)),
            forward: Vec2(Double(-t.columns.2.x), Double(-t.columns.2.z))
        )
    }

    // MARK: RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let geometry = ScanGeometry(room)
        Task { @MainActor in self.scan.update(geometry) }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let mapped = ScanInstruction(instruction)
        Task { @MainActor in self.scan.instruction = mapped }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let error else { return }
        let message = error.localizedDescription
        Task { @MainActor in
            guard !self.isCancelled else { return }
            self.scan.fail(message)
        }
    }

    // MARK: RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            guard !self.isCancelled else { return }
            if let message {
                self.scan.fail(message)
            } else {
                self.scan.captured(processedResult)
            }
        }
    }
}

struct RoomCaptureContainer: UIViewControllerRepresentable {
    let scan: ScanSession

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        RoomCaptureViewController(scan: scan)
    }

    func updateUIViewController(_ controller: RoomCaptureViewController, context: Context) {}
}
