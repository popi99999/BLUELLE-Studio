import Foundation

public enum ShotKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case front, back, logo, label, detail, flaw
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .front: return "Fronte"
        case .back: return "Retro"
        case .logo: return "Logo"
        case .label: return "Etichetta"
        case .detail: return "Tessuto"
        case .flaw: return "Difetti"
        }
    }
    public var hint: String {
        switch self {
        case .front: return "Lascia un piccolo margine intorno al capo."
        case .back: return "Mantieni luce, distanza e colori del fronte."
        case .logo: return "Tocca il logo per mettere a fuoco. Evita lo zoom digitale."
        case .label: return "Stendi l’etichetta e tieni il telefono parallelo. Se sfoca, allontanati."
        case .detail: return "Luce diffusa di lato per rendere visibile la trama."
        case .flaw: return "Documenta eventuali difetti senza filtri o ritocchi."
        }
    }
}

public struct ShotRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ShotKind
    public let capturedAt: Date
    public let jpeg: String
    public let raw: String?
    public let width: Int
    public let height: Int

    public init(id: UUID, kind: ShotKind, capturedAt: Date, jpeg: String, raw: String?, width: Int, height: Int) {
        self.id = id; self.kind = kind; self.capturedAt = capturedAt
        self.jpeg = jpeg; self.raw = raw; self.width = width; self.height = height
    }
}

public struct ProductSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var shots: [ShotRecord]

    public init(name: String) {
        self.id = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nuovo prodotto" : name
        self.createdAt = Date()
        self.shots = []
    }

    public var completedKinds: Set<ShotKind> { Set(shots.map(\.kind)) }
    public var nextKind: ShotKind { ShotKind.allCases.first { !completedKinds.contains($0) } ?? .front }

    public static func safeName(_ name: String) -> String {
        let components = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return components.isEmpty ? "Prodotto" : String(components.joined(separator: "-").prefix(70))
    }
}
