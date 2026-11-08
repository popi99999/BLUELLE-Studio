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

enum FocusSetting: Equatable {
    /// Continuous autofocus on the centre of the frame.
    case auto
    /// Focused once on a tapped point; returns to `auto` when the scene changes.
    case point
    /// Lens kept where it is.
    case locked
    /// Lens position chosen with the slider.
    case manual
}

enum ExposureSetting: Equatable { case auto, locked, manual }

enum RawKind: Equatable {
    case none, bayer, proRAW
    var title: String {
        switch self {
        case .none: return "—"
        case .bayer: return "RAW"
        case .proRAW: return "ProRAW"
        }
    }
}

struct CameraTelemetry {
    var iso: Float = 0
    var seconds: Double = 0
    var focusing = false
    var lensPosition: Float = 0
    /// Difference, in EV, between the current exposure and what the meter would choose.
    var meterOffset: Float = 0
    var rotation: Double?
    var advice: CaptureAdvice {
        CaptureAdvice.evaluate(iso: iso, seconds: seconds, rotation: rotation, focusing: focusing)
    }
    var shutter: String { ExposureScale.label(seconds) }
}

struct CameraLimits: Equatable {
    var minISO: Float = 50
    var maxISO: Float = 1600
    var minSeconds: Double = 1.0 / 8000
    var maxSeconds: Double = 0.5
    var minBias: Float = -2
    var maxBias: Float = 2
    /// Closest focusing distance in millimetres; 0 when iOS does not report it.
    var minimumFocusDistance = 0
    var manualExposure = false
    var manualFocus = false
}

final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    /// Level, orientation and hand movement. Observed by small views so it does not redraw the whole screen.
    let motion = MotionMonitor()
    /// Histogram, clipping and focus peaking from the live preview.
    let frames: FrameMonitor

    @Published private(set) var ready = false
    @Published private(set) var isCapturing = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var rawKind: RawKind = .none
    @Published private(set) var whiteBalanceLocked = false
    @Published private(set) var focusState: FocusSetting = .auto
    @Published private(set) var exposureState: ExposureSetting = .auto
    @Published private(set) var adjustingColor = false
    @Published private(set) var temperature: Float = 5200
    @Published private(set) var tint: Float = 0
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var colorRevision = 0
    @Published private(set) var resolution = "—"
    @Published private(set) var limits = CameraLimits()
    @Published private(set) var telemetry = CameraTelemetry()
    @Published var error: String?

    var rawAvailable: Bool { rawKind != .none }

    private let queue = DispatchQueue(label: "com.bluelle.camera", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.bluelle.analysis", qos: .utility)
    private let output = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameTap: FrameTap
    private var device: AVCaptureDevice?
    private var pending: [Int64: PhotoReceiver] = [:]
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var configured = false
    private var inFlight = false
    private var wantsRunning = false
    private var wantsRAW = false
    private var colorAdjustmentPending = false
    private var colorRequest = 0
    // Owned by `queue`; the published copies above are for the interface.
    private var focusMode: FocusSetting = .auto
    private var exposureMode: ExposureSetting = .auto
    let isPreview = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    override init() {
        let monitor = FrameMonitor()
        frames = monitor
        frameTap = FrameTap(monitor: monitor)
        super.init()
        // The interface preview (simulator, UI tests) never runs the camera, so session events there are noise.
        guard !isPreview else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.ready = false
            self?.error = "Fotocamera interrotta da iOS. Torna all’app per riprendere."
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in self?.start() })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] notification in
            guard let self else { return }
            self.ready = false
            let failure = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            // iOS can reset its media services (for example after a call); the camera only needs to be started again.
            if failure?.code == .mediaServicesWereReset { self.start(); return }
            self.error = "Errore della fotocamera (\(failure?.code.rawValue ?? 0)). Chiudi e riapri l’app."
        })
    }

    deinit {
        timer?.cancel()
        motion.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Session

    func start() {
        guard !isPreview else { return }
        queue.async { self.wantsRunning = true }
        motion.start()
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
        motion.stop()
        frames.reset()
        queue.async {
            self.wantsRunning = false
            self.timer?.cancel(); self.timer = nil
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
        session.sessionPreset = .photo
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw StudioError.message("Impossibile collegare la fotocamera.")
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            throw StudioError.message("Acquisizione foto non disponibile.")
        }
        session.addOutput(output)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(frameTap, queue: analysisQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()

        // The active format is settled once the preset is committed: ask for its largest photos.
        session.beginConfiguration()
        output.maxPhotoQualityPrioritization = .quality
        if let largest = camera.activeFormat.supportedMaxPhotoDimensions.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            output.maxPhotoDimensions = largest
        }
        if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = wantsRAW }
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        session.commitConfiguration()

        try camera.lockForConfiguration()
        camera.videoZoomFactor = 1
        if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
        if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
        if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camera.whiteBalanceMode = .continuousAutoWhiteBalance }
        camera.isSubjectAreaChangeMonitoringEnabled = true
        camera.unlockForConfiguration()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureDeviceSubjectAreaDidChange, object: camera, queue: nil) { [weak self] _ in
            self?.subjectAreaChanged()
        })
        device = camera
        configured = true
        publishCapabilities(of: camera)
        prepareSettings()
    }

    private func publishCapabilities(of camera: AVCaptureDevice) {
        let dims = output.maxPhotoDimensions
        let kind: RawKind
        if output.isAppleProRAWSupported { kind = .proRAW }
        else if output.availableRawPhotoPixelFormatTypes.contains(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) { kind = .bayer }
        else { kind = .none }
        let format = camera.activeFormat
        var limits = CameraLimits()
        limits.minISO = format.minISO
        limits.maxISO = max(format.minISO + 1, format.maxISO)
        limits.minSeconds = max(0.000_01, format.minExposureDuration.seconds)
        limits.maxSeconds = max(limits.minSeconds * 2, min(1, format.maxExposureDuration.seconds))
        limits.minBias = camera.minExposureTargetBias
        limits.maxBias = camera.maxExposureTargetBias
        limits.minimumFocusDistance = max(0, camera.minimumFocusDistance)
        limits.manualExposure = camera.isExposureModeSupported(.custom)
        limits.manualFocus = camera.isLockingFocusWithCustomLensPositionSupported
        let megapixels = Double(dims.width) * Double(dims.height) / 1_000_000
        DispatchQueue.main.async {
            self.rawKind = kind
            self.limits = limits
            self.resolution = String(format: "fino a %.0f MP", megapixels)
        }
    }

    private func startTelemetry() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, let device = self.device else { return }
            var reading = CameraTelemetry()
            reading.iso = device.iso
            reading.seconds = CMTimeGetSeconds(device.exposureDuration)
            reading.focusing = device.isAdjustingFocus
            reading.lensPosition = device.lensPosition
            reading.meterOffset = device.exposureTargetOffset
            let snapshot = reading
            let color = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            let exposureBias = device.exposureTargetBias
            DispatchQueue.main.async {
                var value = snapshot
                value.rotation = self.motion.latestRotation
                self.telemetry = value
                if color.temperature.isFinite { self.temperature = color.temperature }
                if color.tint.isFinite { self.tint = color.tint }
                self.exposureBias = exposureBias
            }
        }
        self.timer = timer
        timer.resume()
    }

    // MARK: Focus

    /// Focuses and meters on the tapped point. The point is released when the scene changes (see `subjectAreaChanged`).
    func focus(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        let point = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
        configureDevice { camera in
            if camera.isFocusPointOfInterestSupported && camera.isFocusModeSupported(.autoFocus) {
                camera.focusPointOfInterest = point
                camera.focusMode = .autoFocus
                self.setFocusState(.point)
            }
            // A new point of interest is used only once the exposure mode is set again.
            if self.exposureMode == .auto && camera.isExposurePointOfInterestSupported && camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposurePointOfInterest = point
                camera.exposureMode = .continuousAutoExposure
            }
        }
    }

    private func subjectAreaChanged() {
        configureDevice { camera in
            guard self.focusMode == .point else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = center }
            if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
            self.setFocusState(.auto)
            if self.exposureMode == .auto && camera.isExposurePointOfInterestSupported && camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposurePointOfInterest = center
                camera.exposureMode = .continuousAutoExposure
            }
        }
    }

    func setFocusLocked(_ locked: Bool) {
        configureDevice { camera in
            if locked {
                guard camera.isFocusModeSupported(.locked) else { throw StudioError.message("Blocco fuoco non disponibile.") }
                camera.focusMode = .locked
                self.setFocusState(.locked)
            } else {
                guard camera.isFocusModeSupported(.continuousAutoFocus) else { throw StudioError.message("Autofocus non disponibile.") }
                if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                camera.focusMode = .continuousAutoFocus
                self.setFocusState(.auto)
            }
        }
    }

    /// 0 is the closest focusing distance, 1 is far away.
    func setLensPosition(_ position: Float) {
        guard position.isFinite else { return }
        configureDevice { camera in
            guard camera.isLockingFocusWithCustomLensPositionSupported else { throw StudioError.message("Fuoco manuale non disponibile.") }
            camera.setFocusModeLocked(lensPosition: min(1, max(0, position)), completionHandler: nil)
            self.setFocusState(.manual)
        }
    }

    private func setFocusState(_ state: FocusSetting) {
        focusMode = state
        DispatchQueue.main.async { self.focusState = state }
    }

    // MARK: Exposure

    func setExposureLocked(_ locked: Bool) {
        configureDevice { camera in
            let mode: AVCaptureDevice.ExposureMode = locked ? .locked : .continuousAutoExposure
            guard camera.isExposureModeSupported(mode) else { throw StudioError.message("Blocco esposizione non disponibile.") }
            if !locked && camera.isExposurePointOfInterestSupported { camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            camera.exposureMode = mode
            self.setExposureState(locked ? .locked : .auto)
        }
    }

    /// Fixed shutter time and ISO. Values are kept inside what the active format allows.
    func setManualExposure(seconds: Double, iso: Float) {
        guard seconds.isFinite, seconds > 0, iso.isFinite else { return }
        configureDevice { camera in
            guard camera.isExposureModeSupported(.custom) else { throw StudioError.message("Esposizione manuale non disponibile.") }
            let format = camera.activeFormat
            let requested = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
            let duration = CMTimeMaximum(format.minExposureDuration, CMTimeMinimum(format.maxExposureDuration, requested))
            let sensitivity = min(format.maxISO, max(format.minISO, iso))
            camera.setExposureModeCustom(duration: duration, iso: sensitivity, completionHandler: nil)
            self.setExposureState(.manual)
        }
    }

    func setExposureBias(_ bias: Float) {
        guard bias.isFinite else { return }
        configureDevice { camera in
            camera.setExposureTargetBias(min(camera.maxExposureTargetBias, max(camera.minExposureTargetBias, bias)))
        }
    }

    private func setExposureState(_ state: ExposureSetting) {
        exposureMode = state
        DispatchQueue.main.async { self.exposureState = state }
    }

    // MARK: Colour

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

    // MARK: Files and overlays

    /// Turns Apple ProRAW on or off on the photo output (it needs a reconfiguration).
    func setRAWEnabled(_ enabled: Bool) {
        queue.async {
            self.wantsRAW = enabled
            guard self.configured, !self.inFlight else { return }
            self.applyProRAW(enabled)
            self.prepareSettings()
        }
    }

    func setOverlays(zebra: Bool, peaking: Bool) {
        let tap = frameTap
        analysisQueue.async { tap.zebra = zebra; tap.peaking = peaking }
    }

    private func applyProRAW(_ enabled: Bool) {
        guard output.isAppleProRAWSupported, output.isAppleProRAWEnabled != enabled else { return }
        session.beginConfiguration()
        output.isAppleProRAWEnabled = enabled
        session.commitConfiguration()
    }

    /// Lets iOS allocate the buffers for full-resolution captures in advance, so the first shot is not delayed.
    private func prepareSettings() {
        guard let settings = try? makeSettings(raw: wantsRAW && rawKindAvailable) else { return }
        output.setPreparedPhotoSettingsArray([settings], completionHandler: nil)
    }

    private var rawKindAvailable: Bool {
        output.isAppleProRAWSupported || output.availableRawPhotoPixelFormatTypes.contains(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) })
    }

    private func makeSettings(raw: Bool) throws -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if raw {
            applyProRAW(true)
            let proRAW = output.isAppleProRAWEnabled
            guard let format = output.availableRawPhotoPixelFormatTypes.first(where: {
                proRAW ? AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) : AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
            }) else { throw StudioError.message("RAW non disponibile su questo iPhone.") }
            // The DNG is the master here; the companion JPEG keeps iOS's default compression.
            settings = AVCapturePhotoSettings(rawPixelFormatType: format, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            // ProRAW keeps Apple's multi-frame fusion; single-frame Bayer RAW uses the conservative priority.
            settings.photoQualityPrioritization = proRAW ? .quality : .speed
        } else {
            applyProRAW(false)
            settings = AVCapturePhotoSettings(format: [
                AVVideoCodecKey: AVVideoCodecType.jpeg,
                AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.95]
            ])
            settings.photoQualityPrioritization = .quality
        }
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        settings.flashMode = .off
        return settings
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

    // MARK: Capture

    /// - Parameter angle: rotation from `MotionMonitor.captureAngle`, so photos held sideways are saved upright.
    func capture(raw: Bool, angle: Double, completion: @escaping (Result<CapturePayload, Error>) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.inFlight, !self.colorAdjustmentPending else {
                DispatchQueue.main.async { completion(.failure(StudioError.message("Fotocamera o colore in regolazione. Attendi e riprova."))) }
                return
            }
            let settings: AVCapturePhotoSettings
            do { settings = try self.makeSettings(raw: raw) } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let rotation = CGFloat(angle)
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                connection.videoRotationAngle = rotation
            }
            let sideways = Int(angle.rounded()) % 180 == 0
            let id = settings.uniqueID
            let receiver = PhotoReceiver(expectRaw: raw) { result in
                self.queue.async {
                    self.pending.removeValue(forKey: id)
                    self.inFlight = false
                    // Dimensions are reported in sensor orientation; store them as the photo is viewed.
                    let oriented = result.map { payload in
                        sideways ? payload : CapturePayload(jpeg: payload.jpeg, raw: payload.raw, width: payload.height, height: payload.width)
                    }
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        completion(oriented)
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

// MARK: - Motion

/// Gravity and rotation from Core Motion, on the main thread.
final class MotionMonitor: ObservableObject {
    @Published private(set) var level: LevelReading?
    /// Rotation rate in rad/s, for the camera-shake advice. Not published: read with the camera telemetry.
    private(set) var latestRotation: Double?
    /// Capture rotation for the photo connection (90 portrait, 0/180 landscape).
    private(set) var captureAngle: Double = 90
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity
            let rate = motion.rotationRate
            self.latestRotation = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            self.captureAngle = Level.captureAngle(x: gravity.x, y: gravity.y, z: gravity.z, previous: self.captureAngle)
            self.level = Level.reading(x: gravity.x, y: gravity.y, z: gravity.z)
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        latestRotation = nil
        if level != nil { level = nil }
    }
}

// MARK: - Live frame analysis

/// Results of the live preview analysis, on the main thread.
final class FrameMonitor: ObservableObject {
    @Published private(set) var histogram: [Double] = []
    @Published private(set) var highlights: Double = 0
    @Published private(set) var shadows: Double = 0
    @Published private(set) var overlay: UIImage?

    func update(_ analysis: LumaAnalysis, overlay: UIImage?) {
        histogram = analysis.histogram
        highlights = analysis.highlights
        shadows = analysis.shadows
        self.overlay = overlay
    }

    func reset() {
        histogram = []
        highlights = 0
        shadows = 0
        overlay = nil
    }
}

/// Receives preview frames on the analysis queue and measures about five of them per second.
private final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let monitor: FrameMonitor
    private var last: CFTimeInterval = 0
    // Accessed only on the analysis queue.
    var zebra = false
    var peaking = false

    init(monitor: FrameMonitor) { self.monitor = monitor }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - last >= 0.2, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        last = now
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixels) > 0, let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let luma = UnsafeRawBufferPointer(start: base, count: rowBytes * height)
        guard let analysis = LumaAnalysis.analyze(luma, width: width, height: height, bytesPerRow: rowBytes) else { return }
        let image = (zebra || peaking) ? Self.overlay(for: analysis, zebra: zebra, peaking: peaking, portraitBuffer: height > width) : nil
        let monitor = self.monitor
        DispatchQueue.main.async { monitor.update(analysis, overlay: image) }
    }

    /// Red cells for clipped whites (zebra), green cells for sharp edges (focus peaking).
    private static func overlay(for analysis: LumaAnalysis, zebra: Bool, peaking: Bool, portraitBuffer: Bool) -> UIImage? {
        let count = analysis.columns * analysis.rows
        guard count > 0, analysis.mask.count == count else { return nil }
        var pixels = [UInt8](repeating: 0, count: count * 4)
        var marked = false
        for index in 0..<count {
            let flags = analysis.mask[index]
            let offset = index * 4
            // Premultiplied RGBA.
            if zebra && (flags & LumaAnalysis.highlightFlag) != 0 {
                pixels[offset] = 200; pixels[offset + 1] = 30; pixels[offset + 2] = 30; pixels[offset + 3] = 200
                marked = true
            } else if peaking && (flags & LumaAnalysis.edgeFlag) != 0 {
                pixels[offset] = 60; pixels[offset + 1] = 210; pixels[offset + 2] = 90; pixels[offset + 3] = 210
                marked = true
            }
        }
        guard marked, let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: analysis.columns, height: analysis.rows, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: analysis.columns * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        // Preview frames arrive in the sensor's landscape orientation; the viewfinder is portrait.
        return UIImage(cgImage: image, scale: 1, orientation: portraitBuffer ? .up : .right)
    }
}
