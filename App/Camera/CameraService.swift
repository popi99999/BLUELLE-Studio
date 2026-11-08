import AVFoundation
import Combine
import CoreMotion
import UIKit

struct CapturePayload {
    let jpeg: Data
    let raw: Data?
    let width: Int
    let height: Int
}

struct CameraTelemetry {
    var iso: Float = 0
    var seconds: Double = 0
    var focusing = false
    var rotation: Double?
    var advice: CaptureAdvice {
        CaptureAdvice.evaluate(iso: iso, seconds: seconds, rotation: rotation, focusing: focusing)
    }
    var shutter: String { seconds > 0 ? (seconds < 1 ? "1/\(Int((1 / seconds).rounded())) s" : String(format: "%.1f s", seconds)) : "—" }
}

final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var ready = false
    @Published private(set) var isCapturing = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var rawAvailable = false
    @Published private(set) var whiteBalanceLocked = false
    @Published private(set) var focusLocked = false
    @Published private(set) var exposureLocked = false
    @Published private(set) var adjustingColor = false
    @Published private(set) var temperature: Float = 5200
    @Published private(set) var tint: Float = 0
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var colorRevision = 0
    @Published private(set) var resolution = "—"
    @Published private(set) var telemetry = CameraTelemetry()
    @Published var error: String?

    private let queue = DispatchQueue(label: "com.bluelle.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let motion = CMMotionManager()
    private var device: AVCaptureDevice?
    private var pending: [Int64: PhotoReceiver] = [:]
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var configured = false
    private var inFlight = false
    private var wantsRunning = false
    private var colorAdjustmentPending = false
    private var colorRequest = 0
    let isPreview = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.ready = false
            self?.error = "Fotocamera interrotta da iOS. Torna all’app per riprendere."
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in self?.start() })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] notification in
            self?.ready = false
            self?.error = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Errore della fotocamera. Riprova."
        })
    }

    deinit {
        timer?.cancel()
        motion.stopGyroUpdates()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        guard !isPreview else { return }
        queue.async { self.wantsRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureAndStart() }
                else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default: permissionDenied = true
        }
    }

    func stop() {
        queue.async {
            self.wantsRunning = false
            self.timer?.cancel(); self.timer = nil
            self.motion.stopGyroUpdates()
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.ready = false }
        }
    }

    private func configureAndStart() {
        queue.async {
            guard self.wantsRunning else { return }
            do {
                if !self.configured { try self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
                if self.motion.isGyroAvailable {
                    self.motion.gyroUpdateInterval = 0.1
                    self.motion.startGyroUpdates()
                }
                self.startTelemetry()
                DispatchQueue.main.async {
                    self.ready = self.session.isRunning
                    self.permissionDenied = false
                    self.error = nil
                }
            } catch { self.report(error) }
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw StudioError.message("Fotocamera posteriore non disponibile. Serve un iPhone reale.")
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw StudioError.message("Impossibile collegare la fotocamera.") }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw StudioError.message("Acquisizione foto non disponibile.")
        }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        if let largest = camera.activeFormat.supportedMaxPhotoDimensions.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            output.maxPhotoDimensions = largest
        }
        try camera.lockForConfiguration()
        camera.videoZoomFactor = 1
        if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
        if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
        if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camera.whiteBalanceMode = .continuousAutoWhiteBalance }
        camera.unlockForConfiguration()
        device = camera
        configured = true
        let dims = output.maxPhotoDimensions
        let hasRaw = output.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        DispatchQueue.main.async {
            self.rawAvailable = hasRaw
            self.resolution = String(format: "fino a %.0f MP", Double(dims.width) * Double(dims.height) / 1_000_000)
        }
    }

    private func startTelemetry() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, let device = self.device else { return }
            let rate = self.motion.gyroData?.rotationRate
            let rotation = rate.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }
            let reading = CameraTelemetry(iso: device.iso, seconds: CMTimeGetSeconds(device.exposureDuration), focusing: device.isAdjustingFocus, rotation: rotation)
            let color = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            let exposureBias = device.exposureTargetBias
            DispatchQueue.main.async {
                self.telemetry = reading
                if color.temperature.isFinite { self.temperature = color.temperature }
                if color.tint.isFinite { self.tint = color.tint }
                self.exposureBias = exposureBias
            }
        }
        self.timer = timer
        timer.resume()
    }

    func focus(at point: CGPoint) {
        configureDevice { camera in
            if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = point }
            if camera.isFocusModeSupported(.autoFocus) { camera.focusMode = .autoFocus }
            if camera.exposureMode != .locked && camera.isExposurePointOfInterestSupported { camera.exposurePointOfInterest = point }
            DispatchQueue.main.async { self.focusLocked = false }
        }
    }

    func setFocusLocked(_ locked: Bool) {
        configureDevice { camera in
            let mode: AVCaptureDevice.FocusMode = locked ? .locked : .continuousAutoFocus
            guard camera.isFocusModeSupported(mode) else { throw StudioError.message("Blocco fuoco non disponibile.") }
            camera.focusMode = mode
            DispatchQueue.main.async { self.focusLocked = locked }
        }
    }

    func setExposureLocked(_ locked: Bool) {
        configureDevice { camera in
            let mode: AVCaptureDevice.ExposureMode = locked ? .locked : .continuousAutoExposure
            guard camera.isExposureModeSupported(mode) else { throw StudioError.message("Blocco esposizione non disponibile.") }
            camera.exposureMode = mode
            DispatchQueue.main.async { self.exposureLocked = locked }
        }
    }

    func setExposureBias(_ bias: Float) {
        configureDevice { camera in
            camera.setExposureTargetBias(min(camera.maxExposureTargetBias, max(camera.minExposureTargetBias, bias)))
        }
    }

    func lockWhiteBalance(calibrate: Bool = false, kelvin: Float? = nil, tint: Float = 0) {
        configureDevice { camera in
            guard camera.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { throw StudioError.message("Blocco colore non disponibile.") }
            let gains: AVCaptureDevice.WhiteBalanceGains
            if let kelvin {
                gains = camera.deviceWhiteBalanceGains(for: .init(temperature: kelvin, tint: tint))
            } else { gains = calibrate ? camera.grayWorldDeviceWhiteBalanceGains : camera.deviceWhiteBalanceGains }
            let safe = WhiteBalance.clamp(red: gains.redGain, green: gains.greenGain, blue: gains.blueGain, maximum: camera.maxWhiteBalanceGain)
            self.colorRequest += 1
            let request = self.colorRequest
            self.colorAdjustmentPending = true
            DispatchQueue.main.async { self.adjustingColor = true }
            camera.setWhiteBalanceModeLocked(with: .init(redGain: safe.red, greenGain: safe.green, blueGain: safe.blue)) { _ in
                self.queue.async {
                    guard self.colorRequest == request else { return }
                    self.colorAdjustmentPending = false
                    let applied = camera.temperatureAndTintValues(for: camera.deviceWhiteBalanceGains)
                    DispatchQueue.main.async {
                        self.whiteBalanceLocked = true
                        self.adjustingColor = false
                        if applied.temperature.isFinite { self.temperature = applied.temperature }
                        if applied.tint.isFinite { self.tint = applied.tint }
                        self.colorRevision += 1
                    }
                }
            }
        }
    }

    func autoWhiteBalance() {
        configureDevice { camera in
            guard camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { throw StudioError.message("Bilanciamento automatico non disponibile.") }
            self.colorRequest += 1
            self.colorAdjustmentPending = false
            camera.whiteBalanceMode = .continuousAutoWhiteBalance
            DispatchQueue.main.async { self.whiteBalanceLocked = false; self.adjustingColor = false }
        }
    }

    private func configureDevice(_ operation: @escaping (AVCaptureDevice) throws -> Void) {
        queue.async {
            guard let device = self.device, !self.inFlight else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                try operation(device)
            } catch { self.report(error) }
        }
    }

    func capture(raw: Bool, completion: @escaping (Result<CapturePayload, Error>) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.inFlight, !self.colorAdjustmentPending else {
                DispatchQueue.main.async { completion(.failure(StudioError.message("Fotocamera o colore in regolazione. Attendi e riprova."))) }
                return
            }
            let settings: AVCapturePhotoSettings
            if raw {
                guard let format = self.output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) else {
                    DispatchQueue.main.async { completion(.failure(StudioError.message("RAW non disponibile su questo iPhone."))) }
                    return
                }
                settings = AVCapturePhotoSettings(rawPixelFormatType: format, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .speed
            } else {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .quality
            }
            settings.maxPhotoDimensions = self.output.maxPhotoDimensions
            settings.flashMode = .off
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            let id = settings.uniqueID
            let receiver = PhotoReceiver(expectRaw: raw) { result in
                self.queue.async {
                    self.pending.removeValue(forKey: id)
                    self.inFlight = false
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        completion(result)
                    }
                }
            }
            self.inFlight = true
            self.pending[id] = receiver
            DispatchQueue.main.async { self.isCapturing = true }
            self.output.capturePhoto(with: settings, delegate: receiver)
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async { self.error = error.localizedDescription }
    }
}

private final class PhotoReceiver: NSObject, AVCapturePhotoCaptureDelegate {
    private var jpeg: Data?
    private var raw: Data?
    private var dimensions = CMVideoDimensions(width: 0, height: 0)
    private var failure: Error?
    private let expectRaw: Bool
    private let completion: (Result<CapturePayload, Error>) -> Void

    init(expectRaw: Bool, completion: @escaping (Result<CapturePayload, Error>) -> Void) {
        self.expectRaw = expectRaw; self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { failure = error; return }
        guard let data = photo.fileDataRepresentation() else { failure = StudioError.message("Dati foto non disponibili."); return }
        if photo.isRawPhoto { raw = data }
        else { jpeg = data; dimensions = photo.resolvedSettings.photoDimensions }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? failure { completion(.failure(error)); return }
        guard let jpeg, !expectRaw || raw != nil else { completion(.failure(StudioError.message("Acquisizione incompleta. Scatta di nuovo."))); return }
        completion(.success(CapturePayload(jpeg: jpeg, raw: raw, width: Int(dimensions.width), height: Int(dimensions.height))))
    }
}

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
