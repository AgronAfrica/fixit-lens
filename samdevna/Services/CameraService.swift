import CoreGraphics
import AVFoundation
import Combine
import SwiftUI
import CoreImage
import UIKit

final class CameraService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var permissionDenied = false
    @Published var isRunning = false

    let session = AVCaptureSession()
    // All mutable state below is only touched on `sessionQueue`.
    private let sessionQueue = DispatchQueue(label: "com.codewithik.samdevna.camera")
    private let photo = AVCapturePhotoOutput()
    /// Live frames for "Fix it together" (and anything else that needs the stream, not a still).
    private let video = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.codewithik.samdevna.camera.frames")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastFrameAt: CFTimeInterval = 0
    /// Called on a background queue with an upright frame (long edge ≤ 1280), at most `maxFrameRate` per second.
    /// Only set while someone needs frames, so the Lens doesn't pay for it.
    var onFrame: (@Sendable (UIImage) -> Void)? {
        get { frameLock.lock(); defer { frameLock.unlock() }; return _onFrame }
        set { frameLock.lock(); _onFrame = newValue; frameLock.unlock() }
    }
    var maxFrameRate: Double = 15
    private let frameLock = NSLock()
    private var _onFrame: (@Sendable (UIImage) -> Void)?
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var configured = false

    func start() {
        sessionQueue.async { [weak self] in self?.configure() }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.continuation == nil else {
                    continuation.resume(throwing: FixError.noImage)   // a capture is already in flight
                    return
                }
                guard self.session.isRunning else {
                    continuation.resume(throwing: FixError.noImage)
                    return
                }
                self.continuation = continuation
                self.photo.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async { self?.configure() }
                } else {
                    DispatchQueue.main.async { self?.permissionDenied = true }
                }
            }
            return
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
            return
        }

        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input),
                session.canAddOutput(photo)
            else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.permissionDenied = true }
                return
            }
            session.addInput(input)
            session.addOutput(photo)
            if session.canAddOutput(video) {
                video.alwaysDiscardsLateVideoFrames = true
                video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                video.setSampleBufferDelegate(self, queue: videoQueue)
                session.addOutput(video)
                if let connection = video.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90   // portrait, matching the preview
                }
            }
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning { session.startRunning() }
        DispatchQueue.main.async { self.isRunning = true }
    }

    private func resume(_ result: Result<UIImage, Error>) {
        sessionQueue.async {
            self.continuation?.resume(with: result)
            self.continuation = nil
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            resume(.failure(error))
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            resume(.success(image))
        } else {
            resume(.failure(FixError.noImage))
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let onFrame else { return }
        let now = CACurrentMediaTime()
        guard now - lastFrameAt >= 1 / max(maxFrameRate, 1) else { return }
        lastFrameAt = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: buffer)
        let longEdge = max(image.extent.width, image.extent.height)
        if longEdge > 1280 {
            let scale = 1280 / longEdge
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return }
        onFrame(UIImage(cgImage: cg))
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
