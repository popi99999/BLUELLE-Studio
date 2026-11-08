import Foundation

public enum CaptureAdvice: String, Sendable {
    case focusing, moving, slowShutter, lowLight, motionUnknown, steady

    public static func evaluate(iso: Float, seconds: Double, rotation: Double?, focusing: Bool) -> Self {
        if focusing { return .focusing }
        if let rotation, rotation > 0.12 { return .moving }
        if seconds > 1.0 / 60 { return .slowShutter }
        if iso > 800 { return .lowLight }
        guard rotation != nil else { return .motionUnknown }
        return .steady
    }

    public var title: String {
        switch self {
        case .focusing: return "Messa a fuoco in corso"
        case .moving: return "Ferma il telefono"
        case .slowShutter: return "Tempo lento: usa un supporto"
        case .lowLight: return "Aggiungi luce al prodotto"
        case .motionUnknown: return "Movimento non disponibile"
        case .steady: return "Telefono stabile"
        }
    }

    public var detail: String {
        switch self {
        case .focusing: return "Aspetta prima di scattare. Per i dettagli, tocca l’etichetta."
        case .moving: return "Appoggia i gomiti o usa un treppiede e il timer."
        case .slowShutter: return "Sotto 1/60 s aumenta il rischio di mosso a mano libera."
        case .lowLight: return "ISO elevati possono ridurre il dettaglio del tessuto."
        case .motionUnknown: return "Controlla la stabilità con un supporto."
        case .steady: return "Controlla comunque il dettaglio ingrandendo la foto dopo lo scatto."
        }
    }
}

public enum WhiteBalance {
    public struct Gains: Equatable, Sendable {
        public let red: Float
        public let green: Float
        public let blue: Float
    }

    public static func clamp(red: Float, green: Float, blue: Float, maximum: Float) -> Gains {
        let limit = maximum.isFinite ? max(1, maximum) : 1
        func safe(_ value: Float) -> Float { value.isFinite ? min(limit, max(1, value)) : 1 }
        return Gains(red: safe(red), green: safe(green), blue: safe(blue))
    }
}

// MARK: - Level

/// A spirit-level reading derived from the gravity vector in device coordinates
/// (x towards the right edge, y towards the top edge, z out of the screen).
public struct LevelReading: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// The phone is held up, facing the product (front, back, hanging garments).
        case upright
        /// The phone looks down at a product laid flat (flat lay, labels on a table).
        case flat
    }

    public let mode: Mode
    /// Upright: how far the phone is rolled away from the nearest straight orientation.
    /// Flat: how far the camera is tilted away from pointing straight down.
    public let degrees: Double
    /// Upright: forward or backward tilt, 0 when the phone is perfectly vertical.
    public let pitch: Double
    /// Upright: clockwise screen rotation that keeps a drawn line parallel to the real horizon.
    public let horizon: Double
    /// Upright: clockwise screen rotation of the straight orientation the phone is closest to.
    public let reference: Double
    /// Flat: bubble offset towards the raised edge, -1...1 on each screen axis.
    public let bubbleX: Double
    public let bubbleY: Double

    public var isLevel: Bool { abs(degrees) <= Level.tolerance }
    public var isVertical: Bool { abs(pitch) <= Level.pitchTolerance }
}

public enum Level {
    /// Degrees within which the phone counts as level.
    public static let tolerance = 1.0
    /// Degrees of forward/backward tilt still considered vertical.
    public static let pitchTolerance = 2.0
    /// Tilt, in degrees, that moves the flat-lay bubble to the edge of its ring.
    public static let bubbleRange = 10.0
    static let flatThreshold = 0.8

    public static func reading(x: Double, y: Double, z: Double) -> LevelReading? {
        guard x.isFinite, y.isFinite, z.isFinite else { return nil }
        let length = (x * x + y * y + z * z).squareRoot()
        guard length > 0.5 else { return nil }
        let gx = x / length, gy = y / length, gz = z / length
        if gz < -flatThreshold {
            let tilt = acos(min(1, -gz)) * 180 / .pi
            let scale = sin(bubbleRange * .pi / 180)
            return LevelReading(mode: .flat, degrees: tilt, pitch: 0, horizon: 0, reference: 0,
                                bubbleX: unit(-gx / scale), bubbleY: unit(gy / scale))
        }
        // Camera pointing at the ceiling: nothing useful to show for product photos.
        guard gz < flatThreshold else { return nil }
        let roll = atan2(gx, -gy) * 180 / .pi
        let nearest = (roll / 90).rounded() * 90
        let pitch = asin(max(-1, min(1, gz))) * 180 / .pi
        return LevelReading(mode: .upright, degrees: roll - nearest, pitch: pitch, horizon: -roll, reference: -nearest,
                            bubbleX: 0, bubbleY: 0)
    }

    /// Rotation, in degrees, to apply to the back camera's capture connection so the photo is saved upright.
    /// 90 is portrait, 0 and 180 are the two landscape orientations, 270 is upside down.
    /// While the phone is flat (flat lay) the previous orientation is kept, like a dedicated camera.
    public static func captureAngle(x: Double, y: Double, z: Double, previous: Double) -> Double {
        guard x.isFinite, y.isFinite, z.isFinite, abs(z) < flatThreshold else { return previous }
        let margin = 0.15
        if abs(y) > abs(x) + margin { return y < 0 ? 90 : 270 }
        if abs(x) > abs(y) + margin { return x < 0 ? 0 : 180 }
        return previous
    }

    private static func unit(_ value: Double) -> Double { max(-1, min(1, value)) }
}

// MARK: - Manual exposure

public enum ExposureScale {
    /// Maps a 0...1 slider position to a shutter time on a logarithmic scale, so each stop gets the same travel.
    public static func seconds(at position: Double, minimum: Double, maximum: Double) -> Double {
        guard minimum > 0, maximum > minimum, position.isFinite else { return max(0, minimum) }
        let clamped = max(0, min(1, position))
        return exp(log(minimum) + clamped * (log(maximum) - log(minimum)))
    }

    public static func position(for seconds: Double, minimum: Double, maximum: Double) -> Double {
        guard minimum > 0, maximum > minimum, seconds > 0, seconds.isFinite else { return 0 }
        return max(0, min(1, (log(seconds) - log(minimum)) / (log(maximum) - log(minimum))))
    }

    public static func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        if seconds < 0.95 { return "1/\(Int((1 / seconds).rounded())) s" }
        return String(format: "%.1f s", seconds)
    }
}

// MARK: - Live frame analysis

/// Histogram, clipping and focus-edge map computed from the luma plane of a live preview frame.
/// It describes the preview, not the final processed photo: it is a guide for exposure and focus.
public struct LumaAnalysis: Equatable, Sendable {
    public static let binCount = 32
    public static let highlightLevel: UInt8 = 250
    public static let shadowLevel: UInt8 = 4
    public static let highlightFlag: UInt8 = 1
    public static let edgeFlag: UInt8 = 2

    /// Fraction of samples in each of `binCount` equal brightness bins; sums to 1.
    public let histogram: [Double]
    /// Fraction of samples at or above `highlightLevel`.
    public let highlights: Double
    /// Fraction of samples at or below `shadowLevel`.
    public let shadows: Double
    /// Size of the coarse mask, in the frame's own orientation.
    public let columns: Int
    public let rows: Int
    /// One cell per mask position, combining `highlightFlag` and `edgeFlag`.
    public let mask: [UInt8]

    public static func analyze(_ luma: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                               columns targetColumns: Int = 192, edgeThreshold: Int = 40) -> LumaAnalysis? {
        guard width >= 4, height >= 4, bytesPerRow >= width, targetColumns > 0,
              luma.count >= bytesPerRow * (height - 1) + width else { return nil }
        let cell = max(2, width / targetColumns)
        let columns = width / cell
        let rows = height / cell
        let step = max(1, cell / 4)
        var bins = [Int](repeating: 0, count: binCount)
        var mask = [UInt8](repeating: 0, count: columns * rows)
        var total = 0, bright = 0, dark = 0
        for row in 0..<rows {
            for column in 0..<columns {
                var samples = 0, clipped = 0, edges = 0
                var y = row * cell + step / 2
                while y < (row + 1) * cell {
                    var x = column * cell + step / 2
                    while x < (column + 1) * cell {
                        let index = y * bytesPerRow + x
                        let value = luma[index]
                        bins[Int(value) >> 3] += 1
                        samples += 1
                        if value >= highlightLevel { clipped += 1 } else if value <= shadowLevel { dark += 1 }
                        if x > 0, x < width - 1, y > 0, y < height - 1 {
                            let horizontal = abs(Int(luma[index + 1]) - Int(luma[index - 1]))
                            let vertical = abs(Int(luma[index + bytesPerRow]) - Int(luma[index - bytesPerRow]))
                            if horizontal + vertical >= edgeThreshold { edges += 1 }
                        }
                        x += step
                    }
                    y += step
                }
                total += samples
                bright += clipped
                var flags: UInt8 = 0
                if clipped > 0 && clipped * 4 >= samples { flags |= highlightFlag }
                if edges > 0 && edges * 8 >= samples { flags |= edgeFlag }
                mask[row * columns + column] = flags
            }
        }
        guard total > 0 else { return nil }
        return LumaAnalysis(histogram: bins.map { Double($0) / Double(total) },
                            highlights: Double(bright) / Double(total),
                            shadows: Double(dark) / Double(total),
                            columns: columns, rows: rows, mask: mask)
    }
}
