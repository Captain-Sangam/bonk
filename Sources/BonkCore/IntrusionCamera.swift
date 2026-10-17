import AVFoundation
import Foundation

/// Takes one webcam still on a genuine failed unlock attempt. Lazy per capture (no always-on
/// camera LED), bounded by a timeout, and entirely off the main thread so it can never stall the
/// input tap. Fire-and-forget: a pending capture is never torn down by guard cleanup.
public final class IntrusionCamera: IntrusionCapturing {
    public let captureDirectory: URL

    public init() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        captureDirectory = pictures.appendingPathComponent("Bonk", isDirectory: true)
    }

    public var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// Called when the user enables the monitor (while idle), so the TCC prompt never appears
    /// under the guard overlay.
    public func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    @discardableResult
    public func captureIntrusion() async -> Bool {
        guard isAuthorized else { return false }
        let directory = captureDirectory
        return await Task.detached(priority: .utility) {
            await IntrusionCamera.capture(to: directory)
        }.value
    }

    private static func capture(to directory: URL) async -> Bool {
        let shot = CameraShot()
        guard let data = await shot.takePhoto() else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("intruder-\(stamp).jpg")
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// One-shot capture session wrapper. Resolves to JPEG data, or nil on any failure (no camera,
/// busy, denied mid-flight, encode failure, or timeout).
private final class CameraShot: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var finished = false
    private let lock = NSLock()

    func takePhoto(timeout: TimeInterval = 4) async -> Data? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.configureAndShoot(timeout: timeout)
        }
    }

    private func configureAndShoot(timeout: TimeInterval) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            finish(nil)
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()

        // Brief warm-up so exposure/white-balance settle before the first frame.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
        // Hard safety timeout so a stuck device never hangs the task.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(nil)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        finish(error == nil ? photo.fileDataRepresentation() : nil)
    }

    private func finish(_ data: Data?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if session.isRunning { session.stopRunning() }
        continuation?.resume(returning: data)
    }
}
