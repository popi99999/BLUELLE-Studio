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
