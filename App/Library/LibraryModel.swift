import Combine
import ImageIO
import Photos
import SwiftUI
import UIKit

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var products: [ProductSession] = []
    @Published private(set) var busy = false
    @Published var selectedID: UUID?
    @Published var error: String?
    @Published var notice: String?
    let disk: DiskLibrary
    private let queue = DispatchQueue(label: "com.bluelle.files", qos: .userInitiated)

    var current: ProductSession? { products.first { $0.id == selectedID } }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "StudioUITests-\(UUID().uuidString)" : "BLUELLE Studio"
        disk = DiskLibrary(root: documents.appendingPathComponent(folder, isDirectory: true))
        do {
            let recovered = try disk.recover()
            products = recovered.products
            selectedID = products.first?.id
            if !recovered.unreadable.isEmpty {
                error = "\(recovered.unreadable.count) sessioni non leggibili. Le altre sono disponibili. I file danneggiati restano in File > Sul mio iPhone > BLUELLE Studio."
            }
        }
        catch { self.error = "Impossibile leggere l’archivio: \(error.localizedDescription). I file restano in File > Sul mio iPhone > BLUELLE Studio." }
    }

    func create(name: String) {
        guard !busy else { return }
        do {
            let product = try disk.create(name: name)
            products.insert(product, at: 0)
            selectedID = product.id
        } catch { self.error = error.localizedDescription }
    }

    func save(_ payload: CapturePayload, productID: UUID, kind: ShotKind, completion: @escaping (Bool) -> Void) {
        busy = true
        let disk = disk
        queue.async {
            let result = Result {
                try disk.append(productID: productID, kind: kind, jpeg: payload.jpeg, raw: payload.raw, width: payload.width, height: payload.height)
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let product):
                    if let index = self.products.firstIndex(where: { $0.id == product.id }) { self.products[index] = product }
                    self.notice = "\(kind.title) salvato · \(payload.width) × \(payload.height)"
                    completion(true)
                case .failure(let error):
                    self.error = "Foto non salvata: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }
    }

    func url(for shot: ShotRecord, in product: ProductSession) -> URL { disk.folder(for: product.id).appendingPathComponent(shot.jpeg) }

    func files(for product: ProductSession) -> [URL] {
        let folder = disk.folder(for: product.id)
        return product.shots.flatMap { shot in
            [folder.appendingPathComponent(shot.jpeg)] + (shot.raw.map { [folder.appendingPathComponent($0)] } ?? [])
        }
    }

    func deleteShot(_ shot: ShotRecord, in product: ProductSession) {
        guard !busy else { return }
        do { replace(try disk.deleteShot(productID: product.id, shotID: shot.id)) }
        catch { self.error = "Foto non eliminata: \(error.localizedDescription)" }
    }

    func deleteProduct(_ product: ProductSession) {
        guard !busy else { return }
        do {
            try disk.deleteProduct(id: product.id)
            products.removeAll { $0.id == product.id }
            if selectedID == product.id { selectedID = products.first?.id }
        } catch { self.error = "Prodotto non eliminato: \(error.localizedDescription)" }
    }

    func rename(_ product: ProductSession, to name: String) {
        guard !busy else { return }
        do { replace(try disk.rename(productID: product.id, to: name)) }
        catch { self.error = "Nome non modificato: \(error.localizedDescription)" }
    }

    private func replace(_ product: ProductSession) {
        if let index = products.firstIndex(where: { $0.id == product.id }) { products[index] = product }
    }

    /// Adds each shot as one asset in Photos: the JPEG, with the DNG attached as its RAW alternate when present.
    func saveToPhotos(_ shots: [ShotRecord], in product: ProductSession) {
        guard !shots.isEmpty else { return }
        let folder = disk.folder(for: product.id)
        let files = shots.map { shot in (folder.appendingPathComponent(shot.jpeg), shot.raw.map { folder.appendingPathComponent($0) }) }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.error = "Accesso a Foto negato. Puoi condividere i file oppure abilitarlo in Impostazioni." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for (jpeg, raw) in files {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: jpeg, options: nil)
                    if let raw { request.addResource(with: .alternatePhoto, fileURL: raw, options: nil) }
                }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success { self.notice = files.count == 1 ? "Originale aggiunto a Foto" : "\(files.count) originali aggiunti a Foto" }
                    else { self.error = error?.localizedDescription ?? "Salvataggio in Foto non riuscito." }
                }
            }
        }
    }
}

func thumbnail(at url: URL, maximum: Int = 600) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum
          ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

struct ShareFiles: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
