import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        view.onFocus = onFocus
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(PreviewSurface.tap(_:))))
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.onFocus = onFocus
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
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
}
