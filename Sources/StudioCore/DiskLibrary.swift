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
        try write(product)
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

    /// Writes the files first, then the manifest. A failed write leaves no shot behind.
    /// Files are named after the product and the view, e.g. `Celine-bianca_01_fronte.jpg`, and never overwrite an existing file.
    public func append(productID: UUID, kind: ShotKind, jpeg: Data, raw: Data?, width: Int, height: Int) throws -> ProductSession {
        let directory = folder(for: productID)
        var product = try read(productID)
        let id = UUID()
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let used = Set(onDisk + product.shots.flatMap { [$0.jpeg] + ($0.raw.map { [$0] } ?? []) })
        let prefix = ProductSession.safeName(product.name) + "_"
        func numbered(_ number: Int) -> String { prefix + String(format: "%02d", number) + "_" }
        var number = product.shots.count + 1
        while used.contains(where: { $0.hasPrefix(numbered(number)) }) { number += 1 }
        let stem = numbered(number) + kind.fileLabel
        let jpegName = stem + ".jpg"
        let rawName = raw.map { _ in stem + ".dng" }
        let jpegURL = directory.appendingPathComponent(jpegName)
        let rawURL = rawName.map { directory.appendingPathComponent($0) }
        do {
            try jpeg.write(to: jpegURL, options: .atomic)
            if let raw, let rawURL { try raw.write(to: rawURL, options: .atomic) }
            product.shots.append(ShotRecord(id: id, kind: kind, capturedAt: Date(), jpeg: jpegName, raw: rawName, width: width, height: height))
            try write(product)
        } catch {
            try? FileManager.default.removeItem(at: jpegURL)
            if let rawURL { try? FileManager.default.removeItem(at: rawURL) }
            throw error
        }
        return product
    }

    /// Removes the shot from the manifest first, then its files, so the archive never lists a missing photo.
    public func deleteShot(productID: UUID, shotID: UUID) throws -> ProductSession {
        var product = try read(productID)
        guard let index = product.shots.firstIndex(where: { $0.id == shotID }) else { return product }
        let shot = product.shots.remove(at: index)
        try write(product)
        let directory = folder(for: productID)
        for name in [shot.jpeg] + (shot.raw.map { [$0] } ?? []) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        return product
    }

    public func deleteProduct(id: UUID) throws {
        let directory = folder(for: id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public func rename(productID: UUID, to name: String) throws -> ProductSession {
        var product = try read(productID)
        product.name = ProductSession.cleanName(name, fallback: product.name)
        try write(product)
        return product
    }

    private func manifest(for id: UUID) -> URL { folder(for: id).appendingPathComponent("product.json") }

    private func read(_ id: UUID) throws -> ProductSession {
        try JSONDecoder().decode(ProductSession.self, from: Data(contentsOf: manifest(for: id)))
    }

    private func write(_ product: ProductSession) throws {
        try JSONEncoder().encode(product).write(to: manifest(for: product.id), options: .atomic)
    }
}
