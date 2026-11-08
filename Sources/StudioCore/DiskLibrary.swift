import Foundation

/// Photos stay in the app's Documents directory. The original JPEG/DNG bytes are retained.
public struct DiskLibrary: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    public func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func create(name: String) throws -> ProductSession {
        let product = ProductSession(name: name)
        let directory = folder(for: product.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(product).write(to: directory.appendingPathComponent("product.json"), options: .atomic)
        return product
    }

    public func load() throws -> [ProductSession] {
        try recover().products
    }

    public func recover() throws -> (products: [ProductSession], unreadable: [String]) {
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], []) }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        var products: [ProductSession] = []
        var unreadable: [String] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            do {
                let product = try JSONDecoder().decode(ProductSession.self, from: Data(contentsOf: folder.appendingPathComponent("product.json")))
                guard product.id.uuidString == folder.lastPathComponent else { unreadable.append(folder.lastPathComponent); continue }
                products.append(product)
            } catch { unreadable.append(folder.lastPathComponent) }
        }
        return (products.sorted { $0.createdAt > $1.createdAt }, unreadable)
    }

    public func append(productID: UUID, kind: ShotKind, jpeg: Data, raw: Data?, width: Int, height: Int) throws -> ProductSession {
        let directory = folder(for: productID)
        let manifest = directory.appendingPathComponent("product.json")
        var product = try JSONDecoder().decode(ProductSession.self, from: Data(contentsOf: manifest))
        let id = UUID()
        let stem = String(format: "%02d", product.shots.count + 1) + "_" + kind.rawValue + "_" + id.uuidString
        let jpegName = stem + ".jpg"
        let rawName = raw.map { _ in stem + ".dng" }
        let jpegURL = directory.appendingPathComponent(jpegName)
        let rawURL = rawName.map { directory.appendingPathComponent($0) }
        do {
            try jpeg.write(to: jpegURL, options: .atomic)
            if let raw, let rawURL { try raw.write(to: rawURL, options: .atomic) }
            product.shots.append(ShotRecord(id: id, kind: kind, capturedAt: Date(), jpeg: jpegName, raw: rawName, width: width, height: height))
            try JSONEncoder().encode(product).write(to: manifest, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: jpegURL)
            if let rawURL { try? FileManager.default.removeItem(at: rawURL) }
            throw error
        }
        return product
    }
}
