import AVFoundation
import AVKit
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onFocus: (CGPoint) -> Void
    /// When true, the volume buttons (and Camera Control) take the photo, as in a dedicated camera.
    var shutterEnabled = false
    var onShutter: (() -> Void)? = nil

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        view.onFocus = onFocus
        view.onShutter = onShutter
        view.shutterEnabled = shutterEnabled
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(PreviewSurface.tap(_:))))
        return view
    }

    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.onFocus = onFocus
        view.onShutter = onShutter
        view.shutterEnabled = shutterEnabled
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    var onShutter: (() -> Void)?
    var shutterEnabled = false { didSet { updateShutterInteraction() } }
    private var shutterInteraction: UIInteraction?

    override func layoutSubviews() {
        super.layoutSubviews()
        // The interface is portrait only; captured photos are rotated separately from the phone's orientation.
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }

    @objc func tap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: point))
        let ring = UIView(frame: CGRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56))
        ring.isUserInteractionEnabled = false
        ring.layer.borderColor = UIColor.systemYellow.cgColor
        ring.layer.borderWidth = 1.5
        ring.layer.cornerRadius = 8
        addSubview(ring)
        UIView.animate(withDuration: 0.8, delay: 0.5, options: []) { ring.alpha = 0 } completion: { _ in ring.removeFromSuperview() }
    }

    private func updateShutterInteraction() {
        guard #available(iOS 17.2, *) else { return }
        if shutterInteraction == nil && onShutter != nil {
            let interaction = AVCaptureEventInteraction(handler: { [weak self] event in
                if event.phase == .ended { self?.onShutter?() }
            })
            addInteraction(interaction)
            shutterInteraction = interaction
        }
        // Disabled interactions give the buttons back to the system (volume).
        (shutterInteraction as? AVCaptureEventInteraction)?.isEnabled = shutterEnabled
    }
}
